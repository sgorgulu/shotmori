import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Küçük resimler: tam görsel asla belleğe alınmaz; ImageIO küçük resim üretir, NSCache tutar.
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()
    /// Çözme kuyruğu: en çok 3 eşzamanlı çözme; toplu gelişte (300 kare) CPU/bellek patlamasın.
    private let queue: OperationQueue = { let q = OperationQueue(); q.name = "dev.shotmori.thumbs"; q.maxConcurrentOperationCount = 3; q.qualityOfService = .userInitiated; return q }()
    /// Aynı dosya sürümü için bekleyen tamamlamalar (yalnız ana kuyrukta): tek çözme, hepsine dağıtım. Kutu, geçersiz kılınan çözmenin kendi bekleyenlerini yine bulabilmesi için.
    private final class Waiters { var list: [(NSImage?) -> Void] = [] }
    private var inFlight: [String: Waiters] = [:]
    private let generate: (URL, Int) -> NSImage?
    let maxPixel = 320
    init(generate: @escaping (URL, Int) -> NSImage? = ThumbnailCache.generate) { self.generate = generate; cache.countLimit = 200 }

    /// Sürümlü anahtar `yol|mtime|boyut` (tek stat): aynı yola yeniden yazılan dosya (Önizleme kaydı, silinip yeniden oluşturma) eski küçük resme düşmez.
    static func key(_ url: URL) -> String {
        var st = stat()
        guard stat(url.path, &st) == 0 else { return "\(url.path)|-|-" }
        return "\(url.path)|\(st.st_mtimespec.tv_sec).\(st.st_mtimespec.tv_nsec)|\(st.st_size)"
    }

    func cached(_ url: URL) -> NSImage? { cache.object(forKey: Self.key(url) as NSString) }

    func thumbnail(for url: URL, completion: @escaping (NSImage?) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        let key = Self.key(url)
        if let img = cache.object(forKey: key as NSString) { completion(img); return }
        if let w = inFlight[key] { w.list.append(completion); return }
        let w = Waiters(); w.list = [completion]; inFlight[key] = w
        let gen = generate, px = maxPixel
        queue.addOperation { [weak self] in
            let img = gen(url, px)
            DispatchQueue.main.async {
                guard let self = self else { return }
                // Geçersiz kılındıysa sonuç önbelleğe girmez, ama bekleyenler yine yanıt alır.
                if self.inFlight[key] === w { self.inFlight.removeValue(forKey: key); if let img = img { self.cache.setObject(img, forKey: key as NSString) } }
                w.list.forEach { $0(img) }
            }
        }
    }
    func invalidate(_ url: URL) {
        dispatchPrecondition(condition: .onQueue(.main))
        let key = Self.key(url); cache.removeObject(forKey: key as NSString); inFlight.removeValue(forKey: key)
    }

    static func generate(_ url: URL, maxPixel: Int) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceShouldCacheImmediately: true]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / 2, height: CGFloat(cg.height) / 2))
    }
    /// Tam çözünürlüklü PNG verisi (panoya kopyalama için diskten okunur, bellekte tutulmaz).
    /// PNG olmayan kaynak tam çözülür (yapıştırma anında, ana iş parçacığında): `maxPixels`'ı aşan kaynak için nil (donma/bellek sınırı).
    /// Yeniden kodlamada kaynak üst verisi (EXIF/GPS) taşınmaz.
    static func pngData(_ url: URL, maxPixels: Int = EditRenderer.maxSourcePixels) -> Data? {
        if url.pathExtension.lowercased() == "png" { return try? Data(contentsOf: url) }
        guard let info = ImageResizer.sourceInfo(url), info.pixelSize.width * info.pixelSize.height <= maxPixels,
              let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }
}
