import AppKit
import QuartzCore

// Uyarlama: Tendedero/ClipBoardLine CaptureFlight.swift, MIT, © 2026 Alejandro Buján
// Fark: cam çerçeve ve kenar katmanları yerine kartla aynı opak çerçeve (`ShotmoriStyle.elevated` + ayırıcı ince kenar);
// kart ve uçuş katmanı asla cam değildir. Süre, yay ve düşme değerleri `StripMotion`dan, mandal `StripClipStyle`dan.
// Fark: örnek başına pencere ve zamanlayıcı yerine ekran başına tek paylaşılan katman penceresi ve tek 120 Hz zamanlayıcı.

/// Yakalanan kare ekrandan kalkıp ipteki kartına uçar; yolda karta dönüşür (küçülür, eğilir, çerçevesi ve mandalı belirir),
/// inişte değişecek bir şey kalmaz. Raftan kaldırılan kart da aynı katmanla ipten düşer (spec §5.3, §5.7).
/// Tüm ekranı kaplayan, tıklama almayan, `floating + 1` seviyeli, odak almayan panelde çizilir; şeridin penceresi kesmez.
/// Aynı ekrandaki tüm uçuş ve düşmeler tek pencerede (`Overlay`) ayrı katmanlardır; hepsini tek zamanlayıcı ilerletir.
/// Pencere son hareket bitince kapanır (boşta ekran boyutunda arka bellek tutulmaz).
@MainActor
final class CaptureFlight {
    /// Uçuş katmanı şeridin (`.floating`) hemen üstünde.
    static let windowLevel = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)

    /// Bir ekranın paylaşılan katman penceresi; kullanan hareket kalmayınca kapanır.
    @MainActor private final class Overlay {
        let window: NSPanel
        let host: NSView
        let frame: CGRect
        var users = 0

        init(screen: NSScreen) {
            frame = screen.frame
            window = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            window.animationBehavior = .none
            window.level = CaptureFlight.windowLevel
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            window.setAccessibilityElement(false)
            window.setFrame(screen.frame, display: false)
            host = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            host.wantsLayer = true
            window.contentView = host
        }
    }

    private static var overlays: [Overlay] = []
    private static var ticker: Timer?
    private static var current: [CaptureFlight] = []

    private let overlay: Overlay
    private let container = CALayer()
    private let frameLayer = CALayer()
    private let photo = CALayer()
    private let clip = CALayer()

    private let from: CGRect
    private let to: CGRect
    private let tilt: CGFloat
    private var falling = false
    private var duration: CFTimeInterval = StripMotion.flightDuration
    private var start: CFTimeInterval = 0
    private var completion: () -> Void = {}

    /// Şu an ipe uçan kareler. Her biri büyük bir görüntü tutar; art arda çekimlerde yalnız ikisi uçar, kalanı varışla gelir.
    static var flightsInProgress: Int { current.filter { !$0.falling }.count }
    /// Açık katman penceresi sayısı (ekran başına en çok bir; test ve tanılama için).
    static var overlayWindowCount: Int { overlays.count }

    /// - Parameters:
    ///   - from: yakalanan alan, ekran koordinatı.
    ///   - to: kartın ipteki çerçevesi, ekran koordinatı, eğimsiz.
    ///   - tilt: kartın dinlenme eğimi (derece, saat yönü; SwiftUI ile aynı).
    static func fly(image: CGImage, from: CGRect, to: CGRect, tilt: Double, on screen: NSScreen, completion: @escaping () -> Void) {
        let flight = CaptureFlight(image: image, from: from, to: to, tilt: CGFloat(tilt), screen: screen)
        current.append(flight)
        flight.completion = { [weak flight] in
            completion()
            current.removeAll { $0 === flight }
        }
        flight.run()
    }

    /// Kaldırılan kart ipten düşer: 520 pt aşağı, eğim artarak, sönerek, 0,55 sn `t³`. Tüm ekranda çizilir, şerit kesmez.
    static func fall(image: CGImage, card: CGRect, tilt: Double, on screen: NSScreen) {
        let flight = CaptureFlight(image: image, from: card, to: card, tilt: CGFloat(tilt), screen: screen)
        flight.falling = true
        flight.duration = StripMotion.fallDuration
        current.append(flight)
        flight.completion = { [weak flight] in current.removeAll { $0 === flight } }
        flight.run()
    }

    private static func overlay(for screen: NSScreen) -> Overlay {
        if let o = overlays.first(where: { $0.frame == screen.frame }) { return o }
        let o = Overlay(screen: screen)
        overlays.append(o)
        return o
    }

    private static func release(_ o: Overlay) {
        o.users -= 1
        guard o.users <= 0 else { return }
        o.window.orderOut(nil)
        overlays.removeAll { $0 === o }
    }

    private init(image: CGImage, from: CGRect, to: CGRect, tilt: CGFloat, screen: NSScreen) {
        self.from = from
        self.to = to
        self.tilt = tilt
        overlay = Self.overlay(for: screen)
        let scale = screen.backingScaleFactor

        // Kartın görünümüyle aynı (`StripCardView.card`): opak çerçeve, ince ayırıcı kenar, yumuşak gölge.
        container.anchorPoint = CGPoint(x: 0.5, y: 1) // kartın üst ortası (mandal noktası)
        container.shadowColor = NSColor.black.cgColor
        container.shadowOpacity = 0.18
        container.shadowRadius = 10
        container.shadowOffset = CGSize(width: 0, height: -5)

        frameLayer.backgroundColor = Self.resolved(ShotmoriStyle.elevated)
        frameLayer.borderColor = Self.resolved(ShotmoriStyle.separator)
        frameLayer.borderWidth = ShotmoriStyle.increaseContrast ? 1.5 : 1

        photo.contents = image
        photo.contentsGravity = .resizeAspectFill
        photo.masksToBounds = true

        Self.buildClip(clip, scale: scale)

        for layer in [container, frameLayer, photo, clip] as [CALayer] { layer.contentsScale = scale }
        container.addSublayer(frameLayer)
        container.addSublayer(photo)
        container.addSublayer(clip)
    }

    /// Mandal (`StripClip` ile aynı `StripClipStyle` değerleri): fırçalanmış metal, üstten alta degrade kenar, ipin yarığı, gölge.
    /// Katman koordinatı alttan yukarı (macOS): "üst" = maxY.
    private static func buildClip(_ clip: CALayer, scale: CGFloat) {
        let bounds = CGRect(origin: .zero, size: StripLayout.clipSize)
        let r = StripClipStyle.cornerRadius
        clip.bounds = bounds
        clip.shadowColor = NSColor.black.cgColor
        clip.shadowOpacity = Float(StripClipStyle.shadowOpacity)
        clip.shadowRadius = StripClipStyle.shadowRadius
        clip.shadowOffset = CGSize(width: 0, height: -StripClipStyle.shadowOffsetY)
        clip.shadowPath = CGPath(roundedRect: bounds, cornerWidth: r, cornerHeight: r, transform: nil)

        let metal = CAGradientLayer()
        metal.frame = bounds
        metal.colors = StripClipStyle.metal.map { NSColor(white: $0.white, alpha: 1).cgColor }
        metal.locations = StripClipStyle.metal.map { NSNumber(value: Double($0.location)) }
        metal.startPoint = CGPoint(x: 0, y: 0.5); metal.endPoint = CGPoint(x: 1, y: 0.5)
        metal.cornerRadius = r
        metal.cornerCurve = .continuous
        metal.masksToBounds = true

        let edge = CAGradientLayer()
        edge.frame = bounds
        edge.colors = [NSColor(white: StripClipStyle.edgeTop.white, alpha: StripClipStyle.edgeTop.alpha).cgColor,
                       NSColor(white: StripClipStyle.edgeBottom.white, alpha: StripClipStyle.edgeBottom.alpha).cgColor]
        edge.startPoint = CGPoint(x: 0.5, y: 1); edge.endPoint = CGPoint(x: 0.5, y: 0)
        let stroke = CAShapeLayer()
        stroke.path = CGPath(roundedRect: bounds.insetBy(dx: StripClipStyle.edgeWidth / 2, dy: StripClipStyle.edgeWidth / 2),
                             cornerWidth: r, cornerHeight: r, transform: nil)
        stroke.fillColor = nil
        stroke.strokeColor = NSColor.black.cgColor
        stroke.lineWidth = StripClipStyle.edgeWidth
        edge.mask = stroke

        let slit = CALayer()
        let s = StripClipStyle.slitSize
        slit.frame = CGRect(x: (bounds.width - s.width) / 2, y: bounds.height - StripClipStyle.slitTop - s.height, width: s.width, height: s.height)
        slit.cornerRadius = s.height / 2
        slit.backgroundColor = NSColor(white: 0, alpha: StripClipStyle.slitOpacity).cgColor

        for l in [metal, edge, stroke, slit] as [CALayer] { l.contentsScale = scale }
        clip.addSublayer(metal)
        clip.addSublayer(edge)
        clip.addSublayer(slit)
    }

    /// Dinamik renk, uygulamanın görünümüne (açık/koyu) göre çözülür.
    private static func resolved(_ color: NSColor) -> CGColor {
        var out = color.cgColor
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance { out = color.cgColor }
        return out
    }

    private func run() {
        overlay.users += 1
        overlay.host.layer?.addSublayer(container)
        if falling { update(1); updateFall(0) } else { update(0) }
        if !overlay.window.isVisible { overlay.window.orderFrontRegardless() }
        start = CACurrentMediaTime()
        Self.startTicker()
    }

    private static func startTicker() {
        guard ticker == nil else { return }
        let t = Timer(timeInterval: 1.0 / 120.0, repeats: true) { _ in
            MainActor.assumeIsolated { CaptureFlight.tickAll() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    /// Tek zamanlayıcı tüm süren hareketleri ilerletir; kalmayınca durur.
    private static func tickAll() {
        let now = CACurrentMediaTime()
        for f in current { f.tick(now: now) }
        if current.isEmpty { ticker?.invalidate(); ticker = nil }
    }

    private func tick(now: CFTimeInterval) {
        let k = min(1, (now - start) / duration)
        if falling { updateFall(k) } else { update(k) }
        guard k >= 1 else { return }
        completion() // `current`dan çıkar
        let overlay = overlay, container = container
        if falling {
            container.removeFromSuperlayer()
            Self.release(overlay)
            return
        }
        // Gerçek kart altında anında belirir; bu katman üstünde söner (spec §5.3).
        CATransaction.begin()
        CATransaction.setAnimationDuration(StripMotion.flightFadeOut)
        CATransaction.setCompletionBlock {
            MainActor.assumeIsolated {
                container.removeFromSuperlayer()
                CaptureFlight.release(overlay)
            }
        }
        container.opacity = 0
        CATransaction.commit()
    }

    private func updateFall(_ raw: Double) {
        let e = CGFloat(StripMotion.fallProgress(raw))
        let origin = overlay.frame.origin
        let angle = CGFloat(StripMotion.fallAngle(tilt: Double(tilt), e: Double(e)))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.position = CGPoint(x: to.midX - origin.x, y: to.maxY - origin.y - StripMotion.fallDistance * e)
        container.setAffineTransform(CGAffineTransform(rotationAngle: -angle * .pi / 180))
        container.opacity = Float(1 - e)
        CATransaction.commit()
    }

    private static func smooth(_ x: Double, _ a: Double, _ b: Double) -> Double {
        let t = max(0, min(1, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    private func update(_ raw: Double) {
        let k = CGFloat(StripMotion.flightProgress(raw))
        let chrome = Float(Self.smooth(Double(k), 0.35, 1))
        let origin = overlay.frame.origin
        func lerp(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * k }

        let w = lerp(from.width, to.width), h = lerp(from.height, to.height)
        let topX = lerp(from.midX, to.midX) - origin.x
        let topY = lerp(from.maxY, to.maxY) - origin.y + sin(.pi * k) * StripMotion.flightArc
        let inset = StripLayout.frameInset * k
        let radius = lerp(0, StripLayout.frameRadius)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        container.position = CGPoint(x: topX, y: topY)
        // SwiftUI pozitif açıyı saat yönünde döndürür; Core Animation tersine.
        container.setAffineTransform(CGAffineTransform(rotationAngle: -tilt * .pi / 180 * k))
        container.shadowPath = CGPath(roundedRect: container.bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)

        frameLayer.frame = container.bounds
        frameLayer.cornerRadius = radius
        frameLayer.cornerCurve = .continuous
        frameLayer.opacity = chrome
        photo.frame = container.bounds.insetBy(dx: inset, dy: inset)
        photo.cornerRadius = max(0, radius - inset)
        photo.cornerCurve = .continuous
        // Mandal üst kenarı tutar: 26 pt yüksek, 12 pt'si kartın üstünde.
        clip.frame = CGRect(x: w / 2 - StripLayout.clipSize.width / 2, y: h - StripLayout.clipOverlap,
                            width: StripLayout.clipSize.width, height: StripLayout.clipSize.height)
        clip.opacity = chrome
        CATransaction.commit()
    }
}
