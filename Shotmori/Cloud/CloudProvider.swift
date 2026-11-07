#if SHOTMORI_CLOUD // Bulut kodu SHOTMORI_CLOUD bayrağıyla derlenir (Debug ve Release 1.0'da açık, bkz. Features.swift); bayrak kaldırılırsa derlenmez.
import Foundation
import CryptoKit

/// Sağlayıcıdan bağımsız hatalar; kullanıcıya sade, yerelleştirilmiş metinle gösterilir (sunucunun ham yanıt gövdesi gösterilmez).
enum CloudError: LocalizedError, Equatable {
    case notConnected, unauthorized, forbidden, notFound, network(String), verifyMismatch, cancelled, invalidResponse
    /// HTTP kodu + sunucunun kısa hata kodu (S3 `<Code>`, Google `reason`/`status`); kod yalnız bilinen metne eşlemek için tutulur.
    case server(Int, String)
    /// Kuyruktaki görevin yerel dosyası artık yok.
    case localFileMissing
    /// Yerel dosya diskte duruyor ama okunamadı (izin/sandbox kapsamı, iCloud'a boşaltılmış dosya). Görev kuyrukta kalır, yeniden denenir.
    case localFileUnreadable
    /// Google girişi iptal edildi ya da izin verilmedi (`error=access_denied` vb.).
    case authDenied
    /// Google token yanıtında yenileme belirteci yok.
    case noRefreshToken

    var errorDescription: String? {
        switch self {
        case .notConnected: return S.cloudErrNotConnected
        case .unauthorized: return S.cloudErrUnauthorized
        case .forbidden: return S.cloudErrForbidden
        case .notFound: return S.cloudErrNotFound
        case .network(let m): return S.cloudErrNetwork(m)
        case .server(let code, let service): return Self.knownMessage(status: code, service: service) ?? S.cloudErrServerCode(code)
        case .verifyMismatch: return S.cloudErrVerify
        case .cancelled: return S.cloudErrCancelled
        case .invalidResponse: return S.cloudErrInvalidResponse
        case .localFileMissing: return S.missingFile
        case .localFileUnreadable: return S.cloudErrFileUnreadable
        case .authDenied: return S.cloudErrAuthDenied
        case .noRefreshToken: return S.cloudErrNoRefreshToken
        }
    }
    /// Günlük için: durum adı, sunucu hatasında HTTP kodu. İlişkili metinler (URL, yanıt gövdesi) hiç yazılmaz.
    var logSummary: String {
        switch self {
        case .notConnected: return "notConnected"
        case .unauthorized: return "unauthorized"
        case .forbidden: return "forbidden"
        case .notFound: return "notFound"
        case .network: return "network"
        case .server(let code, _): return "server \(code)"
        case .verifyMismatch: return "verifyMismatch"
        case .cancelled: return "cancelled"
        case .invalidResponse: return "invalidResponse"
        case .localFileMissing: return "localFileMissing"
        case .localFileUnreadable: return "localFileUnreadable"
        case .authDenied: return "authDenied"
        case .noRefreshToken: return "noRefreshToken"
        }
    }

    /// Bilinen kısa sunucu kodları → yerelleştirilmiş metin; bilinmiyorsa nil (yalnız HTTP kodu gösterilir).
    static func knownMessage(status: Int, service: String) -> String? {
        switch service {
        case "NoSuchBucket": return S.cloudErrBucketNotFound
        case "InvalidAccessKeyId", "SignatureDoesNotMatch": return S.cloudErrBadCredentials
        case "SlowDown", "TooManyRequests", "rateLimitExceeded", "userRateLimitExceeded": return S.cloudErrRateLimited
        case "storageQuotaExceeded", "QuotaExceeded": return S.cloudErrQuotaExceeded
        default: return status == 429 ? S.cloudErrRateLimited : nil
        }
    }

    /// HTTP durum kodunu hataya çevirir; 2xx → nil. Bilinen sunucu kodu (ör. kota, yanlış anahtar) genel 401/403/404 eşlemesinden önce gelir.
    static func from(status: Int, body: Data?) -> CloudError? {
        guard !(200..<300).contains(status) else { return nil }
        let service = serviceCode(in: body)
        if let s = service, knownMessage(status: status, service: s) != nil { return .server(status, s) }
        switch status {
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404: return .notFound
        default: return .server(status, service ?? "")
        }
    }
    /// Yanıt gövdesinden kısa hata kodu: S3 XML `<Code>…</Code>` ya da Google JSON `error.errors[0].reason` / `error.status`.
    /// Yalnız harf/rakam/alt çizgi, en çok 64 karakter; başka bir şey gövdeden alınmaz.
    static func serviceCode(in body: Data?) -> String? {
        guard let body, !body.isEmpty else { return nil }
        var code: String?
        if let obj = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any], let err = obj["error"] as? [String: Any] {
            code = ((err["errors"] as? [[String: Any]])?.first?["reason"] as? String) ?? (err["status"] as? String)
        } else if let text = String(data: body.prefix(4096), encoding: .utf8), let r = text.range(of: "<Code>"), let e = text.range(of: "</Code>", range: r.upperBound..<text.endIndex) {
            code = String(text[r.upperBound..<e.lowerBound])
        }
        guard let c = code, !c.isEmpty, c.count <= 64, c.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "_" }) else { return nil }
        return c
    }
}

