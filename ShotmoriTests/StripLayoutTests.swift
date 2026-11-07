import XCTest
@testable import Shotmori

final class StripLayoutTests: XCTestCase {
    func testSagAndRope() {
        XCTAssertEqual(StripLayout.sag(width: 3000), 30)
        XCTAssertEqual(StripLayout.sag(width: 1000), 18, accuracy: 0.0001)
        XCTAssertEqual(StripLayout.ropeY(x: 500, width: 1000), 50, accuracy: 0.0001)
        XCTAssertEqual(StripLayout.ropeY(x: 0, width: 1000), 32)
        XCTAssertEqual(StripLayout.ropeY(x: 1000, width: 1000), 32)
        XCTAssertEqual(StripLayout.stripHeight, 202)
    }

    func testPositionsAndRange() {
        XCTAssertEqual(StripLayout.x(index: 2, scrollOffset: 0), 447)
        XCTAssertEqual(StripLayout.contentWidth(count: 0), 0)
        XCTAssertEqual(StripLayout.contentWidth(count: 3), 48 + 150 + 2 * 174)
        XCTAssertEqual(StripLayout.maximumOffset(count: 1, width: 1000), 0)
        XCTAssertEqual(StripLayout.visibleRange(count: 100, width: 1000, offset: 0), 0..<7)
        XCTAssertEqual(StripLayout.visibleRange(count: 0, width: 1000, offset: 0), 0..<0)
    }

    func testPhotoAndCardSize() {
        XCTAssertEqual(StripLayout.photoSize(for: CGSize(width: 2000, height: 500)), CGSize(width: 136, height: 34))
        XCTAssertEqual(StripLayout.photoSize(for: CGSize(width: 500, height: 2000)).height, 104)
        XCTAssertEqual(StripLayout.cardSize(for: CGSize(width: 2000, height: 500)), CGSize(width: 144, height: 42))
    }

    func testTiltDeterministicAndBounded() {
        for _ in 0..<1000 {
            let id = UUID()
            let t = StripLayout.tilt(for: id)
            XCTAssertTrue((-2.5...2.5).contains(t))
            XCTAssertEqual(t, StripLayout.tilt(for: id))
        }
    }

    func testMotion() {
        XCTAssertEqual(StripMotion.flightProgress(0.5), 0.5, accuracy: 0.0001)
        XCTAssertEqual(StripMotion.fallAngle(tilt: 2, e: 1), 36, accuracy: 0.0001)
        XCTAssertEqual(StripMotion.duration(0.42, reduceMotion: true), 0)
        XCTAssertEqual(StripMotion.duration(0.42, reduceMotion: false), 0.42)
        XCTAssertEqual(StripMotion.hiddenOffset(stripHeight: 202), -214)
        XCTAssertEqual(StripMotion.fallProgress(0.5), 0.125, accuracy: 0.0001)
    }

    // MARK: - CaptureRect

    private func plist(_ v: Any) -> Data {
        try! PropertyListSerialization.data(fromPropertyList: v, format: .binary, options: 0)
    }

    func testCaptureRectParse() {
        XCTAssertEqual(CaptureRect.parse(plist([100, 50, 400, 300]), mainScreenMaxY: 1000), CGRect(x: 100, y: 650, width: 400, height: 300))
        XCTAssertEqual(CaptureRect.parse(plist([1800, 50, 400, 300]), mainScreenMaxY: 1000)?.origin.x, 1800)
        XCTAssertNil(CaptureRect.parse(plist([1, 1, 2, 2]), mainScreenMaxY: 1000))
        XCTAssertNil(CaptureRect.parse(plist(["a"]), mainScreenMaxY: 1000))
        XCTAssertNil(CaptureRect.parse(Data([1, 2, 3]), mainScreenMaxY: 1000))
        // Aşırı büyük / sonsuz / NaN değerler reddedilir (sonraki Int dönüşümü çökmesin).
        XCTAssertNil(CaptureRect.parse(plist([0, 0, 1e300, 300]), mainScreenMaxY: 1000))
        XCTAssertNil(CaptureRect.parse(plist([0, 0, Double.infinity, 300]), mainScreenMaxY: 1000))
        XCTAssertNil(CaptureRect.parse(plist([Double.nan, 0, 400, 300]), mainScreenMaxY: 1000))
        XCTAssertNil(CaptureRect.parse(plist([-200_000, 0, 400, 300]), mainScreenMaxY: 1000))
        XCTAssertNotNil(CaptureRect.parse(plist([-3000, 0, 6016, 3384]), mainScreenMaxY: 1000), "geniş çok ekranlı düzen")
    }

