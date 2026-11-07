import XCTest
@testable import Shotmori

/// macOS ekran görüntüsü kısayolu okuma: varsayılan, özelleştirilmiş, bilinmeyen tuş kodu (karakter yedeği), kapalı.
final class ScreenshotHotKeysTests: XCTestCase {
    private func entry(_ ch: Int, _ code: Int, _ mods: UInt, enabled: Bool = true) -> [String: Any] {
        ["enabled": NSNumber(value: enabled), "value": ["type": "standard", "parameters": [NSNumber(value: ch), NSNumber(value: code), NSNumber(value: mods)]]]
    }
    func testMissingEntryUsesMacOSDefault() {
        XCTAssertEqual(ScreenshotHotKeys.display(.areaToFile, table: [:]), "⇧⌘4")
        XCTAssertEqual(ScreenshotHotKeys.display(.optionsPanel, table: [:]), "⇧⌘5")
        XCTAssertEqual(ScreenshotHotKeys.display(.areaToClipboard, table: [:]), "⌃⇧⌘4")
    }
    /// Alan kısayolu kapalı ve tabloda seçenek paneli girdisi yok → panelin macOS varsayılanı ⇧⌘5 önerilir.
    /// Release'te sistem tablosu hiç okunmaz (`readTable()` boş; ikilide `symbolichotkeys` metni yok — `scripts/check-release-binary.sh`).
    func testDisabledAreaWithoutOptionsEntryFallsBackToDefaultOptionsPanel() {
        let t: [String: Any] = ["31": entry(52, 21, 1179648, enabled: false)]
        XCTAssertEqual(ScreenshotHotKeys.display(.areaToFile, table: t), "⇧⌘5")
        #if !DEBUG
        XCTAssertTrue(ScreenshotHotKeys.readTable().isEmpty)
        #endif
    }
    func testCustomBindingIsShown() {
        let t: [String: Any] = ["31": entry(51, 20, 262144 | 1048576)] // ⌃⌘3
        XCTAssertEqual(ScreenshotHotKeys.display(.areaToFile, table: t), "⌃⌘3")
    }
    func testUnknownKeyCodeFallsBackToCharacter() {
        let t: [String: Any] = ["30": entry(167, 10, 1048576)] // ⌘§ (ISO klavye, tuş kodu 10 tabloda yok)
        XCTAssertEqual(ScreenshotHotKeys.display(.fullScreenToFile, table: t), "⌘§")
    }
    /// L10N-03 gerilemesi: macOS kısayolu etkin düzenden çevrilmez (AZERTY'de rakam sırası sembol verir); ABD adı kullanılır.
    func testDefaultShortcutsUseLayoutIndependentDigits() {
        XCTAssertEqual(HotKeyCenter.usName(21), "4"); XCTAssertEqual(HotKeyCenter.usName(23), "5")
        let t: [String: Any] = ["31": entry(65535, 21, 1179648)] // karakter saklanmamış girdi
        XCTAssertEqual(ScreenshotHotKeys.display(.areaToFile, table: t), "⇧⌘4")
        XCTAssertEqual(ScreenshotHotKeys.display(.optionsPanel, table: [:]), "⇧⌘5")
    }
    func testDisabledAreaShortcutShowsOptionsPanel() {
        let t: [String: Any] = ["31": entry(52, 21, 1179648, enabled: false), "184": entry(53, 23, 1179648)]
        XCTAssertEqual(ScreenshotHotKeys.display(.areaToFile, table: t), "⇧⌘5")
    }
    func testStringsEmbedTheShortcut() {
        XCTAssertFalse(ScreenshotHotKeys.area.isEmpty); XCTAssertFalse(S.thumbnailWarningBody.contains("%@"))
        XCTAssertTrue(S.thumbnailWarningBody.contains(ScreenshotHotKeys.options))
    }
}
