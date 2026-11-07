import XCTest
@testable import Shotmori

/// Sandbox klasör erişimi: bookmark, tercih anahtarları, erişim oturumu. Gerçek tercihlere/klasörlere dokunmaz.
final class FolderAccessTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var prefs: Preferences!
    private var tmp: URL!

    override func setUp() {
        suiteName = "dev.shotmori.tests.folder.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName); prefs = Preferences(defaults: defaults)
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("folder-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: Task 1 — FolderBookmark + tercihler
    func testBookmarkRoundTripResolvesSameDirectory() throws {
        let data = try FolderBookmark.make(for: tmp)
        let r = try XCTUnwrap(FolderBookmark.resolve(data))
        XCTAssertEqual(r.url.standardizedFileURL.resolvingSymlinksInPath().path, tmp.standardizedFileURL.resolvingSymlinksInPath().path)
        XCTAssertFalse(r.isStale)
    }
    func testResolveGarbageReturnsNil() {
        XCTAssertNil(FolderBookmark.resolve(Data([1, 2, 3])))
    }
    func testSetFolderKeepsThreePrevious() {
        let d = (1...5).map { Data([UInt8($0)]) }
        d.forEach { prefs.setFolderBookmark($0) }
        XCTAssertEqual(prefs.folderBookmark, d[4])
        XCTAssertEqual(prefs.previousFolderBookmarks, [d[3], d[2], d[1]])
        prefs.setFolderBookmark(d[4])
        XCTAssertEqual(prefs.folderBookmark, d[4])
        XCTAssertEqual(prefs.previousFolderBookmarks, [d[3], d[2], d[1]], "aynı veri yeniden seçilince liste değişmemeli")
    }
    func testResetScreenshotsSectionKeepsFolder() {
        prefs.setFolderBookmark(Data([9]))
        prefs.resetScreenshotsSection()
        XCTAssertEqual(prefs.folderBookmark, Data([9]), "sıfırlama izlemeyi durdurmamalı")
    }

    // MARK: Task 2 — FolderAccess + FolderAccessSession
    func testNoBookmarkNeedsSelectionWithDesktopSuggestion() {
        XCTAssertEqual(FolderAccess(prefs: prefs).resolve(), .needsSelection(suggested: AppPaths.realHome.appendingPathComponent("Desktop", isDirectory: true)))
    }
    func testChooseThenResolveIsReady() throws {
        let a = FolderAccess(prefs: prefs)
        try a.choose(tmp)
        guard case .ready(let u) = a.resolve() else { return XCTFail("hazır olmalı") }
        XCTAssertEqual(u.resolvingSymlinksInPath().path, tmp.resolvingSymlinksInPath().path)
    }
    func testDeletedFolderNeedsSelection() throws {
        let a = FolderAccess(prefs: prefs)
        try a.choose(tmp)
        try FileManager.default.removeItem(at: tmp)
        guard case .needsSelection = a.resolve() else { return XCTFail("silinmiş klasör seçim istemeli") }
    }
    func testPreviousFoldersResolveAfterChange() throws {
        let other = tmp.appendingPathComponent("ikinci", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let a = FolderAccess(prefs: prefs)
        try a.choose(tmp); try a.choose(other)
        XCTAssertEqual(a.previousFolders().map { $0.resolvingSymlinksInPath().path }, [tmp.resolvingSymlinksInPath().path])
    }
    func testSessionActivateDiffsScopes() {
        var started: [String] = [], stopped: [String] = []
        let s = FolderAccessSession(start: { started.append($0.lastPathComponent); return true }, stop: { stopped.append($0.lastPathComponent) })
        let a = URL(fileURLWithPath: "/x/a"), b = URL(fileURLWithPath: "/x/b"), c = URL(fileURLWithPath: "/x/c")
        s.activate([a, b])
        XCTAssertEqual(started, ["a", "b"])
        s.activate([b, c])
        XCTAssertEqual(stopped, ["a"]); XCTAssertEqual(started, ["a", "b", "c"], "ortak kapsam yeniden başlamamalı")
        s.endAll()
        XCTAssertEqual(Set(stopped), ["a", "b", "c"]); XCTAssertTrue(s.active.isEmpty)
    }

    // MARK: Klasör yokken yönlendirme
    func testFolderPromptOnlyWhenNoFolder() {
        XCTAssertEqual(FolderPrompt.menuTitle(folder: nil), S.menuChooseFolder)
        XCTAssertNil(FolderPrompt.menuTitle(folder: tmp))
        XCTAssertEqual(FolderPrompt.emptyBody(folder: nil, otherwise: "x"), S.emptyNoFolderBody)
        XCTAssertEqual(FolderPrompt.emptyBody(folder: tmp, otherwise: "x"), "x")
    }
    /// Popover Yardım menüsü: "Panodan ekle" hep; "İzlenen klasörü seç…" yalnız klasör yokken ve en üstte.
    func testPopoverHelpMenuOffersClipboardAndFolderPrompt() {
        let titles = { (has: Bool) in MenuBarPopoverViewController.helpMenu(hasFolder: has, popover: nil, app: nil).items.filter { !$0.isSeparatorItem }.map(\.title) }
        XCTAssertEqual(titles(false).first, S.menuChooseFolder); XCTAssertTrue(titles(false).contains(S.menuAddFromClipboard))
        XCTAssertFalse(titles(true).contains(S.menuChooseFolder)); XCTAssertTrue(titles(true).contains(S.menuAddFromClipboard))
    }

    // MARK: İnceleme küçük bulguları
    /// Aynı klasör farklı baytlı bookmark'la yeniden seçilince önceki listeye ikinci kez girmez (yol üzerinden tekilleştirme).
    func testReselectingSameFolderWithDifferentBookmarkBytesDoesNotDuplicate() throws {
        let other = tmp.appendingPathComponent("ikinci", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let plain = try tmp.bookmarkData() // güvenlik kapsamsız: farklı baytlar, aynı klasör
        prefs.setFolderBookmark(plain)
        let a = FolderAccess(prefs: prefs)
        try a.choose(other); try a.choose(tmp)
        XCTAssertEqual(a.previousFolders().map { $0.resolvingSymlinksInPath().path }, [other.resolvingSymlinksInPath().path])
    }
    /// Apple kuralı: yalnız `true` dönen start için stop.
    func testSessionStopsOnlySuccessfulStarts() {
        var stopped: [String] = []
        let s = FolderAccessSession(start: { $0.lastPathComponent != "a" }, stop: { stopped.append($0.lastPathComponent) })
        s.activate([URL(fileURLWithPath: "/x/a"), URL(fileURLWithPath: "/x/b")])
        s.endAll()
        XCTAssertEqual(stopped, ["b"])
    }
    /// Güncel klasör kaybolsa da önceki klasörlerin kapsamı açık kalır (eski raf öğeleri okunur).
    func testScopesKeepPreviousWhenNeedsSelection() throws {
        let other = tmp.appendingPathComponent("ikinci", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let a = FolderAccess(prefs: prefs)
        try a.choose(tmp); try a.choose(other)
        let paths = a.scopes(for: .needsSelection(suggested: tmp)).map { $0.resolvingSymlinksInPath().path }
        XCTAssertEqual(paths, [tmp.resolvingSymlinksInPath().path])
        XCTAssertEqual(a.scopes(for: .ready(other)).map { $0.resolvingSymlinksInPath().path }, [other, tmp].map { $0.resolvingSymlinksInPath().path })
    }
    /// Klasör Çöp'e taşınırsa bookmark onu izler; Çöp'teki klasör izlenmez.
    func testFolderInTrashNeedsSelection() throws {
        let trashed = tmp.appendingPathComponent(".Trash/eski", isDirectory: true)
        try FileManager.default.createDirectory(at: trashed, withIntermediateDirectories: true)
        let a = FolderAccess(prefs: prefs)
        try a.choose(trashed)
        guard case .needsSelection = a.resolve() else { return XCTFail("Çöp'teki klasör seçim istemeli") }
    }
    /// Erişim kapsamı dışındaki raf öğesi "eksik" sayılır; Shotmori'nin kendi klasörü her zaman erişilebilir.
    func testSessionCoversPathsInsideActiveScopesAndExtraRoots() {
        let s = FolderAccessSession(start: { _ in true }, stop: { _ in })
        s.activate([URL(fileURLWithPath: "/u/Shots", isDirectory: true)])
        let own = URL(fileURLWithPath: "/c/Shotmori", isDirectory: true)
        XCTAssertTrue(s.covers("/u/Shots/a.png", extraRoots: [own]))
        XCTAssertTrue(s.covers("/c/Shotmori/Türevler/b.png", extraRoots: [own]))
        XCTAssertFalse(s.covers("/u/Shots2/c.png", extraRoots: [own]))
        XCTAssertFalse(s.covers("/u/Eski/d.png", extraRoots: [own]))
    }
    // MARK: Görev 4 — erişim kapsamı içinde denetim
    /// Varlık denetimi security scope açıkken yapılır (kapsam dışı `fileExists` sandbox'ta yanlış "yok" verebilir): bir start, bir stop.
    func testResolveChecksExistenceInsideScope() throws {
        let a = FolderAccess(prefs: prefs)
        try a.choose(tmp)
        var started = 0, stopped = 0
        let st = a.resolve(start: { _ in started += 1; return true }, stop: { _ in stopped += 1 })
        guard case .ready = st else { return XCTFail("hazır olmalı") }
        XCTAssertEqual(started, 1); XCTAssertEqual(stopped, 1)
    }
    func testResolveDoesNotStopWhenStartFailed() throws {
        let a = FolderAccess(prefs: prefs)
        try a.choose(tmp)
        var stopped = 0
        _ = a.resolve(start: { _ in false }, stop: { _ in stopped += 1 })
        XCTAssertEqual(stopped, 0, "yalnız başarılı start için stop")
    }
    func testIsReadableTrueForDirFalseForMissing() {
        XCTAssertTrue(FolderAccess.isReadable(tmp))
        XCTAssertFalse(FolderAccess.isReadable(tmp.appendingPathComponent("yok", isDirectory: true)))
    }
    /// Erişilemeyen klasördeki öğe "kapsam dışı" sayılır → AppController'ın budama kuralı onu düşürmez.
    func testUnreachableFolderDoesNotPruneItems() throws {
        let s = ShelfStore(fileURL: tmp.appendingPathComponent("shelf.json"), maxItems: 50)
        s.add(ShelfItem(path: "/bagli-degil/yok.png", fileID: nil, capturedAt: Date()))
        XCTAssertEqual(s.pruneMissing { _ in false }, 0)
        XCTAssertEqual(s.allItems.count, 1)
    }
    func testRelaunchGateParsesWaitPID() {
        XCTAssertEqual(RelaunchGate.waitPID(arguments: ["Shotmori", RelaunchGate.argument, "4321"]), 4321)
        XCTAssertNil(RelaunchGate.waitPID(arguments: ["Shotmori"]))
        XCTAssertNil(RelaunchGate.waitPID(arguments: ["Shotmori", RelaunchGate.argument, "x"]))
    }
    func testRelaunchGateWaitsUntilOldInstanceExits() {
        var checks = 0
        let ok = RelaunchGate.wait(for: 1, timeout: 2, interval: 0.001) { _ in checks += 1; return checks < 3 }
        XCTAssertTrue(ok); XCTAssertEqual(checks, 3)
        XCTAssertFalse(RelaunchGate.wait(for: 1, timeout: 0.01, interval: 0.001) { _ in true }, "zaman aşımı")
    }

    func testRelaunchGateTreatsEPERMAsAlive() {
        XCTAssertTrue(RelaunchGate.isAlive(killResult: -1, errno: EPERM))
        XCTAssertTrue(RelaunchGate.isAlive(killResult: 0, errno: 0))
        XCTAssertFalse(RelaunchGate.isAlive(killResult: -1, errno: ESRCH))
    }
    func testCorruptHotKeyPrefsDoNotTrap() {
        let suite = "dev.shotmori.tests.hotkey.\(UUID().uuidString)"; let d = UserDefaults(suiteName: suite)!; defer { d.removePersistentDomain(forName: suite) }
        d.set(-5, forKey: Preferences.Key.hotKeyCode.rawValue); d.set(-1, forKey: Preferences.Key.hotKeyModifiers.rawValue)
        let p = Preferences(defaults: d)
        XCTAssertEqual(p.hotKeyCode, 0)
        XCTAssertEqual(p.hotKeyModifiers.rawValue, UInt.max, "-1 → truncatingIfNeeded: tuzak yok, tanımlı değer")
    }

    // MARK: İnceleme küçük bulguları (G1)
    func testVolumeChangeAffectsOnlyWatchedVolume() {
        let watched = URL(fileURLWithPath: "/Volumes/Disk/Shots", isDirectory: true)
        XCTAssertFalse(AppController.volumeChangeAffectsWatch(folder: watched, volume: URL(fileURLWithPath: "/Volumes/DMG", isDirectory: true)), "ilgisiz DMG")
        XCTAssertFalse(AppController.volumeChangeAffectsWatch(folder: watched, volume: URL(fileURLWithPath: "/Volumes/Dis", isDirectory: true)), "yalnız dizin sınırında eşleşir")
        XCTAssertTrue(AppController.volumeChangeAffectsWatch(folder: watched, volume: URL(fileURLWithPath: "/Volumes/Disk/", isDirectory: true)))
        XCTAssertTrue(AppController.volumeChangeAffectsWatch(folder: URL(fileURLWithPath: "/Volumes/Disk", isDirectory: true), volume: URL(fileURLWithPath: "/Volumes/Disk", isDirectory: true)), "klasör diskin kökü")
        XCTAssertTrue(AppController.volumeChangeAffectsWatch(folder: nil, volume: URL(fileURLWithPath: "/Volumes/DMG", isDirectory: true)), "klasör bekleniyor")
        XCTAssertTrue(AppController.volumeChangeAffectsWatch(folder: watched, volume: nil), "disk bilinmiyor")
        XCTAssertFalse(AppController.volumeChangeAffectsWatch(folder: URL(fileURLWithPath: "/Users/u/Desktop", isDirectory: true), volume: URL(fileURLWithPath: "/", isDirectory: true)), "kök disk önekle eşleşmez")
    }
    func testRootRenameRebasesOnlyOnRestartWhenOldFolderGone() throws {
        let old = URL(fileURLWithPath: "/u/Shots", isDirectory: true), new = URL(fileURLWithPath: "/u/Kareler", isDirectory: true)
        let r = try XCTUnwrap(AppController.rebaseRoot(previous: old, current: new, restart: true, previousExists: false))
        XCTAssertEqual(r.from, "/u/Shots"); XCTAssertEqual(r.to, "/u/Kareler")
        XCTAssertNil(AppController.rebaseRoot(previous: old, current: new, restart: true, previousExists: true), "eski klasör duruyor: kullanıcı başka klasör seçti")
        XCTAssertNil(AppController.rebaseRoot(previous: old, current: new, restart: false, previousExists: false), "yeniden kurulum değil (klasör değişimi)")
        XCTAssertNil(AppController.rebaseRoot(previous: old, current: old, restart: true, previousExists: false), "aynı klasör")
        XCTAssertNil(AppController.rebaseRoot(previous: nil, current: new, restart: true, previousExists: false))
        // Raf: eski kökteki öğe yeni köke bağlanır, kök dışındaki dokunulmaz.
        let s = ShelfStore(fileURL: tmp.appendingPathComponent("shelf.json"), maxItems: 50)
        s.add([ShelfItem(path: "/u/Shots2/x.png", fileID: "2", capturedAt: Date()), ShelfItem(path: "/u/Shots/a.png", fileID: "1", capturedAt: Date())])
        XCTAssertEqual(s.rebasePaths(from: r.from, to: r.to), 1)
        XCTAssertEqual(Set(s.allItems.map(\.path)), ["/u/Kareler/a.png", "/u/Shots2/x.png"])
        let reloaded = ShelfStore(fileURL: tmp.appendingPathComponent("shelf.json"), maxItems: 50)
        XCTAssertEqual(Set(reloaded.allItems.map(\.path)), ["/u/Kareler/a.png", "/u/Shots2/x.png"], "kalıcı")
    }
    func testPruneOnlyWhenFolderReady() {
        XCTAssertTrue(AppController.shouldPruneOnLaunch(.ready(tmp)))
        XCTAssertFalse(AppController.shouldPruneOnLaunch(.needsSelection(suggested: tmp)))
    }
}
