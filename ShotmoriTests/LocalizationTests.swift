import XCTest
@testable import Shotmori

/// tr.lproj / en.lproj tabloları: anahtar eşitliği, boş değer yok, biçim yer tutucuları aynı; İngilizce paket İngilizce döner.
final class LocalizationTests: XCTestCase {
    private func table(_ lang: String, _ name: String = "Localizable") throws -> [String: String] {
        let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "strings", subdirectory: nil, localization: lang), "\(lang).lproj/\(name).strings yok")
        return try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String], "\(lang) tablosu okunamadı")
    }
    /// Biçim yer tutucuları ("%%" hariç); konumsal olanlar (`%2$d`) konuma göre sıralanır (dillerde sıra farklı olabilir).
    private func specs(_ s: String) -> [String] {
        let re = try! NSRegularExpression(pattern: #"%(?:(\d+)\$)?(.)"#)
        var seq: [String] = [], pos: [(Int, String)] = []
        for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            guard let t = Range(m.range(at: 2), in: s).map({ String(s[$0]) }), t != "%" else { continue } // "%%" düz yüzde
            if let r = Range(m.range(at: 1), in: s), let n = Int(s[r]) { pos.append((n, t)) } else { seq.append(t) }
        }
        return seq + pos.sorted { $0.0 < $1.0 }.map { "\($0.0)$\($0.1)" }
    }
    /// Kaynak ağacındaki dosya (widget uzantısı hedefi bu pakete derlenmez).
    private func sourceTable(_ relative: String) throws -> [String: String] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent(relative)
        return try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String], "\(relative) okunamadı")
    }

    func testTurkishAndEnglishTablesMatch() throws {
        let tr = try table("tr"), en = try table("en")
        XCTAssertEqual(Set(tr.keys), Set(en.keys), "anahtar kümeleri farklı")
        XCTAssertGreaterThan(tr.count, 150)
        for (k, v) in tr {
            XCTAssertFalse(v.isEmpty, "boş tr: \(k)"); XCTAssertFalse((en[k] ?? "").isEmpty, "boş en: \(k)")
            XCTAssertEqual(specs(v), specs(en[k] ?? ""), "biçim uyuşmazlığı: \(k)")
        }
    }
    func testEnglishBundleResolvesEnglish() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "en", withExtension: "lproj")); let b = try XCTUnwrap(Bundle(url: url))
        XCTAssertEqual(b.localizedString(forKey: "shelfTitle", value: nil, table: nil), "Screenshot shelf")
        XCTAssertEqual(String(format: b.localizedString(forKey: "popoverCount.other", value: nil, table: nil), 3), "3 images on the shelf")
        XCTAssertEqual(b.localizedString(forKey: "editedBadge", value: nil, table: nil), "edited")
    }
    func testTurkishBundleResolvesTurkish() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "tr", withExtension: "lproj")); let b = try XCTUnwrap(Bundle(url: url))
        XCTAssertEqual(b.localizedString(forKey: "shelfTitle", value: nil, table: nil), "Screenshot rafı")
        XCTAssertEqual(String(format: b.localizedString(forKey: "actionMoveToTrashMany", value: nil, table: nil), 2), "2 dosyayı Çöp’e taşı…")
    }
    #if SHOTMORI_CLOUD
    /// Bulut metinleri ayrı `Cloud` tablosunda (Release paketine girmez); bulutlu derlemede iki dil eşit, ana tabloyla ortak anahtar yok.
    func testCloudTableIsSeparateAndResolves() throws {
        let tr = try table("tr", "Cloud"), en = try table("en", "Cloud"), main = try table("tr")
        XCTAssertEqual(Set(tr.keys), Set(en.keys), "bulut anahtar kümeleri farklı")
        XCTAssertGreaterThan(tr.count, 50)
        XCTAssertTrue(Set(main.keys).isDisjoint(with: tr.keys), "bulut anahtarı ana tabloda da var")
        for (k, v) in tr { XCTAssertEqual(specs(v), specs(en[k] ?? ""), "biçim uyuşmazlığı: \(k)") }
        XCTAssertTrue(["Yeniden dene", "Retry"].contains(S.cloudRetry))
        XCTAssertTrue(["Ağ hatası: x", "Network error: x"].contains(S.cloudErrNetwork("x")))
    }
    #endif
    /// Servisler menü adı (tablo I): anahtar Info.plist'teki varsayılan İngilizce metin; iki dilde aynı anahtarlar.
    func testServicesMenuStringsExist() throws {
        let tr = try table("tr", "ServicesMenu"), en = try table("en", "ServicesMenu")
        XCTAssertEqual(Set(tr.keys), Set(en.keys))
        XCTAssertEqual(tr["Add to Shotmori Shelf"], "Shotmori rafına ekle")
        XCTAssertEqual(en["Add to Shotmori Shelf"], "Add to Shotmori Shelf")
    }
    /// App Shortcuts ifadeleri (tablo A): her satır iki dilde `${applicationName}` taşır; anahtar İngilizce ifade.
    func testAppShortcutsStringsKeepPlaceholders() throws {
        let tr = try table("tr", "AppShortcuts"), en = try table("en", "AppShortcuts")
        XCTAssertEqual(Set(tr.keys), Set(en.keys))
        XCTAssertGreaterThanOrEqual(tr.count, 10)
        for (k, v) in tr {
            XCTAssertTrue(k.contains("${applicationName}"), "anahtar: \(k)")
            XCTAssertTrue(v.contains("${applicationName}"), "tr: \(k)")
            XCTAssertTrue((en[k] ?? "").contains("${applicationName}"), "en: \(k)")
        }
        XCTAssertEqual(tr["Show ${applicationName} shelf"], "${applicationName} rafını göster")
    }
    /// Parametre özetleri (tablo P): boş raf parametresi "Raf", varsayılan adlar "Raf 1" → TR özette raf adından sonra "raf" eki yok ("Raf rafını göster" olmasın).
    func testParameterSummariesAvoidDoubleShelfNoun() throws {
        let tr = try table("tr")
        for k in ["Add ${files} to ${shelf}", "Get ${limit} images from ${shelf}", "Get ${limit} new images from ${shelf}", "Show ${shelf}", "Clear ${shelf}"] {
            let v = try XCTUnwrap(tr[k], k)
            XCTAssertTrue(v.contains("${shelf}"), k)
            XCTAssertFalse(v.contains("${shelf} raf"), "çift isim: \(v)")
            XCTAssertFalse(v.replacingOccurrences(of: "${shelf}", with: "Raf 1").lowercased().contains("raf 1 raf"), v)
        }
        XCTAssertEqual(tr["Show ${shelf}"], "Göster: ${shelf}")
    }
    /// URL izin sorusu: geri dönüş yolu gövdede. Widget intent ile çalışır ve `copy-last` URL'de yok (SEC-04/STORE-02);
    /// gövde ve yardım metni bunları anmaz.
    func testURLSchemeAskNamesSettingsNotWidgetOrCopy() {
        XCTAssertFalse(S.urlSchemeAskTitle.isEmpty)
        XCTAssertTrue(S.urlSchemeAskTitle.contains("shotmori://"))
        let tr = (try? table("tr")) ?? [:], en = (try? table("en")) ?? [:]
        XCTAssertTrue(tr["urlSchemeAskBody"]?.contains("Otomasyon") == true)
        XCTAssertTrue(en["urlSchemeAskBody"]?.contains("Automation") == true)
        for k in ["urlSchemeAskBody", "urlSchemeHelp"] {
            let t = tr[k]?.lowercased() ?? "", e = en[k]?.lowercased() ?? ""
            XCTAssertFalse(t.isEmpty || e.isEmpty, k)
            XCTAssertFalse(t.contains("widget") || t.contains("kopyala"), "tr \(k): \(t)")
            XCTAssertFalse(e.contains("widget") || e.contains("copy"), "en \(k): \(e)")
        }
    }
    /// App Review notu izin diyaloğunu gerçek başlık ve düğme adlarıyla anar (STORE-02): hakem notta yazanı ekranda görmeli.
    func testAppReviewNoteQuotesRealURLDialog() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let note = try String(contentsOf: root.appendingPathComponent("docs/app-review-notu.md"), encoding: .utf8)
        let tr = try table("tr"), en = try table("en")
        for k in ["urlSchemeAskTitle", "urlSchemeAllow", "urlSchemeDeny"] {
            let e = try XCTUnwrap(en[k], k), t = try XCTUnwrap(tr[k], k)
            XCTAssertTrue(note.contains("\"\(e)\""), "notta İngilizce \(k) yok: \(e)")
            XCTAssertTrue(note.contains(t), "notta Türkçe \(k) yok: \(t)")
        }
        XCTAssertFalse(note.contains("Another app wants to control"), "eski, var olmayan diyalog metni")
        let widgetTitle = try XCTUnwrap(sourceTable("ShotmoriWidgets/en.lproj/Localizable.strings")["widgetRecentTitle"])
        XCTAssertTrue(note.contains("\"\(widgetTitle)\""), "widget adı notta gerçek adıyla")
    }
    /// Widget metinleri (tablo W): tr/en anahtar ve biçim eşit; ana tabloyla ortak üç komut başlığı aynı değerde.
    func testWidgetStringsMatch() throws {
        let tr = try sourceTable("ShotmoriWidgets/tr.lproj/Localizable.strings"), en = try sourceTable("ShotmoriWidgets/en.lproj/Localizable.strings")
        XCTAssertEqual(Set(tr.keys), Set(en.keys))
        XCTAssertTrue(Set(["widgetRecentTitle", "widgetEmpty", "widgetNew.other", "widgetTotal.one", "cmdShowTitle"]).isSubset(of: tr.keys))
        for (k, v) in tr {
            XCTAssertFalse(v.isEmpty, "boş tr: \(k)"); XCTAssertFalse((en[k] ?? "").isEmpty, "boş en: \(k)")
            XCTAssertEqual(specs(v), specs(en[k] ?? ""), "biçim uyuşmazlığı: \(k)")
        }
        let mainTR = try table("tr"), mainEN = try table("en")
        let shared = Set(tr.keys).intersection(mainTR.keys)
        XCTAssertEqual(shared, ["cmdShowTitle", "cmdClipboardTitle", "cmdCopyLatestTitle"])
        for k in shared { XCTAssertEqual(tr[k], mainTR[k], k); XCTAssertEqual(en[k], mainEN[k], k) }
    }
    /// Konumsal yer tutucu: Türkçe ve İngilizcede sıra farklı, değerler doğru yere düşer.
    func testClearConfirmUsesPositionalArguments() throws {
        let tr = try table("tr"), en = try table("en")
        XCTAssertEqual(String(format: try XCTUnwrap(tr["intentClearConfirm.other"]), "Raf 1", 3), "“Raf 1” içindeki 3 görüntü listeden kaldırılsın mı? Dosyalar diskte kalır.")
        XCTAssertEqual(String(format: try XCTUnwrap(en["intentClearConfirm.other"]), "Work", 3), "Remove 3 images from “Work”? Files stay on disk.")
        // Tekil: "Remove 1 images" değil.
        XCTAssertEqual(String(format: try XCTUnwrap(en["intentClearConfirm.one"]), "Work"), "Remove 1 image from “Work”? Files stay on disk.")
        XCTAssertEqual(String(format: try XCTUnwrap(tr["intentClearConfirm.one"]), "Raf 1"), "“Raf 1” içindeki 1 görüntü listeden kaldırılsın mı? Dosyalar diskte kalır.")
        XCTAssertTrue(S.intentClearConfirm("İş", 1).contains("1"))
        XCTAssertNotEqual(S.intentClearConfirm("İş", 1), S.intentClearConfirm("İş", 2))
        XCTAssertEqual(specs("%2$d a %1$@"), specs("%1$@ b %2$d"))
        XCTAssertEqual(specs("%%%d"), specs("%d%%"))
        XCTAssertTrue(S.intentClearConfirm("İş", 3).contains("3"))
    }
    /// Geliştirme dili İngilizce: Türkçe ya da İngilizce dışındaki sistem dillerinde (ör. Almanca) arayüz İngilizce açılır; Türkçe seçilince Türkçe kalır.
    func testDevelopmentRegionIsEnglish() {
        XCTAssertEqual(Bundle.main.developmentLocalization, "en")
        XCTAssertEqual(Bundle.preferredLocalizations(from: Bundle.main.localizations, forPreferences: ["de"]).first, "en")
        XCTAssertEqual(Bundle.preferredLocalizations(from: Bundle.main.localizations, forPreferences: ["tr"]).first, "tr")
    }
    /// Kurulum metni üçüncü taraf ürün adı anmaz (App Store 2.3.x / marka).
    func testOnboardingCopyNamesNoThirdPartyProducts() throws {
        for lang in ["tr", "en"] {
            let v = try XCTUnwrap(try table(lang)["obDragBody"], "\(lang) obDragBody yok")
            XCTAssertFalse(v.contains("Claude"), "\(lang): \(v)"); XCTAssertFalse(v.contains("Codex"), "\(lang): \(v)")
        }
    }
    func testStringsResolveToSomeLanguage() {
        // Çalışma dili ne olursa olsun anahtar adı sızmamalı.
        XCTAssertTrue(["Screenshot rafı", "Screenshot shelf"].contains(S.shelfTitle))
        XCTAssertTrue(["3 yeni", "3 new"].contains(S.newCount(3)))
        XCTAssertTrue(["Serbest", "Free"].contains(CropAspect.free.label))
        XCTAssertEqual(S.editSizeLabel(1200, 800), "1200 × 800 px")
    }
    /// İngilizce sayılı metinler: tekil biçimi olmayan "%d … images/files/characters/areas" kalmaz; tekil metinler "1 …s" demez.
    func testEnglishCountStringsHaveSingularForms() throws {
        let en = try table("en")
        let plural = try NSRegularExpression(pattern: "%d (more )?(images|files|characters|hidden areas)\\b")
        for (k, v) in en where !k.hasSuffix(".other") && !k.hasSuffix("Many") { // "…Many" yalnız n > 1 için çağrılır
            XCTAssertNil(plural.firstMatch(in: v, range: NSRange(v.startIndex..., in: v)), "tekil biçimi yok: \(k)")
        }
        let wrongOne = try NSRegularExpression(pattern: "\\b1 (more )?(images|files|characters|hidden areas)\\b")
        for (k, v) in en { XCTAssertNil(wrongOne.firstMatch(in: v, range: NSRange(v.startIndex..., in: v)), "yanlış tekil: \(k)") }
        XCTAssertEqual(S.saveAsCopiedToast(1).isEmpty, false)
    }
}

