import Foundation
import CoreGraphics

// Uyarlama: Tendedero/ClipBoardLine LineLayout.swift, MIT, © 2026 Alejandro Buján

/// Üst şeridin saf yerleşim hesabı: ip eğrisi, kart konumu, görünür aralık, kart boyutu.
enum StripLayout {
    static let ropeTop: CGFloat = 32
    static let pinAbove: CGFloat = 9.5
    static let edgePadding: CGFloat = 24
    static let cardWidth: CGFloat = 150
    static let photoMaxHeight: CGFloat = 104
    static let cardGap: CGFloat = 24
    static let frameInset: CGFloat = 4
    static let frameRadius: CGFloat = 16
    static let clipSize = CGSize(width: 9, height: 26)
    static let clipOverlap: CGFloat = 12

    static var stripHeight: CGFloat { 202 }
    private static var spacing: CGFloat { cardWidth + cardGap }

    static func sag(width: CGFloat) -> CGFloat { min(30, width * 0.018) }

    static func ropeY(x: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0 else { return ropeTop }
        let f = max(0, min(1, x / width))
        return ropeTop + 4 * sag(width: width) * f * (1 - f)
    }

    static func x(index: Int, scrollOffset: CGFloat) -> CGFloat {
        edgePadding + cardWidth / 2 + CGFloat(index) * spacing - scrollOffset
    }

    static func contentWidth(count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return edgePadding * 2 + cardWidth + CGFloat(count - 1) * spacing
    }

    static func maximumOffset(count: Int, width: CGFloat) -> CGFloat {
        max(0, contentWidth(count: count) - max(1, width))
    }

    /// ±1 kartlık tampon: girmekte olan kartlar hazır, ekran dışı kartlar kurulmaz.
    static func visibleRange(count: Int, width: CGFloat, offset: CGFloat) -> Range<Int> {
        guard count > 0 else { return 0..<0 }
        let off = max(0, offset)
        let first = max(0, Int(floor(off / spacing)) - 1)
        let last = min(count, Int(ceil((off + max(1, width)) / spacing)) + 1)
        return min(first, last)..<last
    }

    /// En çok (cardWidth − 14) × photoMaxHeight, oran korunur.
    static func photoSize(for image: CGSize) -> CGSize {
        let maxW = cardWidth - 14, maxH = photoMaxHeight
        guard image.width > 0, image.height > 0 else { return CGSize(width: maxW, height: maxH) }
        let scale = min(maxW / image.width, maxH / image.height)
        return CGSize(width: (image.width * scale).rounded(), height: (image.height * scale).rounded())
    }

    static func cardSize(for image: CGSize) -> CGSize {
        let p = photoSize(for: image)
        return CGSize(width: p.width + 2 * frameInset, height: p.height + 2 * frameInset)
    }

    /// Kimlikten kararlı eğim, −2.5…2.5 derece.
    static func tilt(for id: UUID) -> Double {
        let b = id.uuid
        let n = (UInt32(b.0) << 24) | (UInt32(b.1) << 16) | (UInt32(b.2) << 8) | UInt32(b.3)
        let unit = Double(n) / Double(UInt32.max)
        return (unit * 2 - 1) * 2.5
    }
}
