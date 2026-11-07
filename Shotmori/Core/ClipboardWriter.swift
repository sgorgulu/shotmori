import AppKit

/// Shotmori'nin tanıdığı görüntü uzantıları tek yerde: içe aktarma kabulü, izleyici ad süzgeci ve pano türü aynı kümeden beslenir.
enum ImageFormats {
    static let extensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "gif", "webp"]
    /// Uzantının doğal pano türü; görüntü olmayan uzantı için nil. `extensions`'taki her uzantının bir türü vardır.
    static func pasteboardType(forExtension ext: String) -> NSPasteboard.PasteboardType? {
        switch ext.lowercased() {
        case "png": return .png
        case "jpg", "jpeg": return NSPasteboard.PasteboardType("public.jpeg")
        case "heic": return NSPasteboard.PasteboardType("public.heic")
        case "heif": return NSPasteboard.PasteboardType("public.heif")
        case "tif", "tiff": return .tiff
        case "gif": return NSPasteboard.PasteboardType("com.compuserve.gif")
        case "webp": return NSPasteboard.PasteboardType("org.webmproject.webp")
        default: return nil
        }
    }
}

/// Görüntü dosyasını panoya yazar: dosyanın kendi verisi kendi türüyle + dosya URL'si; PNG yalnız yapıştıran uygulama isterse (tembel) çözülür.
enum ClipboardWriter {
    /// Dosya uzantısının doğal pano türü; görüntü olmayan uzantı için nil.
    static func nativeType(forExtension ext: String) -> NSPasteboard.PasteboardType? { ImageFormats.pasteboardType(forExtension: ext) }

    /// Tembel PNG sağlayıcısı: çözme yalnız `provideDataForType` ile, yani yapıştıran uygulama PNG isteyince olur.
    final class PNGProvider: NSObject, NSPasteboardItemDataProvider {
        let url: URL
        init(url: URL) { self.url = url }
        func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
            guard type == .png, let png = ThumbnailCache.pngData(url) else { return }
            item.setData(png, forType: .png)
        }
        func pasteboardFinishedWithDataProvider(_ pasteboard: NSPasteboard) { if ClipboardWriter.provider === self { ClipboardWriter.provider = nil } }
    }
    /// Pano sağlayıcıyı zayıf tutar; panoya yazılan son sağlayıcı burada güçlü tutulur, pano işi bitirince bırakılır.
    static var provider: PNGProvider?

    @discardableResult
    static func writeImage(_ url: URL, to pb: NSPasteboard = .general) -> Bool {
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        if let native = nativeType(forExtension: url.pathExtension) {
            guard let bytes = try? Data(contentsOf: url) else { return false }
            item.setData(bytes, forType: native)
            if native != .png {
                let p = PNGProvider(url: url)
                guard item.setDataProvider(p, forTypes: [.png]) else { return false }
                provider = p
            }
        }
        pb.clearContents()
        return pb.writeObjects([item])
    }
}
