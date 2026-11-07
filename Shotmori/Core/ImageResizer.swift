import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Boyutlandırma matematiği (test edilebilir).
enum ResizeMath {
    struct Size: Equatable { var width: Int; var height: Int }
    static func scaled(_ s: Size, percent: Double) -> Size {
        Size(width: clamp(Double(s.width) * percent / 100), height: clamp(Double(s.height) * percent / 100))
    }
    static func heightKeepingAspect(original: Size, width: Int) -> Int { clamp(Double(width) * Double(original.height) / Double(original.width)) }
    static func widthKeepingAspect(original: Size, height: Int) -> Int { clamp(Double(height) * Double(original.width) / Double(original.height)) }
    static let maxDimension = 16384
    /// Yuvarlar ve `1...(maxDimension * 8)` aralığına sıkıştırır; NaN/sonsuz/negatif → 1 (Int dönüşümü çökmez).
    static func clamp(_ v: Double) -> Int {
        guard v.isFinite else { return 1 }
        return Int(min(max(v.rounded(), 1), Double(maxDimension * 8)))
    }
    enum Validation: Equatable { case ok, tooSmall, tooLarge }
    static func validate(_ s: Size) -> Validation {
        if s.width < 1 || s.height < 1 { return .tooSmall }
        if s.width > maxDimension || s.height > maxDimension { return .tooLarge }
        return .ok
    }
}

enum ImageOutputFormat: String, CaseIterable, Identifiable { case png, jpeg; var id: String { rawValue }
    var label: String { self == .png ? "PNG" : "JPEG" }
    var utType: UTType { self == .png ? .png : .jpeg }
    var ext: String { self == .png ? "png" : "jpg" }
}

/// Native ImageIO/Core Graphics ile türev üretimi. Orijinale dokunmaz.
enum ImageResizer {
    enum ResizeError: LocalizedError {
        case unreadable, invalidSize, encodeFailed, tooLargeSource
        var errorDescription: String? {
            switch self {
            case .unreadable: return S.resizeErrorUnreadable
            case .invalidSize: return S.resizeErrorInvalidSize
            case .encodeFailed: return S.resizeErrorEncode
            case .tooLargeSource: return S.resizeErrorTooLarge
            }
        }
    }
    struct SourceInfo { let pixelSize: ResizeMath.Size; let hasAlpha: Bool; let fileSize: Int }
    /// Küçültülerek çözülen yolların (boyutlandır, OCR) kaynak piksel sınırı. Tam çözen yollar daha düşük `EditRenderer.maxSourcePixels` kullanır.
    static let maxSourcePixels = 400_000_000

    /// Genişlik ve yükseklik pozitif olmalı (0×0 kaynak kabul edilmez).
    static func validSize(w: Int, h: Int) -> Bool { w > 0 && h > 0 }

    static func sourceInfo(_ url: URL) -> SourceInfo? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              var w = p[kCGImagePropertyPixelWidth] as? Int, var h = p[kCGImagePropertyPixelHeight] as? Int, validSize(w: w, h: h) else { return nil }
        if let o = p[kCGImagePropertyOrientation] as? UInt32, o >= 5 { swap(&w, &h) } // 90° döndürülmüş kaynaklar
        let alpha = (p[kCGImagePropertyHasAlpha] as? Bool) ?? false
        let fs = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        return SourceInfo(pixelSize: .init(width: w, height: h), hasAlpha: alpha, fileSize: fs)
    }

    /// Kontrollü çözme: hedefe yakın bir küçük resim istenir (çok büyük kaynaklarda tam çözme yapılmaz), yön düzeltilir.
    static func render(_ url: URL, to target: ResizeMath.Size, format: ImageOutputFormat, quality: Double, background: NSColor = .white) throws -> Data {
        guard ResizeMath.validate(target) == .ok else { throw ResizeError.invalidSize }
        guard let info = sourceInfo(url) else { throw ResizeError.unreadable }
        guard info.pixelSize.width * info.pixelSize.height <= maxSourcePixels else { throw ResizeError.tooLargeSource }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { throw ResizeError.unreadable }
        let maxSide = max(target.width, target.height)
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maxSide,
                                     kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true]
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { throw ResizeError.unreadable }
        let space = decoded.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let alpha: CGImageAlphaInfo = format == .png ? .premultipliedLast : .noneSkipLast
        guard let ctx = CGContext(data: nil, width: target.width, height: target.height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: alpha.rawValue) else { throw ResizeError.encodeFailed }
        ctx.interpolationQuality = .high
        if format == .jpeg { // JPEG saydamlık taşımaz: açıkça arka plan rengiyle düzleştir
            ctx.setFillColor(background.usingColorSpace(.sRGB)?.cgColor ?? CGColor.white); ctx.fill(CGRect(x: 0, y: 0, width: target.width, height: target.height))
        }
        ctx.draw(decoded, in: CGRect(x: 0, y: 0, width: target.width, height: target.height))
        guard let out = ctx.makeImage() else { throw ResizeError.encodeFailed }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, format.utType.identifier as CFString, 1, nil) else { throw ResizeError.encodeFailed }
        var props: [CFString: Any] = [:]
        if format == .jpeg { props[kCGImageDestinationLossyCompressionQuality] = min(max(quality, 0.05), 1.0) }
        CGImageDestinationAddImage(dest, out, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ResizeError.encodeFailed }
        return format == .png ? PNGChunkFilter.stripMetadata(data as Data) : data as Data
    }

    /// Türevler izlenen klasöre değil Shotmori'nin kendi klasörüne yazılır → izleyici döngüsü ve mükerrer kayıt olmaz.
    static var derivativesFolder: URL {
        let u = AppPaths.applicationSupport.appendingPathComponent("Türevler", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true); return u
    }
    static func derivativeURL(for source: URL, size: ResizeMath.Size, format: ImageOutputFormat, in folder: URL? = nil) -> URL {
        let base = source.deletingPathExtension().lastPathComponent
        // Ortak, test edilmiş ad üretimi: "ad 800×600.png", doluysa "ad 800×600 (2).png"… (sınırlı döngü, klasör bir kez çözülür).
        return InboundImport.uniqueDestination(for: "\(base) \(size.width)×\(size.height).\(format.ext)", in: folder ?? derivativesFolder)
    }
    static func isInside(_ url: URL, folder: URL) -> Bool { url.standardizedFileURL.path.hasPrefix(folder.standardizedFileURL.path + "/") }
}
