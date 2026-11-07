import XCTest
@testable import Shotmori

/// G: render tamamlanması teslim değildir; iptal/hata belgeyi kirli bırakır, eskimiş anlık görüntü teslim edilmez.
final class OutputCompletionTests: XCTestCase {
    private func edited() -> EditState { var s = EditState(); s.crop = CGRect(x: 0, y: 0, width: 10, height: 10); return s }

    func testCancelOrErrorKeepsUnsavedWarning() {
        var o = OutputSession<EditState>(); let s = edited()
        o.begin(s); o.abort()
        XCTAssertTrue(o.needsCloseConfirmation(hasEdits: s.hasEdits), "Save As iptali sonrası kapatma uyarısı atlanmamalı")
    }
    func testDeliveryClearsWarningOnlyAfterSuccess() {
        var o = OutputSession<EditState>(); let s = edited()
        o.begin(s); XCTAssertTrue(o.needsCloseConfirmation(hasEdits: true), "render başladı diye temiz sayılmamalı")
        o.markDelivered(); XCTAssertFalse(o.needsCloseConfirmation(hasEdits: true))
    }
    func testStaleSnapshotIsNotDelivered() {
        var o = OutputSession<EditState>(); let s1 = edited(); var s2 = s1; s2.crop = CGRect(x: 1, y: 1, width: 5, height: 5)
        o.begin(s1)
        XCTAssertFalse(o.canDeliver(current: s2)); XCTAssertTrue(o.canDeliver(current: s1))
    }
    func testNoEditsNeverAsks() {
        let o = OutputSession<EditState>()
        XCTAssertFalse(o.needsCloseConfirmation(hasEdits: false))
    }
    func testClipboardWriteReportsResultOnPrivatePasteboard() {
        let pb = NSPasteboard(name: NSPasteboard.Name("dev.shotmori.test.out.\(UUID())"))
        let ok = ClipboardPayload.make(edited: Data([0x89, 0x50]), format: .png, fileURL: nil).write(to: pb)
        XCTAssertTrue(ok); XCTAssertNotNil(pb.data(forType: .png)); pb.releaseGlobally()
    }
}