    func testCaptureRectReadFromXattr() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("shotmori-rect-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNil(CaptureRect.read(url, mainScreenMaxY: 1000))
        let data = plist([100, 50, 400, 300])
        let rc = url.withUnsafeFileSystemRepresentation { path in
            data.withUnsafeBytes { setxattr(path!, CaptureRect.xattr, $0.baseAddress, data.count, 0, 0) }
        }
        XCTAssertEqual(rc, 0)
        XCTAssertEqual(CaptureRect.read(url, mainScreenMaxY: 1000), CGRect(x: 100, y: 650, width: 400, height: 300))
    }

    // MARK: - StripPanel

    func testStripHitTest() {
        let r = [CGRect(x: 10, y: 10, width: 100, height: 50)]
        XCTAssertTrue(StripHitTest.accepts(CGPoint(x: 8, y: 8), rects: r))
        XCTAssertFalse(StripHitTest.accepts(CGPoint(x: 5, y: 5), rects: r))
        XCTAssertFalse(StripHitTest.accepts(CGPoint(x: 8, y: 8), rects: []))
    }

    @MainActor
    func testStripPanelRevealModel() {
        let panel = StripPanel(content: NSView(), reduceMotion: { false })
        panel.setRevealed(true, animated: false)
        XCTAssertEqual(panel.compositorLayer?.sublayerTransform.m42, 0)
        XCTAssertFalse(panel.isTransitioning)
        panel.setRevealed(false, animated: false)
        XCTAssertEqual(panel.compositorLayer?.sublayerTransform.m42, StripMotion.hiddenOffset(stripHeight: StripLayout.stripHeight))
        XCTAssertFalse(panel.canBecomeKey)
        panel.keyboardFocusAllowed = true
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertTrue(panel.ignoresMouseEvents)
    }

    @MainActor
    func testStripPanelReduceMotionIsInstant() {
        let panel = StripPanel(content: NSView(), reduceMotion: { true })
        panel.setRevealed(true, animated: true)
        XCTAssertFalse(panel.isTransitioning)
        XCTAssertEqual(panel.compositorLayer?.sublayerTransform.m42, 0)
    }

    @MainActor
    func testStripPanelHiddenOffsetFollowsHeightChangeDuringRetract() throws {
        let screen = try XCTUnwrap(NSScreen.main ?? NSScreen.screens.first)
        let panel = StripPanel(content: NSView(), reduceMotion: { false })
        panel.place(on: screen, height: 100)
        panel.setRevealed(true, animated: false)
        let done = expectation(description: "retract")
        panel.setRevealed(false, animated: true) { done.fulfill() }
        XCTAssertTrue(panel.isTransitioning)
        panel.place(on: screen, height: 300)
        wait(for: [done], timeout: StripMotion.retractDuration + 2)
        XCTAssertEqual(panel.compositorLayer?.sublayerTransform.m42, StripMotion.hiddenOffset(stripHeight: 300))
    }

    @MainActor
    func testStripPanelReversalDropsFirstCompletion() {
        let panel = StripPanel(content: NSView(), reduceMotion: { false })
        var first = false
        let second = expectation(description: "second")
        panel.setRevealed(true, animated: true) { first = true }
        panel.setRevealed(false, animated: true) { second.fulfill() }
        wait(for: [second], timeout: StripMotion.revealDuration + 2)
        XCTAssertFalse(first)
        XCTAssertEqual(panel.compositorLayer?.sublayerTransform.m42, StripMotion.hiddenOffset(stripHeight: StripLayout.stripHeight))
    }

    @MainActor
    func testStripPanelUpdatePassThrough() {
        let panel = StripPanel(content: NSView(), reduceMotion: { false })
        panel.setFrame(NSRect(x: 100, y: 500, width: 800, height: 200), display: false)
        panel.setRevealed(true, animated: false)
        panel.hitRects = [CGRect(x: 10, y: 10, width: 100, height: 50)]
        // Üstten aşağı yerel (20, 20) -> ekran (120, 500 + 200 - 20)
        panel.updatePassThrough(mouseLocation: NSPoint(x: 120, y: 680))
        XCTAssertFalse(panel.ignoresMouseEvents)
        panel.updatePassThrough(mouseLocation: NSPoint(x: 700, y: 520))
        XCTAssertTrue(panel.ignoresMouseEvents)
    }
}
