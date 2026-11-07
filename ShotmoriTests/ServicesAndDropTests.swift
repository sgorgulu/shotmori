import XCTest
import AppKit
@testable import Shotmori

/// Finder Servisi pasteboard'u ve menü çubuğu simgesine bırakma: saf karar ve çıkarma işlevleri.
final class ServicesAndDropTests: XCTestCase {
    private var boards: [NSPasteboard] = []
    override func tearDown() { boards.forEach { $0.releaseGlobally() }; boards = []; super.tearDown() }
    private func board() -> NSPasteboard { let pb = NSPasteboard.withUniqueName(); boards.append(pb); pb.clearContents(); return pb }
    private func pngData() -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    func testPasteboardFileURLsFiltered() {
        let pb = board()
        let a = URL(fileURLWithPath: "/tmp/shotmori-a.png"), b = URL(fileURLWithPath: "/tmp/shotmori-b.jpg")
        pb.writeObjects([a as NSURL, b as NSURL, "merhaba" as NSString, URL(string: "https://example.com/c.png")! as NSURL])
        let urls = ServicePasteboard.fileURLs(from: pb)
        XCTAssertEqual(urls.map(\.path), [a.path, b.path])
    }

    func testPasteboardFileURLsEmptyForStringOnly() {
        let pb = board(); pb.setString("/tmp/shotmori-a.png", forType: .string)
        XCTAssertTrue(ServicePasteboard.fileURLs(from: pb).isEmpty, "düz metin yol dosya sayılmaz")
    }

    func testPasteboardImageDataPNG() {
        let pb = board(); let d = pngData(); pb.setData(d, forType: .png)
        let out = ServicePasteboard.imageData(from: pb)
        XCTAssertEqual(out?.0, d); XCTAssertEqual(out?.1, "png")
    }

    func testPasteboardImageDataTIFFKeptAsTIFF() {
        let pb = board(); let t = NSImage(data: pngData())!.tiffRepresentation!; pb.setData(t, forType: .tiff)
        let out = ServicePasteboard.imageData(from: pb)
        XCTAssertEqual(out?.0, t); XCTAssertEqual(out?.1, "tiff")
    }

    func testPasteboardImageDataNilForText() {
        let pb = board(); pb.setString("yok", forType: .string)
        XCTAssertNil(ServicePasteboard.imageData(from: pb))
    }

    func testDropOperationAcceptsFilesRejectsInternal() {
        let internalType = ShelfPanelController.internalItemsType
        XCTAssertEqual(StatusDropView.operation(for: [.fileURL], internalType: internalType), .copy)
        XCTAssertEqual(StatusDropView.operation(for: [.png], internalType: internalType), .copy)
        XCTAssertEqual(StatusDropView.operation(for: [.tiff], internalType: internalType), .copy)
        XCTAssertEqual(StatusDropView.operation(for: [internalType], internalType: internalType), [])
        XCTAssertEqual(StatusDropView.operation(for: [.fileURL, internalType], internalType: internalType), [], "raftan gelen iç sürükleme reddedilir")
        XCTAssertEqual(StatusDropView.operation(for: [.string], internalType: internalType), [])
        XCTAssertEqual(StatusDropView.operation(for: [], internalType: internalType), [])
    }

    func testDropViewPassesClicks() {
        let v = StatusDropView(frame: NSRect(x: 0, y: 0, width: 24, height: 22))
        XCTAssertNil(v.hitTest(NSPoint(x: 10, y: 10)), "sol/sağ tık düğmeye geçer")
        XCTAssertFalse(v.isAccessibilityElement(), "VoiceOver düğmeyi okur, saydam katmanı değil")
    }

    func testDropViewRegistersDragTypes() {
        let v = StatusDropView(frame: .zero)
        XCTAssertEqual(Set(v.registeredDraggedTypes), [.fileURL, .png, .tiff])
    }
}
