import XCTest
import AppKit
@testable import Shotmori

/// Kart v2: görüntü kartı doldurur, saat alt şeritte, dosya adı ipucunda, "Yeni" nokta + VoiceOver değeri.
final class ThumbnailCardTests: XCTestCase {
    private func sampleItem(derivative: Bool = false) throws -> ShelfItem {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("card-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let u = dir.appendingPathComponent("Örnek 11.42.png"); try Data([1]).write(to: u)
        return ShelfItem(path: u.path, fileID: nil, capturedAt: Date(), source: derivative ? .derivative : .screenshot)
    }
    func testSizes() {
        XCTAssertEqual(ThumbnailItemView.shelfSize, NSSize(width: 146, height: 118))
        XCTAssertEqual(ThumbnailItemView.popoverSize, NSSize(width: 124, height: 118))
        XCTAssertEqual(ThumbnailItemView.footerHeight, 18)
    }
    func testFooterText() {
        let d = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 11, minute: 42))!
        let t = ThumbnailItemView.makeTimeFormatter().string(from: d) // bölgeden bağımsız: saat biçimi yerelin
        XCTAssertEqual(ThumbnailItemView.footerText(capturedAt: d, isDerivative: false, isMissing: false, editedCaption: "Düzenlendi"), t)
        XCTAssertEqual(ThumbnailItemView.footerText(capturedAt: d, isDerivative: true, isMissing: false, editedCaption: "Düzenlendi"), "Düzenlendi · \(t)")
        XCTAssertEqual(ThumbnailItemView.footerText(capturedAt: d, isDerivative: true, isMissing: true, editedCaption: "Düzenlendi"), t, "kayıp kartta yalnız saat")
    }
    /// L10N-04: kart saati sabit "HH:mm" değil, bölgenin 12/24 saat tercihine uyar.
    func testFooterTimeFollowsLocale() {
        let d = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 15, minute: 42))!
        XCTAssertEqual(ThumbnailItemView.makeTimeFormatter(locale: Locale(identifier: "tr_TR")).string(from: d), "15:42")
        let us = ThumbnailItemView.makeTimeFormatter(locale: Locale(identifier: "en_US")).string(from: d)
        XCTAssertTrue(us.hasPrefix("3:42") && us.contains("PM"), "ABD bölgesinde 12 saat: \(us)")
    }
    func testFooterAlpha() {
        XCTAssertEqual(ThumbnailItemView.footerAlpha(reduceTransparency: false), 0.7)
        XCTAssertEqual(ThumbnailItemView.footerAlpha(reduceTransparency: true), 0.9)
    }
    func testAXValueKeepsNewAndTime() throws {
        let v = ThumbnailItemView(item: try sampleItem()); v.isNew = true
        let value = v.accessibilityValue() as? String ?? ""
        XCTAssertTrue(value.contains(S.newBadge), value)
        XCTAssertTrue(value.contains(":"), "saat kalır: \(value)")
        XCTAssertEqual(v.toolTip, "Örnek 11.42.png", "dosya adı araç ipucunda")
    }
    func testCloudBadgeSitsAboveFooter() {
        let area = NSRect(x: 6, y: 4, width: 134, height: 110)
        let r = ThumbnailItemView.cloudBadgeRect(in: area)
        XCTAssertGreaterThanOrEqual(r.minY, area.minY + ThumbnailItemView.footerHeight + 2)
        XCTAssertEqual(r.maxX, area.maxX - 6)
    }
    func testImageAreaFillsCard() throws {
        let v = ThumbnailItemView(item: try sampleItem())
        XCTAssertEqual(v.imageArea, v.bounds.insetBy(dx: 6, dy: 4))
    }
}
