import XCTest
@testable import Shotmori

final class DerivativeJanitorTests: XCTestCase {
    private func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("shotmori-janitor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); return d
    }
    private func file(_ name: String, in d: URL, modified: Date) throws -> URL {
        let u = d.appendingPathComponent(name); try Data([0x89, 0x50, 0x4E, 0x47]).write(to: u)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: u.path); return u
    }

    func testSweepTrashesOnlyOldUnreferenced() throws {
        let d = try tempDir(), now = Date(), old = now.addingTimeInterval(-8 * 86_400)
        let oldFree = try file("eski.png", in: d, modified: old)
        let oldRef = try file("rafta.png", in: d, modified: old)
        _ = try file("yeni.png", in: d, modified: now.addingTimeInterval(-3600))
        var trashed: [URL] = []
        let n = DerivativeJanitor.sweep(roots: [d], referenced: [oldRef.path], olderThan: 7 * 86_400, now: now) { trashed.append($0) }
        XCTAssertEqual(n, 1)
        XCTAssertEqual(trashed.map(\.lastPathComponent), [oldFree.lastPathComponent])
    }
    func testSweepSkipsDirectoriesMissingRootsAndCountsOnlySuccess() throws {
        let d = try tempDir(), now = Date(), old = now.addingTimeInterval(-30 * 86_400)
        let sub = d.appendingPathComponent("alt", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: sub.path)
        _ = try file("a.png", in: d, modified: old); _ = try file("b.png", in: d, modified: old)
        var calls = 0
        let n = DerivativeJanitor.sweep(roots: [d, d.appendingPathComponent("yok")], referenced: [], olderThan: 7 * 86_400, now: now) { u in
            calls += 1; if u.lastPathComponent == "b.png" { throw CocoaError(.fileWriteNoPermission) }
        }
        XCTAssertEqual(calls, 2); XCTAssertEqual(n, 1)
    }
    /// Raftaki yol klasöre sembolik bağlantı üzerinden verilmiş olsa da (ör. `/var` ↔ `/private/var`) aynı dosya sayılır, Çöp'e gitmez.
    func testReferencedThroughSymlinkIsKept() throws {
        let d = try tempDir(), now = Date(), old = now.addingTimeInterval(-8 * 86_400)
        let alias = FileManager.default.temporaryDirectory.appendingPathComponent("shotmori-janitor-alias-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: d); defer { try? FileManager.default.removeItem(at: alias) } // yalnız test bağlantısı
        _ = try file("rafta.png", in: d, modified: old); let free = try file("eski.png", in: d, modified: old)
        var trashed: [URL] = []
        let n = DerivativeJanitor.sweep(roots: [d], referenced: [alias.appendingPathComponent("rafta.png").path], olderThan: 7 * 86_400, now: now) { trashed.append($0) }
        XCTAssertEqual(n, 1); XCTAssertEqual(trashed.map(\.lastPathComponent), [free.lastPathComponent])
    }
    /// Gizli dosyalar (`.x.png`, `.DS_Store`) eski ve rafta olmasalar da Çöp'e gönderilmez.
    func testHiddenFilesAreNeverTrashed() throws {
        let d = try tempDir(), now = Date(), old = now.addingTimeInterval(-30 * 86_400)
        _ = try file(".x.png", in: d, modified: old); let free = try file("eski.png", in: d, modified: old)
        var trashed: [URL] = []
        let n = DerivativeJanitor.sweep(roots: [d], referenced: [], olderThan: 7 * 86_400, now: now) { trashed.append($0) }
        XCTAssertEqual(n, 1); XCTAssertEqual(trashed.map(\.lastPathComponent), [free.lastPathComponent])
    }
    /// Yarım kalmış içe aktarma kopyası (`.gelen-*.tmp`) gizli olsa da yaşı dolunca Çöp'e gider; yaş mtime'dan değil ctime'dan ölçülür
    /// (kopya kaynağın eski mtime'ını taşır, süren kopya alınmamalı).
    func testStaleImportTempIsTrashedByAttributeAge() throws {
        let d = try tempDir(), old = Date().addingTimeInterval(-30 * 86_400)
        let tmp = try file("\(InboundImport.tempPrefix)\(UUID().uuidString).tmp", in: d, modified: old)
        _ = try file(".gelen-not.png", in: d, modified: old); _ = try file(InboundImport.indexFileName, in: d, modified: old)
        var trashed: [URL] = []
        XCTAssertEqual(DerivativeJanitor.sweep(roots: [d], referenced: [], olderThan: 7 * 86_400, now: Date()) { trashed.append($0) }, 0,
                       "yeni oluşturulmuş geçici kopya eski mtime'a rağmen kalır")
        let later = Date().addingTimeInterval(8 * 86_400)
        let n = DerivativeJanitor.sweep(roots: [d], referenced: [], olderThan: 7 * 86_400, now: later) { trashed.append($0) }
        XCTAssertEqual(n, 1); XCTAssertEqual(trashed.map(\.lastPathComponent), [tmp.lastPathComponent], "yalnız .tmp artığı; diğer gizli dosyalar ve tekilleştirme indeksi kalır")
    }
}
