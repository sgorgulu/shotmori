import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Düzenleme modeli: tüm dikdörtgenler **görüntü piksel** koordinatındadır (sol-üst köken).
/// Görünüm ölçeği/zoom bu modele hiç girmez; dönüşüm `CanvasTransform` ile yapılır.
struct EditState: Equatable {
    var crop: CGRect?                 // nil = kırpma yok
    var redactions: [CGRect] = []     // opak kapatma alanları
    var selectedRedaction: Int? = nil
    var hasEdits: Bool { crop != nil || !redactions.isEmpty }
}

enum CropAspect: Equatable { case free, square, wide16x9
    var ratio: CGFloat? { switch self { case .free: return nil; case .square: return 1; case .wide16x9: return 16.0 / 9.0 } }
    var label: String { switch self { case .free: return S.editAspectFree; case .square: return "1:1"; case .wide16x9: return "16:9" } }
}

final class EditDocument {
    let imageSize: CGSize            // piksel
    private(set) var state = EditState()
    private var undoStack: [EditState] = []
    private var redoStack: [EditState] = []
    var onChange: (() -> Void)?

    init(imageSize: CGSize) { self.imageSize = imageSize }
    var bounds: CGRect { CGRect(origin: .zero, size: imageSize) }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// `beginChange`'in temizlediği yineleme geçmişi: değişiklik iptal edilirse (`cancelChange`) geri yüklenir.
    private var stashedRedo: [EditState]?

    /// Her kalıcı değişiklik öncesi çağrılır (sürüklemede bir kez, mouseDown'da). Yineleme geçmişi kenara alınır.
    func beginChange() {
        undoStack.append(state); if undoStack.count > 200 { undoStack.removeFirst() }
        stashedRedo = redoStack; redoStack.removeAll()
    }
    func undo() { guard let s = undoStack.popLast() else { return }; stashedRedo = nil; redoStack.append(state); state = s; onChange?() }
    func redo() { guard let s = redoStack.popLast() else { return }; stashedRedo = nil; undoStack.append(state); state = s; onChange?() }
    /// beginChange sonrası gerçek değişiklik olmadıysa: kaydı düşür, mevcut durumu (seçim dahil) ve yineleme geçmişini koru.
    func cancelChange() {
        _ = undoStack.popLast()
        if let r = stashedRedo { redoStack = r }
        stashedRedo = nil
    }

    /// Görüntü sınırına kırpılmış, tam piksele yuvarlanmış, en az 1×1 dikdörtgen; sıfır alan → nil.
    func clamped(_ r: CGRect) -> CGRect? {
        let i = r.standardized.intersection(bounds)
        guard !i.isNull else { return nil }
        let x = floor(i.minX), y = floor(i.minY), w = floor(i.maxX) - x, h = floor(i.maxY) - y
        guard w >= 1, h >= 1 else { return nil }
        return CGRect(x: x, y: y, width: w, height: h)
    }
    func setCrop(_ r: CGRect?) { state.crop = r.flatMap { clamped($0) }; onChange?() }
    func addRedaction(_ r: CGRect) { guard let c = clamped(r) else { return }; state.redactions.append(c); state.selectedRedaction = state.redactions.count - 1; onChange?() }
    func updateRedaction(_ i: Int, _ r: CGRect) { guard state.redactions.indices.contains(i), let c = clamped(r) else { return }; state.redactions[i] = c; onChange?() }
    func removeRedaction(_ i: Int) { guard state.redactions.indices.contains(i) else { return }; state.redactions.remove(at: i); state.selectedRedaction = nil; onChange?() }
    func select(_ i: Int?) { state.selectedRedaction = i; onChange?() }

    /// Orana göre dikdörtgen üret (sürükleme başlangıcı sabit köşe, serbest uç `p`).
    static func rect(from anchor: CGPoint, to p: CGPoint, aspect: CropAspect) -> CGRect {
        var w = p.x - anchor.x, h = p.y - anchor.y
        if let r = aspect.ratio {
            let sw = w < 0 ? -1.0 : 1.0, sh = h < 0 ? -1.0 : 1.0
            if abs(w) / r >= abs(h) { h = sh * abs(w) / r } else { w = sw * abs(h) * r }
        }
        return CGRect(x: anchor.x, y: anchor.y, width: w, height: h).standardized
    }
}

