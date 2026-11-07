import AppKit
import SwiftUI

/// Widget kartının renk rolleri: `ShotmoriStyle` (Grafit & Porselen) küçük kopyası — uzantı ana uygulamanın UI kodunu derlemez.
/// Kart düz (cam yok); tek vurgu rengi `accent` (AccentColor varlığıyla aynı mor).
enum WidgetStyle {
    private static func dyn(_ light: Int, _ dark: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { app in
            app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? rgb(dark) : rgb(light)
        })
    }
    private static func rgb(_ hex: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
    static let background = dyn(0xFFFEFA, 0x303137)  // surface
    static let tileFill = dyn(0xF7F6F3, 0x292A2F)    // window
    static let text = dyn(0x28292E, 0xF2F1F5)
    static let secondaryText = dyn(0x66656D, 0xB4B2BD)
    static let accent = dyn(0x6B54AD, 0xB9A6E8)
    static let accentFill = dyn(0xEEE8FA, 0x494059) // selectionFill: "yeni" kapsülü zemini
    static let separator = dyn(0xD8D6D2, 0x4B4B54)

    static let tileRadius: CGFloat = 10 // ShotmoriStyle.Metric.imageRadius
    static let spacing: CGFloat = 8
}
