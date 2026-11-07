import AppKit

/// Şeridin neden indiği: kısayol (odak alır, kendiliğinden çekilmez), yeni kare, menü çubuğunda bekleme, dış yollar.
enum StripRevealReason: Equatable { case shortcut, newCapture, menuBar, external }

/// Otomatik çekilme kararının girdileri (spec §7.1, §7.4a). Denetleyici her tıkta doldurur.
struct StripRetractState: Equatable {
    var reason: StripRevealReason
    var mode: NewCaptureStripMode
    var pinned: Bool
    var pointerInside: Bool
    var dragging: Bool
    var menuOpen: Bool
    var pressing: Bool
    var quickLookOpen: Bool
    var editorOpen: Bool
    var persistentNotice: Bool
    var busy: Bool
    var secondsSinceReveal: Double
    var secondsPointerAway: Double
}

enum StripRetract {
    /// Kısayol ve iğne hiç; durduranlardan biri varsa hayır; yeni kare/dış yol "kapatana kadar"da hayır,
    /// "kısa süre"de 2,5 sn geçmiş ve imleç 0,5 sn uzaksa evet; menü çubuğu yolu yalnız imleç 0,5 sn uzaksa.
    static func shouldRetract(_ s: StripRetractState) -> Bool {
        if s.reason == .shortcut || s.pinned { return false }
        if s.pointerInside || s.dragging || s.menuOpen || s.pressing || s.quickLookOpen || s.editorOpen || s.persistentNotice || s.busy { return false }
        let away = s.secondsPointerAway >= StripMotion.retractAwayDelay
        switch s.reason {
        case .shortcut: return false
        case .newCapture, .external: return s.mode == .peek && s.secondsSinceReveal >= StripMotion.peekDuration && away
        case .menuBar: return away
        }
    }
}

/// Shotmori'nin bir penceresinin çekilme kararı için özeti (`NSApp.windows`'tan; saf kural test edilebilsin diye).
struct StripWindowSnapshot: Equatable {
    var level: Int
    var visible: Bool
    /// `NSSavePanel` / `NSOpenPanel` (Farklı kaydet, Buraya kopyala).
    var isFilePanel: Bool
    var isSheet: Bool
    var hasAttachedSheet: Bool
    /// Şeridin kendi penceresi ve yakalama uçuşu katmanları: sayılmaz.
    var excluded: Bool
}

extension StripRetract {
    /// Kipsiz bir sistem yüzeyi açık mı: paylaşım seçicisi ve menüler (katman ≥ açılır menü), dosya paneli ya da bir sayfa (sheet).
    /// Açıkken şerit kendiliğinden çekilmez; çekilse şeride demirli seçici de onunla kapanırdı (spec §7.4a).
    static func otherWindowHoldsOpen(_ windows: [StripWindowSnapshot]) -> Bool {
        windows.contains { w in
            guard w.visible, !w.excluded else { return false }
            return w.level >= NSWindow.Level.popUpMenu.rawValue || w.isFilePanel || w.isSheet || w.hasAttachedSheet
        }
    }
}
