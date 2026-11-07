import XCTest
@testable import Shotmori

/// B adımı: ok eşlemesi, favori taşması, durum mesajı kuralları, kısayol kaydedicinin klavye yolu, favori sıra değişimi.
final class PanelBehaviorTests: XCTestCase {
    private func keyEvent(_ ch: String, code: UInt16, flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, characters: ch, charactersIgnoringModifiers: ch, isARepeat: false, keyCode: code)!
    }
    func testPanelKeyEquivalentSkipsHandleKeyWhileFieldEditorIsFirstResponder() {
        let panel = ShelfPanel(); var calls = 0
        panel.keyHandler = { _ in calls += 1; return true }
        let field = NSTextField(string: "Raf"); panel.contentView?.addSubview(field)
        XCTAssertTrue(panel.makeFirstResponder(field)); XCTAssertTrue(panel.firstResponder is NSText, "alan düzenleyicisi first responder olmalı")
        _ = panel.performKeyEquivalent(with: keyEvent("a", code: 0, flags: .command))
        _ = panel.performKeyEquivalent(with: keyEvent("c", code: 8, flags: .command))
        XCTAssertEqual(calls, 0, "ad düzenlenirken panel kısayolları devralmamalı")
    }
    func testPanelKeyEquivalentConsultsHandleKeyOnlyForCommandEvents() {
        let panel = ShelfPanel(); var calls = 0
        panel.keyHandler = { _ in calls += 1; return true }
        XCTAssertTrue(panel.performKeyEquivalent(with: keyEvent("c", code: 8, flags: .command)))
        XCTAssertEqual(calls, 1)
        _ = panel.performKeyEquivalent(with: keyEvent("\u{7F}", code: 51, flags: []))
        XCTAssertEqual(calls, 1, "komutsuz tuşlar performKeyEquivalent'ta işlenmez")
    }

    func testLeftArrowGoesToPreviousAndRightToNextInVisibleOrder() {
        // Şerit LTR: en yeni solda. Sol ok soldaki (bir önceki indeks), sağ ok sağdaki (bir sonraki indeks).
        func delta(_ code: UInt16, _ f: NSEvent.ModifierFlags = []) -> (Int, Bool)? {
            if case .move(let d, let e)? = ShelfKeyboard.command(keyCode: code, characters: nil, flags: f, editingText: false) { return (d, e) }; return nil
        }
        XCTAssertEqual(delta(123)?.0, -1); XCTAssertEqual(delta(124)?.0, +1); XCTAssertNil(delta(125))
        var sel = ShelfSelection(); let ids = (0..<4).map { _ in UUID() }
        sel.selectOnly(ids[2])
        XCTAssertEqual(sel.move(by: delta(123)!.0, order: ids, extend: false), ids[1], "sol ok soldakine gitmeli")
        let ext = delta(124, [.shift])!
        XCTAssertEqual(sel.move(by: ext.0, order: ids, extend: ext.1), ids[2]); XCTAssertEqual(sel.count, 2)
    }
    func testFavoritesOverflowKeepsOrderAndNeverTruncatesList() {
        let widths: [CGFloat] = [90, 120, 80, 110, 100]
        XCTAssertEqual(FavoritesLayout.visibleCount(widths: widths, available: 400, spacing: 8, reserved: 96), 2) // 96+90+8+120=314; +8+80=402 > 400
        XCTAssertEqual(FavoritesLayout.visibleCount(widths: widths, available: 1000, spacing: 8, reserved: 96), 5)
        XCTAssertEqual(FavoritesLayout.visibleCount(widths: widths, available: 150, spacing: 8, reserved: 96), 0)
        let favs = ["copy-image", "reveal-in-finder", "share", "open-with", "edit"]
        let visible = FavoritesLayout.visibleCount(widths: widths, available: 400, spacing: 8, reserved: 96)
        XCTAssertEqual(Array(favs.dropFirst(visible)), ["share", "open-with", "edit"], "taşanlar aynı sırayla")
    }
    func testStatusRulesPersistentUntilDismissOrNextActionAndBusyBlocks() {
        var s = StatusCenter()
        s.show(StatusMessage(text: "hata", kind: .persistent)); XCTAssertTrue(s.isPersistent); XCTAssertNil(StatusCenter.autoDismissDelay(.persistent))
        s.actionWillRun(); XCTAssertNil(s.current, "sonraki işlem kalıcı mesajı yeniler")
        s.show(StatusMessage(text: "OCR", kind: .busy)); XCTAssertTrue(s.isBusy); s.actionWillRun(); XCTAssertTrue(s.isBusy, "meşgul mesajı işlemle silinmez")
        s.busyEnded(); XCTAssertNil(s.current)
        s.show(StatusMessage(text: "ok", kind: .success)); XCTAssertEqual(StatusCenter.autoDismissDelay(.success), 1.6)
        s.show(StatusMessage(text: "boş", kind: .persistent)); s.dismiss(); XCTAssertNil(s.current)
    }
    private func key(_ code: UInt16, _ mods: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: mods, timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
    }
    func testKeyRecorderStartsWithSpaceOrReturnCancelsWithEscAndRecordsCombination() {
        let v = KeyRecorderNSView(frame: NSRect(x: 0, y: 0, width: 180, height: 26)); var recorded: (UInt32, NSEvent.ModifierFlags)?
        v.onRecord = { recorded = ($0, $1) }
        XCTAssertFalse(v.recording)
        v.keyDown(with: key(49)); XCTAssertTrue(v.recording, "Boşluk kaydı başlatmalı")
        v.keyDown(with: key(53)); XCTAssertFalse(v.recording, "Esc iptal etmeli"); XCTAssertNil(recorded)
        v.keyDown(with: key(36)); XCTAssertTrue(v.recording, "Return kaydı başlatmalı")
        v.keyDown(with: key(40, [.shift])); XCTAssertNil(recorded, "yalnız ⇧ kabul edilmez"); XCTAssertTrue(v.recording)
        v.keyDown(with: key(40, [.command, .shift])); XCTAssertEqual(recorded?.0, 40); XCTAssertEqual(recorded?.1, [.command, .shift]); XCTAssertFalse(v.recording)
    }
    func testAutoShowShelfOnNewScreenshot() {
        XCTAssertTrue(AppController.shouldAutoShowShelf(enabled: true, onboarding: false, panelVisible: false, mouseDown: false))
        XCTAssertFalse(AppController.shouldAutoShowShelf(enabled: false, onboarding: false, panelVisible: false, mouseDown: false), "Ayarlar'dan kapatılınca açılmaz")
        XCTAssertFalse(AppController.shouldAutoShowShelf(enabled: true, onboarding: true, panelVisible: false, mouseDown: false), "kurulum penceresi açıkken araya girmez")
        XCTAssertFalse(AppController.shouldAutoShowShelf(enabled: true, onboarding: false, panelVisible: true, mouseDown: false), "zaten açıksa yeniden konumlanmaz")
        XCTAssertFalse(AppController.shouldAutoShowShelf(enabled: true, onboarding: false, panelVisible: false, mouseDown: true), "sürükleme/tıklama sürerken açılmaz")
        let suite = "dev.shotmori.tests.autoshow"; let d = UserDefaults(suiteName: suite)!; d.removePersistentDomain(forName: suite); let p = Preferences(defaults: d)
        XCTAssertTrue(p.showShelfOnNewScreenshot, "varsayılan açık"); p.showShelfOnNewScreenshot = false; XCTAssertFalse(p.showShelfOnNewScreenshot)
        p.resetScreenshotsSection(); XCTAssertTrue(p.showShelfOnNewScreenshot, "Varsayılanlara dön açar")
        p.showShelfOnNewScreenshot = false
        var s = SettingsModel.Snapshot(prefs: p); XCTAssertFalse(s.showShelfOnNewScreenshot); s.showShelfOnNewScreenshot = true
        XCTAssertTrue(SettingsModel.needsSave(model: s, stored: SettingsModel.Snapshot(prefs: p)), "anahtar değişince yazılır")
        d.removePersistentDomain(forName: suite)
    }
    /// Panel bildirimindeki eylem bağlantısının başlığı eylemden; yeniden deneme yolu "Yeniden dene"yi korur.
    func testPanelNoticeActionTitleComesFromAction() {
        let suite = "dev.shotmori.tests.noticeaction"; let d = UserDefaults(suiteName: suite)!; d.removePersistentDomain(forName: suite); defer { d.removePersistentDomain(forName: suite) }
        let prefs = Preferences(defaults: d)
        let p = ShelfPanelController(store: ShelfStore(fileURL: nil, maxItems: 5), registry: ActionRegistry(prefs: prefs), prefs: prefs)
        p.showNotice("bilgi", action: NoticeAction(title: "Eylem") {})
        XCTAssertEqual(p.noticeActionTitleForTesting, "Eylem")
        p.showNotice("yükleme başarısız", retry: {})
        XCTAssertEqual(p.noticeActionTitleForTesting, S.cloudRetry)
        p.showNotice("kalıcı")
        XCTAssertNil(p.noticeActionTitleForTesting)
        p.showNotice("bilgi", action: NoticeAction(title: "Eylem") {})
        p.showToast("başka")
        XCTAssertNil(p.noticeActionTitleForTesting, "yeni bildirim eskisinin bağlantısını taşımaz")
    }
    func testShelfPanelControllerConformsToShelfPresenting() {
        let suite = "dev.shotmori.tests.presenting"; let d = UserDefaults(suiteName: suite)!; d.removePersistentDomain(forName: suite); defer { d.removePersistentDomain(forName: suite) }
        let prefs = Preferences(defaults: d)
        let p: ShelfPresenting = ShelfPanelController(store: ShelfStore(fileURL: nil, maxItems: 5), registry: ActionRegistry(prefs: prefs), prefs: prefs)
        XCTAssertFalse(p.isVisible); XCTAssertTrue(p.showsTabs)
    }
    func testStripPreferencesDefaultsAndReset() {
        let suite = "dev.shotmori.tests.strip"; let d = UserDefaults(suiteName: suite)!; d.removePersistentDomain(forName: suite); let p = Preferences(defaults: d)
        XCTAssertEqual(p.shelfStyle, .floating); XCTAssertEqual(p.newCaptureStripMode, .peek); XCTAssertTrue(p.stripRevealFromMenuBar)
        p.shelfStyle = .strip; p.newCaptureStripMode = .stay; p.stripRevealFromMenuBar = false
        XCTAssertEqual(p.shelfStyle, .strip); XCTAssertEqual(p.newCaptureStripMode, .stay); XCTAssertFalse(p.stripRevealFromMenuBar)
        p.resetScreenshotsSection()
        XCTAssertEqual(p.shelfStyle, .floating); XCTAssertEqual(p.newCaptureStripMode, .peek); XCTAssertTrue(p.stripRevealFromMenuBar, "Varsayılanlara dön üçünü de sıfırlar")
        d.set("x", forKey: "shelfStyle"); d.set("y", forKey: "newCaptureStripMode")
        XCTAssertEqual(p.shelfStyle, .floating, "geçersiz ham değer → yüzen"); XCTAssertEqual(p.newCaptureStripMode, .peek)
        p.resetScreenshotsSection()
        let base = SettingsModel.Snapshot(prefs: p)
        XCTAssertEqual(base.shelfStyle, .floating); XCTAssertEqual(base.newCaptureStripMode, .peek); XCTAssertTrue(base.stripRevealFromMenuBar)
        var s = base; s.shelfStyle = .strip; XCTAssertTrue(SettingsModel.needsSave(model: s, stored: base))
        s = base; s.newCaptureStripMode = .stay; XCTAssertTrue(SettingsModel.needsSave(model: s, stored: base))
        s = base; s.stripRevealFromMenuBar = false; XCTAssertTrue(SettingsModel.needsSave(model: s, stored: base))
        XCTAssertFalse(SettingsModel.needsSave(model: base, stored: base))
        d.removePersistentDomain(forName: suite)
    }
    /// Açılışta panel `init`indeki ilk reload klasör erişimi açılmadan çalışır: erişim kapısı bağlanmadan küçük resim istenmez.
    /// (İstenirse sandbox EPERM verir; aynı dosyayı isteyen şerit kartları bu başarısız isteğe katılır ve boş kalır.)
    func testThumbnailNotRequestedBeforeFolderAccessIsWired() {
        XCTAssertFalse(ShelfPanelController.requestsThumbnail(cached: false, isMissing: false, accessible: nil), "kapı yok → istek yok")
        XCTAssertTrue(ShelfPanelController.requestsThumbnail(cached: false, isMissing: false, accessible: true))
        XCTAssertFalse(ShelfPanelController.requestsThumbnail(cached: false, isMissing: true, accessible: true))
        XCTAssertFalse(ShelfPanelController.requestsThumbnail(cached: true, isMissing: false, accessible: true))
        XCTAssertFalse(ShelfPanelController.requestsThumbnail(cached: false, isMissing: false, accessible: false))
    }
    func testPinnedShelfIgnoresOutsideClickAndDrop() {
        XCTAssertTrue(ShelfPanelController.shouldHideOnOutsideClick(pinned: false)); XCTAssertFalse(ShelfPanelController.shouldHideOnOutsideClick(pinned: true))
        XCTAssertTrue(ShelfPanelController.shouldHideAfterDrop(hideAfterDrop: true, optionHeld: false, pinned: false))
        XCTAssertFalse(ShelfPanelController.shouldHideAfterDrop(hideAfterDrop: true, optionHeld: true, pinned: false))
        XCTAssertFalse(ShelfPanelController.shouldHideAfterDrop(hideAfterDrop: true, optionHeld: false, pinned: true))
        XCTAssertFalse(ShelfPanelController.shouldHideAfterDrop(hideAfterDrop: false, optionHeld: false, pinned: false))
        let suite = "dev.shotmori.tests.pin"; let d = UserDefaults(suiteName: suite)!; d.removePersistentDomain(forName: suite); let p = Preferences(defaults: d)
        XCTAssertFalse(p.keepShelfOpen, "varsayılan kapalı"); p.keepShelfOpen = true; XCTAssertTrue(p.keepShelfOpen); p.resetScreenshotsSection(); XCTAssertFalse(p.keepShelfOpen); d.removePersistentDomain(forName: suite)
    }
    func testActionMenuListsEachActionOnce() throws {
        let reg = ActionRegistry(prefs: Preferences(defaults: UserDefaults(suiteName: "dev.shotmori.tests.menuonce")!))
        let store = ShelfStore(fileURL: nil, maxItems: 5)
        let menu = reg.menu(for: [], store: store, anchor: nil, panel: nil)
        let titles = menu.items.filter { !$0.isSeparatorItem && $0.isEnabled || $0.representedObject != nil }.map(\.title)
        XCTAssertEqual(titles.count, Set(titles).count, "menüde yinelenen başlık yok: \(titles)")
    }
    func testMoveFavoriteUpDownStaysInBoundsAndKeepsMembership() {
        let suite = "dev.shotmori.tests.favmove"; let d = UserDefaults(suiteName: suite)!; d.removePersistentDomain(forName: suite)
        let p = Preferences(defaults: d); p.favoriteActionIDs = ["a", "b", "c"]
        var favs = p.favoriteActionIDs
        func move(_ i: Int, _ delta: Int) { let j = i + delta; guard favs.indices.contains(i), favs.indices.contains(j) else { return }; favs.move(fromOffsets: IndexSet(integer: i), toOffset: delta < 0 ? j : j + 1) }
        move(0, -1); XCTAssertEqual(favs, ["a", "b", "c"], "ilk öğe yukarı gitmez")
        move(2, +1); XCTAssertEqual(favs, ["a", "b", "c"], "son öğe aşağı gitmez")
        move(0, +1); XCTAssertEqual(favs, ["b", "a", "c"])
        move(2, -1); XCTAssertEqual(favs, ["b", "c", "a"])
        d.removePersistentDomain(forName: suite)
    }

    // MARK: Çoklu raf — sekme geçişi ve ad kısaltma
    func testShelfIndexMapsCommandDigits() {
        func idx(_ code: UInt16, _ f: NSEvent.ModifierFlags) -> Int? {
            if case .shelfIndex(let i)? = ShelfKeyboard.command(keyCode: code, characters: nil, flags: f, editingText: false) { return i }; return nil
        }
        XCTAssertEqual(idx(18, [.command]), 0); XCTAssertEqual(idx(28, [.command]), 7, "⌘8"); XCTAssertNil(idx(25, [.command]), "⌘9 yok: en çok 8 raf")
        XCTAssertEqual(idx(23, [.command]), 4, "⌘5")
        XCTAssertNil(idx(18, [])); XCTAssertNil(idx(18, [.command, .shift])); XCTAssertNil(idx(0, [.command]))
    }
    func testShelfIndexIgnoresOutOfRange() {
        XCTAssertNil(ShelfPanelController.shelfToActivate(index: 4, count: 2)); XCTAssertEqual(ShelfPanelController.shelfToActivate(index: 1, count: 2), 1); XCTAssertNil(ShelfPanelController.shelfToActivate(index: -1, count: 2))
    }
    func testTabDisplayNameTruncatesMiddle() {
        XCTAssertEqual(ShelfTabBar.displayName("Raf 1"), "Raf 1")
        XCTAssertEqual(ShelfTabBar.displayName("Müşteri sunumu ekranları"), "Müşte…nları")
        XCTAssertEqual(ShelfTabBar.displayName("123456789012"), "123456789012", "tam 12 karakter kısaltılmaz")
    }

    func testShelfCloseOptions() {
        let a = UUID(), b = UUID(), c = UUID()
        XCTAssertEqual(ShelfCloseDecision.options(shelfIDs: [a], closing: a, itemCount: 3), [], "tek raf kapatılamaz")
        XCTAssertEqual(ShelfCloseDecision.options(shelfIDs: [a, b], closing: b, itemCount: 0), [], "boş raf dialogsuz kapanır")
        XCTAssertEqual(ShelfCloseDecision.options(shelfIDs: [a, b, c], closing: b, itemCount: 2), [.cancel, .move(to: a), .drop])
        XCTAssertEqual(ShelfCloseDecision.options(shelfIDs: [a, b, c], closing: a, itemCount: 2), [.cancel, .move(to: b), .drop], "ilk raf kapanınca komşu sonraki")
        XCTAssertEqual(ShelfCloseDecision.option(for: .alertFirstButtonReturn, options: [.cancel, .move(to: a), .drop]), .cancel)
        XCTAssertEqual(ShelfCloseDecision.option(for: .alertSecondButtonReturn, options: [.cancel, .move(to: a), .drop]), .move(to: a))
        XCTAssertEqual(ShelfCloseDecision.option(for: .alertThirdButtonReturn, options: [.cancel, .move(to: a), .drop]), .drop)
    }

    // MARK: Çoklu raf — taşıma menüsü ve dahili sürükleme
    func testMoveSubmenuListsOtherShelvesThenNew() {
        let a = UUID(), b = UUID()
        let one = ActionRegistry.moveSubmenuEntries(shelves: [(a, "Raf 1", 2)], active: a); XCTAssertEqual(one.map(\.target), [nil]); XCTAssertEqual(one.map(\.title), [S.moveToNewShelf])
        let two = ActionRegistry.moveSubmenuEntries(shelves: [(a, "Raf 1", 2), (b, "İş", 0)], active: a)
        XCTAssertEqual(two.map(\.title), ["İş", S.moveToNewShelf], "0 öğede sayı eki yok"); XCTAssertEqual(two.map(\.target), [b, nil])
        let counted = ActionRegistry.moveSubmenuEntries(shelves: [(a, "Raf 1", 2), (b, "İş", 4)], active: a)
        XCTAssertEqual(counted.map(\.title), ["İş · 4", S.moveToNewShelf], "spec: diğer raflar (ad · N)")
    }
    func testInternalDropDoesNotCountAsHandoff() {
        XCTAssertFalse(ShelfPanelController.shouldCountAsHandoff(operation: .move, internalDropHandled: true))
        XCTAssertTrue(ShelfPanelController.shouldCountAsHandoff(operation: .copy, internalDropHandled: false))
        XCTAssertFalse(ShelfPanelController.shouldCountAsHandoff(operation: [], internalDropHandled: false))
    }
    func testMenuListsMoveToShelfOnceWithTwoShelves() throws {
        let reg = ActionRegistry(prefs: Preferences(defaults: UserDefaults(suiteName: "dev.shotmori.tests.menumove")!))
        let store = ShelfStore(fileURL: nil, maxItems: 5); _ = try XCTUnwrap(store.addShelf(name: "İş"))
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("mv-\(UUID()).png"); try Data([1]).write(to: tmp); defer { try? FileManager.default.removeItem(at: tmp) }
        store.add(ShelfItem(path: tmp.path, fileID: nil, capturedAt: Date()))
        let menu = reg.menu(for: store.items, store: store, anchor: nil, panel: nil)
        let titles = menu.items.filter { !$0.isSeparatorItem }.map(\.title)
        XCTAssertEqual(titles.count, Set(titles).count, "yinelenen başlık yok: \(titles)")
        let move = try XCTUnwrap(menu.items.first { $0.title == S.actionMoveToShelf }); XCTAssertEqual(move.submenu?.items.filter { !$0.isSeparatorItem }.map(\.title), ["İş", S.moveToNewShelf])
        let empty = reg.menu(for: [], store: store, anchor: nil, panel: nil); let mv = try XCTUnwrap(empty.items.first { $0.title.hasPrefix(S.actionMoveToShelf) }); XCTAssertFalse(mv.isEnabled); XCTAssertNil(mv.submenu)
    }

    // MARK: Son inceleme düzeltmeleri
    func testTabChipMakesNonActivatingPanelKeyOnClick() { XCTAssertTrue(TabChip(title: "x", isAdd: false).needsPanelToBecomeKey) }
    func testChipWidthsShrinkProportionallyWhenOverflowing() {
        XCTAssertEqual(ShelfTabBar.chipWidths(natural: [100, 100, 100], available: 400, spacing: 6, minimum: 44), [100, 100, 100], "sığıyorsa dokunulmaz")
        let w = ShelfTabBar.chipWidths(natural: Array(repeating: 100, count: 8), available: 400, spacing: 6, minimum: 44)
        XCTAssertEqual(w.count, 8); XCTAssertEqual(w.reduce(0, +) + 7 * 6, 400, accuracy: 0.01, "toplam alana sığar"); XCTAssertEqual(w[0], w[7])
        let tight = ShelfTabBar.chipWidths(natural: Array(repeating: 100, count: 8), available: 200, spacing: 6, minimum: 44)
        XCTAssertEqual(tight, Array(repeating: 44, count: 8), "en az genişliğin altına inmez")
        let mixed = ShelfTabBar.chipWidths(natural: [40, 200], available: 150, spacing: 6, minimum: 44)
        XCTAssertEqual(mixed[0], 40, accuracy: 0.01, "zaten dar olan daralmaz"); XCTAssertEqual(mixed[1], 104, accuracy: 0.01)
    }
    func testMoveStringsHaveNoHardcodedSuffixAndSingularForms() {
        XCTAssertFalse(S.movedToShelfToast(1, "Raf 2").contains("”e ")); XCTAssertFalse(S.shelfCloseMove("Raf 1").contains("”e "))
        XCTAssertFalse(S.shelfCloseBody(1).contains("1 images")); XCTAssertFalse(S.movedToShelfToast(1, "X").contains("1 images")); XCTAssertFalse(S.shelfTabAX("X", 1).contains("1 images"))
    }
    // MARK: Çoklu raf Aşama 2 — ayrı pencere
    func testNextActiveSkipsDetachedShelves() {
        let a = UUID(), b = UUID(), c = UUID()
        XCTAssertEqual(ShelfPanelController.nextActive(after: b, in: [a, b, c], detached: [a]), c)
        XCTAssertEqual(ShelfPanelController.nextActive(after: b, in: [a, b, c], detached: [a, c]), nil, "hepsi pencerede: ana panel boş raf uyarısı")
        XCTAssertEqual(ShelfPanelController.nextActive(after: b, in: [a, b, c], detached: []), a, "önce önceki komşu")
        XCTAssertEqual(ShelfPanelController.nextActive(after: a, in: [a, b, c], detached: []), b, "ilk raf ayrılınca sonraki")
    }
    func testCanDetachRequiresAnotherAttachedShelf() {
        let a = UUID(), b = UUID()
        XCTAssertTrue(ShelfPanelController.canDetach(a, in: [a, b], detached: []))
        XCTAssertFalse(ShelfPanelController.canDetach(a, in: [a, b], detached: [b]), "son takılı raf ayrılamaz")
        XCTAssertFalse(ShelfPanelController.canDetach(a, in: [a, b], detached: [a]), "zaten pencerede")
        XCTAssertFalse(ShelfPanelController.canDetach(a, in: [a], detached: []), "tek raf")
    }
    func testStoreNotifiesEveryObserverUntilRemoved() throws {
        let store = ShelfStore(fileURL: nil, maxItems: 5)
        var first = 0, second = 0
        let t1 = store.addObserver { first += 1 }
        let t2 = store.addObserver { second += 1 }
        _ = try XCTUnwrap(store.addShelf(name: "İş"))
        XCTAssertEqual(first, 1); XCTAssertEqual(second, 1)
        store.removeObserver(t1)
        store.renameShelf(id: store.shelves[1].id, to: "Ev")
        XCTAssertEqual(first, 1, "çıkarılan gözlemci bir daha çağrılmaz"); XCTAssertEqual(second, 2)
        store.removeObserver(t2); store.removeObserver(t1) // iki kez çıkarmak zararsız
        store.setActiveShelf(id: store.shelves[1].id); XCTAssertEqual(second, 2)
    }
    func testDetachedPanelShowsOnlyItsShelfAndIsPinned() throws {
        let suite = "dev.shotmori.tests.detached"; let d = UserDefaults(suiteName: suite)!; d.removePersistentDomain(forName: suite); defer { d.removePersistentDomain(forName: suite) }
        let prefs = Preferences(defaults: d); prefs.keepShelfOpen = false
        let reg = ActionRegistry(prefs: prefs)
        let store = ShelfStore(fileURL: nil, maxItems: 5)
        let work = try XCTUnwrap(store.addShelf(name: "İş"))
        store.add(ShelfItem(path: "/nonexistent/a.png", fileID: nil, capturedAt: Date()), to: work.id)
        store.add(ShelfItem(path: "/nonexistent/b.png", fileID: nil, capturedAt: Date())) // etkin raf (Raf 1)
        let main = ShelfPanelController(store: store, registry: reg, prefs: prefs, mode: .main)
        let det = ShelfPanelController(store: store, registry: reg, prefs: prefs, mode: .detached(work.id))
        XCTAssertEqual(main.displayedShelfID, store.activeShelfID); XCTAssertEqual(main.displayedItems.map(\.path), ["/nonexistent/b.png"])
        XCTAssertEqual(det.displayedShelfID, work.id); XCTAssertEqual(det.displayedItems.map(\.path), ["/nonexistent/a.png"])
        XCTAssertTrue(det.isPinned, "ayrılmış panel zorunlu iğneli"); XCTAssertFalse(main.isPinned)
        XCTAssertTrue(det.showsTabs == false); XCTAssertTrue(main.showsTabs)
        XCTAssertEqual(det.panel.title, "İş")
        store.renameShelf(id: work.id, to: "Ev"); XCTAssertEqual(det.panel.title, "İş", "gizliyken gözlemci çizmez")
        var reattached = 0; det.onReattach = { reattached += 1 }
        det.show(takeKey: false); XCTAssertTrue(det.isVisible); XCTAssertEqual(det.panel.title, "Ev", "show: bekleyen değişiklik yansır")
        store.renameShelf(id: work.id, to: "Okul"); XCTAssertEqual(det.panel.title, "Okul", "görünürken gözlemci başlığı yeniler")
        det.hide(reason: "test"); XCTAssertEqual(reattached, 1, "Gizle/Esc ayrılmış paneli sekmeye geri takar"); XCTAssertFalse(det.isVisible)
        main.hide(reason: "test")
    }
    // MARK: Aşama 2 inceleme düzeltmeleri
    private func detachedPair(suite: String) throws -> (ShelfStore, ActionRegistry, ShelfPanelController, ShelfPanelController, UUID) {
        let d = UserDefaults(suiteName: suite)!; d.removePersistentDomain(forName: suite)
        let prefs = Preferences(defaults: d); let reg = ActionRegistry(prefs: prefs)
        let store = ShelfStore(fileURL: nil, maxItems: 5)
        let work = try XCTUnwrap(store.addShelf(name: "İş"))
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("det-\(UUID()).png"); try Data([1]).write(to: tmp)
        store.add(ShelfItem(path: tmp.path, fileID: nil, capturedAt: Date()), to: work.id)
        let main = ShelfPanelController(store: store, registry: reg, prefs: prefs, mode: .main)
        let det = ShelfPanelController(store: store, registry: reg, prefs: prefs, mode: .detached(work.id))
        return (store, reg, main, det, work.id)
    }
    func testActionContextAndMoveMenuUseDisplayedShelf() throws {
        let (store, reg, main, det, work) = try detachedPair(suite: "dev.shotmori.tests.detctx")
        XCTAssertEqual(ActionContext(items: [], anchorView: nil, store: store, panel: det).shelfID, work, "ayrılmış panelde eylemler kendi rafında çalışır (Rafı temizle)")
        XCTAssertEqual(ActionContext(items: [], anchorView: nil, store: store, panel: main).shelfID, store.activeShelfID)
        XCTAssertNil(ActionContext(items: [], anchorView: nil, store: store, panel: nil).shelfID)
        let menu = reg.menu(for: det.displayedItems, store: store, anchor: nil, panel: det)
        let move = try XCTUnwrap(menu.items.first { $0.title == S.actionMoveToShelf })
        XCTAssertEqual(move.submenu?.items.filter { !$0.isSeparatorItem }.map(\.title), [S.shelfDefaultName(1), S.moveToNewShelf], "hedefler: pencerenin kendi rafı hariç")
    }
    func testInternalDropMarksDragSourceController() throws {
        let (_, _, main, det, _) = try detachedPair(suite: "dev.shotmori.tests.detdrop")
        main.noteInternalDrop(from: det)
        XCTAssertTrue(det.internalDropHandled, "ayrılmış panelden ana sekmeye bırakma: kaynak panel aktarım saymaz"); XCTAssertFalse(main.internalDropHandled)
        main.noteInternalDrop(from: nil); XCTAssertTrue(main.internalDropHandled, "kaynak bilinmiyorsa kendisi")
    }
    func testOutsideDragIsCopyOnlyNeverMoveOrGeneric() {
        XCTAssertEqual(ShelfPanelController.dragOperationMask(outside: true, allowsInternalMove: true), .copy)
        XCTAssertFalse(ShelfPanelController.dragOperationMask(outside: true, allowsInternalMove: false).contains(.generic))
        XCTAssertEqual(ShelfPanelController.dragOperationMask(outside: false, allowsInternalMove: true), .move)
        XCTAssertEqual(ShelfPanelController.dragOperationMask(outside: false, allowsInternalMove: false), [])
    }
}

