import XCTest
import AppKit
@testable import Shotmori

final class ClipboardWriterTests: XCTestCase {
    func testNativeTypeForCommonExtensions() {
        XCTAssertEqual(ClipboardWriter.nativeType(forExtension: "png"), .png)
        XCTAssertEqual(ClipboardWriter.nativeType(forExtension: "PNG"), .png)
        XCTAssertEqual(ClipboardWriter.nativeType(forExtension: "jpg"), NSPasteboard.PasteboardType("public.jpeg"))
        XCTAssertEqual(ClipboardWriter.nativeType(forExtension: "jpeg"), NSPasteboard.PasteboardType("public.jpeg"))
        XCTAssertEqual(ClipboardWriter.nativeType(forExtension: "heic"), NSPasteboard.PasteboardType("public.heic"))
        XCTAssertEqual(ClipboardWriter.nativeType(forExtension: "tiff"), .tiff)
        XCTAssertNil(ClipboardWriter.nativeType(forExtension: "txt"))
        XCTAssertEqual(ClipboardWriter.nativeType(forExtension: "webp"), NSPasteboard.PasteboardType("org.webmproject.webp"))
    }
    /// Kabul edilen her uzantının pano türü var (WebP "Görüntüyü kopyala" yalnız URL yazmasın); izleyici ve içe aktarma aynı kümeyi kullanır.
    func testEveryAcceptedExtensionHasPasteboardType() {
        for ext in ImageFormats.extensions { XCTAssertNotNil(ClipboardWriter.nativeType(forExtension: ext), ext) }
        XCTAssertEqual(InboundImport.allowedExtensions, ImageFormats.extensions)
        XCTAssertEqual(ScreenshotFileInspector.imageExtensions, ImageFormats.extensions)
    }
    func testWriteImageForJPEGDoesNotDecodeAndOffersFileURL() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cw-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("a.jpg")
        let ctx = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0, green: 0.5, blue: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let jpeg = NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .jpeg, properties: [:])!
        try jpeg.write(to: url)
        let pb = NSPasteboard(name: NSPasteboard.Name("dev.shotmori.test.\(UUID())"))
        defer { pb.releaseGlobally() }
        XCTAssertTrue(ClipboardWriter.writeImage(url, to: pb))
        let types = pb.types ?? []
        let jpegType = NSPasteboard.PasteboardType("public.jpeg")
        XCTAssertTrue(types.contains(jpegType)); XCTAssertTrue(types.contains(.fileURL))
        XCTAssertEqual(pb.data(forType: jpegType), jpeg)
    }
    func testLazyPNGIsProducedOnDemandForJPEG() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cw-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("b.jpg")
        let ctx = CGContext(data: nil, width: 12, height: 7, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0.5, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 12, height: 7))
        try NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .jpeg, properties: [:])!.write(to: url)
        let pb = NSPasteboard(name: NSPasteboard.Name("dev.shotmori.test.\(UUID())"))
        defer { pb.releaseGlobally() }
        XCTAssertTrue(ClipboardWriter.writeImage(url, to: pb))
        XCTAssertTrue((pb.types ?? []).contains(.png), "PNG türü sözü verilmiş olmalı")
        let png = try XCTUnwrap(pb.data(forType: .png), "yapıştıran PNG isteyince sağlayıcı üretmeli")
        XCTAssertEqual(Array(png.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
        let rep = try XCTUnwrap(NSBitmapImageRep(data: png))
        XCTAssertEqual(rep.pixelsWide, 12); XCTAssertEqual(rep.pixelsHigh, 7)
    }
}
