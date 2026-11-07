import Foundation
import CoreGraphics

/// Yakalanan yerden uçuşun koşulu (spec §5.3, §5.9).
enum FlightGate {
    static func shouldFly(reduceMotion: Bool, hasCaptureRect: Bool, stripVisible: Bool, flightsInProgress: Int, hasTarget: Bool) -> Bool {
        !reduceMotion && hasCaptureRect && stripVisible && hasTarget && flightsInProgress < StripMotion.maxConcurrentFlights
    }
}

/// Yeni karede şeridin nereye ve nasıl ineceği (spec §7.1, §7.4).
enum StripPresentation {
    enum NewCaptureStep: Equatable {
        /// Yeni kare şeridi etkilemez (tercih kapalı, kurulum açık ya da tıklama sürüyor).
        case none
        /// Gizli şerit odak almadan iner, en yeni kart seçilir.
        case reveal
        /// Şerit zaten görünür: kısa gösterim süresi yeniden başlar, seçim değişmez, yalnız uçuş/varış.
        case refresh
    }

    /// Fare basılıyken gizli şerit inmez (sürükleme ya da tıklama sürerken araya girilmez, `shouldAutoShowShelf` ile aynı).
    static func newCaptureStep(enabled: Bool, onboarding: Bool, visible: Bool, mouseDown: Bool) -> NewCaptureStep {
        guard enabled, !onboarding else { return .none }
        if visible { return .refresh }
        return mouseDown ? .none : .reveal
    }

    /// Dikdörtgen merkezini içeren ekranın sırası; yoksa nil (şerit imlecin ekranına iner).
    static func screen(containing rect: CGRect?, screens: [CGRect]) -> Int? {
        guard let rect else { return nil }
        let mid = CGPoint(x: rect.midX, y: rect.midY)
        return screens.firstIndex { $0.contains(mid) }
    }
}
