import AppKit
import Quartz
import QuartzCore

// Uyarlama: Tendedero/ClipBoardLine LinePanel.swift, MIT, © 2026 Alejandro Buján

private final class StripCompositorView: NSView {
    override var isFlipped: Bool { true }
}

/// Ekranın üstünde tam genişlikte saydam pencere. İniş/çekiliş yalnız compositor katmanının
/// `sublayerTransform` Y değeriyle animasyonlanır; pencere ve SwiftUI geometrisi sabit kalır.
/// Tıklamalar yalnız isabet dikdörtgenlerinde yakalanır, başka yerde alttaki uygulamaya geçer.
final class StripPanel: NSPanel {
    static let animationKey = "stripRevealTranslation"

    private let reduceMotion: () -> Bool
    private let compositor = StripCompositorView()
    private var generation = 0
    private var revealed = false
    private var stripHeight = StripLayout.stripHeight

    var keyboardFocusAllowed = false
    var onKey: ((NSEvent) -> Bool)?
    var onScroll: ((CGFloat, CGFloat, Bool) -> Void)?
    private(set) var isTransitioning = false

    /// Pencere içeriği (üstten aşağı, düz) koordinatında isabet alanları.
    var hitRects: [CGRect] = []

    var compositorLayer: CALayer? { compositor.layer }
    private var hiddenOffset: CGFloat { StripMotion.hiddenOffset(stripHeight: stripHeight) }
    private var presentationOffset: CGFloat {
        compositor.layer?.presentation()?.sublayerTransform.m42 ?? compositor.layer?.sublayerTransform.m42 ?? 0
    }

