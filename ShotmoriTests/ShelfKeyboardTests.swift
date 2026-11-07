import XCTest
@testable import Shotmori

/// Ortak raf kısayolları: yüzen panel ve üst şerit aynı eşlemeyi kullanır (tuş kodları ANSI).
final class ShelfKeyboardTests: XCTestCase {
    private func cmd(_ code: UInt16, _ ch: String? = nil, _ flags: NSEvent.ModifierFlags = [], editing: Bool = false) -> ShelfKeyCommand? {
        ShelfKeyboard.command(keyCode: code, characters: ch, flags: flags, editingText: editing)
    }
    // ANSI tuş kodları
    private let left: UInt16 = 123, right: UInt16 = 124, space: UInt16 = 49, tab: UInt16 = 48, ret: UInt16 = 36, del: UInt16 = 51, esc: UInt16 = 53
    private let kA: UInt16 = 0, kC: UInt16 = 8, kE: UInt16 = 14, kK: UInt16 = 40, kO: UInt16 = 31, kR: UInt16 = 15, kW: UInt16 = 13
    private let digits: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25] // 1…9

    func testArrowsMoveAndShiftExtends() {
        XCTAssertEqual(cmd(left), .move(-1, extend: false))
        XCTAssertEqual(cmd(right), .move(1, extend: false))
        XCTAssertEqual(cmd(left, nil, [.shift]), .move(-1, extend: true))
        XCTAssertEqual(cmd(right, nil, [.shift]), .move(1, extend: true))
        XCTAssertEqual(cmd(right, nil, [.numericPad, .function]), .move(1, extend: false), "ok tuşu olayının kendi bayrakları eşlemeyi bozmaz")
    }
    func testCommandArrowsJumpToEnds() {
        XCTAssertEqual(cmd(left, nil, [.command]), .first)
        XCTAssertEqual(cmd(right, nil, [.command]), .last)
    }
    func testCommandAAndQuickNumbers() {
        XCTAssertEqual(cmd(kA, "a", [.command]), .selectAll)
        for (i, code) in digits.enumerated() { XCTAssertEqual(cmd(code, "\(i + 1)"), .selectNumber(i + 1), "\(i + 1)") }
        XCTAssertNil(cmd(digits[0], "!", [.shift]), "⇧1 eşlenmez")
    }
    func testSpaceAndActionsMenu() {
        XCTAssertEqual(cmd(space, " "), .quickLook)
        XCTAssertEqual(cmd(kK, "k", [.command]), .actionsMenu)
    }
    func testTabCyclesShelvesAndCommandDigitsPickShelf() {
        XCTAssertEqual(cmd(tab, "\t"), .nextShelf)
        XCTAssertEqual(cmd(tab, "\u{19}", [.shift]), .previousShelf)
        for i in 0..<8 { XCTAssertEqual(cmd(digits[i], "\(i + 1)", [.command]), .shelfIndex(i), "⌘\(i + 1)") }
        XCTAssertNil(cmd(digits[8], "9", [.command]), "⌘9 yok: en çok 8 raf")
        XCTAssertNil(cmd(digits[0], "1", [.command, .shift]))
    }
    func testOutputCommands() {
        XCTAssertEqual(cmd(ret, "\r"), .copyAndClose)
        XCTAssertEqual(cmd(kC, "c", [.command]), .copy)
        XCTAssertEqual(cmd(kO, "o", [.command]), .open)
        XCTAssertEqual(cmd(kR, "r", [.command]), .reveal)
        XCTAssertEqual(cmd(kE, "e"), .edit)
        XCTAssertEqual(cmd(kC, "C", [.command, .shift]), .copyText, "⇧⌘C: charactersIgnoringModifiers büyük harf verir")
        XCTAssertEqual(cmd(del, "\u{7F}"), .remove)
        XCTAssertEqual(cmd(esc, "\u{1B}"), .close)
        XCTAssertEqual(cmd(kW, "w", [.command]), .close)
    }
    func testUnmappedKeysReturnNil() {
        XCTAssertNil(cmd(kE, "e", [.command]), "⌘E eşlenmez")
        XCTAssertNil(cmd(kK, "k"), "K tek başına eşlenmez")
        XCTAssertNil(cmd(125, nil), "aşağı ok eşlenmez")
        XCTAssertNil(cmd(kC, "c"), "C tek başına eşlenmez")
    }
    func testEditingTextOnlyAllowsClose() {
        XCTAssertNil(cmd(kE, "e", editing: true))
        XCTAssertNil(cmd(digits[0], "1", editing: true))
        XCTAssertNil(cmd(space, " ", editing: true))
        XCTAssertNil(cmd(ret, "\r", editing: true))
        XCTAssertNil(cmd(kC, "c", [.command], editing: true))
        XCTAssertEqual(cmd(esc, "\u{1B}", editing: true), .close)
    }
    func testQuickNumbersCoverFirstNineVisible() {
        let ids = (0..<12).map { _ in UUID() }
        let n = ShelfKeyboard.quickNumbers(visible: ids)
        XCTAssertEqual(n.count, 9)
        for i in 0..<9 { XCTAssertEqual(n[ids[i]], i + 1) }
        XCTAssertNil(n[ids[9]], "onuncu karenin numarası yok")
        XCTAssertTrue(ShelfKeyboard.quickNumbers(visible: []).isEmpty)
    }
    // MARK: Yürütme yardımcıları ve gösterim
    func testTabCycleSkipsDetachedShelvesAndWraps() {
        let a = UUID(), b = UUID(), c = UUID()
        XCTAssertEqual(ShelfPanelController.cycledShelf(from: a, order: [a, b, c], detached: [], forward: true), b)
        XCTAssertEqual(ShelfPanelController.cycledShelf(from: c, order: [a, b, c], detached: [], forward: true), a, "sondan başa döner")
        XCTAssertEqual(ShelfPanelController.cycledShelf(from: a, order: [a, b, c], detached: [], forward: false), c, "⇧Tab baştan sona döner")
        XCTAssertEqual(ShelfPanelController.cycledShelf(from: a, order: [a, b, c], detached: [b], forward: true), c, "pencerede duran raf atlanır")
        XCTAssertNil(ShelfPanelController.cycledShelf(from: a, order: [a, b], detached: [b], forward: true), "tek takılı rafta geçiş yok")
    }
    func testMenuShowsSameShortcutsAsKeyboard() {
        let k = ActionRegistry.menuKeys
        XCTAssertEqual(k["open"]?.0, "o"); XCTAssertEqual(k["open"]?.1, [.command], "↩ artık kopyala ve kapat; Aç ⌘O")
        XCTAssertEqual(k["edit"]?.0, "e"); XCTAssertEqual(k["edit"]?.1, [])
        XCTAssertEqual(k["copy-text"]?.0, "c"); XCTAssertEqual(k["copy-text"]?.1, [.command, .shift])
        XCTAssertEqual(k["copy-image"]?.1, [.command]); XCTAssertEqual(k["reveal-in-finder"]?.0, "r"); XCTAssertEqual(k["remove-from-shelf"]?.0, "\u{8}")
    }
    func testQuickNumberBadgeOnlyWhenKeyAndNumbered() {
        XCTAssertTrue(ThumbnailItemView.showsQuickNumber(3, windowIsKey: true))
        XCTAssertFalse(ThumbnailItemView.showsQuickNumber(3, windowIsKey: false))
        XCTAssertFalse(ThumbnailItemView.showsQuickNumber(nil, windowIsKey: true))
        let r = ThumbnailItemView.quickNumberRect(in: NSRect(x: 6, y: 4, width: 134, height: 110))
        XCTAssertEqual(r.size, NSSize(width: 16, height: 16)); XCTAssertEqual(r.minX, 12, "sol alt")
        XCTAssertGreaterThanOrEqual(r.minY, 4 + ThumbnailItemView.footerHeight, "alt şeridin üstünde")
    }
    func testQuickNumberIsNotInVoiceOverValue() {
        let v = ThumbnailItemView(item: ShelfItem(path: "/nonexistent/a.png", fileID: nil, capturedAt: Date()))
        let before = v.accessibilityValue() as? String
        v.quickNumber = 1
        XCTAssertEqual(v.accessibilityValue() as? String, before)
    }
    func testQuickLookIndexIsClamped() {
        XCTAssertEqual(ShelfQuickLook.clampedIndex(5, count: 3), 2); XCTAssertEqual(ShelfQuickLook.clampedIndex(-1, count: 3), 0); XCTAssertEqual(ShelfQuickLook.clampedIndex(0, count: 0), 0)
    }
    func testPanelTabSwitchesShelvesAndDetachedPanelPassesTab() throws {
        let suite = "dev.shotmori.tests.shelfkeys"; let d = UserDefaults(suiteName: suite)!; d.removePersistentDomain(forName: suite); defer { d.removePersistentDomain(forName: suite) }
        let prefs = Preferences(defaults: d); let reg = ActionRegistry(prefs: prefs)
        let store = ShelfStore(fileURL: nil, maxItems: 5); let first = store.activeShelfID
        let work = try XCTUnwrap(store.addShelf(name: "İş"))
        let main = ShelfPanelController(store: store, registry: reg, prefs: prefs, mode: .main)
        XCTAssertTrue(main.perform(.nextShelf)); XCTAssertEqual(store.activeShelfID, work.id)
        XCTAssertTrue(main.perform(.previousShelf)); XCTAssertEqual(store.activeShelfID, first)
        let det = ShelfPanelController(store: store, registry: reg, prefs: prefs, mode: .detached(work.id))
        XCTAssertFalse(det.perform(.nextShelf), "ayrılmış panelde raf geçişi yok")
        XCTAssertFalse(det.perform(.shelfIndex(0)))
    }
    func testReturnHidesOnlyAfterAvailableCopyAndWhenUnpinned() throws {
        XCTAssertTrue(ShelfPanelController.shouldHideAfterCopy(copyAvailable: true, pinned: false))
        XCTAssertFalse(ShelfPanelController.shouldHideAfterCopy(copyAvailable: true, pinned: true), "iğne açıkken kapanmaz")
        XCTAssertFalse(ShelfPanelController.shouldHideAfterCopy(copyAvailable: false, pinned: false), "kopyalanamadıysa neden görünür kalır")
        // Uçtan uca (panoya dokunmadan): diskte olmayan kare kopyalanamaz → panel açık kalır.
        let suite = "dev.shotmori.tests.shelfkeys.ret"; let d = UserDefaults(suiteName: suite)!; d.removePersistentDomain(forName: suite); defer { d.removePersistentDomain(forName: suite) }
        let prefs = Preferences(defaults: d); prefs.keepShelfOpen = false
        let store = ShelfStore(fileURL: nil, maxItems: 5); store.add(ShelfItem(path: "/nonexistent/a.png", fileID: nil, capturedAt: Date()))
        let c = ShelfPanelController(store: store, registry: ActionRegistry(prefs: prefs), prefs: prefs)
        c.show(takeKey: false); XCTAssertEqual(c.selection.count, 1)
        XCTAssertTrue(c.perform(.copyAndClose)); XCTAssertTrue(c.isVisible); c.hide(reason: "test")
    }
}
