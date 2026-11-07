import XCTest
import SwiftUI
@testable import Shotmori

@MainActor
final class StripViewTests: XCTestCase {
    private func items(_ n: Int) -> [ShelfItem] {
        (0..<n).map { i in
            ShelfItem(path: "/nonexistent/shotmori-strip-test/\(i).png", fileID: nil,
                      capturedAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(i)))
        }
    }

    func testModelDefaultsAreEmpty() {
        let m = StripModel(reduceMotion: { false })
        XCTAssertTrue(m.items.isEmpty)
        XCTAssertTrue(m.newIDs.isEmpty)
        XCTAssertTrue(m.selection.isEmpty)
        XCTAssertEqual(m.scrollOffset, 0)
        XCTAssertEqual(m.gust, 0)
        XCTAssertNil(m.copiedID)
        XCTAssertTrue(m.flyingIDs.isEmpty)
        XCTAssertTrue(m.fallingIDs.isEmpty)
        XCTAssertNil(m.pressedID)
        XCTAssertNil(m.draggingID)
        XCTAssertFalse(m.keyboardFocused)
        XCTAssertTrue(m.quickNumbers.isEmpty)
        XCTAssertTrue(m.tabs.isEmpty)
        XCTAssertTrue(m.capsule.isEmpty)
        XCTAssertNil(m.notice)
        XCTAssertEqual(m.emptyState, StripEmptyState.none)
        XCTAssertTrue(m.hitRects.isEmpty)
        XCTAssertFalse(m.reduceMotion())
    }

    /// Varış yalnız bu oturumda ilk kez görünen, uçmayan yeni kart için; tekrar çizimde yeniden oynamaz.
    func testArrivalConsumedOncePerSession() {
        let m = StripModel(reduceMotion: { false })
        let a = UUID(), b = UUID(), c = UUID()
        m.newIDs = [a, b]
        m.flyingIDs = [b]
        XCTAssertTrue(m.needsArrival(a))
        XCTAssertTrue(m.consumeArrival(a))
        XCTAssertFalse(m.consumeArrival(a), "ikinci görünüşte düşüş yeniden oynamaz")
        XCTAssertFalse(m.needsArrival(a))
        XCTAssertFalse(m.consumeArrival(b), "uçarak gelen kart düşmez")
        XCTAssertFalse(m.consumeArrival(c), "yeni olmayan kart düşmez")
        let reduced = StripModel(reduceMotion: { true })
        reduced.newIDs = [a]
        XCTAssertFalse(reduced.consumeArrival(a), "hareket azaltmada varış yok")
        XCTAssertEqual(StripCardView.scale(pressed: true, hovering: false, reduceMotion: true), 1, "hareket azaltmada basma ölçeği yok")
        XCTAssertEqual(StripCardView.scale(pressed: false, hovering: true, reduceMotion: true), 1, "hareket azaltmada hover yalnız gölge")
        XCTAssertEqual(StripCardView.scale(pressed: true, hovering: true, reduceMotion: false), StripMotion.pressScale)
        XCTAssertEqual(StripCardView.scale(pressed: false, hovering: true, reduceMotion: false), StripMotion.hoverScale)
        XCTAssertEqual(StripCardView.scale(pressed: false, hovering: false, reduceMotion: false), 1)
    }

    func testStripViewRendersVisibleCardsOnly() {
        let m = StripModel(reduceMotion: { false })
        m.items = items(30)
        let host = NSHostingView(rootView: StripView(model: m, actions: StripViewActions()))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: StripLayout.stripHeight),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        host.frame = NSRect(x: 0, y: 0, width: 1000, height: StripLayout.stripHeight)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let expected = StripLayout.visibleRange(count: 30, width: 1000, offset: 0).count
        let deadline = Date().addingTimeInterval(1)
        while cardKeys(m).count != expected, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            host.layoutSubtreeIfNeeded()
        }
        XCTAssertEqual(cardKeys(m).count, expected)
        XCTAssertEqual(Set(cardKeys(m)), Set(m.items.prefix(expected).map(\.id.uuidString)))
        // Kart çerçeveleri pencerenin sol üst köşesine göre (y aşağı doğru): ilk kart ipin altında.
        if let r = m.hitRects[m.items[0].id.uuidString] {
            // Eğim (±2,5°) mandal noktasından döndüğü için sınır kutusunun ortası birkaç pt kayar.
            XCTAssertEqual(r.midX, StripLayout.x(index: 0, scrollOffset: 0), accuracy: 4)
            XCTAssertGreaterThan(r.minY, StripLayout.ropeTop)
            XCTAssertLessThan(r.maxY, StripLayout.stripHeight)
        }
        window.close()
    }

    private func cardKeys(_ m: StripModel) -> [String] {
        m.hitRects.keys.filter { UUID(uuidString: $0) != nil }
    }

    private func mouse(_ type: NSEvent.EventType, _ p: NSPoint, clicks: Int = 1, flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: p, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                           windowNumber: 0, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
    }

    private func grabView() -> StripGrabNSView {
        StripGrabNSView(frame: NSRect(x: 0, y: 0, width: 144, height: 112))
    }

    func testGrabViewLongPressNotAfterDrag() {
        let v = grabView()
        var dragged = 0
        let noLongPress = expectation(description: "longPress"); noLongPress.isInverted = true
        v.onBeginDrag = { _, _ in dragged += 1 }
        v.onLongPress = { noLongPress.fulfill() }
        v.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: 70, y: 40)))
        v.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: 76, y: 40)))
        XCTAssertEqual(dragged, 1)
        wait(for: [noLongPress], timeout: 0.5)
    }

    func testGrabViewLongPressFiresWithoutDrag() {
        let v = grabView()
        var pressed: [Bool] = []
        let long = expectation(description: "longPress")
        v.onPressChange = { pressed.append($0) }
        v.onLongPress = { long.fulfill() }
        var clicks = 0
        v.onClick = { _ in clicks += 1 }
        v.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: 70, y: 40)))
        wait(for: [long], timeout: 1)
        v.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 70, y: 40)))
        XCTAssertEqual(clicks, 0, "uzun basma tık sayılmaz")
        XCTAssertEqual(pressed.first, true)
        XCTAssertEqual(pressed.last, false)
    }

    func testGrabViewClickDoubleClickAndCorner() {
        let v = grabView()
        var clicks: [NSEvent.ModifierFlags] = [], doubles = 0, removes = 0, drags = 0
        v.onClick = { clicks.append($0) }
        v.onDoubleClick = { doubles += 1 }
        v.onRemove = { removes += 1 }
        v.onBeginDrag = { _, _ in drags += 1 }
        // Tek tık: bırakınca seçer; 3 pt kayma sürükleme değildir.
        v.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: 70, y: 40)))
        v.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: 73, y: 40)))
        v.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 73, y: 40)))
        XCTAssertEqual(clicks, [[]]); XCTAssertEqual(drags, 0)
        // ⌘ tık basışta seçer.
        v.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: 70, y: 40), flags: .command))
        v.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 70, y: 40), flags: .command))
        XCTAssertEqual(clicks.count, 2); XCTAssertTrue(clicks[1].contains(.command))
        // Çift tık.
        v.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: 70, y: 40), clicks: 2))
        v.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 70, y: 40), clicks: 2))
        XCTAssertEqual(doubles, 1); XCTAssertEqual(clicks.count, 2)
        // Sol üst köşe ✕ (düz koordinatta üst = büyük y).
        v.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: 8, y: 106)))
        v.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 8, y: 106)))
        XCTAssertEqual(removes, 1); XCTAssertEqual(clicks.count, 2)
        XCTAssertTrue(v.acceptsFirstMouse(for: nil))
    }
}
