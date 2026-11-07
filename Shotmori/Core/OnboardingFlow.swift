import Foundation

/// Kurulum akışının durum mantığı (B): altı içerik sayfası, son indeks ayrı; hayalet yedinci sayfa yok.
struct OnboardingFlow: Equatable {
    static let pageCount = 6
    static let folderPage = 1, hotKeyPage = 3, tryPage = 4
    private(set) var step = 0
    /// Yalnız klasör sayfası (erişim kaybolunca yeniden seçim): tek sayfa, baştan kurulum yok.
    let folderOnly: Bool
    init(folderOnly: Bool = false) { self.folderOnly = folderOnly; step = folderOnly ? Self.folderPage : 0 }
    var isLast: Bool { folderOnly || step == Self.pageCount - 1 }
    var isFirst: Bool { folderOnly || step == 0 }
    /// Deneme sayfasında henüz algılama yoksa "Şimdilik atla" görünür.
    func canSkip(detected: Bool) -> Bool { step == Self.tryPage && !detected }
    /// Klasör sayfası seçim olmadan geçilmez: sandbox'ta izlenecek klasörü yalnız kullanıcı verebilir.
    func canAdvance(folderChosen: Bool) -> Bool { step != Self.folderPage || folderChosen }
    /// İlerleme göstergesi: 0...5 arası dolu segment sayısı (1 tabanlı etiket için step + 1).
    var filledSegments: Int { step + 1 }
    mutating func next() { guard !folderOnly else { return }; step = min(step + 1, Self.pageCount - 1) }
    mutating func back() { guard !folderOnly else { return }; step = max(step - 1, 0) }
}
