import XCTest
@testable import Shotmori

/// Çoklu raf incelemesinin ertelediği küçük maddeler (20 Ekim 2026).
final class ShelfReviewFixesTests: XCTestCase {
    private func entry(_ id: UUID, _ name: String, _ count: Int) -> ShelfTabBar.Entry { .init(id: id, name: name, count: count, detached: false) }
    private func existingFile() throws -> URL { let u = FileManager.default.temporaryDirectory.appendingPathComponent("rf-\(UUID()).png"); try Data([1]).write(to: u); return u }

    // 1. Kırpma bildirimi metni
    func testMoveTrimmedToastHasSingularAndPluralForms() {
        XCTAssertFalse(S.moveTrimmedToast(1).contains("%d")); XCTAssertFalse(S.moveTrimmedToast(1).contains("1 images"))
        XCTAssertTrue(S.moveTrimmedToast(3).contains("3"))
    }

    // 3. Sekme çubuğu: kimlik listesi aynıysa yeniden kurulmaz, düzenleme korunur
    func testNeedsRebuildOnlyWhenShelfIDsChange() {
        let a = UUID(), b = UUID()
        XCTAssertFalse(ShelfTabBar.needsRebuild(old: [entry(a, "Raf 1", 0)], new: [entry(a, "Raf 1", 1)]), "sayı değişti: yalnız başlık güncellenir")
        XCTAssertFalse(ShelfTabBar.needsRebuild(old: [entry(a, "Raf 1", 0)], new: [entry(a, "İş", 0)]), "ad değişti: yalnız başlık güncellenir")
        XCTAssertTrue(ShelfTabBar.needsRebuild(old: [entry(a, "Raf 1", 0)], new: [entry(a, "Raf 1", 0), entry(b, "Raf 2", 0)]), "raf eklendi")
        XCTAssertTrue(ShelfTabBar.needsRebuild(old: [entry(a, "Raf 1", 0), entry(b, "Raf 2", 0)], new: [entry(b, "Raf 2", 0), entry(a, "Raf 1", 0)]), "sıra değişti")
        XCTAssertTrue(ShelfTabBar.needsRebuild(old: [], new: [entry(a, "Raf 1", 0)]))
    }
    func testRenameSurvivesCountChangeAndChipTitleUpdates() {
        let a = UUID(), b = UUID()
        let bar = ShelfTabBar(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        bar.entries = [entry(a, "Raf 1", 0), entry(b, "Raf 2", 0)]; bar.activeID = a
        bar.startRename(a); XCTAssertTrue(bar.isRenaming)
        bar.entries = [entry(a, "Raf 1", 1), entry(b, "Raf 2", 0)] // etkin rafa kare geldi
        XCTAssertTrue(bar.isRenaming, "adlandırma sırasında gelen kare yazılan adı silmez")
        let chips = bar.subviews.compactMap { $0 as? TabChip }.filter { !$0.isAdd }
        XCTAssertEqual(chips.first?.title, "Raf 1 · 1", "başlık yerinde güncellenir")
        bar.entries = [entry(a, "Raf 1", 1)]
        XCTAssertFalse(bar.isRenaming, "raf listesi değişince yeniden kurulur, düzenleme biter")
    }

    // 4. Rafa taşı ▸ başlıkları "ad · N"
    func testMoveSubmenuAppendsCountWhenNonZero() {
        let a = UUID(), b = UUID(), c = UUID()
        let e = ActionRegistry.moveSubmenuEntries(shelves: [(a, "Raf 1", 2), (b, "İş", 3), (c, "Boş", 0)], active: a)
        XCTAssertEqual(e.map(\.title), ["İş · 3", "Boş", S.moveToNewShelf])
    }

    // 5. Popover sayacı: "N yeni" tüm rafların toplamı
    func testPopoverCountTextUsesAllShelvesNewCount() {
        XCTAssertEqual(MenuBarPopoverViewController.countText(total: 0, newCount: 0), S.popoverCount(0))
        XCTAssertEqual(MenuBarPopoverViewController.countText(total: 0, newCount: 3), "\(S.popoverCount(0)) · \(S.newCount(3))", "etkin raf boşken rozet 3 diyorsa popover 0 demez")
        XCTAssertEqual(MenuBarPopoverViewController.countText(total: 4, newCount: 0), S.imageCount(4))
        XCTAssertEqual(MenuBarPopoverViewController.countText(total: 4, newCount: 2), "\(S.imageCount(4)) · \(S.newCount(2))")
    }

    // 6. "Son görüntüyü kopyala" etkinliği eylemle aynı kümeye (tüm raflar) bakar
    func testCopyLastEnabledLooksAtAllShelves() throws {
        let s = ShelfStore(fileURL: nil, maxItems: 5); let b = try XCTUnwrap(s.addShelf()).id
        XCTAssertFalse(StatusItemController.copyLastEnabled(store: s))
        let u = try existingFile(); defer { try? FileManager.default.removeItem(at: u) }
        s.add(ShelfItem(path: u.path, fileID: nil, capturedAt: Date()), to: b)
        XCTAssertTrue(StatusItemController.copyLastEnabled(store: s), "etkin raf boş, başka rafta dosya var")
        s.add(ShelfItem(path: "/tmp/yok-\(UUID()).png", fileID: nil, capturedAt: Date(), addedAt: Date(timeIntervalSinceNow: 10)))
        XCTAssertFalse(StatusItemController.copyLastEnabled(store: s), "en yeni dosya diskte yoksa pasif")
    }
    /// COR-27: Çöp'e taşınmış en yeni kare atlanır; menü etkinliği ve kopyalanan kare `ShelfIntentCore.latest` ile aynı.
    func testCopyLastSkipsLocallyTrashedNewest() throws {
        let s = ShelfStore(fileURL: nil, maxItems: 5)
        let u = try existingFile(); defer { try? FileManager.default.removeItem(at: u) }
        let older = ShelfItem(path: u.path, fileID: nil, capturedAt: Date())
        s.add(older)
        let trashed = ShelfItem(path: "/tmp/cop-\(UUID()).png", fileID: nil, capturedAt: Date(), addedAt: Date(timeIntervalSinceNow: 10))
        s.add(trashed); s.markLocalTrashed(itemID: trashed.id)
        XCTAssertEqual(MainActor.assumeIsolated { ShelfIntentCore.latest(store: s)?.id }, older.id)
        XCTAssertTrue(StatusItemController.copyLastEnabled(store: s), "Çöp'teki en yeni kare menüyü pasifleştirmez")
    }

    // 7. Rafa taşı alt menüsü: ortak hedef + representedObject, statik havuz yok
    func testMoveSubmenuItemsUseSharedTargetAndRepresentedObject() throws {
        let reg = ActionRegistry(prefs: Preferences(defaults: UserDefaults(suiteName: "dev.shotmori.tests.movetarget")!))
        let store = ShelfStore(fileURL: nil, maxItems: 5); let b = try XCTUnwrap(store.addShelf(name: "İş")).id
        let u = try existingFile(); defer { try? FileManager.default.removeItem(at: u) }
        store.add(ShelfItem(path: u.path, fileID: nil, capturedAt: Date()))
        let menu = reg.menu(for: store.items, store: store, anchor: nil, panel: nil)
        let sub = try XCTUnwrap(menu.items.first { $0.title == S.actionMoveToShelf }?.submenu)
        let toWork = try XCTUnwrap(sub.items.first { $0.title == "İş" })
        XCTAssertTrue(toWork.target === MoveToShelfMenuTarget.shared); XCTAssertNotNil(toWork.representedObject as? MoveToShelfTarget)
        _ = try XCTUnwrap(toWork.target as? NSObject).perform(try XCTUnwrap(toWork.action), with: toWork)
        XCTAssertEqual(store.shelves[1].items.count, 1); XCTAssertTrue(store.items.isEmpty); XCTAssertEqual(store.shelves[1].id, b)
    }

    // 8. Sekme çipi VoiceOver eylemleri
    func testTabChipExposesRenameAndCloseCustomActions() throws {
        let a = UUID(), b = UUID()
        let bar = ShelfTabBar(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        var closed: UUID?; bar.onCloseRequest = { closed = $0 }
        bar.entries = [entry(a, "Raf 1", 0), entry(b, "Raf 2", 0)]
        let chip = try XCTUnwrap(bar.subviews.compactMap { $0 as? TabChip }.first { !$0.isAdd })
        let actions = chip.accessibilityCustomActions() ?? []
        XCTAssertEqual(actions.map(\.name), [S.shelfRename, S.shelfClose])
        _ = actions[1].handler?(); XCTAssertEqual(closed, a)
        bar.entries = [entry(a, "Raf 1", 0)]
        let single = try XCTUnwrap(bar.subviews.compactMap { $0 as? TabChip }.first { !$0.isAdd })
        XCTAssertEqual(single.accessibilityCustomActions()?.map(\.name), [S.shelfRename], "tek raf kapatılamaz")
    }
}
