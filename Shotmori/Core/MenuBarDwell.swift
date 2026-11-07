import Foundation
import CoreGraphics

/// Menü çubuğunda bekleme (spec §7.1, "ClipBoardLine gibi"): imleç bir ekranın menü çubuğu bandında
/// `StripMotion.menuBarDwell` (0,25 sn) kesintisiz durunca bir kez tetikler. Tetikledikten ya da menü çubuğuna
/// tıklandıktan sonra imleç banttan çıkana dek yeniden tetiklemez (açılan menünün üstüne inmemek için).
struct MenuBarDwell: Equatable {
    private(set) var since: Date?
    private(set) var suppressed = false

    /// Her tikte: imleç menü çubuğu bandında mı. Bant içinde 0,25 sn kesintisiz → true (bir kez). Bant dışı → since=nil, suppressed=false.
    mutating func tick(inMenuBar: Bool, now: Date) -> Bool {
        guard inMenuBar else { since = nil; suppressed = false; return false }
        guard !suppressed else { return false }
        guard let start = since else { since = now; return false }
        guard now.timeIntervalSince(start) >= StripMotion.menuBarDwell else { return false }
        since = nil; suppressed = true // bir kez: banttan çıkana dek
        return true
    }

    mutating func menuBarClicked() { suppressed = true; since = nil }
}

/// Bir ekranın menü çubuğu bandı: çerçevenin tepesinden görünür alanın tepesine, tam genişlikte.
/// Menü çubuğu gizliyse (otomatik gizleme, menü çubuğu olmayan ekran) durum çubuğu kalınlığında bant.
enum MenuBarBand {
    static func rect(screenFrame: CGRect, visibleFrame: CGRect, statusBarThickness: CGFloat) -> CGRect {
        let measured = screenFrame.maxY - visibleFrame.maxY
        let height = measured < 1 ? statusBarThickness : measured
        return CGRect(x: screenFrame.minX, y: screenFrame.maxY - height, width: screenFrame.width, height: height)
    }
}
