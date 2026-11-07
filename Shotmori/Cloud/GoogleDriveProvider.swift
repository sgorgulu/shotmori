#if SHOTMORI_CLOUD // Bulut kodu SHOTMORI_CLOUD bayrağıyla derlenir (Debug ve Release 1.0'da açık, bkz. Features.swift); bayrak kaldırılırsa derlenmez.
import Foundation

/// Google Drive (drive.file kapsamı): klasör çöz/oluştur, kesintiye dayanıklı yükleme, izin yönetimi, doğrulama, Çöp'e taşıma.
/// 401'de belirteç bir kez yenilenir ve istek tekrarlanır; yine 401 ise `.unauthorized` (kullanıcı yeniden giriş yapar).
final class GoogleDriveProvider: CloudProvider {
    let id: CloudProviderID = .googleDrive
    static let api = URL(string: "https://www.googleapis.com/drive/v3")!
    static let uploadAPI = URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable")!
    static let folderMime = "application/vnd.google-apps.folder"
    private let oauth: GoogleOAuth
    private let session: URLSession
    private var folderCache: [String: String] = [:]   // yol → folderId
    var now: () -> Date = Date.init
    init(oauth: GoogleOAuth, session: URLSession = .shared) { self.oauth = oauth; self.session = session }
    var isConnected: Bool { oauth.isSignedIn }

