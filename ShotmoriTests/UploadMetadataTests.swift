#if SHOTMORI_CLOUD // Bulut kodu SHOTMORI_CLOUD bayrağıyla derlenir (Debug ve Release'te açık).
import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import Shotmori

/// Test görselleri: üst veri taşıyan küçük PNG ve JPEG.
enum PNGFixture {
    static func image() -> CGImage {
        let ctx = CGContext(data: nil, width: 4, height: 3, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 3))
        return ctx.makeImage()!
    }
    static func encode(_ type: UTType, properties: [CFString: Any] = [:]) throws -> Data {
        let out = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image(), properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return out as Data
    }
    /// IEND'den önce `tEXt` chunk'ı eklenmiş PNG (CRC doğru).
    static func withTextChunk() throws -> Data {
        let png = try encode(.png)
        let iend = png.count - 12
        let typeAndData = Data("tEXt".utf8) + Data("Comment\u{0}gizli".utf8)
        var chunk = Data(); var len = UInt32(typeAndData.count - 4).bigEndian; chunk.append(Data(bytes: &len, count: 4))
        chunk.append(typeAndData); var crc = crc32(typeAndData).bigEndian; chunk.append(Data(bytes: &crc, count: 4))
        return png.prefix(iend) + chunk + png.suffix(12)
    }
    static func crc32(_ d: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in d { c ^= UInt32(b); for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1) } }
        return c ^ 0xFFFF_FFFF
    }
}

/// SEC-05: paylaşım yüklemesinde üst veri temizliği.
final class UploadMetadataTests: XCTestCase {
    private func props(_ d: Data) -> [CFString: Any] {
        guard let s = CGImageSourceCreateWithData(d as CFData, nil) else { return [:] }
        return CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [CFString: Any] ?? [:]
    }
    func testJPEGLosesGPSAndExifButKeepsOrientation() throws {
        let gps: [CFString: Any] = [kCGImagePropertyGPSLatitude: 41.01, kCGImagePropertyGPSLatitudeRef: "N", kCGImagePropertyGPSLongitude: 28.97, kCGImagePropertyGPSLongitudeRef: "E"]
        let exif: [CFString: Any] = [kCGImagePropertyExifUserComment: "gizli not"]
        let jpeg = try PNGFixture.encode(.jpeg, properties: [kCGImagePropertyGPSDictionary: gps, kCGImagePropertyExifDictionary: exif, kCGImagePropertyOrientation: 6])
        XCTAssertNotNil(props(jpeg)[kCGImagePropertyGPSDictionary], "fikstür GPS taşımalı")
        let out = UploadMetadata.stripped(jpeg, fileExtension: "JPG")
        let p = props(out)
        XCTAssertNil(p[kCGImagePropertyGPSDictionary], "GPS atılır")
        XCTAssertNil((p[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifUserComment], "EXIF yorumu atılır")
        XCTAssertEqual(p[kCGImagePropertyOrientation] as? Int, 6, "yönlendirme korunur")
        XCTAssertEqual(p[kCGImagePropertyPixelWidth] as? Int, 4)
    }
    func testPNGDropsTextChunks() throws {
        let png = try PNGFixture.withTextChunk()
        let out = UploadMetadata.stripped(png, fileExtension: "png")
        XCTAssertFalse(PNGChunkFilter.chunkTypes(out).contains("tEXt")); XCTAssertTrue(PNGChunkFilter.chunkTypes(out).contains("IDAT"))
    }
    func testUnknownFormatIsUnchanged() {
        let d = Data([1, 2, 3])
        XCTAssertEqual(UploadMetadata.stripped(d, fileExtension: "pdf"), d)
        XCTAssertEqual(UploadMetadata.stripped(d, fileExtension: "jpg"), d, "çözülemeyen bayt olduğu gibi")
    }
}
#endif
