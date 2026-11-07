import Foundation
import AppKit

// B adımı: panel davranışının test edilebilir çekirdeği (görünümden bağımsız).

/// Panel durum mesajları: rutin başarı süreli; hata ve boş sonuç kalıcı (kapatılana veya sonraki işleme kadar);
/// meşgul (OCR) durumu aynı işlemin yeniden tetiklenmesini engeller.
/// Her mesajın kendi kimliği var: aynı metin art arda gösterilince ilk mesajın zamanlayıcısı ikincisini erken kapatmaz.
struct StatusMessage: Equatable {
    enum Kind: Equatable { case success, persistent, busy }
    let id = UUID()
    var text: String
    var kind: Kind
}
struct StatusCenter: Equatable {
    private(set) var current: StatusMessage?
    var isBusy: Bool { current?.kind == .busy }
    var isPersistent: Bool { current?.kind == .persistent }
    mutating func show(_ m: StatusMessage) { current = m }
    mutating func dismiss() { current = nil }
    /// Yeni bir işlem başlamadan önce: kalıcı mesaj yenilenebilir (kaldırılır), meşgul mesajı korunur.
    mutating func actionWillRun() { if isPersistent { current = nil } }
    mutating func busyEnded() { if isBusy { current = nil } }
    /// Rutin başarı 1,6 s sonra kaybolur; kalıcı ve meşgul mesajlar kendiliğinden kaybolmaz.
    static func autoDismissDelay(_ k: StatusMessage.Kind) -> TimeInterval? { k == .success ? 1.6 : nil }
}

/// Favori çubuğu taşması: öncü favoriler sığdığı kadar görünür, kalanı aynı sırayla İşlemler menüsüne taşar.
/// Favori listesi ve sırası hiçbir zaman değiştirilmez.
enum FavoritesLayout {
    /// `widths`: favori düğme genişlikleri (sırayla); `reserved`: sağdaki İşlemler düğmesi + aralığı.
    static func visibleCount(widths: [CGFloat], available: CGFloat, spacing: CGFloat, reserved: CGFloat) -> Int {
        var used: CGFloat = reserved, n = 0
        for w in widths {
            let need = (n == 0 ? 0 : spacing) + w
            if used + need > available { break }
            used += need; n += 1
        }
        return n
    }
}

// Raf klavyesi: Core/ShelfKeyboard (panel ve üst şerit ortak).

/// VoiceOver duyuruları (seçim sayısı, hata, başarı). Sistem ayarı değiştirilmez; duyuru yoksa sessizce geçer.
enum AXAnnounce {
    static func post(_ text: String, high: Bool = false) {
        guard !text.isEmpty else { return }
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: (high ? NSAccessibilityPriorityLevel.high : .medium).rawValue])
    }
}
