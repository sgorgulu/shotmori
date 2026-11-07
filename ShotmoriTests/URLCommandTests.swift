import XCTest
@testable import Shotmori

/// `shotmori://` ayrıştırıcısı ve izin kapısı: beyaz liste, dosya yolu reddi, raf aralığı, tek seferlik soru.
final class URLCommandTests: XCTestCase {
    private func parse(_ s: String) -> URLCommand? { URLCommand.parse(URL(string: s)!) }

    func testParsesWhitelist() {
        XCTAssertEqual(parse("shotmori://show"), .show(shelf: nil))
        XCTAssertEqual(parse("shotmori://show?shelf=2"), .show(shelf: 2))
        XCTAssertEqual(parse("shotmori://hide"), .hide)
        XCTAssertEqual(parse("shotmori://toggle?shelf=8"), .toggle(shelf: 8))
        XCTAssertEqual(parse("shotmori://add-clipboard"), .addClipboard)
        XCTAssertEqual(parse("shotmori://new-shelf?name=Tasar%C4%B1m"), .newShelf(name: "Tasarım"))
        XCTAssertEqual(parse("shotmori://shelf?index=3"), .selectShelf(index: 3))
        XCTAssertEqual(parse("shotmori://settings"), .settings(page: nil))
        // Büyük/küçük harf ve sondaki "/" tolere edilir.
        XCTAssertEqual(parse("SHOTMORI://Show/"), .show(shelf: nil))
    }

    func testRejectsPathParameters() {
        XCTAssertNil(parse("shotmori://show?path=/x"))
        XCTAssertNil(parse("shotmori://show?file=/etc/hosts"))
        XCTAssertNil(parse("shotmori://show?url=file:///etc/hosts"))
        XCTAssertNil(parse("shotmori://new-shelf?name=a&path=/tmp"))
        XCTAssertNil(parse("shotmori://show/etc/hosts"))           // URL yolu
        XCTAssertNil(parse("shotmori://show?FILE=/x"))              // anahtar büyük harfle de reddedilir
        XCTAssertNil(parse("shotmori://show#/etc"))                 // parça
        XCTAssertNil(parse("shotmori://user@show"))                 // kullanıcı bilgisi
        XCTAssertNil(parse("shotmori://show?shelf=1&shelf=2"))      // yinelenen anahtar
        XCTAssertNil(parse("shotmori://hide?shelf=1"))              // komutun almadığı parametre
        XCTAssertNil(parse("shotmori://show?foo=1"))                // bilinmeyen parametre
        XCTAssertNil(parse("file:///etc/hosts"))
        XCTAssertNil(parse("https://show"))
    }

    func testRejectsShelfOutOfRange() {
        XCTAssertNil(parse("shotmori://shelf?index=9"))
        XCTAssertNil(parse("shotmori://shelf?index=0"))
        XCTAssertNil(parse("shotmori://shelf?index=-1"))
        XCTAssertNil(parse("shotmori://shelf?index=abc"))
        XCTAssertNil(parse("shotmori://shelf"))                     // index zorunlu
        XCTAssertNil(parse("shotmori://show?shelf=9"))
        XCTAssertNil(parse("shotmori://toggle?shelf=0"))
        XCTAssertNil(parse("shotmori://show?shelf="))
        XCTAssertEqual(parse("shotmori://shelf?index=1"), .selectShelf(index: 1))
        XCTAssertEqual(parse("shotmori://shelf?index=8"), .selectShelf(index: 8))
    }

    func testRejectsUnknownCommand() {
        XCTAssertNil(parse("shotmori://copy-last"), "panoya yazan komut URL'de yok (SEC-04): CopyLatestIntent kullanılır")
        XCTAssertNil(parse("shotmori://upload"))
        XCTAssertNil(parse("shotmori://clear"))
        XCTAssertNil(parse("shotmori://trash"))
        XCTAssertNil(parse("shotmori://"))
        XCTAssertNil(parse("shotmori:show"))
    }

    func testNameTrimmedAndLimited() {
        XCTAssertNil(parse("shotmori://new-shelf?name=" + String(repeating: "a", count: 25)))
        XCTAssertEqual(parse("shotmori://new-shelf?name=" + String(repeating: "a", count: 24)), .newShelf(name: String(repeating: "a", count: 24)))
        XCTAssertEqual(parse("shotmori://new-shelf?name="), .newShelf(name: nil))
        XCTAssertEqual(parse("shotmori://new-shelf?name=%20%20"), .newShelf(name: nil))
        XCTAssertEqual(parse("shotmori://new-shelf"), .newShelf(name: nil))
        XCTAssertEqual(parse("shotmori://new-shelf?name=%20%C3%87al%C4%B1%C5%9Fma%20"), .newShelf(name: "Çalışma"))
        XCTAssertNil(parse("shotmori://new-shelf?name=a%0Ab"))     // denetim karakteri
    }

    func testGateAsksOnceThenDrops() {
        XCTAssertEqual(URLCommand.gate(enabled: false, asked: false), .ask)
        XCTAssertEqual(URLCommand.gate(enabled: false, asked: true), .drop)
        XCTAssertEqual(URLCommand.gate(enabled: true, asked: false), .run)
        XCTAssertEqual(URLCommand.gate(enabled: true, asked: true), .run)

        // "İzin verme": komut yürümez, anahtar kapalı kalır, `asked` kaydedilir; ikinci istekte soru yok.
        let prefs = makePrefs()
        var asks = 0
        XCTAssertFalse(URLCommand.authorize(prefs: prefs) { asks += 1; return false })
        XCTAssertEqual(asks, 1)
        XCTAssertFalse(prefs.urlSchemeEnabled)
        XCTAssertTrue(prefs.urlSchemeAsked)
        XCTAssertFalse(URLCommand.authorize(prefs: prefs) { asks += 1; return true })
        XCTAssertEqual(asks, 1)
    }

    func testGateAllowEnablesAndRuns() {
        let prefs = makePrefs()
        var asks = 0
        XCTAssertTrue(URLCommand.authorize(prefs: prefs) { asks += 1; return true })
        XCTAssertTrue(prefs.urlSchemeEnabled)
        XCTAssertTrue(prefs.urlSchemeAsked)
        XCTAssertTrue(URLCommand.authorize(prefs: prefs) { asks += 1; return false })
        XCTAssertEqual(asks, 1)
        // Sıfırlama izni geri alır: bir sonraki istekte yeniden sorulur.
        prefs.resetGeneralSection()
        XCTAssertEqual(URLCommand.gate(enabled: prefs.urlSchemeEnabled, asked: prefs.urlSchemeAsked), .ask)
    }

    func testSettingsPageParsing() {
        XCTAssertEqual(parse("shotmori://settings?page=cloud"), .settings(page: .cloud))
        XCTAssertEqual(parse("shotmori://settings?page=general"), .settings(page: .general))
        XCTAssertEqual(parse("shotmori://settings?page=about"), .settings(page: .about))
        XCTAssertEqual(parse("shotmori://settings?page=nope"), .settings(page: nil))
        XCTAssertNil(parse("shotmori://settings?page=general&file=/x"))
    }

    private func makePrefs() -> Preferences {
        let suite = "dev.shotmori.tests.urlcommand.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        addTeardownBlock { d.removePersistentDomain(forName: suite) }
        return Preferences(defaults: d)
    }
}
