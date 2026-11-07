import XCTest
import AppKit
@testable import Shotmori

/// Tek giriş kapısı: dış dosya `Gelen/`e kopyalanır, özgün dosya değişmez; aynı içerik ikinci kez yazılmaz.
final class InboundImportTests: XCTestCase {
    private var lockedFolders: [URL] = []
    override func tearDown() {
        for d in lockedFolders { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: d.path) }
        super.tearDown()
    }
    private func tempDir(_ tag: String = "") throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("shotmori-inbound-\(tag)\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); return d
    }
    /// 2×2 PNG; `seed` farklı piksel rengi verir (farklı içerik).
    private func pngData(seed: Int = 0) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let c = NSColor(deviceRed: CGFloat(seed % 256) / 255, green: CGFloat((seed / 256) % 256) / 255, blue: 0.5, alpha: 1)
        for x in 0..<2 { for y in 0..<2 { rep.setColor(c, atX: x, y: y) } }
        return rep.representation(using: .png, properties: [:])!
    }
    private func source(_ name: String, in d: URL, seed: Int = 0) throws -> URL {
        let u = d.appendingPathComponent(name); try pngData(seed: seed).write(to: u); return u
    }
    private func runImport(_ urls: [URL], into folder: URL, watched: URL? = nil, now: Date = Date()) -> InboundImport.Result {
        let exp = expectation(description: "import"); var out: InboundImport.Result?
        InboundImport.importFiles(urls, source: .intent, watchedFolder: watched, now: now, into: folder) { r in
            XCTAssertTrue(Thread.isMainThread); out = r; exp.fulfill()
        }
        wait(for: [exp], timeout: 20)
        return out ?? InboundImport.Result(added: [], alreadyPresent: [], rejected: -1, limited: -1)
    }
    private func images(in folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { !$0.hasPrefix(".") && $0 != "index.json" }.sorted()
    }

    func testAcceptsImageExtensionsRejectsOthers() throws {
        let d = try tempDir()
        XCTAssertTrue(InboundImport.accepts(try source("a.png", in: d)))
        XCTAssertTrue(InboundImport.accepts(try source("b.JPG", in: d)))
        XCTAssertTrue(InboundImport.accepts(try source("c.heic", in: d)))
        XCTAssertFalse(InboundImport.accepts(try source("a.txt", in: d)))
        XCTAssertFalse(InboundImport.accepts(try source(".hidden.png", in: d)))
        XCTAssertFalse(InboundImport.accepts(try source("~tmp.png", in: d)))
        XCTAssertFalse(InboundImport.accepts(d.appendingPathComponent("yok.png")), "olmayan dosya")
        let dir = d.appendingPathComponent("klasor.png", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        XCTAssertFalse(InboundImport.accepts(dir), "klasör")
    }

    func testCopiesIntoFolderAndKeepsSource() throws {
        let src = try tempDir("src"), folder = try tempDir("gelen")
        let s = try source("Ekran.png", in: src)
        let old = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: s.path)
        let before = try Data(contentsOf: s)
        let now = Date()
        let r = runImport([s], into: folder, now: now)
        XCTAssertEqual(r.added.count, 1); XCTAssertEqual(r.rejected, 0); XCTAssertEqual(r.limited, 0)
        let copy = try XCTUnwrap(r.added.first)
        XCTAssertEqual(copy.deletingLastPathComponent().resolvingSymlinksInPath().path, folder.resolvingSymlinksInPath().path)
        XCTAssertEqual(copy.lastPathComponent, "Ekran.png", "özgün ad korunur")
        XCTAssertEqual(try Data(contentsOf: copy), before)
        // Özgün dosya: aynı yer, aynı bayt, aynı mtime.
        XCTAssertEqual(try Data(contentsOf: s), before)
        let srcMod = try FileManager.default.attributesOfItem(atPath: s.path)[.modificationDate] as? Date
        XCTAssertEqual(srcMod?.timeIntervalSince1970 ?? 0, old.timeIntervalSince1970, accuracy: 1)
        // Kopyanın mtime'ı içe aktarma anı: temizlikçinin 7 günlük saati kopyadan başlar.
        let copyMod = try FileManager.default.attributesOfItem(atPath: copy.path)[.modificationDate] as? Date
        XCTAssertEqual(copyMod?.timeIntervalSince1970 ?? 0, now.timeIntervalSince1970, accuracy: 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("index.json").path))
    }

    func testDuplicateContentReusesCopy() throws {
        let src = try tempDir("src"), folder = try tempDir("gelen")
        let s = try source("a.png", in: src)
        let first = runImport([s], into: folder)
        XCTAssertEqual(first.added.count, 1)
        let second = runImport([s], into: folder)
        XCTAssertEqual(second.added, [])
        XCTAssertEqual(second.alreadyPresent, first.added)
        XCTAssertEqual(images(in: folder), ["a.png"], "ikinci kopya yazılmaz")
        // Aynı içerik başka adla gelse de mevcut kopya verilir.
        let other = src.appendingPathComponent("b.png"); try FileManager.default.copyItem(at: s, to: other)
        XCTAssertEqual(runImport([other], into: folder).alreadyPresent, first.added)
        XCTAssertEqual(images(in: folder), ["a.png"])
    }

    func testIndexEntryDroppedWhenCopyGone() throws {
        let src = try tempDir("src"), folder = try tempDir("gelen"), elsewhere = try tempDir("baska")
        let s = try source("a.png", in: src)
        let copy = try XCTUnwrap(runImport([s], into: folder).added.first)
        try FileManager.default.moveItem(at: copy, to: elsewhere.appendingPathComponent("a.png")) // kopya artık yok
        let again = runImport([s], into: folder)
        XCTAssertEqual(again.added.count, 1, "indeks girdisi düşer, yeni kopya yazılır")
        XCTAssertEqual(again.alreadyPresent, [])
        XCTAssertEqual(images(in: folder), ["a.png"])
    }

    func testNameCollisionGetsSuffix() throws {
        let src1 = try tempDir("s1"), src2 = try tempDir("s2"), folder = try tempDir("gelen")
        let a1 = try source("a.png", in: src1, seed: 1), a2 = try source("a.png", in: src2, seed: 2)
        XCTAssertEqual(runImport([a1], into: folder).added.map(\.lastPathComponent), ["a.png"])
        XCTAssertEqual(runImport([a2], into: folder).added.map(\.lastPathComponent), ["a (2).png"])
        XCTAssertEqual(InboundImport.uniqueDestination(for: "a.png", in: folder).lastPathComponent, "a (3).png")
        XCTAssertEqual(InboundImport.uniqueDestination(for: "yeni.png", in: folder).lastPathComponent, "yeni.png")
    }

    func testShortCircuitsWatchedFolderAndContainer() throws {
        let watched = try tempDir("izlenen"), other = try tempDir("diger"), container = try tempDir("konteyner")
        let w = try source("x.png", in: watched), o = try source("x.png", in: other, seed: 3)
        XCTAssertTrue(InboundImport.shortCircuit(w, watchedFolder: watched, container: container))
        XCTAssertFalse(InboundImport.shortCircuit(o, watchedFolder: watched, container: container))
        XCTAssertFalse(InboundImport.shortCircuit(o, watchedFolder: nil, container: container))
        let sub = container.appendingPathComponent("Türevler", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        XCTAssertTrue(InboundImport.shortCircuit(try source("t.png", in: sub), watchedFolder: nil, container: container))
        // Ad öneki benzerliği kapsam sayılmaz ("/izlenen" ≠ "/izlenen2").
        let sibling = URL(fileURLWithPath: watched.path + "2", isDirectory: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        XCTAssertFalse(InboundImport.shortCircuit(try source("y.png", in: sibling), watchedFolder: watched, container: container))
        // importFiles: izlenen klasördeki dosya kopyalanmaz, URL olduğu gibi döner.
        let folder = try tempDir("gelen")
        let r = runImport([w], into: folder, watched: watched)
        XCTAssertEqual(r.added, [w]); XCTAssertEqual(images(in: folder), [])
    }

    func testLimitsCountAndSize() throws {
        let src = try tempDir("src"), folder = try tempDir("gelen")
        let urls = try (0..<21).map { try source("k\($0).png", in: src, seed: $0 + 10) }
        let r = runImport(urls, into: folder)
        XCTAssertEqual(r.added.count, InboundImport.maxCount); XCTAssertEqual(r.limited, 1); XCTAssertEqual(r.rejected, 0)
        XCTAssertEqual(images(in: folder).count, 20)

        let big = src.appendingPathComponent("buyuk.png")
        XCTAssertTrue(FileManager.default.createFile(atPath: big.path, contents: nil))
        let h = try FileHandle(forWritingTo: big); try h.truncate(atOffset: UInt64(InboundImport.maxBytes + 1)); try h.close()
        let folder2 = try tempDir("gelen2")
        let rb = runImport([big], into: folder2)
        XCTAssertEqual(rb.oversized, 1, "boyut reddi türden ayrı sayılır"); XCTAssertEqual(rb.rejected, 0)
        XCTAssertEqual(rb.added, []); XCTAssertEqual(images(in: folder2), [])
        // Kabul edilmeyen tür reddedilir, sınıra sayılmaz.
        let txt = src.appendingPathComponent("not.txt"); try Data("x".utf8).write(to: txt)
        XCTAssertEqual(runImport([txt], into: folder2).rejected, 1)
    }

    /// Sembolik bağlantı: hedefin içeriği düzenli dosya olarak kopyalanır; hedefin mtime'ı değişmez; boyut hedeften okunur.
    func testSymlinkCopiesTargetContentAndKeepsSourceMtime() throws {
        let fm = FileManager.default
        let src = try tempDir("src"), links = try tempDir("link"), folder = try tempDir("gelen")
        let target = try source("a.png", in: src, seed: 41)
        let old = Date(timeIntervalSince1970: 1_700_000_000)
        try fm.setAttributes([.modificationDate: old], ofItemAtPath: target.path)
        let link = links.appendingPathComponent("link.png")
        try fm.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertTrue(InboundImport.accepts(link))
        let r = runImport([link], into: folder, now: Date())
        XCTAssertEqual(r.added.count, 1); XCTAssertEqual(r.rejected, 0)
        let copy = try XCTUnwrap(r.added.first)
        XCTAssertEqual(try fm.attributesOfItem(atPath: copy.path)[.type] as? FileAttributeType, .typeRegular, "kopya bağlantı değil")
        XCTAssertEqual(copy.lastPathComponent, "link.png", "bırakılan ad korunur")
        XCTAssertEqual(try Data(contentsOf: copy), try Data(contentsOf: target))
        let mtime = try XCTUnwrap(try fm.attributesOfItem(atPath: target.path)[.modificationDate] as? Date)
        XCTAssertEqual(mtime.timeIntervalSince1970, old.timeIntervalSince1970, accuracy: 1, "özgün dosyanın mtime'ı değişmez")
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: link.path), target.path, "bağlantı yerinde")

        // Büyük hedefe bağlantı: boyut bağlantıdan değil hedeften → oversized.
        let big = src.appendingPathComponent("buyuk.png")
        XCTAssertTrue(fm.createFile(atPath: big.path, contents: nil))
        let h = try FileHandle(forWritingTo: big); try h.truncate(atOffset: UInt64(InboundImport.maxBytes + 1)); try h.close()
        let bigLink = links.appendingPathComponent("buyuk-link.png")
        try fm.createSymbolicLink(at: bigLink, withDestinationURL: big)
        let folder2 = try tempDir("gelen2")
        XCTAssertEqual(runImport([bigLink], into: folder2).oversized, 1)
        XCTAssertEqual(images(in: folder2), [])

        // Görsel adlı bağlantı görsel olmayan hedefe: reddedilir.
        let txt = src.appendingPathComponent("not.txt"); try Data("x".utf8).write(to: txt)
        let txtLink = links.appendingPathComponent("sahte.png")
        try fm.createSymbolicLink(at: txtLink, withDestinationURL: txt)
        XCTAssertFalse(InboundImport.accepts(txtLink))
        XCTAssertEqual(runImport([txtLink], into: folder2).rejected, 1)
    }

    func testImportDataOversizedOutcome() throws {
        let folder = try tempDir("gelen")
        let exp = expectation(description: "big"); var out: InboundImport.Outcome?
        InboundImport.importDataOutcome(Data(count: InboundImport.maxBytes + 1), fileExtension: "tiff", source: .service, into: folder, completion: { out = $0; exp.fulfill() })
        wait(for: [exp], timeout: 20)
        XCTAssertEqual(out, .oversized)
        let png = pngData(seed: 9)
        func run() -> InboundImport.Outcome? {
            let e = expectation(description: "png"); var o: InboundImport.Outcome?
            InboundImport.importDataOutcome(png, fileExtension: "png", source: .service, into: folder, completion: { o = $0; e.fulfill() })
            wait(for: [e], timeout: 20); return o
        }
        guard case .added(let u)? = run() else { return XCTFail("ilk yazım eklenmeli") }
        XCTAssertEqual(run(), .alreadyPresent(u))
    }

    func testImportDataWritesPNG() throws {
        let folder = try tempDir("gelen")
        func run(_ data: Data, _ ext: String) -> URL? {
            let exp = expectation(description: "data"); var out: URL?
            InboundImport.importDataOutcome(data, fileExtension: ext, source: .service, into: folder) { o in
                XCTAssertTrue(Thread.isMainThread)
                if case .added(let u) = o { out = u } else if case .alreadyPresent(let u) = o { out = u }
                exp.fulfill()
            }
            wait(for: [exp], timeout: 20); return out
        }
        let png = pngData(seed: 7)
        let u = try XCTUnwrap(run(png, "png"))
        XCTAssertEqual(u.pathExtension, "png")
        XCTAssertEqual(try Data(contentsOf: u).prefix(8), Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
        XCTAssertEqual(run(png, "png"), u, "aynı veri ikinci kez yazılmaz")
        XCTAssertEqual(images(in: folder).count, 1)
        XCTAssertNil(run(Data("x".utf8), "txt"), "kabul edilmeyen uzantı")
    }

    func testSha256Streams() throws {
        let d = try tempDir()
        let u = d.appendingPathComponent("abc.bin"); try Data("abc".utf8).write(to: u)
        XCTAssertEqual(try InboundImport.sha256(of: u), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        let big = d.appendingPathComponent("big.bin"); try Data(repeating: 0x61, count: 2_500_000).write(to: big) // birden çok parça
        XCTAssertEqual(try InboundImport.sha256(of: big).count, 64)
    }

    func testSourceUntouchedOnFailure() throws {
        let src = try tempDir("src"), folder = try tempDir("gelen")
        let s = try source("a.png", in: src); let before = try Data(contentsOf: s)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: folder.path); lockedFolders.append(folder)
        let r = runImport([s], into: folder)
        XCTAssertEqual(r.rejected, 1); XCTAssertEqual(r.added, []); XCTAssertEqual(r.alreadyPresent, [])
        XCTAssertEqual(try Data(contentsOf: s), before)
        XCTAssertTrue(FileManager.default.fileExists(atPath: s.path))
    }

    func testImportedSourceRoundTrips() throws {
        let item = ShelfItem(path: "/tmp/x.png", fileID: nil, capturedAt: Date(timeIntervalSince1970: 0), source: .imported)
        let back = try JSONDecoder().decode(ShelfItem.self, from: JSONEncoder().encode(item))
        XCTAssertEqual(back.source, .imported)
    }
}
