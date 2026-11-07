import XCTest
import AppKit
import ImageIO
@testable import Shotmori

/// Widget anlık görüntüsü: en yeni 3 kare (tüm raflar), sabit adlı küçük resimler, atomik yazım, debounce, yalıtılmış klasör.
final class WidgetSnapshotTests: XCTestCase {
    private func tempDir(_ tag: String = "") throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("shotmori-widget-\(tag)\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); return d
    }
    private func png(width: Int, height: Int, seed: Int = 0) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let c = NSColor(deviceRed: CGFloat(seed % 7) / 7, green: 0.4, blue: 0.6, alpha: 1)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        c.setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }
    /// Diskte gerçek PNG'si olan raf öğesi.
    private func item(_ name: String, in dir: URL, added: Date, width: Int = 400, height: Int = 300) throws -> ShelfItem {
        let u = dir.appendingPathComponent(name); try png(width: width, height: height).write(to: u)
        return ShelfItem(path: u.path, fileID: nil, capturedAt: added, addedAt: added)
    }
    private func store() -> ShelfStore { ShelfStore(fileURL: nil, maxItems: 50) }
    private func readSnapshot(_ container: URL) throws -> WidgetSnapshot {
        try JSONDecoder().decode(WidgetSnapshot.self, from: Data(contentsOf: container.appendingPathComponent(WidgetSnapshot.fileName)))
    }
    private func pixelSize(_ data: Data) -> (Int, Int)? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (w, h)
    }
    private func files(in d: URL) -> [String] { ((try? FileManager.default.contentsOfDirectory(atPath: d.path)) ?? []).sorted() }

    func testBuildTakesNewestThreeAcrossShelves() throws {
        let d = try tempDir("src"), s = store(), b = try XCTUnwrap(s.addShelf()).id
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        let a1 = try item("a1.png", in: d, added: t), a4 = try item("a4.png", in: d, added: t + 4)
        let b2 = try item("b2.png", in: d, added: t + 2), b3 = try item("b3.png", in: d, added: t + 3), b5 = try item("b5.png", in: d, added: t + 5)
        let trashed = try item("b6.png", in: d, added: t + 6)
        s.add([a1, a4]); s.add([b2, b3, b5, trashed], to: b)
        s.markLocalTrashed(itemID: trashed.id)
        let snap = WidgetSnapshotWriter.build(store: s)
        XCTAssertEqual(snap.version, WidgetSnapshot.version)
        XCTAssertEqual(snap.items.map(\.id), [b5.id, a4.id, b3.id], "tüm raflardan en yeni 3 (eklenme zamanı); yerelde çöpe atılan küçük resim veremez")
        XCTAssertEqual(snap.items.map(\.thumb), ["thumb-0.png", "thumb-1.png", "thumb-2.png"])
        XCTAssertEqual(snap.items.map(\.fileName), ["", "", ""], "dosya adı grup konteynerine yazılmaz (widget kullanmıyor)")
        XCTAssertEqual(snap.totalCount, 6)
    }

    func testBuildCarriesAppLanguageAndDecodesWithoutIt() throws {
        let d = try tempDir("src"), c = try tempDir("grp"), s = store()
        s.add(try item("tek.png", in: d, added: Date()))
        XCTAssertNil(WidgetSnapshotWriter.build(store: s).language, "dil verilmezse sistem dili (nil)")
        try WidgetSnapshotWriter(store: s, container: c, language: { "tr" }, reload: {}).writeNow()
        XCTAssertEqual(try readSnapshot(c).language, "tr", "uygulama dili anlık görüntüye yazılır")
        let old = Data(#"{"version":1,"totalCount":0,"newCount":0,"items":[]}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(WidgetSnapshot.self, from: old).language, "dil alanı olmayan eski JSON okunur")
    }

    func testLanguageChangeSchedulesWrite() throws {
        let d = try tempDir("src"), c = try tempDir("grp"), s = store()
        s.add(try item("tek.png", in: d, added: Date()))
        var lang: String? = nil
        let w = WidgetSnapshotWriter(store: s, container: c, language: { lang }, reload: {})
        try w.writeNow(); XCTAssertNil(try readSnapshot(c).language)
        lang = "en"; try w.writeNow()
        XCTAssertEqual(try readSnapshot(c).language, "en", "dil değişince yeni yazım dili taşır")
    }

    func testSnapshotWithFewerThanThreeItems() throws {
        let d = try tempDir("src"), c = try tempDir("grp"), s = store()
        try Data("eski kare".utf8).write(to: c.appendingPathComponent("thumb-1.png")) // önceki yazımdan kalan
        s.add(try item("tek.png", in: d, added: Date()))
        try WidgetSnapshotWriter(store: s, container: c, reload: {}).writeNow()
        let snap = try readSnapshot(c)
        XCTAssertEqual(snap.items.count, 1)
        XCTAssertEqual(snap.items.first?.thumb, "thumb-0.png")
        let json = try String(contentsOf: c.appendingPathComponent(WidgetSnapshot.fileName), encoding: .utf8)
        XCTAssertFalse(json.contains("thumb-1"), "kalan eski thumb dosyası JSON'da yok; widget onu göstermez")
        XCTAssertFalse(json.contains("tek.png"), "dosya adı yazılmaz")
        XCTAssertNotNil(pixelSize(try Data(contentsOf: c.appendingPathComponent("thumb-0.png"))))
        for i in 1...2 { XCTAssertEqual(try Data(contentsOf: c.appendingPathComponent("thumb-\(i).png")), WidgetSnapshotWriter.blankPNG, "boş yuva saydam PNG ile ezildi") }
    }
    /// Raftan düşen karenin küçük resmi grup konteynerinde kalmaz: yuva saydam PNG ile ezilir (silme yok).
    func testRemovedItemThumbIsOverwritten() throws {
        let d = try tempDir("src"), c = try tempDir("grp"), s = store()
        let a = try item("a.png", in: d, added: Date(timeIntervalSinceNow: -10)), b = try item("b.png", in: d, added: Date())
        s.add([a, b])
        let w = WidgetSnapshotWriter(store: s, container: c, reload: {})
        try w.writeNow()
        XCTAssertNotEqual(try Data(contentsOf: c.appendingPathComponent("thumb-1.png")), WidgetSnapshotWriter.blankPNG)
        s.remove(ids: [a.id]); try w.writeNow()
        XCTAssertEqual(try Data(contentsOf: c.appendingPathComponent("thumb-1.png")), WidgetSnapshotWriter.blankPNG)
        XCTAssertEqual(pixelSize(WidgetSnapshotWriter.blankPNG).map { [$0.0, $0.1] }, [1, 1])
    }

    func testWriteIsAtomicAndOverwrites() throws {
        let d = try tempDir("src"), c = try tempDir("grp"), s = store()
        let first = try item("ilk.png", in: d, added: Date(timeIntervalSinceNow: -10), width: 320, height: 160)
        s.add(first)
        let w = WidgetSnapshotWriter(store: s, container: c, reload: {})
        try w.writeNow()
        let thumbBefore = try Data(contentsOf: c.appendingPathComponent("thumb-0.png"))
        let second = try item("ikinci.png", in: d, added: Date(), width: 160, height: 320)
        s.add(second)
        try w.writeNow()
        let thumbAfter = try Data(contentsOf: c.appendingPathComponent("thumb-0.png"))
        XCTAssertNotEqual(thumbBefore, thumbAfter, "thumb-0 en yeni kareyle üzerine yazıldı")
        let (tw, th) = try XCTUnwrap(pixelSize(thumbAfter)); XCTAssertLessThan(tw, th, "dikey ikinci kare")
        XCTAssertEqual(try readSnapshot(c).items.map(\.id), [second.id, first.id])
        let names = files(in: c)
        XCTAssertEqual(names.filter { $0.hasSuffix(".json") }, [WidgetSnapshot.fileName], "tek JSON, geçici dosya kalmaz")
        XCTAssertLessThanOrEqual(names.count, 4)
        XCTAssertTrue(names.allSatisfy { $0 == WidgetSnapshot.fileName || $0.hasPrefix("thumb-") }, "\(names)")
    }

    func testDebounceCoalesces() throws {
        let d = try tempDir("src"), c = try tempDir("grp"), s = store()
        s.add(try item("a.png", in: d, added: Date()))
        let w = WidgetSnapshotWriter(store: s, container: c, debounce: 0.2, reload: {})
        let wrote = expectation(description: "yazım")
        w.onWrite = { wrote.fulfill() }
        for _ in 0..<3 { w.scheduleWrite(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03)) }
        wait(for: [wrote], timeout: 5)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
        XCTAssertEqual(w.writeCount, 1, "0,1 sn içindeki 3 istek tek yazıma iner")
        XCTAssertEqual(try readSnapshot(c).items.count, 1)
    }

    func testNewCountMatchesHandoff() throws {
        let d = try tempDir("src"), s = store(), b = try XCTUnwrap(s.addShelf()).id
        s.add(try item("eski.png", in: d, added: Date(timeIntervalSinceNow: -100)))
        s.markHandoff(at: Date(timeIntervalSinceNow: -50))
        s.add(try item("yeni.png", in: d, added: Date()))
        s.add(try item("diger.png", in: d, added: Date()), to: b) // aktarım yapılmamış raf: hepsi yeni
        let snap = WidgetSnapshotWriter.build(store: s)
        XCTAssertEqual(snap.newCount, 2)
        XCTAssertEqual(snap.newCount, s.newCountAll)
        XCTAssertEqual(snap.totalCount, 3)
    }

    func testThumbnailMaxPixel() throws {
        let d = try tempDir("src")
        let big = d.appendingPathComponent("buyuk.png"); try png(width: 1200, height: 600).write(to: big)
        let data = try XCTUnwrap(WidgetSnapshotWriter.thumbnailPNG(for: big))
        XCTAssertEqual(Array(data.prefix(4)), [0x89, 0x50, 0x4E, 0x47], "PNG imzası")
        let (w, h) = try XCTUnwrap(pixelSize(data))
        XCTAssertEqual(max(w, h), 160); XCTAssertEqual(w, 2 * h, "en-boy oranı korunur")
        let small = d.appendingPathComponent("kucuk.png"); try png(width: 40, height: 30).write(to: small)
        let (sw, sh) = try XCTUnwrap(pixelSize(try XCTUnwrap(WidgetSnapshotWriter.thumbnailPNG(for: small))))
        XCTAssertLessThanOrEqual(max(sw, sh), 160)
        XCTAssertNil(WidgetSnapshotWriter.thumbnailPNG(for: d.appendingPathComponent("yok.png")))
    }

    func testIsolatedContainerUsedWhenDataDirSet() throws {
        let root = try tempDir("veri")
        XCTAssertEqual(WidgetSnapshotWriter.containerURL(isolatedRoot: root)?.standardizedFileURL,
                       root.appendingPathComponent("WidgetGroup", isDirectory: true).standardizedFileURL)
        XCTAssertNotEqual(WidgetSnapshotWriter.containerURL(isolatedRoot: nil)?.standardizedFileURL.path,
                          root.appendingPathComponent("WidgetGroup").standardizedFileURL.path, "yalıtımsız: sistem grup konteyneri")
        // Yazıcı klasörü kendisi oluşturur.
        let d = try tempDir("src"), s = store()
        s.add(try item("a.png", in: d, added: Date()))
        let c = try XCTUnwrap(WidgetSnapshotWriter.containerURL(isolatedRoot: root))
        try WidgetSnapshotWriter(store: s, container: c, reload: {}).writeNow()
        XCTAssertTrue(FileManager.default.fileExists(atPath: c.appendingPathComponent(WidgetSnapshot.fileName).path))
    }

    /// Değişmeyen anlık görüntü yeniden yazılmaz, widget zaman çizelgesi boşuna yenilenmez (WidgetKit yenileme bütçesi).
    func testUnchangedSnapshotSkipsReload() throws {
        let d = try tempDir("src"), c = try tempDir("grp"), s = store()
        s.add(try item("a.png", in: d, added: Date()))
        var reloads = 0
        let w = WidgetSnapshotWriter(store: s, container: c, reload: { reloads += 1 })
        try w.writeNow(); try w.writeNow()
        XCTAssertEqual(reloads, 1)
        s.add(try item("b.png", in: d, added: Date(timeIntervalSinceNow: 1)))
        try w.writeNow()
        XCTAssertEqual(reloads, 2)
    }

    /// Grup konteyneri yoksa (entitlement eksik) yazıcı sessizce hiçbir şey yapmaz.
    func testNilContainerIsNoOp() throws {
        let s = store(); var reloads = 0
        let w = WidgetSnapshotWriter(store: s, container: nil, reload: { reloads += 1 })
        XCTAssertNoThrow(try w.writeNow())
        XCTAssertEqual(reloads, 0)
    }
}
