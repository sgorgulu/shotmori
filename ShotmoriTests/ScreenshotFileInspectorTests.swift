import XCTest
@testable import Shotmori

final class ScreenshotFileInspectorTests: XCTestCase {
    func testTemporaryAndHiddenNamesAreRejected() {
        XCTAssertFalse(ScreenshotFileInspector.isCandidateFileName("..Screenshot 2026-10-18 at 17.09.13.png-U4ao2w"))
        XCTAssertFalse(ScreenshotFileInspector.isCandidateFileName(".Screenshot 2026-10-18 at 17.09.13.png"))
        XCTAssertFalse(ScreenshotFileInspector.isCandidateFileName(".DS_Store"))
        XCTAssertFalse(ScreenshotFileInspector.isCandidateFileName("notes.txt"))
        XCTAssertTrue(ScreenshotFileInspector.isCandidateFileName("Screenshot 2026-10-18 at 17.09.13.png"))
        XCTAssertTrue(ScreenshotFileInspector.isCandidateFileName("Ekran Resmi 2026-10-18 17.09.13.JPG"))
    }
    func testMarkerDetectedViaXattr() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("m-\(UUID()).png")
        try Data([1, 2, 3]).write(to: tmp)
        XCTAssertFalse(ScreenshotFileInspector.hasScreenCaptureMarker(tmp))
        let plist = try PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0)
        let rc = plist.withUnsafeBytes { setxattr(tmp.path, ScreenshotFileInspector.markerXattr, $0.baseAddress, plist.count, 0, 0) }
        XCTAssertEqual(rc, 0)
        XCTAssertTrue(ScreenshotFileInspector.hasScreenCaptureMarker(tmp))
    }
    func testIncompleteImageIsNotComplete() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("half-\(UUID()).png")
        // Yalnızca PNG imzası + IHDR parçası: yarım dosya
        var bytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        bytes += [0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52, 0, 0, 0, 10, 0, 0, 0, 10, 8, 6, 0, 0, 0]
        try Data(bytes).write(to: tmp)
        XCTAssertFalse(ScreenshotFileInspector.isCompleteImage(tmp))
    }
    func testCompleteImageIsComplete() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("full-\(UUID()).png")
        let img = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { r in NSColor.red.setFill(); r.fill(); return true }
        let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
        try rep.representation(using: .png, properties: [:])!.write(to: tmp)
        XCTAssertTrue(ScreenshotFileInspector.isCompleteImage(tmp))
        XCTAssertNotNil(ScreenshotFileInspector.fileIdentifier(tmp))
    }

    func testIsCompleteImageOnTruncatedFileReturnsFalse() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("trunc-\(UUID()).png")
        try Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52, 0, 0, 0, 10]).write(to: tmp)
        XCTAssertFalse(ScreenshotFileInspector.isCompleteImage(tmp))
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent("empty-\(UUID()).png")
        try Data().write(to: empty)
        XCTAssertFalse(ScreenshotFileInspector.isCompleteImage(empty))
        XCTAssertFalse(ScreenshotFileInspector.isCompleteImage(URL(fileURLWithPath: "/nonexistent/\(UUID()).png")))
    }
}
