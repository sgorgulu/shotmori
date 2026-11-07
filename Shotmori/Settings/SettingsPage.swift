import AppKit

/// Ayarlar kenar çubuğu sayfaları (Sistem Ayarları deseni: renkli ikon karesi + ad).
enum SettingsPage: String, CaseIterable, Identifiable {
    case general, shelf, actions, cloud, about
    var id: Self { self }

    var title: String {
        switch self {
        case .general: return S.tabGeneral
        case .shelf: return S.tabShelf
        case .actions: return S.tabQuickActions
        case .cloud:
            #if SHOTMORI_CLOUD
            return S.tabCloud
            #else
            return ""
            #endif
        case .about: return S.settingsAbout
        }
    }
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .shelf: return "tray.full"
        case .actions: return "bolt.fill"
        case .cloud: return "icloud.fill"
        case .about: return "info"
        }
    }
    /// İkon karesinin dolgusu: sistem tonları; raf = vurgu.
    var tint: NSColor {
        switch self {
        case .general: return .systemGray
        case .shelf: return ShotmoriStyle.accent
        case .actions: return .systemOrange
        case .cloud: return .systemBlue
        case .about: return .systemGray
        }
    }
    /// Bu derlemede görünen sayfalar: Bulut yalnız bulutlu derlemede ve bayrak açıkken.
    static var available: [SettingsPage] {
        allCases.filter { p in
            guard p == .cloud else { return true }
            #if SHOTMORI_CLOUD
            return Features.cloud
            #else
            return false
            #endif
        }
    }
}
