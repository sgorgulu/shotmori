import Foundation
import CoreGraphics

// Uyarlama: Tendedero/ClipBoardLine CaptureFlight.swift captureRect(of:), MIT, © 2026 Alejandro Buján

/// macOS'un ekran görüntüsüne yazdığı yakalama dikdörtgeni (xattr) okuma.
enum CaptureRect {
    static let xattr = "com.apple.metadata:kMDItemScreenCaptureGlobalRect"

    /// Kabul edilen en büyük koordinat/boyut (pt): gerçek ekran düzenlerinin çok üstünde; aşırı ya da sonsuz değer
    /// sonraki `Int` dönüşümlerini çökertmesin (xattr dosyayla taşınabilir, güvenilir kaynak değildir).
    static let maxMagnitude: CGFloat = 100_000

    /// İkili plist `[x, y, w, h]` (sol üst köken) → AppKit ekran koordinatı. Sonlu olmayan ya da `maxMagnitude`'u aşan değer → nil.
    static func parse(_ plist: Data, mainScreenMaxY: CGFloat) -> CGRect? {
        guard let values = try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [NSNumber],
              values.count == 4 else { return nil }
        let x = CGFloat(truncating: values[0]), y = CGFloat(truncating: values[1])
        let w = CGFloat(truncating: values[2]), h = CGFloat(truncating: values[3])
        guard [x, y, w, h].allSatisfy({ $0.isFinite && abs($0) <= maxMagnitude }), w > 2, h > 2 else { return nil }
        return CGRect(x: x, y: mainScreenMaxY - y - h, width: w, height: h)
    }

    static func read(_ url: URL, mainScreenMaxY: CGFloat) -> CGRect? {
        let data: Data? = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return nil }
            let size = getxattr(path, xattr, nil, 0, 0, 0)
            guard size > 0 else { return nil }
            var buffer = Data(count: size)
            let got = buffer.withUnsafeMutableBytes { getxattr(path, xattr, $0.baseAddress, size, 0, 0) }
            return got == size ? buffer : nil
        }
        guard let data else { return nil }
        return parse(data, mainScreenMaxY: mainScreenMaxY)
    }
}
