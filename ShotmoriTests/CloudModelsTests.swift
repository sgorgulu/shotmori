import XCTest
@testable import Shotmori

final class CloudModelsTests: XCTestCase {
    private var oct19: Date { var c = DateComponents(); c.year = 2026; c.month = 10; c.day = 19; c.hour = 11; return Calendar(identifier: .gregorian).date(from: c)! }

    func testPathTemplateTokens() {
        let cal = Calendar(identifier: .gregorian)
        XCTAssertEqual(PathTemplate.render("Shotmori/{yyyy}-{MM}/{name}.{ext}", fileName: "Ekran Görüntüsü 11.42.png", date: oct19, calendar: cal), "Shotmori/2026-10/Ekran Görüntüsü 11.42.png")
        XCTAssertEqual(PathTemplate.render("{yyyy}/{MM}/{dd}/{name}", fileName: "a.png", date: oct19, calendar: cal), "2026/10/19/a")
        XCTAssertEqual(PathTemplate.render(PathTemplate.default, fileName: "uzantisiz", date: oct19, calendar: cal), "Shotmori/2026-10/uzantisiz")
    }
    func testPathTemplateSanitizesDotDotAndEmptySegments() {
        let cal = Calendar(identifier: .gregorian)
        XCTAssertEqual(PathTemplate.render("//Shotmori/../{name}.{ext}//", fileName: "x.png", date: oct19, calendar: cal), "Shotmori/x.png")
        XCTAssertEqual(PathTemplate.render("", fileName: "x.png", date: oct19, calendar: cal), "x.png")
    }
    func testLinkFormats() {
        let u = URL(string: "https://example.com/a.png")!
        XCTAssertEqual(LinkFormat.url.render(u, name: "a.png"), "https://example.com/a.png")
        XCTAssertEqual(LinkFormat.markdown.render(u, name: "a.png"), "![a.png](https://example.com/a.png)")
        XCTAssertEqual(LinkFormat.html.render(u, name: "a \"b\".png"), "<img src=\"https://example.com/a.png\" alt=\"a &quot;b&quot;.png\">")
    }
    func testPresignedSecondsClampedTo7Days() {
        XCTAssertEqual(LinkAccess.presigned(seconds: 999_999).clamped, .presigned(seconds: 604_800))
        XCTAssertEqual(LinkAccess.presigned(seconds: 0).clamped, .presigned(seconds: 1))    }
    func testShelfItemDecodesLegacyJSONWithoutCloudFields() throws {
        let legacy = """
        {"id":"7B6D5D7E-6E3C-4B1A-9C1E-1F2A3B4C5D6E","path":"/tmp/x.png","capturedAt":"2026-10-18T08:48:00Z","addedAt":"2026-10-18T08:48:00Z","source":"screenshot","startsGroup":false}
        """
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let item = try dec.decode(ShelfItem.self, from: Data(legacy.utf8))
        XCTAssertEqual(item.cloud, []); XCTAssertFalse(item.localTrashed)
        // yeni alanlar gidiş-dönüş
        var withCloud = item; withCloud.cloud = [CloudObject(provider: .s3, remoteID: "k.png", remotePath: "Shotmori/k.png", link: URL(string: "https://b.s3.amazonaws.com/k.png"), access: .publicObject, uploadedAt: Date(timeIntervalSince1970: 1_700_000_000), size: 12, checksum: "abc")]; withCloud.localTrashed = true
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let back = try dec.decode(ShelfItem.self, from: try enc.encode(withCloud))
        XCTAssertEqual(back.cloud, withCloud.cloud); XCTAssertTrue(back.localTrashed)
    }

    #if SHOTMORI_CLOUD // Anahtar Zinciri, bulut hataları, gömülü istemci ve CloudCenter yalnız bulutlu derlemede.
    func testKeychainStoreRoundTrip() throws {
        let k = KeychainStore(service: "dev.shotmori.tests.keychain.\(UUID().uuidString)")
        XCTAssertNil(k.get("a"))
        try k.set("gizli-1", account: "a"); XCTAssertEqual(k.get("a"), "gizli-1")
        try k.set("gizli-2", account: "a"); XCTAssertEqual(k.get("a"), "gizli-2", "üzerine yazılır")
        k.delete("a"); XCTAssertNil(k.get("a"))
    }

    /// Günlük özeti: durum adı + HTTP kodu; ilişkili metin (URL, gövde) yok.
    func testCloudErrorLogSummaryHasCaseAndStatusOnly() {
        XCTAssertEqual(CloudError.server(503, "x/secret").logSummary, "server 503")
        XCTAssertEqual(CloudError.network("https://a").logSummary, "network")
        XCTAssertEqual(CloudError.unauthorized.logSummary, "unauthorized")
        XCTAssertFalse(CloudError.network("https://a/b.png").logSummary.contains("https"))
    }

