import XCTest
@testable import Shotmori

final class ShelfSelectionTests: XCTestCase {
    let a = UUID(), b = UUID(), c = UUID(), d = UUID()
    var order: [UUID] { [a, b, c, d] }

    func testShiftRangeThenCloseTargetsOnlyClickedItem() {
        var s = ShelfSelection()
        s.mouseDown(on: a, order: order, command: false, shift: false)
        s.mouseDown(on: c, order: order, command: false, shift: true)
        XCTAssertEqual(s.ids, [a, b, c])
        XCTAssertEqual(s.closeTargets(for: b), [b], "✕ seçimden bağımsız tek hedef")
        XCTAssertEqual(s.closeTargets(for: d), [d], "seçili olmayan bir karenin ✕'i de yalnızca o kare")
    }
    func testBulkRemovalTargetsOnlySelected() {
        var s = ShelfSelection()
        s.mouseDown(on: b, order: order, command: false, shift: false)
        s.mouseDown(on: d, order: order, command: true, shift: false)
        XCTAssertEqual(s.ids, [b, d], "toplu kaldırma yalnız seçili olanları alır")
    }
    func testPressingSelectedItemKeepsMultiSelectionUntilRelease() {
        var s = ShelfSelection()
        s.mouseDown(on: a, order: order, command: false, shift: false)
        s.mouseDown(on: b, order: order, command: false, shift: true)
        s.mouseDown(on: a, order: order, command: false, shift: false) // sürükleme başlayabilir
        XCTAssertEqual(s.ids, [a, b])
        s.mouseUpWithoutDrag(on: a, command: false, shift: false)
        XCTAssertEqual(s.ids, [a])
    }
    func testNewScreenshotDoesNotBreakExistingSelection() {
        var s = ShelfSelection()
        s.mouseDown(on: a, order: order, command: false, shift: false)
        s.mouseDown(on: b, order: order, command: false, shift: true)
        let newest = UUID()
        s.reconcile(existing: [newest] + order) // yeni kare en başa geldi
        XCTAssertEqual(s.ids, [a, b]); XCTAssertEqual(s.anchor, a)
        s.reconcile(existing: [newest, b, c, d]) // a kaldırıldı
        XCTAssertEqual(s.ids, [b]); XCTAssertEqual(s.anchor, b)
    }
    func testArrowMoveExtends() {
        var s = ShelfSelection()
        s.mouseDown(on: b, order: order, command: false, shift: false)
        XCTAssertEqual(s.move(by: 1, order: order, extend: true), c)
        XCTAssertEqual(s.ids, [b, c])
        XCTAssertEqual(s.move(by: -5, order: order, extend: false), a)
        XCTAssertEqual(s.ids, [a])
    }
}
