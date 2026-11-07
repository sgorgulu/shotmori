import XCTest
import AppKit
import UniformTypeIdentifiers
@testable import Shotmori

final class EditorTests: XCTestCase {
    /// Soldan sağa kırmızı→mavi gradyan, üstten alta yeşil artan: her pikselin yeri renginden okunur.
    func gradient(_ w: Int, _ h: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let p = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h * 4); let bpr = ctx.bytesPerRow
        for y in 0..<h { for x in 0..<w { let i = y * bpr + x * 4; p[i] = UInt8(255 * x / max(w - 1, 1)); p[i+1] = UInt8(255 * y / max(h - 1, 1)); p[i+2] = UInt8(255 - 255 * x / max(w - 1, 1)); p[i+3] = 255 } }
        return ctx.makeImage()!
    }
    /// Renk uzayı dönüşümü olmadan ham örnek değerleri (PNG → sRGB 8 bit).
    func pixel(_ data: Data, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        let src = CGImageSourceCreateWithData(data as CFData, nil)!; let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
        let ctx = CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: img.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        let p = ctx.data!.bindMemory(to: UInt8.self, capacity: img.width * img.height * 4); let i = (y * img.width + x) * 4 // bitmap belleğinde 0. satır en üsttür
        return (Int(p[i]), Int(p[i+1]), Int(p[i+2]), Int(p[i+3]))
    }
    func tempURL(_ name: String) throws -> URL { let d = FileManager.default.temporaryDirectory.appendingPathComponent("editor-\(UUID())", isDirectory: true); try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); return d.appendingPathComponent(name) }

    func testCropProducesExactPixelRegionTopLeftOrigin() throws {
        let src = gradient(200, 100)
        var st = EditState(); st.crop = CGRect(x: 150, y: 20, width: 40, height: 30)   // sağ-üste yakın bölge
        let out = try EditRenderer.render(source: src, state: st, format: .png)
        let rep = NSBitmapImageRep(data: out)!; XCTAssertEqual(rep.pixelsWide, 40); XCTAssertEqual(rep.pixelsHigh, 30)
        let p = pixel(out, 0, 0) // kaynak (150,20): r≈255*150/199=192, g≈255*20/99=52
        XCTAssertEqual(p.r, 192, accuracy: 3); XCTAssertEqual(p.g, 52, accuracy: 3)
        let q = pixel(out, 39, 29) // kaynak (189,49)
        XCTAssertEqual(q.r, 242, accuracy: 3); XCTAssertEqual(q.g, 126, accuracy: 3)
    }
    func testRedactionIsOpaqueBlackAndOutsideUntouched() throws {
        let src = gradient(100, 100)
        var st = EditState(); st.redactions = [CGRect(x: 10, y: 10, width: 20, height: 20)]
        let out = try EditRenderer.render(source: src, state: st, format: .png)
        for (x, y) in [(10, 10), (29, 29), (20, 15)] { let p = pixel(out, x, y); XCTAssertEqual(p.r, 0); XCTAssertEqual(p.g, 0); XCTAssertEqual(p.b, 0); XCTAssertEqual(p.a, 255, "\(x),\(y) tam opak olmalı") }
        let o = pixel(out, 9, 9); XCTAssertNotEqual(o.r + o.g + o.b, 0, "alan dışı değişmemeli")
        let o2 = pixel(out, 30, 30); XCTAssertNotEqual(o2.r + o2.g + o2.b, 0)
    }
    func testCropAndRedactionCombineInSourceCoordinates() throws {
        let src = gradient(200, 200)
        var st = EditState(); st.crop = CGRect(x: 50, y: 50, width: 100, height: 100); st.redactions = [CGRect(x: 60, y: 70, width: 10, height: 10), CGRect(x: 0, y: 0, width: 40, height: 40)] // ikincisi kırpma dışında
        let out = try EditRenderer.render(source: src, state: st, format: .png)
        XCTAssertEqual(pixel(out, 10, 20).a, 255); XCTAssertEqual(pixel(out, 10, 20).r + pixel(out, 10, 20).g + pixel(out, 10, 20).b, 0) // (60,70) → (10,20)
        XCTAssertNotEqual(pixel(out, 9, 19).r + pixel(out, 9, 19).g + pixel(out, 9, 19).b, 0)
        XCTAssertNotEqual(pixel(out, 0, 0).r + pixel(out, 0, 0).g + pixel(out, 0, 0).b, 0, "kırpma dışındaki alan çıktıyı etkilememeli")
    }
    func testOutputCarriesNoSourceMetadataOrThumbnail() throws {
        // EXIF/yön bilgili JPEG kaynak → düzenlenmiş PNG çıktıda EXIF/TIFF yok, gömülü küçük resim yok
        let src = gradient(120, 80)
        let data = NSMutableData(); let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, src, [kCGImagePropertyOrientation: 6, kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "gizli"]] as CFDictionary); CGImageDestinationFinalize(dest)
        let url = try tempURL("src.jpg"); try (data as Data).write(to: url)
        let oriented = try EditRenderer.loadOriented(url)
        XCTAssertEqual(oriented.width, 80); XCTAssertEqual(oriented.height, 120, "yön 6 → 90° döndürülmüş")
        var st = EditState(); st.redactions = [CGRect(x: 0, y: 0, width: 80, height: 120)]
        let out = try EditRenderer.render(source: oriented, state: st, format: .png)
        let s = CGImageSourceCreateWithData(out as CFData, nil)!
        let props = CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as! [CFString: Any]
        XCTAssertNil(props[kCGImagePropertyExifDictionary], "çıktıda EXIF olmamalı"); XCTAssertNil(props[kCGImagePropertyTIFFDictionary]); XCTAssertNil(props[kCGImagePropertyOrientation])
        let chunks = PNGChunkFilter.chunkTypes(out)
        XCTAssertFalse(chunks.contains { ["eXIf", "tEXt", "zTXt", "iTXt", "tIME"].contains($0) }, "yalnızca görüntü/renk chunk'ları kalmalı: \(chunks)")
        XCTAssertTrue(chunks.first == "IHDR" && chunks.last == "IEND" && chunks.contains("IDAT"))
        XCTAssertFalse(String(data: out, encoding: .isoLatin1)!.contains("gizli"))
        XCTAssertNotNil(NSBitmapImageRep(data: out), "temizlenmiş PNG hâlâ geçerli")
        for (x, y) in [(0, 0), (79, 119), (40, 60)] { XCTAssertEqual(pixel(out, x, y).r + pixel(out, x, y).g + pixel(out, x, y).b, 0) }
    }
    func testSourceFileUnchangedAndDerivativeHasDifferentIdentity() throws {
        let url = try tempURL("orig.png")
        let d = NSMutableData(); let dest = CGImageDestinationCreateWithData(d, UTType.png.identifier as CFString, 1, nil)!; CGImageDestinationAddImage(dest, gradient(50, 50), nil); CGImageDestinationFinalize(dest); try (d as Data).write(to: url)
        let before = try Data(contentsOf: url); let id0 = ScreenshotFileInspector.fileIdentifier(url)
        var st = EditState(); st.crop = CGRect(x: 0, y: 0, width: 25, height: 25)
        let out = try EditRenderer.render(source: try EditRenderer.loadOriented(url), state: st, format: .png)
        let folder = url.deletingLastPathComponent().appendingPathComponent("deriv", isDirectory: true); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let du = EditRenderer.derivativeURL(for: url, format: .png, in: folder); try out.write(to: du, options: .atomic)
        XCTAssertEqual(try Data(contentsOf: url), before); XCTAssertNotEqual(ScreenshotFileInspector.fileIdentifier(du), id0)
        XCTAssertTrue(du.lastPathComponent.contains("(\(S.editedBadge))"))
        let du2 = EditRenderer.derivativeURL(for: url, format: .png, in: folder); XCTAssertNotEqual(du, du2)
        let st2 = ShelfStore(fileURL: nil, maxItems: 10)
        XCTAssertTrue(st2.add(ShelfItem(path: du.path, fileID: ScreenshotFileInspector.fileIdentifier(du), capturedAt: Date(), source: .derivative)))
        XCTAssertFalse(st2.add(ShelfItem(path: du.path, fileID: nil, capturedAt: Date(), source: .derivative)), "mükerrer eklenmemeli")
    }
    func testClipboardRepresentationsAllUseEditedData() throws {
        let edited = try EditRenderer.render(source: gradient(30, 30), state: { var s = EditState(); s.redactions = [CGRect(x: 0, y: 0, width: 30, height: 30)]; return s }(), format: .png)
        let url = try tempURL("edited.png"); try edited.write(to: url)
        let payload = ClipboardPayload.make(edited: edited, format: .png, fileURL: url)
        let pb = NSPasteboard(name: NSPasteboard.Name("dev.shotmori.test.\(UUID())")); payload.write(to: pb)
        XCTAssertEqual(pb.data(forType: .png), edited)
        XCTAssertEqual(pb.string(forType: .fileURL).flatMap { URL(string: $0) }?.standardizedFileURL, url.standardizedFileURL)
        XCTAssertEqual(try Data(contentsOf: url), edited, "dosya temsili de düzenlenmiş veri")
    }
    func testUndoRedoAndClamping() {
        let doc = EditDocument(imageSize: CGSize(width: 100, height: 60))
        doc.beginChange(); doc.setCrop(CGRect(x: -10, y: 10, width: 50, height: 100))
        XCTAssertEqual(doc.state.crop, CGRect(x: 0, y: 10, width: 40, height: 50), "görüntü sınırına kırpılmalı")
        doc.beginChange(); doc.setCrop(CGRect(x: 200, y: 200, width: 10, height: 10)); XCTAssertNil(doc.state.crop, "tamamen dışarıda → yok")
        doc.undo(); XCTAssertEqual(doc.state.crop?.width, 40); doc.redo(); XCTAssertNil(doc.state.crop)
        doc.beginChange(); doc.addRedaction(CGRect(x: 10, y: 10, width: 0.4, height: 5)); XCTAssertTrue(doc.state.redactions.isEmpty, "sıfır alan eklenmez")
        doc.beginChange(); doc.addRedaction(CGRect(x: 10.6, y: 10.2, width: 5.9, height: 5.9)); XCTAssertEqual(doc.state.redactions.first, CGRect(x: 10, y: 10, width: 6, height: 6))
        XCTAssertTrue(doc.canUndo); doc.undo(); XCTAssertTrue(doc.state.redactions.isEmpty); XCTAssertTrue(doc.canRedo)
    }
    /// Geri aldıktan sonra değişiklik yapmayan bir hareket (tuvale tıklama, seçimsiz ⌫/ok) yineleme geçmişini silmez; gerçek değişiklik siler.
    func testCancelledChangeKeepsRedo() {
        let doc = EditDocument(imageSize: CGSize(width: 100, height: 60))
        doc.beginChange(); doc.addRedaction(CGRect(x: 2, y: 2, width: 10, height: 10))
        doc.undo(); XCTAssertTrue(doc.canRedo)
        doc.beginChange(); doc.cancelChange()
        XCTAssertTrue(doc.canRedo, "iptal edilen değişiklik yinelemeyi geri getirir")
        XCTAssertFalse(doc.canUndo, "iptal edilen kayıt geri alma yığınında kalmaz")
        doc.redo(); XCTAssertEqual(doc.state.redactions.count, 1)
        doc.undo(); doc.beginChange(); doc.setCrop(CGRect(x: 0, y: 0, width: 50, height: 30))
        XCTAssertFalse(doc.canRedo, "gerçek değişiklik yineleme geçmişini temizler")
        doc.beginChange(); doc.cancelChange()
        XCTAssertFalse(doc.canRedo, "gerçek değişiklikten sonraki iptal eski geçmişi geri getirmez")
    }
    /// Düzen menüsündeki Geri al / Yinele yalnız belgede geri alınacak / yinelenecek adım varken etkin.
    func testCanvasValidatesUndoRedoByDocState() {
        let doc = EditDocument(imageSize: CGSize(width: 40, height: 30)); let canvas = EditorCanvasView(doc: doc, preview: gradient(40, 30))
        let undo = NSMenuItem(title: "", action: #selector(EditorCanvasView.undo(_:)), keyEquivalent: "z"), redo = NSMenuItem(title: "", action: #selector(EditorCanvasView.redo(_:)), keyEquivalent: "Z")
        XCTAssertFalse(canvas.validateMenuItem(undo), "yeni belge"); XCTAssertFalse(canvas.validateMenuItem(redo), "yeni belge")
        doc.beginChange(); doc.addRedaction(CGRect(x: 2, y: 2, width: 10, height: 10))
        XCTAssertTrue(canvas.validateMenuItem(undo)); XCTAssertFalse(canvas.validateMenuItem(redo))
        doc.undo(); XCTAssertFalse(canvas.validateMenuItem(undo)); XCTAssertTrue(canvas.validateMenuItem(redo))
    }
    func testAspectRectAndTransformInvariantUnderZoom() {
        let r = EditDocument.rect(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 90, y: 20), aspect: .square)
        XCTAssertEqual(r.width, 80); XCTAssertEqual(r.height, 80)
        let w = EditDocument.rect(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 160, y: 1000), aspect: .wide16x9)
        XCTAssertEqual(w.width, 1000 * 16 / 9, accuracy: 0.01); XCTAssertEqual(w.height, 1000)
        let pixelRect = CGRect(x: 100, y: 50, width: 300, height: 200)
        for scale in [0.25, 0.5, 1.0, 2.0] as [CGFloat] {
            let t = CanvasTransform(scale: scale, origin: CGPoint(x: 17, y: 23))
            XCTAssertEqual(t.toImage(t.toView(pixelRect)), pixelRect, "zoom \(scale) altında geri dönüşüm kayıpsız")
        }
    }
    func testFitMagnificationIgnoresCurrentZoomAndCapsAt100() {
        // 1500×1000 tuval, 844×500 görünür alan → genişlik ve yükseklik oranlarının küçüğü
        XCTAssertEqual(EditorZoom.fitMagnification(visible: NSSize(width: 844, height: 500), content: NSSize(width: 1500, height: 1000))!, 0.484, accuracy: 0.001)
        XCTAssertEqual(EditorZoom.fitMagnification(visible: NSSize(width: 2000, height: 2000), content: NSSize(width: 300, height: 200)), 1)
        XCTAssertNil(EditorZoom.fitMagnification(visible: .zero, content: NSSize(width: 10, height: 10)))
    }
}