    /// L10N-06/07: ham yanıt gövdesi gösterilmez; bilinen sunucu kodları yerelleştirilmiş metne, diğerleri yalnız HTTP koduna.
    func testCloudErrorMessagesAreLocalizedAndNeverShowRawBody() {
        let xml = Data("<?xml version=\"1.0\"?><Error><Code>NoSuchBucket</Code><Message>The bucket does not exist</Message><BucketName>gizli-kova</BucketName></Error>".utf8)
        let noBucket = CloudError.from(status: 404, body: xml)
        XCTAssertEqual(noBucket, .server(404, "NoSuchBucket")); XCTAssertEqual(noBucket?.errorDescription, S.cloudErrBucketNotFound)
        XCTAssertEqual(CloudError.from(status: 403, body: Data("<Error><Code>SignatureDoesNotMatch</Code></Error>".utf8))?.errorDescription, S.cloudErrBadCredentials)
        XCTAssertEqual(CloudError.from(status: 403, body: Data(#"{"error":{"errors":[{"reason":"storageQuotaExceeded"}],"message":"x"}}"#.utf8))?.errorDescription, S.cloudErrQuotaExceeded)
        XCTAssertEqual(CloudError.from(status: 429, body: nil)?.errorDescription, S.cloudErrRateLimited)
        XCTAssertEqual(CloudError.from(status: 403, body: Data("<Error>AccessDenied</Error>".utf8)), .forbidden)
        XCTAssertEqual(CloudError.from(status: 404, body: Data(#"{"error":{"errors":[{"reason":"notFound"}]}}"#.utf8)), .notFound)
        let raw = CloudError.from(status: 500, body: Data("<Error><Code>InternalError</Code><Message>gizli ayrıntı</Message></Error>".utf8))
        XCTAssertEqual(raw?.errorDescription, S.cloudErrServerCode(500)); XCTAssertFalse(raw?.errorDescription?.contains("gizli") ?? true)
        XCTAssertNil(CloudError.serviceCode(in: Data("<Code>a b<script></Code>".utf8)), "yalnız harf/rakam/alt çizgi")
        XCTAssertNil(CloudError.from(status: 204, body: nil))
        XCTAssertEqual(CloudError.cancelled.errorDescription, S.cloudErrCancelled); XCTAssertNotEqual(S.cloudErrCancelled, S.cancel)
        XCTAssertEqual(CloudError.invalidResponse.errorDescription, S.cloudErrInvalidResponse)
        XCTAssertEqual(KeychainStore.Failure.status(-25300).errorDescription, S.cloudErrKeychain(-25300))
    }

    // MARK: Gömülü Google istemcisi
    func testEffectiveDriveClientPrefersCustomThenEmbedded() {
        let emb: (id: String, secret: String?) = ("embedded-id", "embedded-secret")
        let custom = CloudDefaults.effectiveDriveClient(customID: " my-id ", customSecret: "s", embedded: emb)
        XCTAssertEqual(custom?.id, "my-id"); XCTAssertEqual(custom?.secret, "s")
        let fallback = CloudDefaults.effectiveDriveClient(customID: "", customSecret: nil, embedded: emb)
        XCTAssertEqual(fallback?.id, "embedded-id"); XCTAssertEqual(fallback?.secret, "embedded-secret")
        XCTAssertNil(CloudDefaults.effectiveDriveClient(customID: "  ", customSecret: nil, embedded: ("", nil)), "ne özel ne gömülü → giriş yok")
        XCTAssertEqual(CloudDefaults.hasEmbeddedGoogleClient, !CloudDefaults.googleClientID.isEmpty)
    }

    /// Bulut kapalı (Release 1.0): sağlayıcı kurulmaz (Anahtar Zinciri okunmaz), göçle gelen kayıtlar rozet göstermez.
    func testDisabledCloudCenterHasNoBadgesAndNoProviders() {
        let suite = "dev.shotmori.tests.cloudoff.\(UUID().uuidString)"; let d = UserDefaults(suiteName: suite)!; defer { d.removePersistentDomain(forName: suite) }
        let prefs = Preferences(defaults: d); prefs.s3Config = S3Config()
        let store = ShelfStore(fileURL: nil, maxItems: 5)
        var item = ShelfItem(path: "/tmp/a.png", fileID: nil, capturedAt: Date())
        item.cloud = [CloudObject(provider: .s3, remoteID: "k", remotePath: "k", link: nil, access: .publicObject, uploadedAt: Date(), size: 1, checksum: nil)]
        let c = CloudCenter(prefs: prefs, store: store, dataDir: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), enabled: false)
        XCTAssertNil(c.provider(.s3))
        XCTAssertNil(c.badge(for: item))
    }
    #endif
}
