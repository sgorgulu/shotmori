import XCTest
import AppKit
@testable import Shotmori

/// Popover v2: sayaç kapsülü, ikon düğmeler etiketli, saydam gövde, durum satırı yok.
final class PopoverLayoutTests: XCTestCase {
    func testPillText() {
        XCTAssertEqual(MenuBarPopoverViewController.pillText(total: 3, newCount: 0), "3")
        XCTAssertEqual(MenuBarPopoverViewController.pillText(total: 3, newCount: 2), "3 · \(S.newCount(2))")
        XCTAssertEqual(MenuBarPopoverViewController.pillText(total: 0, newCount: 0), "0")
    }
    func testIconButtonsHaveLabels() {
        let vc = MenuBarPopoverViewController(); vc.loadView()
        XCTAssertEqual(vc.iconButtonsForTesting.count, 3, "raf, ayarlar, yardım")
        for b in vc.iconButtonsForTesting {
            XCTAssertFalse((b.accessibilityLabel() ?? "").isEmpty)
            XCTAssertNotNil(b.toolTip); XCTAssertNotNil(b.image); XCTAssertFalse(b.isBordered)
        }
    }
    func testHeightAndTransparentBody() {
        XCTAssertEqual(MenuBarPopoverViewController.H, 262)
        let vc = MenuBarPopoverViewController(); vc.loadView()
        XCTAssertFalse(vc.view is SurfaceView, "gövde saydam; sistem popover camı görünür")
    }
}