extension PanelBehaviorTests {
    func testMainMenuHasStandardEditActions() throws {
        let menu = MainMenu.build()
        let edit = try XCTUnwrap(menu.items.compactMap(\.submenu).first { $0.title == S.menuEdit })
        func item(_ sel: String) -> NSMenuItem? { edit.items.first { $0.action.map(NSStringFromSelector) == sel } }
        for (sel, key) in [("undo:", "z"), ("cut:", "x"), ("copy:", "c"), ("paste:", "v"), ("selectAll:", "a")] {
            let it = try XCTUnwrap(item(sel), sel); XCTAssertEqual(it.keyEquivalent, key); XCTAssertEqual(it.keyEquivalentModifierMask, [.command])
        }
        let redo = try XCTUnwrap(item("redo:")); XCTAssertEqual(redo.keyEquivalent, "z"); XCTAssertEqual(redo.keyEquivalentModifierMask, [.command, .shift])
    }
}

// MARK: G4 inceleme bulguları: ⌘W, menü ayırıcıları, kayıp kart simgesi, Ayarlar kayıt kuralları
extension PanelBehaviorTests {
    func testCommandWHidesShelfPanel() {
        let panel = ShelfPanel(); var calls = 0; panel.onClose = { calls += 1 }
        let mi = NSMenuItem(title: "Kapat", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        XCTAssertTrue(panel.validateMenuItem(mi), "kapatma düğmesiz panelde ⌘W etkin")
        XCTAssertTrue(panel.validateUserInterfaceItem(mi))
        panel.performClose(nil); XCTAssertEqual(calls, 1, "⌘W paneli gizler (ayrılmış raf hide yoluyla sekmeye döner)")
    }
    func testActionMenuHasNoAdjacentSeparatorsWithoutCloud() {
        let groups = [["a", "b"], ["upload-drive", "upload-s3"], ["c"]]
        XCTAssertEqual(ActionRegistry.visibleGroups(groups) { !$0.hasPrefix("upload-") }, [["a", "b"], ["c"]])
        XCTAssertEqual(ActionRegistry.visibleGroups([["x"], []]) { _ in true }, [["x"]])
        let reg = ActionRegistry(prefs: Preferences(defaults: UserDefaults(suiteName: "dev.shotmori.tests.menusep")!))
        let menu = reg.menu(for: [], store: ShelfStore(fileURL: nil, maxItems: 5), anchor: nil, panel: nil)
        let seps = menu.items.map(\.isSeparatorItem)
        XCTAssertFalse(zip(seps, seps.dropFirst()).contains { $0 && $1 }, "art arda iki ayırıcı yok")
        XCTAssertFalse(seps.last ?? false, "menü ayırıcıyla bitmez")
    }
    func testMissingSymbolMatchesBuildFlavor() {
        #if SHOTMORI_CLOUD
        XCTAssertEqual(ThumbnailItemView.missingSymbol(localTrashed: true), "icloud")
        #else
        XCTAssertEqual(ThumbnailItemView.missingSymbol(localTrashed: true), "photo", "bulutsuz derlemede bulut simgesi yok")
        #endif
        XCTAssertEqual(ThumbnailItemView.missingSymbol(localTrashed: false), "photo")
    }
    func testSaveSkipsWhenModelEqualsPrefs() {
        let base = SettingsModel.Snapshot(hideAfterDrop: true, keepShelfOpen: false, favorites: ["copy-image", "share"], hotKeyCode: 9, hotKeyModifiers: [.command, .shift])
        XCTAssertFalse(SettingsModel.needsSave(model: base, stored: base), "aynı değerler → yazma ve bildirim yok")
        var v = base; v.hideAfterDrop.toggle(); XCTAssertTrue(SettingsModel.needsSave(model: v, stored: base))
        v = base; v.keepShelfOpen.toggle(); XCTAssertTrue(SettingsModel.needsSave(model: v, stored: base))
        v = base; v.favorites = ["share", "copy-image"]; XCTAssertTrue(SettingsModel.needsSave(model: v, stored: base), "sıra da değişikliktir")
        v = base; v.hotKeyCode = 1; XCTAssertTrue(SettingsModel.needsSave(model: v, stored: base))
        v = base; v.hotKeyModifiers = [.command, .option]; XCTAssertTrue(SettingsModel.needsSave(model: v, stored: base))
        let suite = "dev.shotmori.tests.snapshot"; let d = UserDefaults(suiteName: suite)!; d.removePersistentDomain(forName: suite); let p = Preferences(defaults: d)
        let s = SettingsModel.Snapshot(prefs: p); XCTAssertEqual(s.keepShelfOpen, p.keepShelfOpen); XCTAssertEqual(s.favorites, p.favoriteActionIDs); XCTAssertEqual(s.hotKeyModifiers, p.hotKeyModifiers)
        d.removePersistentDomain(forName: suite)
    }
    func testMaxItemsDecision() {
        XCTAssertEqual(SettingsModel.decide(model: 30, stored: 30, dropped: 0), .none)
        XCTAssertEqual(SettingsModel.decide(model: 30, stored: 30, dropped: 3), .none, "değişiklik yoksa düşen sayılmaz")
        XCTAssertEqual(SettingsModel.decide(model: 40, stored: 30, dropped: 0), .apply)
        XCTAssertEqual(SettingsModel.decide(model: 20, stored: 30, dropped: 0), .apply, "düşen öğe yoksa onaysız uygulanır")
        XCTAssertEqual(SettingsModel.decide(model: 10, stored: 30, dropped: 4), .confirm(dropped: 4))
    }
    func testMainMenuAppAndWindowItems() throws {
        let menu = MainMenu.build()
        let app = try XCTUnwrap(menu.items.first?.submenu), win = try XCTUnwrap(menu.items.compactMap(\.submenu).first { $0.title == S.menuWindow })
        func check(_ m: NSMenu, _ sel: Selector, _ key: String) throws {
            let it = try XCTUnwrap(m.items.first { $0.action == sel }, NSStringFromSelector(sel)); XCTAssertEqual(it.keyEquivalent, key); XCTAssertEqual(it.keyEquivalentModifierMask, [.command])
        }
        try check(app, #selector(AppDelegate.openSettings), ","); try check(app, #selector(NSApplication.hide(_:)), "h"); try check(app, #selector(NSApplication.terminate(_:)), "q")
        try check(win, #selector(NSWindow.performClose(_:)), "w"); try check(win, #selector(NSWindow.performMiniaturize(_:)), "m")
    }
}
