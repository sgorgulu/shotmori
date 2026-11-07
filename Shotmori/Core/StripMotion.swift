import Foundation
import CoreGraphics

/// Üst şerit hareket sabitleri (spec §5). 300 ms sınırı bu yüzeyde bilinçli istisnadır.
enum StripMotion {
    struct TimingPoints {
        let c1x: Double, c1y: Double, c2x: Double, c2y: Double
    }

    static let revealDuration = 0.42, retractDuration = 0.22
    static let revealTiming = TimingPoints(c1x: 0.2, c1y: 1.12, c2x: 0.3, c2y: 1.0)
    static let retractTiming = TimingPoints(c1x: 0.4, c1y: 0.0, c2x: 1.0, c2y: 1.0)

    static func hiddenOffset(stripHeight: CGFloat) -> CGFloat { -(stripHeight + 12) }

    static let flightDuration = 0.65, flightArc: CGFloat = 30, flightFadeOut = 0.16, maxConcurrentFlights = 2
    static let fallDuration = 0.55, fallDistance: CGFloat = 520, fallRemoveDelay = 0.6
    /// Varış: kart `arrivalDrop` pt yukarıdan yayla (`arrivalDropResponse`/`arrivalDropDamping`) iner, `arrivalSwing` derecelik
    /// salınım az sönümlü yayla (`arrivalSwingStiffness`/`arrivalSwingDamping`) durulur.
    static let arrivalDrop: CGFloat = 46, arrivalSwing = 16.0
    static let arrivalDropResponse = 0.42, arrivalDropDamping = 0.72
    static let arrivalSwingStiffness = 46.0, arrivalSwingDamping = 2.6
    static let landNudge = 2.2, copyNudge = 3.0, copyBadgeDuration = 1.2
    static let gustInterval = 7.0...16.0, gustJitter = 0.0...0.35, gustNudge = 1.6...3.4
    /// İmleç bu kadar süre şeride uğramazsa (iğneli / açık kalan şerit boşta) esinti durur; imleç dönünce yeniden başlar.
    static let gustIdleLimit: TimeInterval = 60
    /// Dürtme: `nudgeOut` sn ease-out, sonra yaylı (`nudgeStiffness`/`nudgeDamping`) salınımla 0'a.
    static let nudgeOut = 0.3, nudgeStiffness = 38.0, nudgeDamping = 2.4
    static let hoverScale = 1.035, pressScale = 0.95, pressDuration = 0.45, hoverDuration = 0.18, dragOpacity = 0.45
    static let peekDuration = 2.5, retractAwayDelay = 0.5, menuBarDwell = 0.25, hideAfterDropDelay = 0.35

    /// easeInOutCubic
    static func flightProgress(_ t: Double) -> Double {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    static func fallProgress(_ t: Double) -> Double { t * t * t }

    static func fallAngle(tilt: Double, e: Double) -> Double { tilt + (tilt * 7 + 20) * e }

    static func duration(_ d: Double, reduceMotion: Bool) -> Double { reduceMotion ? 0 : d }
}
