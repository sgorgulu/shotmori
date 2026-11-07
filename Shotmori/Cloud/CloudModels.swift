import Foundation

// Veri modeli her derlemede derlenir: shelf.json'daki `cloud` alanı, bayrak kaldırılmış (bulutsuz) bir derlemede de kayıpsız okunup yazılır.
// Bulut metni ve davranışı (sağlayıcılar, kuyruk, ayarlar) `SHOTMORI_CLOUD` ile derlenir: Debug ve Release 1.0'da açık (bkz. Features.swift).

/// Bulut sağlayıcıları (ilk sürüm: Google Drive ve S3 / S3 uyumlu).
enum CloudProviderID: String, Codable, CaseIterable {
    case googleDrive, s3
    #if SHOTMORI_CLOUD
    var title: String { self == .googleDrive ? "Google Drive" : "S3" }
    #endif
}

/// Link gizliliği: kullanıcı seçer ve sonradan değiştirebilir. Drive: bağlantıya sahip herkes / yalnızca ben.
/// S3: herkese açık nesne / imzalı link + süre (en çok 7 gün — SigV4 sınırı).
enum LinkAccess: Codable, Equatable {
    case anyoneWithLink, ownerOnly, publicObject, presigned(seconds: Int)
    static let maxPresignSeconds = 604_800
    var clamped: LinkAccess { if case .presigned(let s) = self { return .presigned(seconds: min(max(s, 1), Self.maxPresignSeconds)) }; return self }
}

/// Panoya kopyalanan linkin biçimi.
enum LinkFormat: String, Codable, CaseIterable {
    case url, markdown, html
    func render(_ url: URL, name: String) -> String {
        switch self {
        case .url: return url.absoluteString
        case .markdown: return "![\(name.replacingOccurrences(of: "]", with: "\\]"))](\(url.absoluteString))"
        case .html: return "<img src=\"\(url.absoluteString)\" alt=\"\(name.replacingOccurrences(of: "\"", with: "&quot;"))\">"
        }
    }
}

enum UploadPurpose: String, Codable { case share, backup }

/// Bir yüklemenin buluttaki karşılığı; raf öğesi birden çok sağlayıcıda kopya taşıyabilir.
struct CloudObject: Codable, Equatable {
    var provider: CloudProviderID
    var remoteID: String        // Drive: fileId · S3: nesne anahtarı
    var remotePath: String      // insan okunur yol (klasör/ad)
    var link: URL?
    var access: LinkAccess
    var uploadedAt: Date
    var size: Int
    var checksum: String?       // Drive md5Checksum · S3 ETag (tırnaksız)
}

/// Klasör/yol şablonu: `{yyyy} {MM} {dd} {name} {ext}`; `{name}` uzantısızdır. Boş segmentler ve `..` temizlenir.
enum PathTemplate {
    static let `default` = "Shotmori/{yyyy}-{MM}/{name}.{ext}"
    static func render(_ template: String, fileName: String, date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let ns = fileName as NSString
        let ext = ns.pathExtension, name = ext.isEmpty ? fileName : ns.deletingPathExtension
        var s = ext.isEmpty ? template.replacingOccurrences(of: ".{ext}", with: "") : template
        for (k, v) in [("{yyyy}", String(format: "%04d", c.year ?? 0)), ("{MM}", String(format: "%02d", c.month ?? 0)), ("{dd}", String(format: "%02d", c.day ?? 0)), ("{name}", name), ("{ext}", ext)] { s = s.replacingOccurrences(of: k, with: v) }
        let parts = s.split(separator: "/", omittingEmptySubsequences: true).map(String.init).filter { $0 != "." && $0 != ".." }
        let joined = parts.joined(separator: "/")
        return joined.isEmpty ? fileName : joined
    }
}
