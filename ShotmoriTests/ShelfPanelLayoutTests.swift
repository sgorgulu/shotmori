import XCTest
import AppKit
@testable import Shotmori

/// Raf paneli v2: cam zemin, durum satırı yok, yükseklik 254/224.
final class ShelfPanelLayoutTests: XCTestCase {
    func testPanelHeights() {
        XCTAssertEqual(ShelfPanelController.panelHeight(showsTabs: true), 254)
        XCTAssertEqual(ShelfPanelController.panelHeight(showsTabs: false), 224)
    }
    func testPanelBackgroundIsGlassSurface() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("panel-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let prefs = Preferences(defaults: UserDefaults(suiteName: "dev.shotmori.tests.panel.\(UUID().uuidString)")!)
        let store = ShelfStore(fileURL: dir.appendingPathComponent("shelf.json"), maxItems: 30)
        let c = ShelfPanelController(store: store, registry: ActionRegistry(prefs: prefs), prefs: prefs)
        XCTAssertTrue(c.panel.contentView is GlassSurfaceView)
    }
}