/// Görünüm noktası ↔ görüntü pikseli. `scale` = ekrandaki nokta / görüntü pikseli (önizleme ölçeği × zoom).
struct CanvasTransform: Equatable {
    var scale: CGFloat
    var origin: CGPoint   // görüntünün (0,0) pikselinin görünümdeki nokta konumu (sol-üst kökenli, flipped view)
    func toView(_ p: CGPoint) -> CGPoint { CGPoint(x: origin.x + p.x * scale, y: origin.y + p.y * scale) }
    func toImage(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - origin.x) / scale, y: (p.y - origin.y) / scale) }
    func toView(_ r: CGRect) -> CGRect { CGRect(origin: toView(r.origin), size: CGSize(width: r.width * scale, height: r.height * scale)) }
    func toImage(_ r: CGRect) -> CGRect { CGRect(origin: toImage(r.origin), size: CGSize(width: r.width / scale, height: r.height / scale)) }
}

/// Düzleştirilmiş çıktı: kırpma + opak kapatma tek bitmap'e işlenir; kaynak piksel verisi, katman veya geçmiş taşınmaz.
enum EditRenderer {
    enum RenderError: LocalizedError { case sourceMissing, unreadable, tooLarge, encode
        var errorDescription: String? { switch self { case .sourceMissing: return S.editErrorSourceMissing; case .unreadable: return S.resizeErrorUnreadable; case .tooLarge: return S.resizeErrorTooLarge; case .encode: return S.resizeErrorEncode } }
    }
    /// Tam çözen yolların (editör dışa aktarımı, pano PNG'si) kaynak sınırı: 150 MP ≈ 600 MB çözülmüş + kırpma boyutunda ikinci bağlam;
    /// küçültülerek çözen yolların sınırından (`ImageResizer.maxSourcePixels`) bilerek düşük.
    static let maxSourcePixels = 150_000_000
    /// Yönü uygulanmış, tam çözünürlüklü kaynak. Çok büyükse hata (sınırsız bellek yok).
    static func loadOriented(_ url: URL) throws -> CGImage {
        guard FileManager.default.fileExists(atPath: url.path) else { throw RenderError.sourceMissing }
        guard let info = ImageResizer.sourceInfo(url) else { throw RenderError.unreadable }
        guard info.pixelSize.width * info.pixelSize.height <= maxSourcePixels else { throw RenderError.tooLarge }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { throw RenderError.unreadable }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: max(info.pixelSize.width, info.pixelSize.height),
                                     kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { throw RenderError.unreadable }
        return cg
    }
    /// Önizleme için sınırlı boyutta, yönü uygulanmış görüntü.
    static func loadPreview(_ url: URL, maxPixel: Int = 2048) throws -> CGImage {
        guard FileManager.default.fileExists(atPath: url.path) else { throw RenderError.sourceMissing }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { throw RenderError.unreadable }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maxPixel, kCGImageSourceCreateThumbnailWithTransform: true]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { throw RenderError.unreadable }
        return cg
    }
    /// `state` görüntü piksel koordinatında (sol-üst köken). Çıktı: kırpılmış alan, kapatmalar siyah ve %100 opak.
    static func render(source: CGImage, state: EditState, format: ImageOutputFormat, quality: Double = 0.9) throws -> Data {
        let full = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        let crop = (state.crop ?? full).intersection(full).integral
        guard crop.width >= 1, crop.height >= 1 else { throw RenderError.encode }
        let w = Int(crop.width), h = Int(crop.height)
        let space = source.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let alpha: CGImageAlphaInfo = format == .png ? .premultipliedLast : .noneSkipLast
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: alpha.rawValue) else { throw RenderError.encode }
        ctx.interpolationQuality = .high
        if format == .jpeg { ctx.setFillColor(CGColor.white); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h)) }
        // Kaynağı, kırpma başlangıcı (0,0)'a gelecek şekilde çiz. CG koordinatı alt-sol: y'yi çevir.
        let drawRect = CGRect(x: -crop.minX, y: -(CGFloat(source.height) - crop.maxY), width: CGFloat(source.width), height: CGFloat(source.height))
        ctx.draw(source, in: drawRect)
        // Kapatmalar: tam opak siyah, kırpma ile kesişim; CG alt-sol y dönüşümü
        ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.setBlendMode(.normal)
        for r in state.redactions {
            let i = r.integral.intersection(crop); guard !i.isNull, i.width >= 1, i.height >= 1 else { continue }
            let cgY = crop.maxY - i.maxY
            ctx.fill(CGRect(x: i.minX - crop.minX, y: cgY, width: i.width, height: i.height))
        }
        guard let out = ctx.makeImage() else { throw RenderError.encode }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, format.utType.identifier as CFString, 1, nil) else { throw RenderError.encode }
        // Yalnızca gerekli özellikler; kaynak metadata (EXIF/TIFF/GPS/küçük resim) kopyalanmaz.
        var props: [CFString: Any] = [kCGImageDestinationEmbedThumbnail: false]
        if format == .jpeg { props[kCGImageDestinationLossyCompressionQuality] = min(max(quality, 0.05), 1.0) }
        CGImageDestinationAddImage(dest, out, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw RenderError.encode }
        return format == .png ? PNGChunkFilter.stripMetadata(data as Data) : data as Data
    }
    static func derivativeURL(for source: URL, format: ImageOutputFormat, in folder: URL? = nil) -> URL {
        let base = source.deletingPathExtension().lastPathComponent
        let dir = folder ?? ImageResizer.derivativesFolder
        var u = dir.appendingPathComponent("\(base) (\(S.editedBadge)).\(format.ext)"); var n = 2
        while FileManager.default.fileExists(atPath: u.path) { u = dir.appendingPathComponent("\(base) (\(S.editedBadge) \(n)).\(format.ext)"); n += 1 }
        return u
    }
}