    // MARK: HTTP
    private func authed(_ r: URLRequest, retry: Bool = true) async throws -> (Data, HTTPURLResponse) {
        var req = r; req.setValue("Bearer \(try await oauth.validAccessToken())", forHTTPHeaderField: "Authorization")
        let (data, http) = try await CloudHTTP.send(req, session: session)
        if http.statusCode == 401, retry {
            var again = r; again.setValue("Bearer \(try await oauth.validAccessToken(forceRefresh: true))", forHTTPHeaderField: "Authorization")
            return try await CloudHTTP.send(again, session: session)
        }
        return (data, http)
    }
    private func json(_ data: Data) -> [String: Any] { (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:] }
    private func check(_ http: HTTPURLResponse, _ data: Data) throws { if let e = CloudError.from(status: http.statusCode, body: data) { throw e } }
    private static func q(_ s: String) -> String { s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'") }

    /// `Shotmori/2026-10` gibi bir yolun klasör kimliği; parça parça aranır, yoksa oluşturulur. Önbelleklenir.
    func ensureFolder(path: String) async throws -> String {
        let parts = path.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        var parent = "root", built = ""
        for name in parts {
            built += (built.isEmpty ? "" : "/") + name
            if let cached = folderCache[built] { parent = cached; continue }
            var c = URLComponents(url: Self.api.appendingPathComponent("files"), resolvingAgainstBaseURL: false)!
            c.queryItems = [URLQueryItem(name: "q", value: "name = '\(Self.q(name))' and mimeType = '\(Self.folderMime)' and '\(parent)' in parents and trashed = false"), URLQueryItem(name: "fields", value: "files(id)"), URLQueryItem(name: "pageSize", value: "1")]
            let (data, http) = try await authed(URLRequest(url: c.url!)); try check(http, data)
            if let id = ((json(data)["files"] as? [[String: Any]])?.first?["id"] as? String) { folderCache[built] = id; parent = id; continue }
            var r = URLRequest(url: Self.api.appendingPathComponent("files")); r.httpMethod = "POST"; r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try JSONSerialization.data(withJSONObject: ["name": name, "mimeType": Self.folderMime, "parents": [parent]])
            let (d2, h2) = try await authed(r); try check(h2, d2)
            guard let id = json(d2)["id"] as? String else { throw CloudError.invalidResponse }
            folderCache[built] = id; parent = id
        }
        return parent
    }

    func upload(file: URL, remotePath: String, access: LinkAccess, stripMetadata: Bool, progress: @escaping (Double) -> Void) async throws -> CloudObject {
        let ns = remotePath as NSString
        let name = ns.lastPathComponent
        let body = try CloudHTTP.body(of: file, stripMetadata: stripMetadata)
        let mime = CloudHTTP.mimeType(for: file)
        progress(0)
        var (fileID, info) = try await put(body, name: name, folderPath: ns.deletingLastPathComponent, mime: mime)
        // Önbellekteki klasör bu arada Çöp'e atılmışsa dosya da Çöp'te görünür: önbellek temizlenir, klasör yeniden çözülüp bir kez daha yüklenir.
        if (info["trashed"] as? Bool) == true {
            folderCache.removeAll()
            (fileID, info) = try await put(body, name: name, folderPath: ns.deletingLastPathComponent, mime: mime)
        }
        progress(0.9)
        var obj = CloudObject(provider: .googleDrive, remoteID: fileID, remotePath: remotePath, link: nil, access: .ownerOnly, uploadedAt: now(), size: Int(info["size"] as? String ?? "") ?? body.count, checksum: info["md5Checksum"] as? String)
        obj = try await setAccess(obj, access: access, knownInfo: info)
        progress(1)
        return obj
    }
    /// Oturum başlat → gövdeyi tek PUT ile gönder (ekran görüntüsü boyutları için yeterli) → ayrıntıları al (size, md5, trashed, webViewLink).
    /// Oturum başlatma 404 verirse (önbellekteki klasör silinmiş) önbellek temizlenir ve klasör bir kez yeniden çözülür.
    private func put(_ body: Data, name: String, folderPath: String, mime: String) async throws -> (String, [String: Any]) {
        let sessionURL: URL
        do { sessionURL = try await startSession(name: name, folderPath: folderPath, mime: mime, length: body.count) }
        catch CloudError.notFound {
            folderCache.removeAll()
            sessionURL = try await startSession(name: name, folderPath: folderPath, mime: mime, length: body.count)
        }
        var put = URLRequest(url: sessionURL); put.httpMethod = "PUT"; put.setValue(mime, forHTTPHeaderField: "Content-Type")
        put.setValue("Bearer \(try await oauth.validAccessToken())", forHTTPHeaderField: "Authorization")
        let (d1, h1) = try await CloudHTTP.upload(put, body: body, session: session); try check(h1, d1)
        guard let fileID = json(d1)["id"] as? String else { throw CloudError.invalidResponse }
        return (fileID, try await fileInfo(fileID))
    }
    private func startSession(name: String, folderPath: String, mime: String, length: Int) async throws -> URL {
        let folderID = try await ensureFolder(path: folderPath)
        var start = URLRequest(url: Self.uploadAPI); start.httpMethod = "POST"; start.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        start.setValue(mime, forHTTPHeaderField: "X-Upload-Content-Type"); start.setValue(String(length), forHTTPHeaderField: "X-Upload-Content-Length")
        start.httpBody = try JSONSerialization.data(withJSONObject: ["name": name, "parents": [folderID]])
        let (d0, h0) = try await authed(start); try check(h0, d0)
        guard let loc = h0.value(forHTTPHeaderField: "Location"), let u = URL(string: loc) else { throw CloudError.invalidResponse }
        return u
    }
    private func fileInfo(_ id: String) async throws -> [String: Any] {
        var c = URLComponents(url: Self.api.appendingPathComponent("files/\(id)"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "fields", value: "id,size,md5Checksum,trashed,webViewLink,webContentLink")]
        let (d, h) = try await authed(URLRequest(url: c.url!)); try check(h, d)
        return json(d)
    }
    func setAccess(_ object: CloudObject, access: LinkAccess) async throws -> CloudObject { try await setAccess(object, access: access, knownInfo: nil) }
    private func setAccess(_ object: CloudObject, access: LinkAccess, knownInfo: [String: Any]?) async throws -> CloudObject {
        if access == .anyoneWithLink {
            var r = URLRequest(url: Self.api.appendingPathComponent("files/\(object.remoteID)/permissions")); r.httpMethod = "POST"; r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try JSONSerialization.data(withJSONObject: ["role": "reader", "type": "anyone"])
            let (d, h) = try await authed(r); try check(h, d)
        } else {
            // "anyone" izinlerini kaldır
            var c = URLComponents(url: Self.api.appendingPathComponent("files/\(object.remoteID)/permissions"), resolvingAgainstBaseURL: false)!; c.queryItems = [URLQueryItem(name: "fields", value: "permissions(id,type)")]
            let (d, h) = try await authed(URLRequest(url: c.url!)); try check(h, d)
            for p in (json(d)["permissions"] as? [[String: Any]]) ?? [] where (p["type"] as? String) == "anyone" {
                if let pid = p["id"] as? String { var del = URLRequest(url: Self.api.appendingPathComponent("files/\(object.remoteID)/permissions/\(pid)")); del.httpMethod = "DELETE"; let (dd, dh) = try await authed(del); if dh.statusCode != 404 { try check(dh, dd) } }
            }
        }
        let info: [String: Any]
        if let k = knownInfo { info = k } else { info = try await fileInfo(object.remoteID) }
        var o = object; o.access = access == .anyoneWithLink ? .anyoneWithLink : .ownerOnly
        o.link = (info["webViewLink"] as? String).flatMap(URL.init(string:))
        return o
    }
    /// Sunucu kopyası Çöp'te değil, boyutu yerel dosyayla aynı ve `md5Checksum` yerelde hesaplanan MD5'e eşit mi.
    /// Sunucu sağlama vermezse doğrulanmış sayılmaz (yerel dosyaya dokunulmaz).
    func verify(_ object: CloudObject, localFile: URL) async throws -> Bool {
        let info = try await fileInfo(object.remoteID)
        if (info["trashed"] as? Bool) == true { return false }
        guard Int(info["size"] as? String ?? "") == CloudHTTP.fileSize(localFile) else { return false }
        guard let remote = (info["md5Checksum"] as? String)?.lowercased(), !remote.isEmpty, let local = CloudHTTP.md5Hex(of: localFile) else { return false }
        return remote == local
    }
    /// Buluttan sil: Drive'da kalıcı silme yerine Çöp'e taşır (`trashed: true`; Drive Çöp'ünden 30 gün geri alınabilir).
    func delete(_ object: CloudObject) async throws {
        var r = URLRequest(url: Self.api.appendingPathComponent("files/\(object.remoteID)")); r.httpMethod = "PATCH"; r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: ["trashed": true])
        let (d, h) = try await authed(r); if h.statusCode == 404 { return }; try check(h, d)
    }
    func testConnection() async throws {
        var c = URLComponents(url: Self.api.appendingPathComponent("about"), resolvingAgainstBaseURL: false)!; c.queryItems = [URLQueryItem(name: "fields", value: "user")]
        let (d, h) = try await authed(URLRequest(url: c.url!)); try check(h, d)
    }
}
#endif
