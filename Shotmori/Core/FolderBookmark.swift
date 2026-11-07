import Foundation

/// Kullanıcının seçtiği klasörün security-scoped bookmark'ı. Sandbox'ta klasöre yeniden açılışta erişmenin tek yolu budur.
enum FolderBookmark {
    struct Resolved: Equatable { let url: URL; let isStale: Bool }

    static func make(for url: URL) throws -> Data {
        try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    }
    /// `.withoutMounting`: takılı olmayan ağ/harici diski çözerken bağlamaya (ve arayüze) kalkışmaz.
    /// Çözülemeyen (silinmiş, bozuk) bookmark → nil.
    static func resolve(_ data: Data) -> Resolved? {
        var stale = false
        guard let u = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        return Resolved(url: u, isStale: stale)
    }
}
