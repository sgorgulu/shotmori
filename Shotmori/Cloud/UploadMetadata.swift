#if SHOTMORI_CLOUD // Bulut kodu SHOTMORI_CLOUD bayrağıyla derlenir (Debug ve Release 1.0'da açık, bkz. Features.swift); bayrak kaldırılırsa derlenmez.
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Paylaşım yüklemesi için üst veri temizliği: EXIF, GPS, TIFF, IPTC ve XMP atılır; görüntü baytları yeniden kodlanmaz.
/// PNG: yalnız görüntü için gerekli chunk'lar kalır (`PNGChunkFilter`). JPEG/HEIC/TIFF: `CGImageDestinationCopyImageSource`
/// (kayıpsız) ile boş üst veri yazılır; yönlendirme korunur. Diğer biçimler ve hata durumunda baytlar olduğu gibi döner.
/// Yalnız bellekteki kopyaya uygulanır; yerel dosya değişmez.
enum UploadMetadata {
    static func stripped(_ data: Data, fileExtension ext: String) -> Data {
        switch ext.lowercased() {
        case "png": return PNGChunkFilter.stripMetadata(data)
        case "jpg", "jpeg", "heic", "heif", "tif", "tiff": return copyWithoutMetadata(data) ?? data
        default: return data
        }
    }

    private static func copyWithoutMetadata(_ data: Data) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil), let type = CGImageSourceGetType(src), CGImageSourceGetCount(src) == 1 else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, type, 1, nil) else { return nil }
        let meta = CGImageMetadataCreateMutable()
        // Yönlendirme görüntünün parçası sayılır: atılırsa fotoğraf yan döner.
        if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any], let o = props[kCGImagePropertyOrientation] as? Int, o != 1 {
            CGImageMetadataSetValueMatchingImageProperty(meta, kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFOrientation, o as CFNumber)
        }
        let opts: [CFString: Any] = [kCGImageDestinationMetadata: meta, kCGImageDestinationMergeMetadata: false,
                                     kCGImageMetadataShouldExcludeGPS: true, kCGImageMetadataShouldExcludeXMP: true]
        var err: Unmanaged<CFError>?
        guard CGImageDestinationCopyImageSource(dest, src, opts as CFDictionary, &err) else { err?.release(); return nil }
        return out as Data
    }
}
#endif
