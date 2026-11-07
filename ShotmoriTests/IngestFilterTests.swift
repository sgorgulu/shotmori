import XCTest
@testable import Shotmori

final class IngestFilterTests: XCTestCase {
    private func urls(_ r: [(url: URL, fileID: String?)]) -> [URL] { r.map(\.url) }
    func testFilterPendingDropsMissingAndDedupesByFileID() {
        let a = URL(fileURLWithPath: "/t/a.png"), b = URL(fileURLWithPath: "/t/b.png"), c = URL(fileURLWithPath: "/t/c.png")
        // a yeniden adlandırıldı (yok), b aynı dosyanın yeni adı, c ayrı dosya. Kimlik geliş anında saklanır; yeniden hesaplanmaz.
        var recomputed = 0
        let r = AppController.filterPending([(a, "1"), (b, "1"), (c, "2")], exists: { $0 != a }, fileID: { _ in recomputed += 1; return nil })
        XCTAssertEqual(urls(r), [b, c]); XCTAssertEqual(r.map(\.fileID), ["1", "2"]); XCTAssertEqual(recomputed, 0)
        // İkisi de varsa aynı fileID tek kalır.
        XCTAssertEqual(urls(AppController.filterPending([(a, "1"), (b, "1")], exists: { _ in true }, fileID: { _ in nil })), [a])
        // Saklı kimlik yoksa flush'ta yeniden hesaplanır ve tekilleştirmeye girer.
        let ids = [a: "1", b: "1"]
        let r2 = AppController.filterPending([(a, nil), (b, "1")], exists: { _ in true }, fileID: { ids[$0] })
        XCTAssertEqual(urls(r2), [a]); XCTAssertEqual(r2.first?.fileID, "1")
    }
    /// Kimliği okunamayan (nil) girişler hiç tekilleştirilmez.
    func testNilFileIDIsNeverDeduped() {
        let a = URL(fileURLWithPath: "/t/a.png"), b = URL(fileURLWithPath: "/t/b.png")
        XCTAssertEqual(urls(AppController.filterPending([(a, nil), (b, nil)], exists: { _ in true }, fileID: { _ in nil })), [a, b])
    }
    /// Gerçek dosyalarla: pencere içinde a.png → b.png yeniden adlandırılınca yalnız diskteki yeni yol kalır.
    func testRenameInsideWindowKeepsOnlyNewPathOnDisk() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ingest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) } // test geçici klasörü
        let a = dir.appendingPathComponent("a.png"), b = dir.appendingPathComponent("b.png")
        try Data([1, 2, 3]).write(to: a)
        let idA = ScreenshotFileInspector.fileIdentifier(a)
        try FileManager.default.moveItem(at: a, to: b)
        let idB = ScreenshotFileInspector.fileIdentifier(b)
        XCTAssertNotNil(idA); XCTAssertEqual(idA, idB, "yeniden adlandırma kimliği korur")
        let r = AppController.filterPending([(a, idA), (b, idB)], exists: { FileManager.default.fileExists(atPath: $0.path) }, fileID: { ScreenshotFileInspector.fileIdentifier($0) })
        XCTAssertEqual(urls(r), [b])
    }
    /// Toplu ekleme eskiden yeniye sıralanır: `store.add` her öğeyi başa koyduğu için en yeni kare rafın başında kalır.
    func testIngestItemsSortOldestFirstSoNewestLandsOnTop() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ingest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) } // test geçici klasörü
        let t = Date(timeIntervalSince1970: 1_000_000)
        let entries: [(URL, String?, Date)] = [("b", t.addingTimeInterval(10)), ("c", t.addingTimeInterval(20)), ("a", t)]
            .map { (URL(fileURLWithPath: "/t/\($0.0).png"), $0.0, $0.1) }
        let items = AppController.ingestItems(entries)
        XCTAssertEqual(items.map(\.fileName), ["a.png", "b.png", "c.png"])
        XCTAssertEqual(items.map(\.fileID), ["a", "b", "c"])
        let s = ShelfStore(fileURL: dir.appendingPathComponent("shelf.json"), maxItems: 50)
        s.add(items)
        XCTAssertEqual(s.allItems.first?.fileName, "c.png"); XCTAssertEqual(s.allItems.map(\.fileName), ["c.png", "b.png", "a.png"])
    }
}
