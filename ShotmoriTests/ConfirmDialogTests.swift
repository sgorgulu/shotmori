import XCTest
import AppKit
@testable import Shotmori

/// B: onay diyaloglarında güvenli varsayılan (Return/Esc → güvenli düğme), devam yalnızca ikinci düğme, dosya listesi tam adlarla.
final class ConfirmDialogTests: XCTestCase {
    func testSafeButtonIsDefaultAndEscapeProceedIsSecond() {
        let a = NSAlert(); ConfirmDialog.configure(a, safe: "Vazgeç", proceed: "2 dosyayı Çöp’e taşı", destructive: true)
        XCTAssertEqual(a.buttons.count, 2)
        XCTAssertEqual(a.buttons[0].title, "Vazgeç"); XCTAssertEqual(a.buttons[0].keyEquivalent, "\r", "Return güvenli düğmeye")
        let esc = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 53)!
        XCTAssertTrue(ConfirmDialog.isEscape(esc)); XCTAssertFalse(ConfirmDialog.isEscape(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 36)!))
        XCTAssertEqual(a.buttons[1].keyEquivalent, "\u{8}", "yıkıcı düğme yalnız ⌘⌫ ile"); XCTAssertEqual(a.buttons[1].keyEquivalentModifierMask, [.command])
        XCTAssertTrue(a.buttons[1].hasDestructiveAction)
        XCTAssertFalse(ConfirmDialog.shouldProceed(.alertFirstButtonReturn)); XCTAssertTrue(ConfirmDialog.shouldProceed(.alertSecondButtonReturn)); XCTAssertFalse(ConfirmDialog.shouldProceed(.cancel))
    }
    func testNeutralConfirmHasNoDestructiveStyle() {
        let a = NSAlert(); ConfirmDialog.configure(a, safe: "Vazgeç", proceed: "Rafı temizle", destructive: false)
        XCTAssertFalse(a.buttons[1].hasDestructiveAction)
    }
    func testFileListAccessoryShowsFullNames() throws {
        let names = (1...8).map { "Ekran Görüntüsü 2026-10-19 11.4\($0).png" }
        let sv = try XCTUnwrap(ConfirmDialog.fileListAccessory(names) as? NSScrollView); let tv = try XCTUnwrap(sv.documentView as? NSTextView)
        XCTAssertEqual(tv.string.components(separatedBy: "\n"), names); XCTAssertFalse(tv.isEditable); XCTAssertTrue(tv.isSelectable); XCTAssertTrue(sv.hasVerticalScroller)
        XCTAssertLessThanOrEqual(sv.frame.height, 112)
        XCTAssertEqual(tv.accessibilityLabel(), S.imageCount(8), "VoiceOver etiketi çıplak sayı değil")
        let single = try XCTUnwrap((ConfirmDialog.fileListAccessory([names[0]]) as? NSScrollView)?.documentView as? NSTextView)
        XCTAssertEqual(single.accessibilityLabel(), names[0])
    }
    func testResizeOutputGateBlocksInvalidAndBusy() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rs-\(UUID())", isDirectory: true); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let u = dir.appendingPathComponent("a.png")
        let img = NSImage(size: NSSize(width: 40, height: 30), flipped: false) { r in NSColor.blue.setFill(); r.fill(); return true }
        try NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: u)
        let m = ResizeModel(source: u, info: try XCTUnwrap(ImageResizer.sourceInfo(u)))
        XCTAssertTrue(m.canOutput); XCTAssertEqual(m.preferredHeight, 440)
        m.format = .jpeg; XCTAssertEqual(m.preferredHeight, 512, "RGBA PNG → JPEG saydamlık uyarısı +28")
        m.format = .png; m.keepAspect = false; m.width = 0
        XCTAssertFalse(m.canOutput, "geçersiz ölçüde çıktı pasif"); XCTAssertEqual(m.preferredHeight, 468)
        var called = false; m.render { _ in called = true }; XCTAssertFalse(called, "geçersizken render çağrılmaz")
        try? FileManager.default.removeItem(at: dir)
    }
}
