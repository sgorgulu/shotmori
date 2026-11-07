#if SHOTMORI_CLOUD // Bulut kodu SHOTMORI_CLOUD bayrağıyla derlenir (Debug ve Release 1.0'da açık, bkz. Features.swift); bayrak kaldırılırsa derlenmez.
import Foundation

/// S3 / S3 uyumlu yapılandırma; gizli anahtar Anahtar Zinciri'nde, burada yok.
struct S3Config: Codable, Equatable {
    enum Preset: String, Codable, CaseIterable { case amazon, cloudflareR2, minio, backblazeB2, other
        var title: String { switch self { case .amazon: return "Amazon S3"; case .cloudflareR2: return "Cloudflare R2"; case .minio: return "MinIO"; case .backblazeB2: return "Backblaze B2"; case .other: return S.s3PresetOther } }
        /// Yol stili varsayılanı: Amazon dışı sağlayıcılarda yol stili.
        var defaultsToPathStyle: Bool { self != .amazon }
    }
    var preset: Preset = .amazon
    var endpoint: String = ""        // boş → Amazon bölgesel uç noktası
    var region: String = "us-east-1"
    var bucket: String = ""
    var pathStyle: Bool = false
    var accessKey: String = ""
    var isComplete: Bool { !bucket.isEmpty && !accessKey.isEmpty && !region.isEmpty && (preset == .amazon || !endpoint.isEmpty) }
    /// Nesne URL'si (imzasız). Sanal-host: `https://bucket.host/key`; yol stili: `https://host/bucket/key`.
    func objectURL(key: String) -> URL? {
        let base: URL
        if endpoint.isEmpty { base = URL(string: "https://s3.\(region).amazonaws.com")! }
        else { guard let u = URL(string: endpoint.hasPrefix("http") ? endpoint : "https://\(endpoint)") else { return nil }; base = u }
        let encodedKey = S3Signer.uriEncode(key, encodeSlash: false)
        if pathStyle { return URL(string: base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/\(bucket)/\(encodedKey)") }
        guard var c = URLComponents(url: base, resolvingAgainstBaseURL: false), let host = c.host else { return nil }
        c.host = "\(bucket).\(host)"; c.percentEncodedPath = "/\(encodedKey)"
        return c.url
    }
}

final class S3Provider: CloudProvider {
    let id: CloudProviderID = .s3
    private let config: S3Config
    private let secretProvider: () -> String?
    private let session: URLSession
    var now: () -> Date = Date.init
    init(config: S3Config, secretProvider: @escaping () -> String?, session: URLSession = .shared) { self.config = config; self.secretProvider = secretProvider; self.session = session }
    var isConnected: Bool { config.isComplete && !(secretProvider() ?? "").isEmpty }

    private func creds() throws -> S3Credentials {
        guard isConnected, let secret = secretProvider() else { throw CloudError.notConnected }
        return S3Credentials(accessKey: config.accessKey, secretKey: secret, region: config.region)
    }
    private func request(_ method: String, key: String, headers: [String: String] = [:], payloadHash: String) throws -> URLRequest {
        guard let url = config.objectURL(key: key) else { throw CloudError.notConnected }
        var r = URLRequest(url: url); r.httpMethod = method
        headers.forEach { r.setValue($1, forHTTPHeaderField: $0) }
        return S3Signer.sign(r, credentials: try creds(), payloadHash: payloadHash, date: now())
    }
    /// Aynı anahtar varsa `-2`, `-3`… eki (üzerine yazılmaz).
    static func uniqueKey(_ key: String, exists: (String) async -> Bool) async -> String {
        guard await exists(key) else { return key }
        let ns = key as NSString; let ext = ns.pathExtension; let base = ext.isEmpty ? key : ns.deletingPathExtension
        var n = 2
        while n < 1000 { let k = ext.isEmpty ? "\(base)-\(n)" : "\(base)-\(n).\(ext)"; if !(await exists(k)) { return k }; n += 1 }
        return "\(base)-\(UUID().uuidString.prefix(6))" + (ext.isEmpty ? "" : ".\(ext)")
    }
    func exists(key: String) async -> Bool {
        guard let r = try? request("HEAD", key: key, payloadHash: S3Signer.unsignedPayload), let (_, http) = try? await CloudHTTP.send(r, session: session) else { return false }
        return http.statusCode == 200
    }

    func upload(file: URL, remotePath: String, access: LinkAccess, stripMetadata: Bool, progress: @escaping (Double) -> Void) async throws -> CloudObject {
        // Dosya bir kez okunur: imzadaki SHA-256 ve gönderilen gövde aynı bayttır (ekran görüntüsü boyutları için bellek yeterli).
        let data = try CloudHTTP.body(of: file, stripMetadata: stripMetadata)
        progress(0)
        let obj = try await put(data, remotePath: remotePath, mime: CloudHTTP.mimeType(for: file), access: access)
        progress(1)
        return obj
    }
    private func put(_ data: Data, remotePath: String, mime: String, access: LinkAccess) async throws -> CloudObject {
        let key = await Self.uniqueKey(remotePath) { await self.exists(key: $0) }
        var headers = ["Content-Type": mime, "Content-Length": String(data.count)]
        if access == .publicObject { headers["x-amz-acl"] = "public-read" }
        let r = try request("PUT", key: key, headers: headers, payloadHash: S3Signer.sha256Hex(data))
        let (body, http) = try await CloudHTTP.upload(r, body: data, session: session)
        if let e = CloudError.from(status: http.statusCode, body: body) { throw e }
        let etag = (http.value(forHTTPHeaderField: "ETag") ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        var obj = CloudObject(provider: .s3, remoteID: key, remotePath: key, link: nil, access: access.clamped, uploadedAt: now(), size: data.count, checksum: etag.isEmpty ? nil : etag)
        obj.link = try link(for: obj, access: access)
        return obj
    }
    private func link(for object: CloudObject, access: LinkAccess) throws -> URL {
        guard let url = config.objectURL(key: object.remoteID) else { throw CloudError.notConnected }
        switch access.clamped {
        case .presigned(let s): return S3Signer.presignedGET(url: url, credentials: try creds(), expires: s, date: now())
        default: return url
        }
    }
    /// Erişim değişimi: herkese açık ↔ imzalı. ACL güncellemesi `PUT ?acl`; imzalıya dönüşte ACL `private`.
    func setAccess(_ object: CloudObject, access: LinkAccess) async throws -> CloudObject {
        guard let base = config.objectURL(key: object.remoteID), var c = URLComponents(url: base, resolvingAgainstBaseURL: false) else { throw CloudError.notConnected }
        c.queryItems = [URLQueryItem(name: "acl", value: nil)]
        var r = URLRequest(url: c.url!); r.httpMethod = "PUT"
        r.setValue(access == .publicObject ? "public-read" : "private", forHTTPHeaderField: "x-amz-acl")
        let signed = S3Signer.sign(r, credentials: try creds(), payloadHash: S3Signer.sha256Hex(Data()), date: now())
        let (body, http) = try await CloudHTTP.send(signed, session: session)
        if let e = CloudError.from(status: http.statusCode, body: body) { throw e }
        var o = object; o.access = access.clamped; o.link = try link(for: o, access: access)
        return o
    }
    /// Boyut + tek parça PUT'un ETag'i (= gövdenin MD5'i) ↔ yerelde hesaplanan MD5. ETag MD5 biçiminde değilse
    /// (çok parçalı yükleme, SSE-KMS) doğrulanmış sayılmaz; yerel dosyaya dokunulmaz.
    func verify(_ object: CloudObject, localFile: URL) async throws -> Bool {
        let r = try request("HEAD", key: object.remoteID, payloadHash: S3Signer.unsignedPayload)
        let (body, http) = try await CloudHTTP.send(r, session: session)
        if let e = CloudError.from(status: http.statusCode, body: body) { throw e }
        let remoteSize = Int(http.value(forHTTPHeaderField: "Content-Length") ?? "") ?? -1
        guard remoteSize == CloudHTTP.fileSize(localFile) else { return false }
        let etag = (http.value(forHTTPHeaderField: "ETag") ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "\"")).lowercased()
        guard Self.isMD5Hex(etag), let local = CloudHTTP.md5Hex(of: localFile) else { return false }
        return etag == local
    }
    static func isMD5Hex(_ s: String) -> Bool { s.count == 32 && s.allSatisfy(\.isHexDigit) }
    func delete(_ object: CloudObject) async throws {
        let r = try request("DELETE", key: object.remoteID, payloadHash: S3Signer.unsignedPayload)
        let (body, http) = try await CloudHTTP.send(r, session: session)
        if http.statusCode == 404 { return }
        if let e = CloudError.from(status: http.statusCode, body: body) { throw e }
    }
    /// Küçük bir nesneyi bellekten yükleyip siler (yerel geçici dosya yok).
    func testConnection() async throws {
        let obj = try await put(Data("shotmori".utf8), remotePath: "Shotmori/.connection-test-\(UUID().uuidString.prefix(8)).txt", mime: "text/plain", access: .presigned(seconds: 60))
        try await delete(obj)
    }
}
#endif
