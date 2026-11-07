import XCTest
@testable import Shotmori

/// Ayarlar kenar çubuğu sayfaları ve Hakkında bağlantıları.
final class SettingsPageTests: XCTestCase {
    func testOrderAndSymbols() {
        XCTAssertEqual(SettingsPage.available.first, .general)
        XCTAssertEqual(SettingsPage.available.last, .about)
        XCTAssertEqual(SettingsPage.general.symbol, "gearshape")
        XCTAssertEqual(SettingsPage.shelf.symbol, "tray.full")
        XCTAssertEqual(SettingsPage.actions.symbol, "bolt.fill")
        XCTAssertEqual(SettingsPage.about.symbol, "info")
        #if !SHOTMORI_CLOUD
        XCTAssertFalse(SettingsPage.available.contains(.cloud))
        #endif
    }
    func testTitlesLocalized() {
        XCTAssertEqual(SettingsPage.about.title, S.settingsAbout)
        XCTAssertEqual(SettingsPage.general.title, S.tabGeneral)
        XCTAssertFalse(S.resetDefaults.isEmpty)
    }
    func testHelpTextsStillExist() {
        for t in [S.folderHelp, S.maxItemsHelp, S.hideAfterDropHelp, S.favoritesOverflowNote, S.generalHotKeyHelp] { XCTAssertFalse(t.isEmpty) }
    }
    func testFootersExist() { XCTAssertFalse(S.folderFooter.isEmpty); XCTAssertFalse(S.quickActionsFooter.isEmpty) }
    #if SHOTMORI_CLOUD
    func testCloudAccountStringsExist() {
        for t in [S.cloudAccountsSection, S.cloudAccountsFooter, S.cloudSharingSection, S.cloudSetUp, S.cloudEdit, S.cloudAdvancedButton, S.s3SheetTitle, S.cloudDriveAdvancedTitle] { XCTAssertFalse(t.isEmpty) }
    }
    #endif
    func testLinksFollowLanguage() {
        XCTAssertEqual(Links.help(language: "tr").absoluteString, "https://shotmori.com/tr/help/")
        XCTAssertEqual(Links.privacy(language: "tr").absoluteString, "https://shotmori.com/tr/privacy/")
        XCTAssertEqual(Links.help(language: "en").absoluteString, "https://shotmori.com/help/")
        XCTAssertEqual(Links.privacy(language: "de").absoluteString, "https://shotmori.com/privacy/")
    }
}
