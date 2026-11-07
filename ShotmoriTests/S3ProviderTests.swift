#if SHOTMORI_CLOUD // Bulut yalnız bulutlu (Debug) derlemede; Release test derlemesi de derlenebilsin.
import XCTest
@testable import Shotmori

final class S3ProviderTests: XCTestCase {
    var dir: URL!; var file: URL!
    override func setUpWithError() throws {
        MockURLProtocol.reset()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("s3p-\(UUID())", isDirectory: true); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        file = dir.appendingPathComponent("Ekran Görüntüsü 1.png"); try Data(repeating: 7, count: 1234).write(to: file)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir); MockURLProtocol.reset() }
    private func provider(_ cfg: S3Config) -> S3Provider { S3Provider(config: cfg, secretProvider: { "SECRET" }, session: MockURLProtocol.session()) }
    private var amazon: S3Config { S3Config(preset: .amazon, endpoint: "", region: "eu-central-1", bucket: "my-bucket", pathStyle: false, accessKey: "AK") }
    private var r2: S3Config { S3Config(preset: .cloudflareR2, endpoint: "https://abc.r2.cloudflarestorage.com", region: "auto", bucket: "shots", pathStyle: true, accessKey: "AK") }

    func testObjectURLStylesAndEncoding() {
        XCTAssertEqual(amazon.objectURL(key: "Shotmori/2026-10/Ekran Görüntüsü 1.png")?.absoluteString, "https://my-bucket.s3.eu-central-1.amazonaws.com/Shotmori/2026-10/Ekran%20G%C3%B6r%C3%BCnt%C3%BCs%C3%BC%201.png")
        XCTAssertEqual(r2.objectURL(key: "a/b#1.png")?.absoluteString, "https://abc.r2.cloudflarestorage.com/shots/a/b%231.png")
    }
    func testUploadPutsWithACLOnlyWhenPublicAndReturnsLink() async throws {
        MockURLProtocol.handler = { req, _ in
            if req.httpMethod == "HEAD" { return (404, [:], Data()) }
            return (200, ["ETag": "\"abc123\""], Data())
        }
        let obj = try await provider(amazon).upload(file: file, remotePath: "Shotmori/2026-10/Ekran Görüntüsü 1.png", access: .publicObject, stripMetadata: false, progress: { _ in })
        let put = try XCTUnwrap(MockURLProtocol.requests.first { $0.0.httpMethod == "PUT" }).0
        XCTAssertEqual(put.url?.absoluteString, "https://my-bucket.s3.eu-central-1.amazonaws.com/Shotmori/2026-10/Ekran%20G%C3%B6r%C3%BCnt%C3%BCs%C3%BC%201.png")
        XCTAssertEqual(put.value(forHTTPHeaderField: "x-amz-acl"), "public-read"); XCTAssertEqual(put.value(forHTTPHeaderField: "Content-Type"), "image/png")
        XCTAssertTrue(put.value(forHTTPHeaderField: "Authorization")?.contains("x-amz-acl") == true)
        XCTAssertEqual(obj.checksum, "abc123"); XCTAssertEqual(obj.size, 1234); XCTAssertEqual(obj.link?.absoluteString, put.url?.absoluteString)
        MockURLProtocol.reset(); MockURLProtocol.handler = { req, _ in req.httpMethod == "HEAD" ? (404, [:], Data()) : (200, [:], Data()) }
        let signed = try await provider(amazon).upload(file: file, remotePath: "k.png", access: .presigned(seconds: 3600), stripMetadata: false, progress: { _ in })
        let put2 = try XCTUnwrap(MockURLProtocol.requests.first { $0.0.httpMethod == "PUT" }).0
        XCTAssertNil(put2.value(forHTTPHeaderField: "x-amz-acl")); XCTAssertTrue(signed.link!.absoluteString.contains("X-Amz-Expires=3600"))
    }
    func testUniqueKeyAvoidsOverwrite() async throws {
        var existing: Set<String> = ["Shotmori/a.png", "Shotmori/a-2.png"]
        let k = await S3Provider.uniqueKey("Shotmori/a.png") { existing.contains($0) }
        XCTAssertEqual(k, "Shotmori/a-3.png"); existing.insert(k)
        let free = await S3Provider.uniqueKey("Shotmori/b.png") { existing.contains($0) }; XCTAssertEqual(free, "Shotmori/b.png")
    }
    /// SEC-07: tek parça PUT'un ETag'i yerelde hesaplanan MD5 ile karşılaştırılır; MD5 biçiminde olmayan ETag doğrulanmış sayılmaz.
    func testVerifyComparesSizeAndETagWithLocalMD5() async throws {
        let local = try XCTUnwrap(CloudHTTP.md5Hex(of: file))
        let obj = CloudObject(provider: .s3, remoteID: "k.png", remotePath: "k.png", link: nil, access: .publicObject, uploadedAt: Date(), size: 1234, checksum: "abc")
        MockURLProtocol.handler = { _, _ in (200, ["Content-Length": "1234", "ETag": "\"\(local)\""], Data()) }
        let ok = try await provider(amazon).verify(obj, localFile: file); XCTAssertTrue(ok)
        MockURLProtocol.handler = { _, _ in (200, ["Content-Length": "999", "ETag": "\"\(local)\""], Data()) }
        let sizeMismatch = try await provider(amazon).verify(obj, localFile: file); XCTAssertFalse(sizeMismatch)
        MockURLProtocol.handler = { _, _ in (200, ["Content-Length": "1234", "ETag": "\"abc\""], Data()) }
        let serverOnly = try await provider(amazon).verify(obj, localFile: file); XCTAssertFalse(serverOnly, "sunucu ↔ sunucu eşleşmesi yetmez")
        MockURLProtocol.handler = { _, _ in (200, ["Content-Length": "1234", "ETag": "\"\(local)-2\""], Data()) }
        let multipart = try await provider(amazon).verify(obj, localFile: file); XCTAssertFalse(multipart, "çok parçalı ETag")
        XCTAssertTrue(S3Provider.isMD5Hex(local)); XCTAssertFalse(S3Provider.isMD5Hex("abc"))
    }
    /// EFF-29: erişim değişimi `PUT ?acl` ile; `x-amz-acl` imzalı başlıklarda.
    func testSetAccessPutsACLAndSignsHeader() async throws {
        MockURLProtocol.handler = { _, _ in (200, [:], Data()) }
        let obj = CloudObject(provider: .s3, remoteID: "k.png", remotePath: "k.png", link: nil, access: .publicObject, uploadedAt: Date(), size: 1, checksum: nil)
        let priv = try await provider(amazon).setAccess(obj, access: .presigned(seconds: 3600))
        let req = try XCTUnwrap(MockURLProtocol.requests.first).0
        XCTAssertEqual(req.httpMethod, "PUT"); XCTAssertEqual(req.url?.query, "acl")
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-amz-acl"), "private")
        XCTAssertTrue(req.value(forHTTPHeaderField: "Authorization")?.contains("x-amz-acl") == true)
        XCTAssertEqual(priv.access, .presigned(seconds: 3600)); XCTAssertTrue(priv.link!.absoluteString.contains("X-Amz-Expires=3600"))
        MockURLProtocol.reset(); MockURLProtocol.handler = { _, _ in (200, [:], Data()) }
        let pub = try await provider(amazon).setAccess(obj, access: .publicObject)
        XCTAssertEqual(MockURLProtocol.requests.first?.0.value(forHTTPHeaderField: "x-amz-acl"), "public-read"); XCTAssertNil(pub.link?.query)
    }
    /// SEC-05: paylaşım yüklemesi PNG'nin üst veri chunk'larını göndermez; yedek orijinal baytları gönderir.
    func testShareUploadStripsPNGMetadata() async throws {
        let png = try PNGFixture.withTextChunk(); let u = dir.appendingPathComponent("meta.png"); try png.write(to: u)
        MockURLProtocol.handler = { req, _ in req.httpMethod == "HEAD" ? (404, [:], Data()) : (200, [:], Data()) }
        _ = try await provider(amazon).upload(file: u, remotePath: "m.png", access: .presigned(seconds: 60), stripMetadata: true, progress: { _ in })
        let sent = try XCTUnwrap(MockURLProtocol.requests.first { $0.0.httpMethod == "PUT" }?.1)
        XCTAssertFalse(PNGChunkFilter.chunkTypes(sent).contains("tEXt")); XCTAssertTrue(PNGChunkFilter.chunkTypes(png).contains("tEXt"))
        MockURLProtocol.reset(); MockURLProtocol.handler = { req, _ in req.httpMethod == "HEAD" ? (404, [:], Data()) : (200, [:], Data()) }
        _ = try await provider(amazon).upload(file: u, remotePath: "m.png", access: .presigned(seconds: 60), stripMetadata: false, progress: { _ in })
        XCTAssertEqual(MockURLProtocol.requests.first { $0.0.httpMethod == "PUT" }?.1, png, "yedek: orijinal bayt")
    }
    func testErrorsMapToCloudError() async {
        MockURLProtocol.handler = { req, _ in req.httpMethod == "HEAD" ? (404, [:], Data()) : (403, [:], Data("<Error>AccessDenied</Error>".utf8)) }
        do { _ = try await provider(amazon).upload(file: file, remotePath: "k.png", access: .publicObject, stripMetadata: false, progress: { _ in }); XCTFail("hata beklenirdi") }
        catch { XCTAssertEqual(error as? CloudError, .forbidden) }
        XCTAssertFalse(S3Provider(config: amazon, secretProvider: { nil }, session: MockURLProtocol.session()).isConnected)
    }
    func testDeleteTreats404AsSuccess() async throws {
        MockURLProtocol.handler = { _, _ in (404, [:], Data()) }
        try await provider(r2).delete(CloudObject(provider: .s3, remoteID: "gone.png", remotePath: "gone.png", link: nil, access: .publicObject, uploadedAt: Date(), size: 1, checksum: nil))
        XCTAssertEqual(MockURLProtocol.requests.first?.0.httpMethod, "DELETE"); XCTAssertEqual(MockURLProtocol.requests.first?.0.url?.path, "/shots/gone.png")
    }
}
#endif
