import AppKit

/// Finder Servisi ve menü çubuğuna bırakma pasteboard'undan dosya URL'si ve görsel verisi çıkarır.
/// Yalnız okur; yol saklanmaz, içerik `InboundImport` ile `Gelen/`e kopyalanır.
enum ServicePasteboard {
    /// Eski (`NSFilenamesPboardType`) servis/sürükleme türü: yol dizisi.
    private static let legacyFilenames = NSPasteboard.PasteboardType("NSFilenamesPboardType")

    /// Yalnız dosya URL'leri (sıra korunur, tekrar yok). Düz metin yol, web URL'si sayılmaz; dosya başvuru URL'si (`/.file/id=`) yola çözülür.
    static func fileURLs(from pb: NSPasteboard) -> [URL] {
        var out: [URL] = [], seen = Set<String>()
        func append(_ u: URL) {
            let resolved = ((u as NSURL).filePathURL ?? u).standardizedFileURL
            guard resolved.isFileURL, seen.insert(resolved.path).inserted else { return }
            out.append(resolved)
        }
        for item in pb.pasteboardItems ?? [] {
            if let s = item.string(forType: .fileURL), let u = URL(string: s), u.isFileURL { append(u) }
        }
        if out.isEmpty, let paths = pb.propertyList(forType: legacyFilenames) as? [String] {
            for p in paths where p.hasPrefix("/") { append(URL(fileURLWithPath: p)) }
        }
        return out
    }

    /// Görsel verisi: PNG → "png"; TIFF PNG'ye çevrilmeden → "tiff". Görsel yoksa nil.
    static func imageData(from pb: NSPasteboard) -> (Data, String)? {
        if let d = pb.data(forType: .png), !d.isEmpty { return (d, "png") }
        if let d = pb.data(forType: .tiff), !d.isEmpty { return (d, "tiff") }
        return nil
    }
}
