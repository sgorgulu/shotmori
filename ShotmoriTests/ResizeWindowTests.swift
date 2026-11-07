import XCTest
import AppKit
@testable import Shotmori

/// Boyutlandır v2: cam krom, dosya adı başlıkta, ölçü·boyut alt başlıkta, notlar araç ipucunda.
final class ResizeWindowTests: XCTestCase {
    private func samplePNG() throws -> ShelfItem {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("resize-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let u = dir.appendingPathComponent("Boyut.png")
        let img = NSImage(size: NSSize(width: 200, height: 120), flipped: false) { r in NSColor.systemOrange.setFill(); r.fill(); return true }
        let png = NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        try png.write(to: u)
        return ShelfItem(path: u.path, fileID: nil, capturedAt: Date())
    }
    /// JPEG + saydam kaynak: "Saydam alanlar beyaz olur." uyarısı görünür kalır (+28 pt).
    func testJPEGAlphaWarningAddsHeight() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("alpha-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let u = dir.appendingPathComponent("a.png")
        let img = NSImage(size: NSSize(width: 40, height: 30), flipped: false) { r in NSColor.red.withAlphaComponent(0.5).setFill(); r.fill(); return true }
        try NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: u)
        let m = ResizeModel(source: u, info: try XCTUnwrap(ImageResizer.sourceInfo(u)))
        XCTAssertTrue(m.info.hasAlpha)
        XCTAssertEqual(m.preferredHeight, 440); m.format = .jpeg; XCTAssertEqual(m.preferredHeight, 512)
    }
    func testWindowChromeAndTitles() throws {
        let item = try samplePNG(); let store = ShelfStore(fileURL: nil, maxItems: 5)
        let exp = expectation(description: "resize"); var wc: ResizeWindowController?
        ResizeWindowController.load(item: item, store: store, panel: nil) { wc = $0; exp.fulfill() }
        wait(for: [exp], timeout: 5)
        let c = try XCTUnwrap(wc); let w = try XCTUnwrap(c.window)
        XCTAssertTrue(w.styleMask.contains(.fullSizeContentView)); XCTAssertNotNil(w.toolbar)
        XCTAssertEqual(w.title, "Boyut.png"); XCTAssertTrue(w.subtitle.contains("200 × 120 px"))
        c.close()
    }
}