/// Tek sağlayıcı arayüzü: yükle, erişimi değiştir, doğrula, sil, bağlantıyı sına.
protocol CloudProvider: AnyObject {
    var id: CloudProviderID { get }
    var isConnected: Bool { get }
    /// `stripMetadata`: paylaşım yüklemesinde EXIF/GPS/XMP atılmış bayt gönderilir (yerel dosya değişmez); yedekte orijinal.
    func upload(file: URL, remotePath: String, access: LinkAccess, stripMetadata: Bool, progress: @escaping (Double) -> Void) async throws -> CloudObject
    func setAccess(_ object: CloudObject, access: LinkAccess) async throws -> CloudObject
    /// Sunucudaki kopya yerel dosyayla eşleşiyor mu: boyut + yerelde hesaplanan MD5 ↔ sunucu sağlaması.
    func verify(_ object: CloudObject, localFile: URL) async throws -> Bool
    func delete(_ object: CloudObject) async throws
    /// Küçük bir nesne yükleyip siler.
    func testConnection() async throws
}

/// Ortak HTTP yardımcıları.
enum CloudHTTP {
    static func send(_ request: URLRequest, session: URLSession) async throws -> (Data, HTTPURLResponse) {
        try await perform { try await session.data(for: request) }
    }
    /// Gövde bellekten: dosya bir kez okunur; imza/sağlama ile gönderilen bayt aynıdır (iki okuma arasında dosya değişemez).
    static func upload(_ request: URLRequest, body: Data, session: URLSession) async throws -> (Data, HTTPURLResponse) {
        try await perform { try await session.upload(for: request, from: body) }
    }
    /// Ortak hata sarmalama: HTTP olmayan yanıt → `.invalidResponse`, iptal → `.cancelled`, diğerleri → `.network`.
    private static func perform(_ op: () async throws -> (Data, URLResponse)) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, resp) = try await op()
            guard let http = resp as? HTTPURLResponse else { throw CloudError.invalidResponse }
            return (data, http)
        } catch let e as CloudError { throw e }
        catch let e as URLError where e.code == .cancelled { throw CloudError.cancelled }
        catch { throw CloudError.network(error.localizedDescription) }
    }
    static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "png": return "image/png"; case "jpg", "jpeg": return "image/jpeg"; case "heic", "heif": return "image/heic"; case "gif": return "image/gif"; case "tiff", "tif": return "image/tiff"; case "pdf": return "application/pdf"
        default: return "application/octet-stream"
        }
    }
    static func fileSize(_ url: URL) -> Int { (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0 }
    /// Yüklenecek bayt: dosya bir kez okunur; istenirse üst veri atılır. Okunamazsa: dosya diskte yoksa `.localFileMissing`
    /// (görev atılır), varsa `.localFileUnreadable` (izin/iCloud; görev kuyrukta kalır, "Yeniden dene" yolu korunur).
    static func body(of file: URL, stripMetadata: Bool) throws -> Data {
        guard let d = try? Data(contentsOf: file) else {
            throw FileManager.default.fileExists(atPath: file.path) ? CloudError.localFileUnreadable : CloudError.localFileMissing
        }
        return stripMetadata ? UploadMetadata.stripped(d, fileExtension: file.pathExtension) : d
    }
    /// Yerel dosyanın MD5'i (küçük harf onaltılık), parça parça okunur. Yedek sonrası Çöp kararında sunucu sağlamasıyla karşılaştırılır.
    static func md5Hex(of file: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? h.close() }
        var md5 = Insecure.MD5()
        do {
            // `read(upToCount:)` dosya sonunda nil ya da boş veri döner.
            while let chunk = try h.read(upToCount: 1 << 20), !chunk.isEmpty { md5.update(data: chunk) }
        } catch { return nil }
        return hex(md5.finalize())
    }
    static func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 { digest.map { String(format: "%02x", $0) }.joined() }
}
#endif