/// Pano yükü: tüm temsiller aynı düzenlenmiş veriden türetilir (biri gizli, diğeri orijinal olamaz).
struct ClipboardPayload {
    let imageData: Data
    let imageType: NSPasteboard.PasteboardType
    let fileURL: URL?
    static func make(edited data: Data, format: ImageOutputFormat, fileURL: URL?) -> ClipboardPayload {
        ClipboardPayload(imageData: data, imageType: format == .png ? .png : NSPasteboard.PasteboardType("public.jpeg"), fileURL: fileURL)
    }
    @discardableResult
    func write(to pb: NSPasteboard = .general) -> Bool {
        pb.clearContents()
        let item = NSPasteboardItem(); item.setData(imageData, forType: imageType)
        if let u = fileURL { item.setString(u.absoluteString, forType: .fileURL) }
        return pb.writeObjects([item])
    }
}

/// PNG çıktısından metadata/yardımcı chunk'ları çıkarır (eXIf, tEXt/zTXt/iTXt, tIME …).
/// Renk yönetimi için gerekli olanlar (sRGB, gAMA, cHRM, iCCP, pHYs) ve görüntü verisi kalır.
enum PNGChunkFilter {
    static let keep: Set<String> = ["IHDR", "PLTE", "IDAT", "IEND", "sRGB", "gAMA", "cHRM", "iCCP", "pHYs", "tRNS", "sBIT", "bKGD"]
    static func chunkTypes(_ d: Data) -> [String] { var out: [String] = []; forEachChunk(d) { t, _ in out.append(t) }; return out }
    static func stripMetadata(_ d: Data) -> Data {
        guard d.count > 8, d.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) else { return d }
        var out = Data(d.prefix(8))
        forEachChunk(d) { type, range in if keep.contains(type) { out.append(d[range]) } }
        return out
    }
    /// Her chunk için (tür, uzunluk+tür+veri+CRC aralığı).
    private static func forEachChunk(_ d: Data, _ body: (String, Range<Int>) -> Void) {
        var i = 8
        while i + 12 <= d.count {
            let len = Int(d[i]) << 24 | Int(d[i + 1]) << 16 | Int(d[i + 2]) << 8 | Int(d[i + 3])
            let end = i + 12 + len; guard end <= d.count else { return }
            let type = String(bytes: d[(i + 4)..<(i + 8)], encoding: .ascii) ?? "?"
            body(type, i..<end); i = end
        }
    }
}
