import XCTest
@testable import Shotmori

/// Paket iskeleti: dış giriş yollarının Info.plist bildirimleri, App Group entitlement'ları, gömülü widget uzantısı.
/// Kaynak dosyalar (`project.yml`, `*.entitlements`) okunur; gömülü uzantı test ana uygulamasında (Bundle.main) denetlenir.
final class ProjectConfigTests: XCTestCase {
    private var root: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent() }
    private func text(_ relative: String) throws -> String { try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8) }
    private func plist(_ relative: String) throws -> [String: Any] {
        let data = try Data(contentsOf: root.appendingPathComponent(relative))
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any], "\(relative) plist değil")
    }
    /// `project.yml` içinde `key:` satırından başlayıp girintisi daha az ya da eşit olan ilk satıra kadar olan blok.
    private func yamlBlock(_ key: String, in yml: String) -> String? {
        let lines = yml.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("\(key):") }) else { return nil }
        let indent = lines[start].prefix(while: { $0 == " " }).count
        var out = [lines[start]]
        for line in lines[(start + 1)...] {
            let t = line.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty, !t.hasPrefix("#"), line.prefix(while: { $0 == " " }).count <= indent, !t.hasPrefix("-") { break }
            out.append(line)
        }
        return out.joined(separator: "\n")
    }

    func testInfoPlistDeclaresSurfaces() throws {
        let yml = try text("project.yml")
        let urlTypes = try XCTUnwrap(yamlBlock("CFBundleURLTypes", in: yml), "CFBundleURLTypes yok")
        XCTAssertTrue(urlTypes.contains("shotmori"), "shotmori:// şeması bildirilmemiş")
        let services = try XCTUnwrap(yamlBlock("NSServices", in: yml), "NSServices yok")
        XCTAssertTrue(services.contains("addToShelfService"))
        XCTAssertTrue(services.contains("Add to Shotmori Shelf"), "servis menü adı ServicesMenu.strings anahtarıyla aynı olmalı")
        XCTAssertTrue(services.contains("public.image"))
        let docs = try XCTUnwrap(yamlBlock("CFBundleDocumentTypes", in: yml), "CFBundleDocumentTypes yok")
        for uti in ["public.png", "public.jpeg", "public.heic", "public.heif", "public.tiff", "com.compuserve.gif", "org.webmproject.webp"] {
            XCTAssertTrue(docs.contains(uti), "belge türü eksik: \(uti)")
        }
        XCTAssertTrue(yml.contains("com.apple.widgetkit-extension"))
        XCTAssertTrue(yml.contains("dev.shotmori.app.widgets"))
    }

    func testEntitlementsHaveAppGroup() throws {
        XCTAssertEqual(WidgetSnapshot.groupID, "ANW6K6228Y.dev.shotmori")
        for file in ["Shotmori/Shotmori.entitlements", "Shotmori/Shotmori-Debug.entitlements", "ShotmoriWidgets/ShotmoriWidgets.entitlements"] {
            let ents = try plist(file)
            let groups = try XCTUnwrap(ents["com.apple.security.application-groups"] as? [String], "\(file): application-groups yok")
            XCTAssertEqual(groups, [WidgetSnapshot.groupID], file)
        }
        let widget = try plist("ShotmoriWidgets/ShotmoriWidgets.entitlements")
        XCTAssertEqual(widget["com.apple.security.app-sandbox"] as? Bool, true, "widget uzantısı sandbox'lı olmalı")
        XCTAssertEqual(Set(widget.keys), ["com.apple.security.app-sandbox", "com.apple.security.application-groups"], "widget'ta fazladan izin")
        // Debug dosyası sandbox dışı kalır (QA betiği konteyner dışına yazar).
        XCTAssertNil(try plist("Shotmori/Shotmori-Debug.entitlements")["com.apple.security.app-sandbox"])
    }

    func testNoOwnerDocumentRole() throws {
        let docs = try XCTUnwrap(yamlBlock("CFBundleDocumentTypes", in: try text("project.yml")))
        XCTAssertTrue(docs.contains("LSHandlerRank: Alternate"))
        XCTAssertTrue(docs.contains("CFBundleTypeRole: Viewer"))
        for banned in ["Owner", "Default", "Editor"] { XCTAssertFalse(docs.contains(banned), "belge türünde yasak değer: \(banned)") }
    }

    func testWidgetExtensionEmbeddedInApp() throws {
        let appex = try XCTUnwrap(Bundle.main.builtInPlugInsURL).appendingPathComponent("ShotmoriWidgets.appex")
        let bundle = try XCTUnwrap(Bundle(url: appex), "ShotmoriWidgets.appex gömülü değil")
        XCTAssertEqual(bundle.bundleIdentifier, "dev.shotmori.app.widgets")
        let ext = try XCTUnwrap(bundle.object(forInfoDictionaryKey: "NSExtension") as? [String: Any])
        XCTAssertEqual(ext["NSExtensionPointIdentifier"] as? String, "com.apple.widgetkit-extension")
        XCTAssertNotNil(bundle.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"), "widget gizlilik beyanı pakette yok")
        // Ana uygulama Info.plist'i dış giriş yollarını taşır.
        let schemes = (Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]])?.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        XCTAssertEqual(schemes, ["shotmori"])
        XCTAssertNotNil(Bundle.main.object(forInfoDictionaryKey: "NSServices"))
        XCTAssertNotNil(Bundle.main.object(forInfoDictionaryKey: "CFBundleDocumentTypes"))
    }

    func testWidgetSnapshotModel() throws {
        XCTAssertEqual(WidgetSnapshot.version, 1)
        XCTAssertEqual(WidgetSnapshot.fileName, "widget-snapshot.json")
        XCTAssertEqual((0..<3).map(WidgetSnapshot.thumbName), ["thumb-0.png", "thumb-1.png", "thumb-2.png"])
        let snap = WidgetSnapshot(version: WidgetSnapshot.version, totalCount: 4, newCount: 2, items: [
            .init(id: UUID(), fileName: "a.png", capturedAt: Date(timeIntervalSince1970: 1_800_000_000), thumb: WidgetSnapshot.thumbName(0)),
            .init(id: UUID(), fileName: "b.png", capturedAt: Date(timeIntervalSince1970: 1_800_000_100), thumb: nil),
        ])
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let back = try dec.decode(WidgetSnapshot.self, from: enc.encode(snap))
        XCTAssertEqual(back.totalCount, 4); XCTAssertEqual(back.newCount, 2)
        XCTAssertEqual(back.items.map(\.fileName), ["a.png", "b.png"]); XCTAssertNil(back.items[1].thumb)
        // Yalıtılmış örnek (test/QA) gerçek grup konteynerine değil kendi klasörüne yazar.
        let iso = FileManager.default.temporaryDirectory.appendingPathComponent("pc-\(UUID().uuidString)", isDirectory: true)
        XCTAssertEqual(WidgetSnapshot.containerURL(isolated: iso), iso.appendingPathComponent("WidgetGroup", isDirectory: true))
    }

    func testThirdPartyNoticesBundled() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt"), "ThirdPartyNotices.txt pakette yok")
        let body = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(body.contains("MIT License"))
        XCTAssertTrue(body.contains("Alejandro Buján"))
    }
}
