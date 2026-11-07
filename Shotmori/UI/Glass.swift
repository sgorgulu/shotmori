// Kaynak: gomin2013/swiftui-mac-skills (MIT) — adopting-liquid-glass/Glass.swift; Shotmori için uyarlandı:
// yalnız kullanılan `glassButton` tutuldu (`glassSurface`/`glassGroup` kaldırıldı; cam kontrol yüzeyi AppKit `GlassSurfaceView`).
import SwiftUI

// Liquid Glass (macOS 26) with a material fallback (macOS 14–15).
// `#if compiler(>=6.2)` keeps this compiling on toolchains whose SDK has no glass API at all;
// `#available` picks the look at run time.

extension View {
    /// `.glassProminent` / `.glass` on macOS 26, `.borderedProminent` / `.bordered` before.
    /// Prominent dolgu `smAccentFill` (koyu modda koyu mor): sistemin beyaz yazısı her iki temada ≥ 4,5:1 okunur.
    /// Prominent düğme pencere etkin değilken de etkin görünümünde çizilir (`controlActiveState = .key`): sistem aksi hâlde
    /// dolguyu kaldırıp açık gri yazıyla bırakıyor (beyaz zeminde ~1,9:1); vurgu dolgusu + beyaz yazı her durumda okunur kalır.
    @ViewBuilder
    func glassButton(prominent: Bool = false) -> some View {
        if prominent { glassButtonStyle(prominent: true).environment(\.controlActiveState, .key) } else { glassButtonStyle(prominent: false) }
    }
    @ViewBuilder
    private func glassButtonStyle(prominent: Bool) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            // Only the primary action carries the accent; plain glass stays neutral (HIG: colour the key action only)
            if prominent { buttonStyle(.glassProminent).tint(.smAccentFill) } else { buttonStyle(.glass).tint(nil) }
        } else {
            if prominent { buttonStyle(.borderedProminent).tint(.smAccentFill) } else { buttonStyle(.bordered) }
        }
        #else
        if prominent { buttonStyle(.borderedProminent).tint(.smAccentFill) } else { buttonStyle(.bordered) }
        #endif
    }
}