final class LanguagePreferenceTests: XCTestCase {
    func testOverrideMirrorsAppleLanguagesAndResetClears() {
        let suite = "dev.shotmori.tests.lang"; let d = UserDefaults(suiteName: suite)!; d.removePersistentDomain(forName: suite)
        let p = Preferences(defaults: d)
        XCTAssertNil(p.uiLanguage)
        p.uiLanguage = "en"
        XCTAssertEqual(p.uiLanguage, "en"); XCTAssertEqual(d.stringArray(forKey: "AppleLanguages"), ["en"])
        p.uiLanguage = "tr"; XCTAssertEqual(d.stringArray(forKey: "AppleLanguages"), ["tr"])
        p.resetGeneralSection()
        XCTAssertNil(p.uiLanguage); XCTAssertNil(d.persistentDomain(forName: suite)?["AppleLanguages"])
        d.removePersistentDomain(forName: suite)
    }
    /// URL şeması izni varsayılan kapalı; Genel bölümü sıfırlaması izni ve "soruldu" işaretini siler.
    func testURLSchemePrefsDefaultOffAndResetClears() {
        let suite = "dev.shotmori.tests.urlscheme"; let d = UserDefaults(suiteName: suite)!; d.removePersistentDomain(forName: suite)
        let p = Preferences(defaults: d)
        XCTAssertFalse(p.urlSchemeEnabled); XCTAssertFalse(p.urlSchemeAsked)
        p.urlSchemeEnabled = true; p.urlSchemeAsked = true
        XCTAssertTrue(Preferences(defaults: d).urlSchemeEnabled); XCTAssertTrue(Preferences(defaults: d).urlSchemeAsked)
        p.resetGeneralSection()
        XCTAssertFalse(p.urlSchemeEnabled); XCTAssertFalse(p.urlSchemeAsked)
        d.removePersistentDomain(forName: suite)
    }
}
