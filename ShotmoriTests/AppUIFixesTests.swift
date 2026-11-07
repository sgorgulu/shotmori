import XCTest
import AppKit
@testable import Shotmori

/// Faz 2 G3 (uygulama, menü çubuğu, kurulum, UI) düzeltmelerinin davranış testleri.
final class AppUIFixesTests: XCTestCase {
    // COR-02 + COR-11: açık kurulum penceresi yeniden kullanılır; kip farklıysa değiştirilir.
    func testOnboardingRequestReusesVisibleWindow() {
        let r = AppController.onboardingRequest
        XCTAssertEqual(r(true, false, false), .bringToFront, "ikinci pencere açılmaz")
        XCTAssertEqual(r(true, true, true), .bringToFront)
        XCTAssertEqual(r(true, false, true), .bringToFront, "açık ilk kurulum klasör isteğiyle kesilmez (Bitir adımları atlatmaz)")
        XCTAssertEqual(r(true, true, false), .replace, "yalnız klasör sayfası tam akışa geçer")
        XCTAssertEqual(r(false, false, false), .open, "✕ ile kapatılmış pencere yeniden açılır")
        XCTAssertEqual(r(false, true, false), .open)
        XCTAssertEqual(r(false, false, true), .open)
    }

    // COR-06: popover yalnız görünen üç kartla çalışır; seçim görünmeyen kareye kaymaz.
    func testPopoverWorksOnlyWithVisibleThumbs() {
        let items = (0..<6).map { ShelfItem(path: "/tmp/p\($0).png", fileID: nil, capturedAt: Date()) }
        let visible = MenuBarPopoverViewController.visibleItems(items)
        XCTAssertEqual(visible.count, MenuBarPopoverViewController.visibleThumbs)
        XCTAssertEqual(visible.map(\.id), items.prefix(3).map(\.id))
        var sel = ShelfSelection(); sel.selectOnly(items[3].id)
        sel.reconcile(existing: visible.map(\.id))
        XCTAssertTrue(sel.isEmpty, "görünmeyen 4. kare seçili kalmaz")
    }

    // A11Y-01: kısayol kaydedicisi VoiceOver'a geçerli kısayolu söyler (ilk değer ve kayıt sonrası).
    func testKeyRecorderAccessibilityValueFollowsDisplay() {
        let v = KeyRecorderNSView()
        v.display = "⌘S"
        XCTAssertEqual(v.accessibilityValue() as? String, "⌘S")
        v.startRecording()
        XCTAssertEqual(v.accessibilityValue() as? String, S.hotKeyRecordHint)
        v.display = "⌥K" // kayıt sırasında değer ipucu kalır
        XCTAssertEqual(v.accessibilityValue() as? String, S.hotKeyRecordHint)
        v.cancelRecording()
        XCTAssertEqual(v.accessibilityValue() as? String, "⌥K")
    }

    // X-06: tercih bildirimi kısayolu yalnız tuş ya da değiştiriciler değişince yeniden kaydeder.
    func testHotKeyReRegistersOnlyOnChange() {
        XCTAssertTrue(AppController.hotKeyNeedsRegistration(registered: nil, code: 1, modifiers: [.command, .shift]), "ilk kayıt")
        XCTAssertFalse(AppController.hotKeyNeedsRegistration(registered: (1, [.command, .shift]), code: 1, modifiers: [.command, .shift]), "iğne vb. değişimde kayıt yok")
        XCTAssertTrue(AppController.hotKeyNeedsRegistration(registered: (1, [.command, .shift]), code: 2, modifiers: [.command, .shift]))
        XCTAssertTrue(AppController.hotKeyNeedsRegistration(registered: (1, [.command, .shift]), code: 1, modifiers: [.option]))
    }

    // X-05: açılış budaması varlık denetimini saf yardımcıyla yapar (yardımcı kuyrukta çalışır).
    func testMissingPathsFiltersExisting() {
        let missing = AppController.missingPaths(["/a", "/b", "/c"], exists: { $0 == "/b" })
        XCTAssertEqual(missing, ["/a", "/c"])
        XCTAssertTrue(AppController.missingPaths([], exists: { _ in false }).isEmpty)
    }

    // PERF-06: menü çubuğuna bırakma kararı yalnız türe bakar; görsel verisi okunmadan PNG/TIFF varlığı yeter.
    func testStatusDropDecisionUsesTypesOnly() {
        let pb = NSPasteboard(name: NSPasteboard.Name("dev.shotmori.tests.statusdrop-\(UUID())")); defer { pb.releaseGlobally() }
        pb.clearContents(); pb.setString("metin", forType: .string)
        XCTAssertEqual(StatusDropView.operation(for: pb), [], "görsel olmayan veri reddedilir")
        pb.clearContents(); pb.setData(Data([0x89, 0x50, 0x4E, 0x47]), forType: .png)
        XCTAssertEqual(StatusDropView.operation(for: pb), .copy)
        pb.clearContents(); pb.setData(Data(), forType: ShelfPanelController.internalItemsType)
        XCTAssertEqual(StatusDropView.operation(for: pb), [], "raftan iç sürükleme reddedilir")
    }

    // L10N-03: tuş adı etkin düzenden; Boşluk ve bilinmeyen tuş yerelleştirilmiş metinle.
    func testKeyNamesAreLocalized() {
        XCTAssertEqual(HotKeyCenter.keyName(49), S.keySpace)
        XCTAssertEqual(HotKeyCenter.keyName(999), S.keyCodeName(999))
        XCTAssertNil(HotKeyCenter.knownKeyName(999))
        XCTAssertEqual(HotKeyCenter.keyName(36), "↩")
        XCTAssertEqual(HotKeyCenter.keyName(122), "F1")
        XCTAssertNil(HotKeyCenter.keyEquivalent(122), "işlev tuşu kısayol alanına yazılmaz")
        XCTAssertNil(HotKeyCenter.keyEquivalent(49))
        let s = HotKeyCenter.keyName(1) // ABD'de "S", Türkçe F'de başka harf: tek görünür karakter
        XCTAssertEqual(s.count, 1, s)
        XCTAssertEqual(HotKeyCenter.keyEquivalent(1)?.count, 1)
        XCTAssertFalse(HotKeyCenter.display(keyCode: 1, modifiers: [.command, .shift]).contains("key"))
    }

    // A11Y-05: menü çubuğu rozetinin VoiceOver etiketi yeni kare sayısını söyler.
    func testBadgeAccessibilityLabelIncludesNewCount() {
        XCTAssertEqual(StatusItemController.badgeAccessibilityLabel(0), S.appName)
        XCTAssertEqual(StatusItemController.badgeAccessibilityLabel(3), "\(S.appName), \(S.newCount(3))")
    }

    // A11Y-08: ChipView metni değişince VoiceOver etiketi de güncellenir.
    func testChipViewAccessibilityLabelFollowsText() {
        let c = ChipView("")
        c.text = "5 · 2 yeni"
        XCTAssertEqual(c.accessibilityLabel(), "5 · 2 yeni")
    }

    // A11Y-10: kurulumdaki örnek raf açıklayıcı bir etiketle okunur.
    func testSampleShelfAccessibilityText() {
        let v = SampleShelfPreview(accessibilityText: S.obSampleShelfAX)
        XCTAssertEqual(v.accessibilityText, S.obSampleShelfAX)
        XCTAssertNotEqual(S.obSampleShelfAX, S.newBadge)
    }
}
