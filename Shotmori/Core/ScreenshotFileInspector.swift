import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Bir dosyanın "tamamlanmış sistem ekran görüntüsü" olup olmadığına karar veren saf mantık (test edilebilir).
/// D1 deneyi: macOS `..Ad.png-XXXX` → `.Ad.png` → `Ad.png` yazar; son yeniden adlandırmada
/// `com.apple.metadata:kMDItemIsScreenCapture` xattr'ı hazırdır.
enum ScreenshotFileInspector {
    static let markerXattr = "com.apple.metadata:kMDItemIsScreenCapture"
    static let imageExtensions: Set<String> = ImageFormats.extensions

    /// Gizli/geçici adlar (nokta ile başlar, `-XXXXXX` eki taşır) elenir.
    static func isCandidateFileName(_ name: String) -> Bool {
        guard !name.hasPrefix(".") else { return false }
        let ext = (name as NSString).pathExtension.lowercased()
        return imageExtensions.contains(ext)
    }
    static func hasScreenCaptureMarker(_ url: URL) -> Bool {
        getxattr(url.path, markerXattr, nil, 0, 0, 0) >= 0
    }
    /// Görsel tam yazılmış mı? Dosya tabanlı ImageIO kaynakları yarım dosyada da "complete" döndürür;
    /// bu yüzden PNG için IEND, JPEG için FFD9 sonlandırıcısı aranır, diğer biçimlerde kod çözme denenir.
    static func isCompleteImage(_ url: URL) -> Bool {
        guard let fh = FileHandle(forReadingAtPath: url.path) else { return false }
        defer { try? fh.close() }
        // Yarış: dosya okurken kısalabilir/silinebilir; `readData` ObjC istisnası atar, `read(upToCount:)` hata fırlatır → false.
        let head: Data, tail: [UInt8]
        do {
            let size = try fh.seekToEnd()
            guard size > 16 else { return false }
            try fh.seek(toOffset: 0)
            head = try fh.read(upToCount: 4) ?? Data()
            try fh.seek(toOffset: size - 12)
            tail = [UInt8](try fh.read(upToCount: 12) ?? Data())
        } catch { return false }
        if head == Data([0x89, 0x50, 0x4E, 0x47]) {
            return tail.count == 12 && Array(tail[4..<12]) == [0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82] // IEND + CRC
        }
        if head.prefix(2) == Data([0xFF, 0xD8]) {
            return tail.suffix(2) == [0xFF, 0xD9]
        }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(src) > 0 else { return false }
        return CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCache: false] as CFDictionary) != nil
    }
    static func fileIdentifier(_ url: URL) -> String? {
        var st = stat()
        guard stat(url.path, &st) == 0 else { return nil }
        return "\(st.st_dev):\(st.st_ino)"
    }
    static func creationDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate)
    }
}
