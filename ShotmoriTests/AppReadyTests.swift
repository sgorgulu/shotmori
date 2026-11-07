import XCTest
@testable import Shotmori

/// Intent'lerin `start()` bitişini beklemesi: `ReadyGate` mantığı (test ana bilgisayarında `AppController` oluşturulmaz, gerçek rafa dokunulmaz).
final class AppReadyTests: XCTestCase {
    private final class Dummy: @unchecked Sendable {}

    func testReadyTimesOut() async {
        let gate = ReadyGate<Dummy>()
        XCTAssertNil(gate.current)
        let started = Date()
        do { _ = try await gate.wait(timeout: 0.3); XCTFail("hazır olmadan döndü") }
        catch { XCTAssertEqual(error as? IntentError, .notReady) }
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(started), 0.25)
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }
    func testReadyResolvesAfterStart() async throws {
        let gate = ReadyGate<Dummy>(), d = Dummy()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { gate.open(d) }
        let got = try await gate.wait(timeout: 2)
        XCTAssertTrue(got === d)
        XCTAssertTrue(gate.current === d)
    }
    func testReadyReturnsImmediatelyWhenOpen() async throws {
        let gate = ReadyGate<Dummy>(), d = Dummy()
        gate.open(d)
        let started = Date()
        let got = try await gate.wait(timeout: 0.3)
        XCTAssertTrue(got === d); XCTAssertLessThan(Date().timeIntervalSince(started), 0.1)
    }
    /// Kapı zayıf tutar: denetleyici giderse intent eski örneğe ulaşmaz.
    func testGateHoldsWeakly() {
        let gate = ReadyGate<Dummy>()
        do { let d = Dummy(); gate.open(d); XCTAssertNotNil(gate.current) }
        XCTAssertNil(gate.current)
    }
    /// Test ana bilgisayarında denetleyici hiç başlatılmaz: `shared` boş, `ready` zaman aşımıyla `notReady`.
    func testAppControllerNotReadyInTestHost() async {
        XCTAssertNil(AppController.shared)
        do { _ = try await AppController.ready(timeout: 0.2); XCTFail("test ana bilgisayarında hazır olmamalı") }
        catch { XCTAssertEqual(error as? IntentError, .notReady) }
    }
    func testIntentErrorsHaveLocalizedDescriptions() {
        let all: [IntentError] = [.notReady, .noImages, .shelfNotFound, .fileRejected, .tooMany, .tooLarge, .notConnected("Google Drive"), .uploadStillRunning, .clipboardEmpty]
        for e in all {
            let d = e.errorDescription ?? ""
            XCTAssertFalse(d.isEmpty, "\(e)"); XCTAssertFalse(d.hasPrefix("intentErr"), "anahtar sızdı: \(e)")
        }
        XCTAssertTrue(IntentError.notConnected("Google Drive").errorDescription?.contains("Google Drive") == true)
    }

    // MARK: Dış dosya → raf kaynağı ve bildirim
    func testWatchedFolderFilesKeepScreenshotSource() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ready-\(UUID().uuidString)", isDirectory: true)
        let watched = root.appendingPathComponent("izlenen", isDirectory: true), other = root.appendingPathComponent("baska", isDirectory: true)
        try FileManager.default.createDirectory(at: watched, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        defer { try? FileManager.default.trashItem(at: root, resultingItemURL: nil) }
        XCTAssertEqual(AppController.shelfSource(for: watched.appendingPathComponent("a.png"), watchedFolder: watched), .screenshot)
        XCTAssertEqual(AppController.shelfSource(for: other.appendingPathComponent("a.png"), watchedFolder: watched), .imported)
        XCTAssertEqual(AppController.shelfSource(for: watched.appendingPathComponent("a.png"), watchedFolder: nil), .imported)
        XCTAssertEqual(AppController.shelfSource(for: InboundImport.folder.appendingPathComponent("a.png"), watchedFolder: watched), .imported)
    }
    func testImportToastPriorities() {
        typealias R = InboundImport.Result
        typealias M = AppController.ImportMessage
        let u = URL(fileURLWithPath: "/tmp/x.png")
        XCTAssertEqual(AppController.importToast(R(added: [u, u]), inserted: 2), M.success(S.inboundAdded(2)))
        XCTAssertEqual(AppController.importToast(R(added: [u]), inserted: 1), M.success(S.inboundAdded(1)))
        XCTAssertEqual(AppController.importToast(R(alreadyPresent: [u]), inserted: 0), M.success(S.inboundAlready))
        XCTAssertEqual(AppController.importToast(R(added: [u]), inserted: 0), M.success(S.inboundAlready))
        // Ret ve sınır hata: kalıcı bildirim (1,6 sn'de kaybolan başarı tostu değil).
        XCTAssertEqual(AppController.importToast(R(rejected: 2), inserted: 0), M.error(S.inboundRejected))
        XCTAssertEqual(AppController.importToast(R(), inserted: 0), M.error(S.inboundRejected))
        XCTAssertEqual(AppController.importToast(R(limited: 3), inserted: 0), M.error(S.inboundLimit))
        XCTAssertEqual(AppController.importToast(R(oversized: 1), inserted: 0), M.error(S.inboundTooLarge), "50 MB üstü görsel: tür değil boyut")
        XCTAssertEqual(AppController.importToast(R(rejected: 1, oversized: 1), inserted: 0), M.error(S.inboundTooLarge))
        // 25 bırakıldı, 20 eklendi, 5 sınır dışı: iki bilgi tek cümlede.
        let both = AppController.importToast(R(added: Array(repeating: u, count: 20), limited: 5), inserted: 20)
        XCTAssertEqual(both, M.error(S.inboundAddedLimited(20)))
        XCTAssertTrue(both?.text.contains("20") == true)
        XCTAssertNotEqual(S.inboundAddedLimited(1), S.inboundAddedLimited(2))
        XCTAssertNotEqual(S.inboundAdded(1), S.inboundAdded(2))
    }
}
