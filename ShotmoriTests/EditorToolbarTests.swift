import XCTest
import AppKit
@testable import Shotmori

/// Editör v2: gerçek araç çubuğu (öğe sırası), cam krom, içerik başlık çubuğunun altına girmez, ipuçları araç ipucunda.
final class EditorToolbarTests: XCTestCase {
    func testItemOrder() {
        XCTAssertEqual(EditorToolbar.itemOrder.first, .editorTools)
        XCTAssertTrue(EditorToolbar.itemOrder.contains(.flexibleSpace))
        XCTAssertEqual(EditorToolbar.itemOrder.last, .editorZoomFit)
        XCTAssertEqual(EditorToolbar.itemOrder.count, 9)
    }
    /// Dar pencerede taşan öğeler » menüsünden çalışmalı: her öğenin menü biçimi var; araçlar yüksek, yüzde etiketi düşük öncelikli.
    func testOverflowMenuFormsAndPriorities() {
        let views = EditorToolbar.Views(tools: NSSegmentedControl(), aspect: NSPopUpButton(), undo: NSButton(), redo: NSButton(), zoomOut: NSButton(), zoomLabel: NSTextField(labelWithString: "%100"), zoomIn: NSButton(), zoomFit: NSButton())
        let tb = EditorToolbar(views: views); let toolbar = NSToolbar(identifier: "t")
        for id in EditorToolbar.itemOrder where id != .flexibleSpace {
            let item = try! XCTUnwrap(tb.toolbar(toolbar, itemForItemIdentifier: id, willBeInsertedIntoToolbar: true))
            XCTAssertNotNil(item.menuFormRepresentation, id.rawValue)
            XCTAssertFalse(item.label.isEmpty, id.rawValue)
        }
        XCTAssertEqual(tb.toolbar(toolbar, itemForItemIdentifier: .editorTools, willBeInsertedIntoToolbar: true)?.visibilityPriority, .high)
        XCTAssertEqual(tb.toolbar(toolbar, itemForItemIdentifier: .editorZoomLabel, willBeInsertedIntoToolbar: true)?.visibilityPriority, .low)
    }
    private func samplePNG() throws -> ShelfItem {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("editor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let u = dir.appendingPathComponent("Örnek.png")
        let img = NSImage(size: NSSize(width: 160, height: 100), flipped: false) { r in NSColor.systemTeal.setFill(); r.fill(); return true }
        let tiff = img.tiffRepresentation!; let png = NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
        try png.write(to: u)
        return ShelfItem(path: u.path, fileID: nil, capturedAt: Date())
    }
    func testContentTopBelowTitlebarAndChrome() throws {
        let item = try samplePNG(); let store = ShelfStore(fileURL: nil, maxItems: 5)
        let exp = expectation(description: "editor")
        var wc: EditorWindowController?
        EditorWindowController.load(item: item, store: store, panel: nil) { wc = $0; exp.fulfill() }
        wait(for: [exp], timeout: 5)
        let c = try XCTUnwrap(wc); let w = try XCTUnwrap(c.window)
        XCTAssertTrue(w.styleMask.contains(.fullSizeContentView)); XCTAssertNotNil(w.toolbar)
        XCTAssertEqual(w.title, "Örnek.png"); XCTAssertTrue(w.subtitle.contains("160 × 100 px"))
        w.layoutIfNeeded()
        XCTAssertGreaterThan(c.rootViewForTesting.frame.height, 0, "yerleşim gerçekten çalıştı")
        XCTAssertLessThanOrEqual(c.rootViewForTesting.frame.maxY, w.contentLayoutRect.maxY + 0.5, "içerik başlık çubuğunun altına girmez")
        XCTAssertFalse(S.editOriginalHelp.isEmpty)
        c.close()
    }
}
