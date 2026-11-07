import XCTest
import CoreServices
@testable import Shotmori

final class WatcherLogicTests: XCTestCase {
    private func f(_ x: Int) -> FSEventStreamEventFlags { FSEventStreamEventFlags(x) }
    func testDirectChildOnly() {
        let folder = URL(fileURLWithPath: "/a/Desktop")
        XCTAssertTrue(ScreenshotWatcher.isDirectChild("/a/Desktop/x.png", of: folder))
        XCTAssertFalse(ScreenshotWatcher.isDirectChild("/a/Desktop/Arsiv/x.png", of: folder))
        XCTAssertFalse(ScreenshotWatcher.isDirectChild("/a/Desktop", of: folder))
        XCTAssertFalse(ScreenshotWatcher.isDirectChild("/a/DesktopX/x.png", of: folder))
        XCTAssertTrue(ScreenshotWatcher.isDirectChild("/a/Desktop/x.png", of: URL(fileURLWithPath: "/a/Desktop/")))
    }
    func testEventKind() {
        let mod = f(kFSEventStreamEventFlagItemModified), xat = f(kFSEventStreamEventFlagItemXattrMod)
        let ino = f(kFSEventStreamEventFlagItemInodeMetaMod), fin = f(kFSEventStreamEventFlagItemFinderInfoMod)
        for fl in [mod, xat, ino, fin, mod | xat | ino | fin] { XCTAssertEqual(ScreenshotWatcher.eventKind(flags: fl, existsNow: true), .ignore) }
        XCTAssertEqual(ScreenshotWatcher.eventKind(flags: f(kFSEventStreamEventFlagItemRemoved), existsNow: true), .candidate, "silinip aynı adla yeniden yazıldı")
        XCTAssertEqual(ScreenshotWatcher.eventKind(flags: f(kFSEventStreamEventFlagItemRemoved), existsNow: false), .removed)
        XCTAssertEqual(ScreenshotWatcher.eventKind(flags: f(kFSEventStreamEventFlagItemRenamed), existsNow: false), .removed)
        XCTAssertEqual(ScreenshotWatcher.eventKind(flags: f(kFSEventStreamEventFlagItemRenamed), existsNow: true), .candidate)
        XCTAssertEqual(ScreenshotWatcher.eventKind(flags: f(kFSEventStreamEventFlagItemCreated), existsNow: true), .candidate)
        XCTAssertEqual(ScreenshotWatcher.eventKind(flags: f(kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemModified), existsNow: true), .candidate)
    }

    /// Önbelleklenmiş kök yollarıyla doğrudan alt öğe: bağlantı üzerinden verilen kök de eşleşir.
    func testDirectChildWithCachedResolvedRoot() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("watch-root-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let root = dir.standardizedFileURL.path, resolved = dir.resolvingSymlinksInPath().path
        XCTAssertTrue(ScreenshotWatcher.isDirectChild(resolved + "/x.png", root: root, resolvedRoot: resolved))
        XCTAssertTrue(ScreenshotWatcher.isDirectChild(root + "/x.png", root: root, resolvedRoot: resolved))
        XCTAssertFalse(ScreenshotWatcher.isDirectChild(root + "/alt/x.png", root: root, resolvedRoot: resolved))
    }
    /// Kapalıyken gelenleri yakalama: işaretsiz ve gizli dosyalar elenir, `newerThan` dışlayıcı, en yeni önce, sınır işaret süzgecinden sonra.
    func testRecentScreenshotsFiltersSortsAndLimits() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("recent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let marker = try PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0)
        func make(_ name: String, _ offset: TimeInterval, marked: Bool) throws {
            let u = dir.appendingPathComponent(name); try Data([1, 2, 3]).write(to: u)
            try FileManager.default.setAttributes([.creationDate: t0 + offset], ofItemAtPath: u.path)
            if marked { XCTAssertEqual(marker.withUnsafeBytes { setxattr(u.path, ScreenshotFileInspector.markerXattr, $0.baseAddress, marker.count, 0, 0) }, 0) }
        }
        try make("eski.png", 0, marked: true)       // newerThan ile aynı an: dışlanır
        try make("a.png", 10, marked: true)
        try make("b.png", 20, marked: true)
        try make("isaretsiz.png", 30, marked: false) // en yeni ama ekran görüntüsü değil
        try make("c.png", 25, marked: true)
        try make(".gizli.png", 40, marked: true)
        try make("not.txt", 50, marked: true)
        let all = ScreenshotWatcher.recentScreenshots(in: dir, limit: 10, newerThan: t0)
        XCTAssertEqual(all.map(\.url.lastPathComponent), ["c.png", "b.png", "a.png"])
        let two = ScreenshotWatcher.recentScreenshots(in: dir, limit: 2, newerThan: t0)
        XCTAssertEqual(two.map(\.url.lastPathComponent), ["c.png", "b.png"], "sınır işaretsiz dosyayı saymaz")
        XCTAssertEqual(ScreenshotWatcher.recentScreenshots(in: dir, limit: 10).count, 4, "newerThan yoksa hepsi")
        XCTAssertTrue(ScreenshotWatcher.recentScreenshots(in: dir.appendingPathComponent("yok"), limit: 10).isEmpty)
    }

    // MARK: İnceleme küçük bulguları (G1)
    /// stop() sonrası ana kuyruğa geç ulaşan bildirimler (yeni/kaldırıldı/kök) düşer: eski klasörden `ingest` gelmez.
    func testCallbacksAfterStopAreDropped() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("watch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) } // test geçici klasörü
        let w = ScreenshotWatcher(folder: dir)
        var calls = 0
        w.onNewScreenshot = { _ in calls += 1 }; w.onRemoved = { _ in calls += 1 }; w.onRootChanged = { calls += 1 }
        w.start(); w.stop()
        let u = dir.appendingPathComponent("a.png")
        w.deliver(.new(u)); w.deliver(.removed(u)); w.deliver(.rootChanged)
        let drained = expectation(description: "ana kuyruk boşaldı")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 2)
        XCTAssertEqual(calls, 0)
    }
    /// Yeniden adlandırma kaynağı: aynı fileID, farklı yol, eski yol artık yok.
    func testRenameSourceMatchesFileIDWhenOldPathGone() {
        let old = ShelfItem(path: "/t/a.png", fileID: "1", capturedAt: Date())
        let other = ShelfItem(path: "/t/c.png", fileID: "2", capturedAt: Date())
        let items = [other, old]
        XCTAssertEqual(AppController.renameSource(fileID: "1", newPath: "/t/b.png", items: items, exists: { _ in false })?.id, old.id)
        XCTAssertNil(AppController.renameSource(fileID: "1", newPath: "/t/b.png", items: items, exists: { $0 == "/t/a.png" }), "eski yol duruyor (sabit bağ/kopya)")
        XCTAssertNil(AppController.renameSource(fileID: nil, newPath: "/t/b.png", items: items, exists: { _ in false }))
        XCTAssertNil(AppController.renameSource(fileID: "1", newPath: "/t/a.png", items: items, exists: { _ in false }), "aynı yol")
    }
}