    init(content: NSView, reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }) {
        self.reduceMotion = reduceMotion
        super.init(contentRect: NSRect(x: 0, y: 0, width: 800, height: StripLayout.stripHeight),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isMovable = false
        becomesKeyOnlyIfNeeded = true
        ignoresMouseEvents = true
        // Menü çubuğu uygulaması çoğu zaman etkin değildir: kapsül düğmelerinin ve ✕'in araç ipuçları yine görünsün.
        allowsToolTipsWhenApplicationIsInactive = true
        compositor.frame = NSRect(x: 0, y: 0, width: 800, height: StripLayout.stripHeight)
        compositor.wantsLayer = true
        compositor.layer?.isGeometryFlipped = true
        content.frame = compositor.bounds
        content.autoresizingMask = [.width, .height]
        compositor.addSubview(content)
        contentView = compositor
        setOffset(hiddenOffset)
    }

    override var canBecomeKey: Bool { keyboardFocusAllowed }
    override var canBecomeMain: Bool { false }

    /// ⌘ kısayolları (⌘C/⌘A/⌘K/⌘W/⌘1…⌘8) ana menüden önce şeride gider.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if keyboardFocusAllowed, event.modifierFlags.contains(.command), onKey?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
    /// Quick Look key iken iletilen tuşlar (`ShelfQuickLook.previewPanel(_:handle:)`) buraya gelir.
    override func keyDown(with event: NSEvent) {
        if keyboardFocusAllowed, onKey?(event) == true { return }
        super.keyDown(with: event)
    }
    // MARK: Quick Look: şerit key iken sorumlu zincirinde önizleme denetleyicisi olur (uygulama etkinleştirilmez).
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) { ShelfQuickLook.shared.begin(panel) }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { ShelfQuickLook.shared.end(panel) }

    override func sendEvent(_ event: NSEvent) {
        if isTransitioning, [.leftMouseDown, .leftMouseUp, .leftMouseDragged,
                             .rightMouseDown, .rightMouseUp, .rightMouseDragged,
                             .otherMouseDown, .otherMouseUp, .otherMouseDragged,
                             .scrollWheel].contains(event.type) { return }
        if event.type == .keyDown, keyboardFocusAllowed, onKey?(event) == true { return }
        if event.type == .scrollWheel, let onScroll {
            onScroll(event.scrollingDeltaX, event.scrollingDeltaY, event.hasPreciseScrollingDeltas)
            return
        }
        super.sendEvent(event)
    }

    /// Fare konumuna (ekran koordinatı) göre geçirgenliği günceller; geçiş sırasında hep geçirgen.
    func updatePassThrough(mouseLocation: NSPoint = NSEvent.mouseLocation) {
        guard revealed, !isTransitioning else { ignoresMouseEvents = true; return }
        let window = convertPoint(fromScreen: mouseLocation)
        let local = CGPoint(x: window.x, y: frame.height - window.y)
        ignoresMouseEvents = !StripHitTest.accepts(local, rects: hitRects)
    }

    /// Ekranın görünür alanının üst kenarına, tam genişlikte yerleştirir.
    func place(on screen: NSScreen, height: CGFloat) {
        let visible = screen.visibleFrame
        stripHeight = height
        let target = NSRect(x: visible.minX, y: visible.maxY - height, width: visible.width, height: height)
        if frame != target { setFrame(target, display: false) }
        if !revealed && !isTransitioning { setOffset(hiddenOffset) }
    }

    private func setOffset(_ offset: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        compositor.layer?.sublayerTransform = CATransform3DMakeTranslation(0, offset, 0)
        CATransaction.commit()
    }

    /// Katman ağacını ekranın üstünden indirir/çeker; yalnız compositor dönüşümü hareket eder.
    /// Ters yönde, eski uç noktaya sıçramadan sunum konumundan döner.
    /// Sözleşme: bir geçiş başka bir `setRevealed` çağrısıyla tersine çevrilirse önceki çağrının
    /// `completion` değeri HİÇ çalışmaz; çağıranlar temizlik için ona güvenmemeli.
    /// İniş sonrası `ignoresMouseEvents` true kalır; her `setRevealed(true…)` sonrası
    /// `updatePassThrough(mouseLocation:)` çağrılmalıdır.
    func setRevealed(_ on: Bool, animated: Bool = true, completion: (() -> Void)? = nil) {
        generation += 1
        let gen = generation
        let current = presentationOffset
        compositor.layer?.removeAnimation(forKey: Self.animationKey)
        revealed = on
        let target: CGFloat = on ? 0 : hiddenOffset
        let base = on ? StripMotion.revealDuration : StripMotion.retractDuration
        let duration = animated ? StripMotion.duration(base, reduceMotion: reduceMotion()) : 0
        isTransitioning = duration > 0 && abs(current - target) > 0.01
        // NSView isabet testi model geometrisini kullanır; kartlar yerine varana dek olay alma.
        if isTransitioning || !on { ignoresMouseEvents = true }
        alphaValue = 1
        setOffset(target)
        if isTransitioning {
            let t = on ? StripMotion.revealTiming : StripMotion.retractTiming
            let a = CABasicAnimation(keyPath: "sublayerTransform")
            a.fromValue = NSValue(caTransform3D: CATransform3DMakeTranslation(0, current, 0))
            a.toValue = NSValue(caTransform3D: CATransform3DMakeTranslation(0, target, 0))
            a.duration = duration
            a.beginTime = compositor.layer?.convertTime(CACurrentMediaTime(), from: nil) ?? CACurrentMediaTime()
            a.timingFunction = CAMediaTimingFunction(controlPoints: Float(t.c1x), Float(t.c1y), Float(t.c2x), Float(t.c2y))
            compositor.layer?.add(a, forKey: Self.animationKey)
        }
        let delay = isTransitioning ? duration : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.generation == gen else { return }
            self.compositor.layer?.removeAnimation(forKey: Self.animationKey)
            self.isTransitioning = false
            // Çekilirken yükseklik değişmiş olabilir: dinlenme konumunu güncel yüksekliğe göre yeniden kur.
            if !self.revealed { self.setOffset(self.hiddenOffset) }
            completion?()
        }
    }
}
