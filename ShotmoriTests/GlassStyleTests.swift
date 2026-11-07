import XCTest
import AppKit
@testable import Shotmori

/// Cam temeli: zemin seçimi (26+ cam / altı Material), düz düğme biçimi, cam pencere kromu.
final class GlassStyleTests: XCTestCase {
    func testBackingChoice() {
        XCTAssertEqual(GlassSurfaceView.backing(available: true), .glass)
        XCTAssertEqual(GlassSurfaceView.backing(available: false), .material)
    }
    func testFlatButtonProminentUsesAccent() {
        let b = NSButton(title: "Kopyala", target: nil, action: nil)
        ShotmoriStyle.flatButton(b, prominent: true)
        XCTAssertEqual(b.bezelColor, ShotmoriStyle.accent)
        XCTAssertEqual(b.bezelStyle, .rounded, "cam zemin üstünde düğmeler düz")
        ShotmoriStyle.flatButton(b, prominent: false)
        XCTAssertNil(b.bezelColor)
    }
    /// SwiftUI birincil düğmesi sistemin beyaz yazısını taşır: dolgu (`accentFill`) iki temada da beyazla ≥ 4,5:1 (camsız 14–15;
    /// macOS 26 camı tonu açar, QA ölçümü not edildi). Koyu `accent` (lavanta) bu eşiği geçmez; ayrı rolün nedeni.
    func testAccentFillKeepsWhiteLabelReadable() throws {
        func whiteContrast(_ c: NSColor, _ name: NSAppearance.Name) throws -> CGFloat {
            var resolved: NSColor?
            try XCTUnwrap(NSAppearance(named: name)).performAsCurrentDrawingAppearance { resolved = c.usingColorSpace(.sRGB) }
            let s = try XCTUnwrap(resolved)
            func ch(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            let l = 0.2126 * ch(s.redComponent) + 0.7152 * ch(s.greenComponent) + 0.0722 * ch(s.blueComponent)
            return 1.05 / (l + 0.05)
        }
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            XCTAssertGreaterThanOrEqual(try whiteContrast(ShotmoriStyle.accentFill, name), 4.5, "\(name.rawValue)")
        }
        XCTAssertLessThan(try whiteContrast(ShotmoriStyle.accent, .darkAqua), 4.5, "koyu accent beyaz yazı taşıyamaz; birincil dolgu accentFill olmalı")
    }
    func testSurfaceContentViewIsInsideHierarchy() {
        let v = GlassSurfaceView(cornerRadius: 16)
        let child = NSView(); v.contentView.addSubview(child)
        XCTAssertTrue(child.isDescendant(of: v))
        XCTAssertEqual(v.backing, GlassSurfaceView.backing(available: GlassSurfaceView.isGlassAvailable))
    }
    /// 14–15 yolu bu Mac'te de çalıştırılır: Material zemin, içerik görünümü zemini doldurur, köşe maskesi var.
    func testMaterialFallbackPathLaysOutContent() {
        let v = GlassSurfaceView(cornerRadius: 16, forceMaterial: true)
        XCTAssertEqual(v.backing, .material)
        v.frame = NSRect(x: 0, y: 0, width: 300, height: 120); v.layoutSubtreeIfNeeded()
        XCTAssertEqual(v.contentView.frame, v.bounds)
        XCTAssertTrue(v.contentView.isDescendant(of: v))
        XCTAssertNotNil(v.materialViewForTesting?.maskImage, "köşeler maskeyle yuvarlanır (layer köşesi .behindWindow'da güvenilir değil)")
    }
    func testIconButtonHasLabelAndTooltip() {
        let b = NSButton()
        ShotmoriStyle.iconButton(b, symbol: "xmark", label: "Gizle (Esc)")
        XCTAssertEqual(b.toolTip, "Gizle (Esc)")
        XCTAssertEqual(b.accessibilityLabel(), "Gizle (Esc)")
        XCTAssertFalse(b.isBordered)
        XCTAssertNotNil(b.image)
    }
    func testGlassChromeInsertsFullSizeContentView() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.applyGlassChrome(toolbarIdentifier: "test", subtitle: "alt")
        XCTAssertTrue(w.styleMask.contains(.fullSizeContentView))
        XCTAssertNotNil(w.toolbar)
        XCTAssertEqual(w.subtitle, "alt")
        XCTAssertEqual(w.toolbarStyle, .unified)
    }
}
