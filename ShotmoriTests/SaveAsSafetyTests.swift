import XCTest
import CryptoKit
@testable import Shotmori

/// G: Farklı Kaydet / Buraya Kopyala dosya güvenliği. Yalnızca geçici dizinler; kullanıcı dosyalarına dokunmaz.
final class SaveAsSafetyTests: XCTestCase {
    var dir: URL!; var src: URL!; let payload = Data("KAYNAK-\(UUID())".utf8)
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("saveas-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        src = dir.appendingPathComponent("kaynak.png"); try payload.write(to: src)
    }
    override func tearDownWithError() throws { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path); try? FileManager.default.removeItem(at: dir) }
    private func sha(_ u: URL) throws -> String { SHA256.hash(data: try Data(contentsOf: u)).map { String(format: "%02x", $0) }.joined() }
    private func assertSourceIntact(file: StaticString = #filePath, line: UInt = #line) throws { XCTAssertEqual(try Data(contentsOf: src), payload, "kaynak değişti", file: file, line: line) }

    func testSameURLIsRefusedAndSourceIntact() throws {
        let before = try sha(src)
        XCTAssertThrowsError(try SafeFileCopy.copy(src, to: src, replace: true)) { XCTAssertEqual($0 as? SafeFileCopy.Failure, .sameFile) }
        XCTAssertThrowsError(try SafeFileCopy.write(Data("X".utf8), to: src, source: src)) { XCTAssertEqual($0 as? SafeFileCopy.Failure, .sameFile) }
        XCTAssertEqual(try sha(src), before); try assertSourceIntact()
    }
    func testNormalizedSymlinkAndHardLinkAliasesAreRefused() throws {
        let dotted = dir.appendingPathComponent("./alt/../kaynak.png")
        XCTAssertTrue(SafeFileCopy.isSameFile(src, dotted))
        let link = dir.deletingLastPathComponent().appendingPathComponent("link-\(UUID())"); try FileManager.default.createSymbolicLink(at: link, withDestinationURL: dir); defer { try? FileManager.default.removeItem(at: link) }
        XCTAssertTrue(SafeFileCopy.isSameFile(src, link.appendingPathComponent("kaynak.png")))
        let hard = dir.appendingPathComponent("sert.png"); try FileManager.default.linkItem(at: src, to: hard)
        XCTAssertTrue(SafeFileCopy.isSameFile(src, hard))
        XCTAssertThrowsError(try SafeFileCopy.copy(src, to: hard, replace: true)) { XCTAssertEqual($0 as? SafeFileCopy.Failure, .sameFile) }
        XCTAssertFalse(SafeFileCopy.isSameFile(src, dir.appendingPathComponent("baska.png")))
        try assertSourceIntact()
    }
    func testReplaceExistingTargetSucceedsWithoutLeftovers() throws {
        let dst = dir.appendingPathComponent("hedef.png"); try Data("ESKI".utf8).write(to: dst)
        try SafeFileCopy.copy(src, to: dst, replace: true)
        XCTAssertEqual(try Data(contentsOf: dst), payload)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: dir.path).contains { $0.hasSuffix(".tmp") }, "geçici dosya kaldı")
        try assertSourceIntact()
    }
    func testWriteFailureKeepsPreexistingTarget() throws {
        let sub = dir.appendingPathComponent("kilitli", isDirectory: true); try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let dst = sub.appendingPathComponent("hedef.png"); let old = Data("ESKI-ICERIK".utf8); try old.write(to: dst)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: sub.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sub.path) }
        XCTAssertThrowsError(try SafeFileCopy.copy(src, to: dst, replace: true))
        XCTAssertThrowsError(try SafeFileCopy.write(payload, to: dst, source: nil))
        XCTAssertEqual(try Data(contentsOf: dst), old, "hata sonrası eski hedef korunmalı")
        try assertSourceIntact()
    }
    func testNoReplaceRefusesExistingTarget() throws {
        let dst = dir.appendingPathComponent("var.png"); let old = Data("VAR".utf8); try old.write(to: dst)
        XCTAssertThrowsError(try SafeFileCopy.copy(src, to: dst, replace: false)) { XCTAssertEqual($0 as? SafeFileCopy.Failure, .destinationExists) }
        XCTAssertEqual(try Data(contentsOf: dst), old)
    }
    func testBatchCopySkipsSameFileAndExistingAndReportsBoth() throws {
        let other = dir.appendingPathComponent("diger", isDirectory: true); try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let b = other.appendingPathComponent("b.png"); try Data("B".utf8).write(to: b)
        let c = other.appendingPathComponent("c.png"); try Data("C".utf8).write(to: c)
        let existingB = dir.appendingPathComponent("b.png"); let oldB = Data("ESKI-B".utf8); try oldB.write(to: existingB)
        let r = SafeFileCopy.copyAll([src, b, c], into: dir) // src zaten dir içinde → aynı dosya; b hedefte var → atla; c kopyalanır
        XCTAssertEqual(r.copied, [c])
        XCTAssertEqual(r.skipped.map { $0.0 }, [src, b]); XCTAssertEqual(r.skipped.map { $0.1 }, [.sameFile, .destinationExists])
        XCTAssertEqual(try Data(contentsOf: existingB), oldB); XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("c.png")), Data("C".utf8))
        try assertSourceIntact()
    }

    /// Sandbox: Farklı kaydet izni yalnız seçilen dosyayı kapsar; hedefin yanına kardeş geçici dosya yazılamaz.
    func testReplacementTempIsNotSiblingOfDestination() throws {
        let dst = dir.appendingPathComponent("hedef.png"); try Data("ESKI".utf8).write(to: dst)
        let tmp = try SafeFileCopy.replacementTemporaryURL(for: dst)
        defer { try? FileManager.default.removeItem(at: tmp.deletingLastPathComponent()) }
        XCTAssertNotEqual(tmp.deletingLastPathComponent().standardizedFileURL.path, dst.deletingLastPathComponent().standardizedFileURL.path)
        try SafeFileCopy.copy(src, to: dst, replace: true)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted(), ["hedef.png", "kaynak.png"], "hedef dizinde yalnız hedef ve kaynak kalmalı")
    }

    /// Dış disk vb.: değiştirme dizini verilemezse hedefin yanındaki geçici dosyaya düşülür (sandbox dışında çalışır, hata güvenli).
    func testReplaceFallsBackWhenReplacementDirectoryUnavailable() throws {
        let dst = dir.appendingPathComponent("hedef.png"); try Data("ESKI".utf8).write(to: dst)
        SafeFileCopy.replacementDirectory = { _ in throw CocoaError(.fileWriteNoPermission) }
        defer { SafeFileCopy.replacementDirectory = SafeFileCopy.systemReplacementDirectory }
        try SafeFileCopy.copy(src, to: dst, replace: true)
        XCTAssertEqual(try Data(contentsOf: dst), payload)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: dir.path).contains { $0.hasSuffix(".tmp") })
    }
}
