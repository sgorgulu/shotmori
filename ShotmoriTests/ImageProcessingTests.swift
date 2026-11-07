import XCTest
import AppKit
@testable import Shotmori

final class ImageProcessingTests: XCTestCase {
    func makeImage(_ w: Int, _ h: Int, alpha: Bool) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("shotmori-img-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        if !alpha { ctx.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h)) }
        else { ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w / 2, height: h)) } // sağ yarı saydam
        let url = dir.appendingPathComponent("src.png")
        let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!); try rep.representation(using: .png, properties: [:])!.write(to: url)
        return url
    }
    func testAspectMathAndValidation() {
        let o = ResizeMath.Size(width: 1600, height: 1000)
        XCTAssertEqual(ResizeMath.heightKeepingAspect(original: o, width: 800), 500)
        XCTAssertEqual(ResizeMath.widthKeepingAspect(original: o, height: 250), 400)
        XCTAssertEqual(ResizeMath.scaled(o, percent: 50), .init(width: 800, height: 500))
        XCTAssertEqual(ResizeMath.validate(.init(width: 0, height: 10)), .tooSmall)
        XCTAssertEqual(ResizeMath.validate(.init(width: 20000, height: 10)), .tooLarge)
        XCTAssertEqual(ResizeMath.validate(.init(width: 1, height: 1)), .ok)
    }
    func testRenderProducesRequestedSizeAndLeavesSourceUntouched() throws {
        let src = try makeImage(400, 300, alpha: false)
        let before = try Data(contentsOf: src)
        let png = try ImageResizer.render(src, to: .init(width: 200, height: 150), format: .png, quality: 1)
        let img = NSBitmapImageRep(data: png)!
        XCTAssertEqual(img.pixelsWide, 200); XCTAssertEqual(img.pixelsHigh, 150)
        XCTAssertEqual(try Data(contentsOf: src), before, "orijinal değişmemeli")
        XCTAssertThrowsError(try ImageResizer.render(src, to: .init(width: 0, height: 5), format: .png, quality: 1))
    }
    func testJPEGFlattensTransparencyAndQualityChangesSize() throws {
        let src = try makeImage(300, 200, alpha: true)
        XCTAssertEqual(ImageResizer.sourceInfo(src)?.hasAlpha, true)
        let hi = try ImageResizer.render(src, to: .init(width: 300, height: 200), format: .jpeg, quality: 1.0)
        let lo = try ImageResizer.render(src, to: .init(width: 300, height: 200), format: .jpeg, quality: 0.3)
        XCTAssertLessThan(lo.count, hi.count)
        let rep = NSBitmapImageRep(data: hi)!
        XCTAssertFalse(rep.hasAlpha)
        let c = rep.colorAt(x: 280, y: 100)! // saydam bölge → beyaz zemin
        XCTAssertGreaterThan(c.redComponent, 0.95); XCTAssertGreaterThan(c.blueComponent, 0.95)
    }
    func testDerivativeNamingAvoidsCollisionsAndStaysOutsideWatchedFolder() throws {
        let src = try makeImage(100, 100, alpha: false)
        let watched = src.deletingLastPathComponent()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("deriv-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let u1 = ImageResizer.derivativeURL(for: src, size: .init(width: 50, height: 50), format: .png, in: folder)
        try Data([1]).write(to: u1)
        let u2 = ImageResizer.derivativeURL(for: src, size: .init(width: 50, height: 50), format: .png, in: folder)
        XCTAssertNotEqual(u1, u2); XCTAssertEqual(u1.lastPathComponent, "src 50×50.png"); XCTAssertEqual(u2.lastPathComponent, "src 50×50 (2).png")
        XCTAssertFalse(ImageResizer.isInside(u1, folder: watched), "türev izlenen klasöre yazılmamalı")
        // Rafa ekleme: aynı türev iki kez eklenmez
        let st = ShelfStore(fileURL: nil, maxItems: 10)
        let it = ShelfItem(path: u1.path, fileID: ScreenshotFileInspector.fileIdentifier(u1), capturedAt: Date(), source: .derivative)
        XCTAssertTrue(st.add(it)); XCTAssertFalse(st.add(ShelfItem(path: u1.path, fileID: nil, capturedAt: Date(), source: .derivative)))
    }
    func testOCRClipboardPolicyKeepsClipboardOnEmptyOrError() {
        var written: [String] = []
        XCTAssertEqual(OCRClipboardPolicy.apply(.success("   \n"), write: { written.append($0) }), .empty)
        XCTAssertEqual(OCRClipboardPolicy.apply(.failure(TextRecognizer.OCRError.unreadable), write: { written.append($0) }), .failed(S.ocrErrorUnreadable))
        XCTAssertTrue(written.isEmpty, "boş sonuç/hata panoya yazmamalı")
        XCTAssertEqual(OCRClipboardPolicy.apply(.success(" merhaba "), write: { written.append($0) }), .copied(characters: 7))
        XCTAssertEqual(written, ["merhaba"])
    }
    func testOCRAssemblyPreservesReadingOrderAndParagraphs() {
        // Vision koordinatları: alt-sol köken. Üst satır y büyük.
        let lines: [(String, CGRect)] = [
            ("ikinci satır", CGRect(x: 0.1, y: 0.80, width: 0.5, height: 0.05)),
            ("birinci satır", CGRect(x: 0.1, y: 0.90, width: 0.5, height: 0.05)),
            ("yeni paragraf", CGRect(x: 0.1, y: 0.50, width: 0.5, height: 0.05)),
            ("sağ sütun", CGRect(x: 0.7, y: 0.90, width: 0.2, height: 0.05)),
        ]
        XCTAssertEqual(TextRecognizer.assemble(lines), "birinci satır\nsağ sütun\nikinci satır\n\nyeni paragraf")
    }
    func testOCROnRenderedTextRecognizesWords() throws {
        // Gerçek Vision çağrısı: basit bir metin görseli
        let w = 600, h = 120
        let img = NSImage(size: NSSize(width: w, height: h), flipped: false) { r in
            NSColor.white.setFill(); r.fill()
            ("Merhaba Shotmori 2026" as NSString).draw(at: NSPoint(x: 20, y: 30), withAttributes: [.font: NSFont.systemFont(ofSize: 48, weight: .semibold), .foregroundColor: NSColor.black]); return true }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ocr-\(UUID())", isDirectory: true); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("t.png"); try NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: url)
        let r = TextRecognizer.recognizeSync(url)
        guard case .success(let text) = r else { return XCTFail("OCR başarısız") }
        XCTAssertTrue(text.contains("Shotmori"), "tanınan metin: \(text)")
        XCTAssertFalse(TextRecognizer.availableLanguages().isEmpty)
    }
    /// OCR ve pano PNG yolu piksel sınırı uygular; OCR çözümü bütçeyi aşan kaynakta en-boy korunarak küçülür.
    func testDecodeLimitsForOCRAndClipboardPNG() throws {
        XCTAssertEqual(TextRecognizer.decodeMaxSide(width: 1200, height: 20_000, budget: 50_000_000), 20_000, "uzun kaydırmalı kare tam boy")
        XCTAssertEqual(TextRecognizer.decodeMaxSide(width: 20_000, height: 10_000, budget: 50_000_000), 10_000, "200 MP → 50 MP: kenarlar yarıya")
        XCTAssertEqual(TextRecognizer.decodeMaxSide(width: 0, height: 0, budget: 10), 1)
        let src = try makeImage(40, 30, alpha: false)
        guard case .failure = TextRecognizer.recognizeSync(src, maxPixels: 100) else { return XCTFail("sınırı aşan kaynak okunmamalı") }
        let jpg = src.deletingLastPathComponent().appendingPathComponent("a.jpg")
        try NSBitmapImageRep(data: Data(contentsOf: src))!.representation(using: .jpeg, properties: [:])!.write(to: jpg)
        XCTAssertNil(ThumbnailCache.pngData(jpg, maxPixels: 100), "sınırı aşan JPEG için PNG üretilmez")
        let png = try XCTUnwrap(ThumbnailCache.pngData(jpg))
        let rep = try XCTUnwrap(NSBitmapImageRep(data: png)); XCTAssertEqual(rep.pixelsWide, 40); XCTAssertEqual(rep.pixelsHigh, 30)
        XCTAssertEqual(Array(png.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
        XCTAssertLessThan(EditRenderer.maxSourcePixels, ImageResizer.maxSourcePixels, "tam çözen editör sınırı küçültülerek çözen yollardan düşük")
        XCTAssertLessThanOrEqual(EditRenderer.maxSourcePixels, 150_000_000)
    }
    func testClipboardImportNeverOverwrites() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pano-\(UUID())", isDirectory: true)
        let pb = NSPasteboard(name: NSPasteboard.Name("dev.shotmori.test.\(UUID())")); defer { pb.releaseGlobally() }
        let a = try makeImage(8, 8, alpha: false), b = try makeImage(12, 12, alpha: true)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func run(_ src: URL) -> URL? {
            pb.clearContents(); pb.setData(try! Data(contentsOf: src), forType: .png)
            let ex = expectation(description: "import"); var out: URL?
            ClipboardImport.importImage(from: pb, now: now, into: dir) { out = $0; ex.fulfill() }
            wait(for: [ex], timeout: 10); return out
        }
        let u1 = try XCTUnwrap(run(a)); let first = try Data(contentsOf: u1)
        let u2 = try XCTUnwrap(run(b))
        XCTAssertNotEqual(u1, u2); XCTAssertTrue(u2.lastPathComponent.contains("(2)"))
        XCTAssertEqual(try Data(contentsOf: u1), first, "ilk dosya değişmemeli")
        XCTAssertNotEqual(try Data(contentsOf: u2), first)
        XCTAssertEqual(run(a), u1, "aynı görsel ikinci kez yazılmaz; mevcut kopya döner")
        let pngs = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".png") }
        XCTAssertEqual(pngs.count, 2)
    }
    /// Boş pano reddedilir; 50 MB sınırı yalnız dış kaynaklara uygulanır: büyük pano görseli (fotoğraf kopyası) "Panoda görsel yok"a düşmez, yazılır.
    func testClipboardImportRejectsEmptyButAcceptsLargeImage() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pano-\(UUID())", isDirectory: true)
        let pb = NSPasteboard(name: NSPasteboard.Name("dev.shotmori.test.\(UUID())")); defer { pb.releaseGlobally() }
        func run() -> InboundImport.Outcome? {
            let ex = expectation(description: "import"); var out: InboundImport.Outcome?
            ClipboardImport.importImageOutcome(from: pb, into: dir) { out = $0; ex.fulfill() }
            wait(for: [ex], timeout: 10); return out
        }
        pb.clearContents(); XCTAssertEqual(run(), .rejected)
        XCTAssertNil(InboundImport.byteLimit(for: .clipboard))
        for s in [InboundSource.intent, .service, .statusDrop, .openWith] { XCTAssertEqual(InboundImport.byteLimit(for: s), InboundImport.maxBytes) }
        pb.clearContents(); pb.setData(Data(count: InboundImport.maxBytes + 1), forType: .png)
        guard case .added(let u)? = run() else { return XCTFail("50 MB üstü pano görseli eklenmeli") }
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: u.path)[.size] as? Int, InboundImport.maxBytes + 1)
    }

    func testClipboardFileStampIsGregorianPOSIX() throws {
        let f = ClipboardImport.fileStampFormatter
        XCTAssertEqual(f.calendar.identifier, .gregorian); XCTAssertEqual(f.locale.identifier, "en_US_POSIX")
        var cal = Calendar(identifier: .gregorian); cal.timeZone = f.timeZone // biçimlendiricinin saat dilimiyle sabit an
        let date = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 14, minute: 5, second: 9)))
        XCTAssertEqual(ClipboardImport.fileStamp(date), "2026-10-21 14.05.09")
    }
    func testClipboardImportFromNSImageOnlyPasteboard() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pano-\(UUID())", isDirectory: true)
        let pb = NSPasteboard(name: NSPasteboard.Name("dev.shotmori.test.\(UUID())")); defer { pb.releaseGlobally() }
        let pdf = NSMutableData(); var box = CGRect(x: 0, y: 0, width: 40, height: 30)
        let ctx = try XCTUnwrap(CGContext(consumer: CGDataConsumer(data: pdf as CFMutableData)!, mediaBox: &box, nil))
        ctx.beginPDFPage(nil); ctx.setFillColor(CGColor(red: 0, green: 0.6, blue: 0.3, alpha: 1)); ctx.fill(box); ctx.endPDFPage(); ctx.closePDF()
        pb.clearContents(); pb.setData(pdf as Data, forType: .pdf)
        XCTAssertNil(pb.data(forType: .png)); XCTAssertNil(pb.data(forType: .tiff)) // yalnız NSImage okuma yolu kalsın
        let ex = expectation(description: "import"); var out: URL?
        ClipboardImport.importImage(from: pb, now: Date(timeIntervalSince1970: 1_800_000_000), into: dir) { out = $0; ex.fulfill() }
        wait(for: [ex], timeout: 10)
        let url = try XCTUnwrap(out); XCTAssertEqual(url.pathExtension, "png")
        let rep = try XCTUnwrap(NSBitmapImageRep(data: try Data(contentsOf: url)))
        XCTAssertGreaterThan(rep.pixelsWide, 0); XCTAssertGreaterThan(rep.pixelsHigh, 0)
    }

    func testAspectMathClampsHugeAndDegenerateInput() {
        let h = ResizeMath.heightKeepingAspect(original: .init(width: 10, height: 1000), width: Int.max / 2)
        XCTAssertEqual(h, ResizeMath.maxDimension * 8)
        XCTAssertEqual(ResizeMath.validate(.init(width: 100, height: h)), .tooLarge)
        XCTAssertEqual(ResizeMath.heightKeepingAspect(original: .init(width: 0, height: 100), width: 50), 1)
        XCTAssertEqual(ResizeMath.widthKeepingAspect(original: .init(width: 100, height: 0), height: 50), 1)
        XCTAssertEqual(ResizeMath.scaled(.init(width: 100, height: 100), percent: .infinity), .init(width: 1, height: 1))
        XCTAssertEqual(ResizeMath.scaled(.init(width: 100, height: 100), percent: .nan), .init(width: 1, height: 1))
        XCTAssertEqual(ResizeMath.clamp(-5), 1)
    }
    func testSourceInfoRejectsZeroSize() {
        XCTAssertFalse(ImageResizer.validSize(w: 0, h: 0)); XCTAssertFalse(ImageResizer.validSize(w: 10, h: 0)); XCTAssertFalse(ImageResizer.validSize(w: -1, h: 5))
        XCTAssertTrue(ImageResizer.validSize(w: 1, h: 1))
    }
}
