#if SHOTMORI_CLOUD // Bulut yalnız bulutlu (Debug) derlemede; Release test derlemesi de derlenebilsin.
import XCTest
@testable import Shotmori

final class GoogleDriveProviderTests: XCTestCase {
    var keychain: KeychainStore!; var file: URL!; var dir: URL!
    override func setUpWithError() throws {
        MockURLProtocol.reset()
        keychain = KeychainStore(service: "dev.shotmori.tests.drive.\(UUID().uuidString)")
        try keychain.set("RT", account: CloudAccount.driveRefreshToken); try keychain.set("AT", account: CloudAccount.driveAccessToken); try keychain.set(String(Int(Date().timeIntervalSince1970) + 3600), account: CloudAccount.driveAccessExpiry)
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("gd-\(UUID())", isDirectory: true); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        file = dir.appendingPathComponent("Örnek kod 11.44.png"); try Data(repeating: 1, count: 500).write(to: file)
    }
    override func tearDownWithError() throws { [CloudAccount.driveRefreshToken, CloudAccount.driveAccessToken, CloudAccount.driveAccessExpiry].forEach { keychain.delete($0) }; try? FileManager.default.removeItem(at: dir); MockURLProtocol.reset() }
    private func provider() -> GoogleDriveProvider { GoogleDriveProvider(oauth: GoogleOAuth(clientID: "cid", clientSecret: nil, keychain: keychain, session: MockURLProtocol.session(), openURL: { _ in }), session: MockURLProtocol.session()) }
    private func js(_ s: String) -> Data { Data(s.utf8) }

