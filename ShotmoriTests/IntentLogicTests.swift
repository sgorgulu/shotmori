import XCTest
import AppKit
@testable import Shotmori

/// Kestirmeler eylemlerinin saf çekirdeği (`ShelfIntentCore`): bellek içi raf (`ShelfStore(fileURL: nil)`), gerçek rafa ve tercihlere dokunulmaz.
/// `IntentFile` sarmalayıcıları test edilmez; App Shortcuts ifadeleri kaynak ve `.strings` taramasıyla denetlenir.
@MainActor
final class IntentLogicTests: XCTestCase {
    private func makeStore(max: Int = 50) -> ShelfStore { ShelfStore(fileURL: nil, maxItems: max) }
    private func item(_ name: String, addedAt: Date, path: String? = nil) -> ShelfItem {
        ShelfItem(path: path ?? "/tmp/intent-test-\(UUID().uuidString)-\(name)", fileID: nil, capturedAt: addedAt, addedAt: addedAt)
    }
    private func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("shotmori-intent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); return d
    }
    private func png(seed: Int) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let c = NSColor(deviceRed: CGFloat(seed % 256) / 255, green: 0.3, blue: 0.5, alpha: 1)
        for x in 0..<2 { for y in 0..<2 { rep.setColor(c, atX: x, y: y) } }
        return rep.representation(using: .png, properties: [:])!
    }
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: Raftan al

    func testItemsOnlyNewMarksHandoff() {
        let s = makeStore()
        for i in 0..<3 { s.add(item("\(i).png", addedAt: t0.addingTimeInterval(Double(i)))) }
        let first = ShelfIntentCore.items(store: s, shelfID: nil, onlyNew: true, limit: 10, markHandoff: true)
        XCTAssertEqual(first.count, 3)
        let second = ShelfIntentCore.items(store: s, shelfID: nil, onlyNew: true, limit: 10, markHandoff: true)
        XCTAssertEqual(second.count, 0, "verilenler teslim edilmiş sayılır")
        XCTAssertEqual(s.itemsSinceLastHandoff().count, 0)
    }
    func testItemsLimitAndOrder() {
        let s = makeStore()
        for i in 0..<5 { s.add(item("\(i).png", addedAt: t0.addingTimeInterval(Double(i)))) }
        let got = ShelfIntentCore.items(store: s, shelfID: nil, onlyNew: false, limit: 2, markHandoff: false)
        XCTAssertEqual(got.map { String($0.fileName.suffix(5)) }, ["4.png", "3.png"], "en yeni 2, yeniden eskiye")
    }
    func testItemsWithoutOnlyNewDoesNotMarkHandoff() {
        let s = makeStore()
        for i in 0..<3 { s.add(item("\(i).png", addedAt: t0.addingTimeInterval(Double(i)))) }
        _ = ShelfIntentCore.items(store: s, shelfID: nil, onlyNew: false, limit: 10, markHandoff: true)
        XCTAssertNil(s.activeShelf.lastHandoffAt)
        XCTAssertEqual(s.itemsSinceLastHandoff().count, 3)
    }
    /// Sınırdan fazla yeni kare varsa yalnız verilenler teslim edilir; kalanlar sonraki çağrıda gelir (hiçbiri kaybolmaz).
    func testOnlyNewWithLimitKeepsRestNew() {
        let s = makeStore()
        for i in 0..<5 { s.add(item("\(i).png", addedAt: t0.addingTimeInterval(Double(i)))) }
        let a = ShelfIntentCore.items(store: s, shelfID: nil, onlyNew: true, limit: 2, markHandoff: true)
        XCTAssertEqual(a.map { String($0.fileName.suffix(5)) }, ["1.png", "0.png"], "en eski yeni parti")
        XCTAssertEqual(s.itemsSinceLastHandoff().count, 3)
        let b = ShelfIntentCore.items(store: s, shelfID: nil, onlyNew: true, limit: 10, markHandoff: true)
        XCTAssertEqual(b.map { String($0.fileName.suffix(5)) }, ["4.png", "3.png", "2.png"])
        XCTAssertTrue(s.itemsSinceLastHandoff().isEmpty)
    }
    func testItemsTargetsGivenShelfAndClampsLimit() throws {
        let s = makeStore()
        let other = try XCTUnwrap(s.addShelf(name: "İş")).id
        s.add(item("a.png", addedAt: t0))
        for i in 0..<3 { s.add(item("b\(i).png", addedAt: t0.addingTimeInterval(Double(i))), to: other) }
        XCTAssertEqual(ShelfIntentCore.items(store: s, shelfID: other, onlyNew: false, limit: 0, markHandoff: false).count, 1, "sınır en az 1")
        XCTAssertEqual(ShelfIntentCore.items(store: s, shelfID: other, onlyNew: false, limit: 500, markHandoff: false).count, 3)
        _ = ShelfIntentCore.items(store: s, shelfID: other, onlyNew: true, limit: 10, markHandoff: true)
        XCTAssertEqual(s.itemsSinceLastHandoff(shelfID: other).count, 0)
        XCTAssertEqual(s.itemsSinceLastHandoff().count, 1, "diğer rafın yenileri etkilenmez")
    }

    // MARK: Temizle / son görüntü / raf

    func testClearReturnsCountKeepsFiles() throws {
        let d = try tempDir(), f = d.appendingPathComponent("kare.png")
        try png(seed: 1).write(to: f)
        let s = makeStore()
        s.add(item("kare.png", addedAt: t0, path: f.path)); s.add(item("b.png", addedAt: t0.addingTimeInterval(1)))
        XCTAssertEqual(ShelfIntentCore.clear(store: s, shelfID: nil), 2)
        XCTAssertTrue(s.items.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.path), "dosya diskte kalır")
        XCTAssertEqual(ShelfIntentCore.clear(store: s, shelfID: nil), 0)
    }
    /// Onay sırasında görülen öğeler düşer; sonradan gelen kare kalır.
    func testClearOnlySnapshotIDs() {
        let s = makeStore()
        let a = item("a.png", addedAt: t0); s.add(a)
        let snapshot = Set(s.items.map(\.id))
        s.add(item("b.png", addedAt: t0.addingTimeInterval(1)))
        XCTAssertEqual(ShelfIntentCore.clear(store: s, shelfID: nil, onlyIDs: snapshot), 1)
        XCTAssertEqual(s.items.count, 1)
    }
    func testLatestPicksNewestAcrossShelves() throws {
        let s = makeStore()
        let other = try XCTUnwrap(s.addShelf()).id
        s.add(item("eski.png", addedAt: t0))
        s.add(item("yeni.png", addedAt: t0.addingTimeInterval(60)), to: other)
        s.add(item("orta.png", addedAt: t0.addingTimeInterval(30)))
        XCTAssertTrue(ShelfIntentCore.latest(store: s)?.fileName.hasSuffix("yeni.png") == true)
        XCTAssertNil(ShelfIntentCore.latest(store: makeStore()))
    }
    func testShelfLookupThrowsWhenMissing() throws {
        let s = makeStore()
        XCTAssertEqual(try ShelfIntentCore.shelf(store: s, id: nil).id, s.activeShelfID)
        let other = try XCTUnwrap(s.addShelf(name: "Tasarım"))
        XCTAssertEqual(try ShelfIntentCore.shelf(store: s, id: other.id).name, "Tasarım")
        XCTAssertThrowsError(try ShelfIntentCore.shelf(store: s, id: UUID())) { XCTAssertEqual($0 as? IntentError, .shelfNotFound) }
    }

    // MARK: Rafa ekle (tek giriş kapısı)

    func testAddCopiesIntoInboundFolderAndTargetsShelf() throws {
        let src = try tempDir(), into = try tempDir()
        let a = src.appendingPathComponent("bir.png"), b = src.appendingPathComponent("not.txt")
        try png(seed: 7).write(to: a); try Data("x".utf8).write(to: b)
        let s = makeStore(); let other = try XCTUnwrap(s.addShelf()).id
        let exp = expectation(description: "add"); var out: Result<[ShelfItem], IntentError>?
        ShelfIntentCore.add(urls: [a, b], shelfID: other, store: s, watchedFolder: nil, into: into) { out = $0; exp.fulfill() }
        wait(for: [exp], timeout: 20)
        let added = try XCTUnwrap(try? out?.get())
        XCTAssertEqual(added.count, 1)
        XCTAssertEqual(added.first?.source, .imported)
        XCTAssertTrue(added.first?.path.hasPrefix(into.resolvingSymlinksInPath().path) == true || added.first?.path.hasPrefix(into.path) == true, "kopya Gelen'de")
        XCTAssertEqual(s.shelves.first { $0.id == other }?.items.count, 1)
        XCTAssertTrue(s.items.isEmpty, "etkin raf değişmez")
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path), "özgün dosya yerinde")
        // Aynı içerik ikinci kez: yeni kopya yok, raftaki öğe döner.
        let exp2 = expectation(description: "again"); var again: Result<[ShelfItem], IntentError>?
        ShelfIntentCore.add(urls: [a], shelfID: other, store: s, watchedFolder: nil, into: into) { again = $0; exp2.fulfill() }
        wait(for: [exp2], timeout: 20)
        XCTAssertEqual((try? again?.get())?.map(\.id), added.map(\.id))
    }
    /// Raftan kaldırılan görüntü aynı dosyayla yeniden eklenebilir (tekilleştirilmiş Gelen kopyası kaldırma izine takılmaz); sonuç boş değil.
    func testAddReaddsRemovedItem() throws {
        let src = try tempDir(), into = try tempDir()
        let a = src.appendingPathComponent("foo.png"); try png(seed: 23).write(to: a)
        let s = makeStore()
        func run() throws -> [ShelfItem] {
            let exp = expectation(description: "add"); var out: Result<[ShelfItem], IntentError>?
            ShelfIntentCore.add(urls: [a], shelfID: nil, store: s, watchedFolder: nil, into: into) { out = $0; exp.fulfill() }
            wait(for: [exp], timeout: 20)
            return try XCTUnwrap(try? out?.get())
        }
        let first = try run()
        XCTAssertEqual(first.count, 1)
        s.remove(ids: Set(first.map(\.id)))
        XCTAssertTrue(s.items.isEmpty)
        let second = try run()
        XCTAssertEqual(second.count, 1, "yeniden ekleme boş dönmez")
        XCTAssertEqual(second.first?.path, first.first?.path, "aynı Gelen kopyası")
        XCTAssertEqual(s.items.map(\.path), first.map(\.path), "öğe yeniden rafta")
        // Rafı temizle sonrası da.
        s.clear()
        XCTAssertEqual(try run().count, 1); XCTAssertEqual(s.items.count, 1)
        // Dış içe aktarma bildirimi: "1 görüntü rafa eklendi" (Zaten rafta değil).
        XCTAssertEqual(AppController.importToast(InboundImport.Result(alreadyPresent: [URL(fileURLWithPath: first[0].path)]), inserted: 1),
                       .success(S.inboundAdded(1)))
    }
    func testAddReportsTooLargeForOversizedImage() throws {
        let s = makeStore(), into = try tempDir(), src = try tempDir()
        let big = src.appendingPathComponent("buyuk.png")
        XCTAssertTrue(FileManager.default.createFile(atPath: big.path, contents: nil))
        let h = try FileHandle(forWritingTo: big); try h.truncate(atOffset: UInt64(InboundImport.maxBytes + 1)); try h.close()
        let txt = src.appendingPathComponent("a.txt"); try Data("x".utf8).write(to: txt)
        func run(_ urls: [URL]) -> IntentError? {
            let exp = expectation(description: "add"); var err: IntentError?
            ShelfIntentCore.add(urls: urls, shelfID: nil, store: s, watchedFolder: nil, into: into) { r in
                if case .failure(let e) = r { err = e }; exp.fulfill()
            }
            wait(for: [exp], timeout: 20); return err
        }
        XCTAssertEqual(run([big]), .tooLarge)
        XCTAssertEqual(IntentError.tooLarge.errorDescription, S.inboundTooLarge)
        XCTAssertEqual(run([big, txt]), .fileRejected, "tür reddi de varsa genel ret")
    }
    func testAddRejectsEmptyTooManyAndNonImages() throws {
        let s = makeStore(), into = try tempDir(), src = try tempDir()
        let txt = src.appendingPathComponent("a.txt"); try Data("x".utf8).write(to: txt)
        func run(_ urls: [URL]) -> IntentError? {
            let exp = expectation(description: "add"); var err: IntentError?
            ShelfIntentCore.add(urls: urls, shelfID: nil, store: s, watchedFolder: nil, into: into) { r in
                if case .failure(let e) = r { err = e }; exp.fulfill()
            }
            wait(for: [exp], timeout: 20); return err
        }
        XCTAssertEqual(run([]), .noImages)
        XCTAssertEqual(run(Array(repeating: txt, count: InboundImport.maxCount + 1)), .tooMany)
        XCTAssertEqual(run([txt]), .fileRejected)
        XCTAssertEqual(ShelfIntentCore.precheck(count: 1, shelfID: UUID(), store: s), .shelfNotFound, "bilinmeyen raf baştan reddedilir")
        XCTAssertNil(ShelfIntentCore.precheck(count: 1, shelfID: nil, store: s))
    }

    // MARK: App Shortcuts

    func testShortcutsPhrasesContainAppName() throws {
        XCTAssertGreaterThan(ShotmoriShortcuts.appShortcuts.count, 0)
        XCTAssertLessThanOrEqual(ShotmoriShortcuts.appShortcuts.count, 10)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let src = try String(contentsOf: root.appendingPathComponent("Shotmori/Intents/ShotmoriShortcuts.swift"), encoding: .utf8)
        let phrases = Self.phrases(in: src)
        XCTAssertGreaterThanOrEqual(phrases.count, ShotmoriShortcuts.appShortcuts.count)
        for p in phrases { XCTAssertTrue(p.contains("\\(.applicationName)"), "ifadede uygulama adı yok: \(p)") }
        // Her ifade iki dilde AppShortcuts.strings anahtarı; başka ürün adı yok.
        for lang in ["tr", "en"] {
            let table = try XCTUnwrap(NSDictionary(contentsOf: root.appendingPathComponent("Shotmori/\(lang).lproj/AppShortcuts.strings")) as? [String: String])
            for p in phrases {
                let key = p.replacingOccurrences(of: "\\(.applicationName)", with: "${applicationName}")
                XCTAssertNotNil(table[key], "\(lang): \(key) yok")
            }
        }
    }
    /// `phrases: [ ... ]` blokları içindeki dize sabitleri.
    static func phrases(in src: String) -> [String] {
        var out: [String] = [], rest = Substring(src)
        while let r = rest.range(of: "phrases: [") {
            guard let end = rest[r.upperBound...].range(of: "]") else { break }
            let block = rest[r.upperBound..<end.lowerBound]
            var inside = false, cur = ""
            for ch in block { if ch == "\"" { if inside { out.append(cur); cur = "" }; inside.toggle() } else if inside { cur.append(ch) } }
            rest = rest[end.upperBound...]
        }
        return out
    }
}