    /// Tam akış: klasör ara (yok) → oluştur → alt klasör ara (var) → oturum → PUT → files.get → permissions.create
    func testUploadFlowCreatesFoldersUploadsAndSharesWhenAnyone() async throws {
        MockURLProtocol.handler = { req, body in
            let u = req.url!.absoluteString; let m = req.httpMethod ?? ""
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer AT")
            if m == "GET", u.contains("/drive/v3/files?"), u.contains("Shotmori'") , !u.contains("2026-10") { return (200, [:], self.js(#"{"files":[]}"#)) }
            if m == "POST", u.hasSuffix("/drive/v3/files") { return (200, [:], self.js(#"{"id":"folderA"}"#)) }
            if m == "GET", u.contains("2026-10") { return (200, [:], self.js(#"{"files":[{"id":"folderB"}]}"#)) }
            if m == "POST", u.contains("uploadType=resumable") { return (200, ["Location": "https://upload.example/session1"], Data()) }
            if m == "PUT", u.contains("session1") { return (200, [:], self.js(#"{"id":"file1"}"#)) }
            if m == "GET", u.contains("/files/file1?") { return (200, [:], self.js(#"{"id":"file1","size":"500","md5Checksum":"m5","webViewLink":"https://drive.google.com/file/d/file1/view"}"#)) }
            if m == "POST", u.contains("/files/file1/permissions") { return (200, [:], self.js(#"{"id":"anyone"}"#)) }
            return (500, [:], Data("beklenmeyen \(m) \(u)".utf8))
        }
        let obj = try await provider().upload(file: file, remotePath: "Shotmori/2026-10/Örnek kod 11.44.png", access: .anyoneWithLink, stripMetadata: false, progress: { _ in })
        XCTAssertEqual(obj.remoteID, "file1"); XCTAssertEqual(obj.size, 500); XCTAssertEqual(obj.checksum, "m5"); XCTAssertEqual(obj.access, .anyoneWithLink)
        XCTAssertEqual(obj.link?.absoluteString, "https://drive.google.com/file/d/file1/view")
        let reqs = MockURLProtocol.requests
        let folderQuery = try XCTUnwrap(reqs.first { $0.0.url!.absoluteString.contains("mimeType") }).0.url!
        let q = URLComponents(url: folderQuery, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "q" }!.value!
        XCTAssertTrue(q.contains("name = 'Shotmori' and mimeType = 'application/vnd.google-apps.folder' and 'root' in parents and trashed = false"), q)
        let create = try XCTUnwrap(reqs.first { $0.0.httpMethod == "POST" && $0.0.url!.absoluteString.hasSuffix("/drive/v3/files") })
        let meta = try JSONSerialization.jsonObject(with: create.1!) as! [String: Any]; XCTAssertEqual(meta["name"] as? String, "Shotmori"); XCTAssertEqual(meta["parents"] as? [String], ["root"])
        let start = try XCTUnwrap(reqs.first { $0.0.url!.absoluteString.contains("uploadType=resumable") })
        let sm = try JSONSerialization.jsonObject(with: start.1!) as! [String: Any]; XCTAssertEqual(sm["name"] as? String, "Örnek kod 11.44.png"); XCTAssertEqual(sm["parents"] as? [String], ["folderB"])
        let perm = try XCTUnwrap(reqs.first { $0.0.url!.absoluteString.contains("/permissions") })
        XCTAssertEqual(try JSONSerialization.jsonObject(with: perm.1!) as? [String: String], ["role": "reader", "type": "anyone"])
    }
    func testOwnerOnlyUploadDoesNotCreatePermission() async throws {
        MockURLProtocol.handler = { req, _ in
            let u = req.url!.absoluteString; let m = req.httpMethod ?? ""
            if m == "GET", u.contains("mimeType") { return (200, [:], self.js(#"{"files":[{"id":"f"}]}"#)) }
            if m == "POST", u.contains("uploadType=resumable") { return (200, ["Location": "https://upload.example/s"], Data()) }
            if m == "PUT" { return (200, [:], self.js(#"{"id":"file2"}"#)) }
            if m == "GET", u.contains("/files/file2?") { return (200, [:], self.js(#"{"id":"file2","size":"500","webViewLink":"https://drive.google.com/file/d/file2/view"}"#)) }
            if m == "GET", u.contains("/files/file2/permissions") { return (200, [:], self.js(#"{"permissions":[{"id":"owner1","type":"user"}]}"#)) }
            return (500, [:], Data())
        }
        let obj = try await provider().upload(file: file, remotePath: "Shotmori/a.png", access: .ownerOnly, stripMetadata: false, progress: { _ in })
        XCTAssertEqual(obj.access, .ownerOnly); XCTAssertFalse(MockURLProtocol.requests.contains { $0.0.httpMethod == "POST" && $0.0.url!.absoluteString.contains("/permissions") })
    }
    func testUnauthorizedRefreshesOnceThenRetries() async throws {
        var calls = 0
        MockURLProtocol.handler = { req, _ in
            let u = req.url!.absoluteString
            if u == GoogleOAuth.tokenEndpoint.absoluteString { return (200, [:], self.js(#"{"access_token":"AT2","expires_in":3600}"#)) }
            calls += 1
            if req.value(forHTTPHeaderField: "Authorization") == "Bearer AT" { return (401, [:], Data()) }
            return (200, [:], self.js(#"{"user":{"emailAddress":"x"}}"#))
        }
        try await provider().testConnection()
        XCTAssertEqual(calls, 2); XCTAssertEqual(keychain.get(CloudAccount.driveAccessToken), "AT2")
    }
    /// SEC-07 + COR-23: sunucu MD5'i yerelde hesaplanan MD5 ile karşılaştırılır; Çöp'teki kopya doğrulanmış sayılmaz.
    func testVerifyComparesServerMD5WithLocalMD5AndRejectsTrashed() async throws {
        let local = try XCTUnwrap(CloudHTTP.md5Hex(of: file)); XCTAssertEqual(local.count, 32)
        // Yükleme anındaki sunucu değeri (`checksum`) yerelle aynı olmasa da karar yerel içeriğe göre verilir.
        let obj = CloudObject(provider: .googleDrive, remoteID: "f1", remotePath: "a", link: nil, access: .ownerOnly, uploadedAt: Date(), size: 500, checksum: "stale")
        MockURLProtocol.handler = { _, _ in (200, [:], self.js("{\"size\":\"500\",\"md5Checksum\":\"\(local)\"}")) }
        let ok = try await provider().verify(obj, localFile: file); XCTAssertTrue(ok)
        MockURLProtocol.handler = { _, _ in (200, [:], self.js(#"{"size":"500","md5Checksum":"m5"}"#)) }
        let bad = try await provider().verify(obj, localFile: file); XCTAssertFalse(bad, "sunucu ↔ sunucu eşleşmesi yetmez")
        MockURLProtocol.handler = { _, _ in (200, [:], self.js(#"{"size":"500"}"#)) }
        let noSum = try await provider().verify(obj, localFile: file); XCTAssertFalse(noSum, "sağlama yoksa doğrulanmış sayılmaz")
        MockURLProtocol.handler = { _, _ in (200, [:], self.js("{\"size\":\"500\",\"md5Checksum\":\"\(local)\",\"trashed\":true}")) }
        let trashed = try await provider().verify(obj, localFile: file); XCTAssertFalse(trashed, "Çöp'teki kopya")
    }
    /// COR-23: önbellekteki klasör silinmişse (oturum başlatma 404) önbellek temizlenir, klasör yeniden çözülüp yükleme sürer.
    func testStaleFolderCacheIsInvalidatedOn404() async throws {
        var sessions = 0, folderLookups = 0
        MockURLProtocol.handler = { req, _ in
            let u = req.url!.absoluteString; let m = req.httpMethod ?? ""
            if m == "GET", u.contains("mimeType") { folderLookups += 1; return (200, [:], self.js(folderLookups == 1 ? #"{"files":[{"id":"gone"}]}"# : #"{"files":[{"id":"fresh"}]}"#)) }
            if m == "POST", u.contains("uploadType=resumable") { sessions += 1; return sessions == 1 ? (404, [:], self.js(#"{"error":{"errors":[{"reason":"notFound"}]}}"#)) : (200, ["Location": "https://upload.example/s"], Data()) }
            if m == "PUT" { return (200, [:], self.js(#"{"id":"file3"}"#)) }
            if m == "GET", u.contains("/files/file3?") { return (200, [:], self.js(#"{"id":"file3","size":"500"}"#)) }
            if m == "GET", u.contains("/permissions") { return (200, [:], self.js(#"{"permissions":[]}"#)) }
            return (500, [:], Data())
        }
        let p = provider()
        _ = try await p.ensureFolder(path: "Shotmori") // önbelleğe "gone"
        let obj = try await p.upload(file: file, remotePath: "Shotmori/a.png", access: .ownerOnly, stripMetadata: false, progress: { _ in })
        XCTAssertEqual(obj.remoteID, "file3"); XCTAssertEqual(sessions, 2); XCTAssertEqual(folderLookups, 2)
        let start = try XCTUnwrap(MockURLProtocol.requests.last { $0.0.url!.absoluteString.contains("uploadType=resumable") })
        XCTAssertEqual((try JSONSerialization.jsonObject(with: start.1!) as? [String: Any])?["parents"] as? [String], ["fresh"])
    }
    /// SEC-02: buluttan silme Drive'da Çöp'e taşır (kalıcı DELETE yok); 404 hata değil.
    func testDeleteMovesToDriveTrash() async throws {
        MockURLProtocol.handler = { _, _ in (200, [:], self.js(#"{"id":"f1","trashed":true}"#)) }
        let obj = CloudObject(provider: .googleDrive, remoteID: "f1", remotePath: "a", link: nil, access: .ownerOnly, uploadedAt: Date(), size: 1, checksum: nil)
        try await provider().delete(obj)
        let req = try XCTUnwrap(MockURLProtocol.requests.first)
        XCTAssertEqual(req.0.httpMethod, "PATCH"); XCTAssertTrue(req.0.url!.absoluteString.hasSuffix("/files/f1"))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: req.1!) as? [String: Bool], ["trashed": true])
        XCTAssertFalse(MockURLProtocol.requests.contains { $0.0.httpMethod == "DELETE" })
        MockURLProtocol.reset(); MockURLProtocol.handler = { _, _ in (404, [:], Data()) }
        try await provider().delete(obj)
    }
    /// EFF-29: linki gizliye çevirme "anyone" izinlerini siler; zaten silinmiş izin (404) hata değildir.
    func testMakingPrivateDeletesAnyonePermissionsTolerating404() async throws {
        MockURLProtocol.handler = { req, _ in
            let u = req.url!.absoluteString; let m = req.httpMethod ?? ""
            if m == "GET", u.contains("/permissions?") { return (200, [:], self.js(#"{"permissions":[{"id":"owner1","type":"user"},{"id":"anyoneWithLink","type":"anyone"},{"id":"anyone2","type":"anyone"}]}"#)) }
            if m == "DELETE", u.hasSuffix("/permissions/anyoneWithLink") { return (204, [:], Data()) }
            if m == "DELETE", u.hasSuffix("/permissions/anyone2") { return (404, [:], Data()) }
            if m == "GET", u.contains("/files/f1?") { return (200, [:], self.js(#"{"id":"f1","webViewLink":"https://drive.google.com/file/d/f1/view"}"#)) }
            return (500, [:], Data())
        }
        let obj = CloudObject(provider: .googleDrive, remoteID: "f1", remotePath: "a", link: nil, access: .anyoneWithLink, uploadedAt: Date(), size: 1, checksum: nil)
        let updated = try await provider().setAccess(obj, access: .ownerOnly)
        XCTAssertEqual(updated.access, .ownerOnly); XCTAssertEqual(updated.link?.absoluteString, "https://drive.google.com/file/d/f1/view")
        let deletes = MockURLProtocol.requests.filter { $0.0.httpMethod == "DELETE" }.map { $0.0.url!.lastPathComponent }
        XCTAssertEqual(deletes, ["anyoneWithLink", "anyone2"], "kullanıcı (sahip) izni silinmez")
    }
}
#endif
