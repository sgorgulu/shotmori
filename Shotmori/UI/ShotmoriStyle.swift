import AppKit
import SwiftUI

/// A — Grafit & Porselen görsel rolleri (19 Ekim 2026 onayı). Açık/koyu dinamik; macOS görünüm değişimini takip eder.
/// Yalnızca Shotmori'nin kendi yüzeyleri için: NSMenu, NSAlert, NSSavePanel ve diğer sistem yüzeyleri boyanmaz.
/// Gizleme (redaction) rengi tema token'ı değildir: önizleme ve çıktıda her zaman %100 opak siyah (editör kendi çizer).
enum ShotmoriStyle {
    private static func dyn(_ name: String, light: Int, dark: Int) -> NSColor {
        NSColor(name: NSColor.Name("shotmori.\(name)")) { app in
            app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        }
    }
    static let surface = dyn("surface", light: 0xFFFEFA, dark: 0x303137)
    static let elevated = dyn("elevated", light: 0xFFFFFF, dark: 0x3A3B42)
    static let text = dyn("text", light: 0x28292E, dark: 0xF2F1F5)
    static let secondaryText = dyn("secondaryText", light: 0x66656D, dark: 0xB4B2BD)
    static let accent = dyn("accent", light: 0x6B54AD, dark: 0xB9A6E8)
    static let onAccent = dyn("onAccent", light: 0xFFFFFF, dark: 0x251C3B)
    /// SwiftUI vurgu dolgulu düğme (`glassButton(prominent:)`) zemini. Sistem yazıyı her zaman beyaz çizer; macOS 26 camı
    /// tonu açar (koyuda `accent` #B9A6E8 → #C9BBED, beyaz yazıyla 1,8:1). Bu yüzden koyuda daha koyu mor:
    /// cam altında ölçülen beyaz yazı 5,1:1 (WCAG AA), 14–15 `.borderedProminent`te 7,1:1. AppKit düğmeleri `accent` + `onAccent` kullanır.
    static let accentFill = dyn("accentFill", light: 0x6B54AD, dark: 0x5F4A9E)
    static let focus = dyn("focus", light: 0x6550A5, dark: 0xC6B5F3)
    static let selectionFill = dyn("selectionFill", light: 0xEEE8FA, dark: 0x494059)
    static let separator = dyn("separator", light: 0xD8D6D2, dark: 0x4B4B54)
    static let destructiveText = dyn("destructive", light: 0xAB282C, dark: 0xFFB1B2)
    /// Küçük resim üstündeki ✕ ve onay rozetlerinin koyu zemini (her iki temada grafit).
    static let badge = NSColor(hex: 0x28292E).withAlphaComponent(0.88)
    /// Editör tuval zemini: görüntünün sınırı okunsun diye orta koyu, her iki temada.
    static let canvasBackground = dyn("canvas", light: 0x74746E, dark: 0x1F2024)

    enum Metric {
        static let groupRadius: CGFloat = 8
        static let imageRadius: CGFloat = 10
        /// Cam yüzey köşesi (yüzen panel), kart köşesi, kapsül rozet yüksekliği, kart alt şeridi.
        static let glassRadius: CGFloat = 16
        static let cardRadius: CGFloat = 10
        static let chipHeight: CGFloat = 20
        static let footer: CGFloat = 18
        static let control: CGFloat = 28
        static let hitTarget: CGFloat = 24
        static let ring: CGFloat = 2
        static let space8: CGFloat = 8
    }
    enum Fonts {
        static let title = NSFont.systemFont(ofSize: 13, weight: .semibold)
        static let body = NSFont.systemFont(ofSize: 13)
        static let control = NSFont.systemFont(ofSize: 12)
        static let emphasis = NSFont.systemFont(ofSize: 12, weight: .semibold)
        static let secondary = NSFont.systemFont(ofSize: 11)
        static let caption = NSFont.systemFont(ofSize: 10)
        static let digits = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    }
    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    static var reduceTransparency: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency }
    static var increaseContrast: Bool { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast }
    /// Küçük geri bildirimler: Reduce Motion'da anlık, aksi hâlde en çok ~150 ms opacity.
    static func fade(_ view: NSView, to alpha: CGFloat, duration: TimeInterval = 0.14) {
        if reduceMotion { view.alphaValue = alpha; return }
        NSAnimationContext.runAnimationGroup { c in c.duration = min(duration, 0.15); c.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1); view.animator().alphaValue = alpha }
    }

    // MARK: Native kontrol yardımcıları
    /// Cam zemin üstünde (raf paneli, popover) düğmeler düzdür: her zaman `.rounded` (cam üstüne cam yok).
    static func flatButton(_ b: NSButton, prominent: Bool) {
        b.bezelStyle = .rounded; b.controlSize = .regular; b.font = Fonts.control
        if prominent && b.isEnabled {
            b.bezelColor = accent; b.contentTintColor = onAccent
            b.attributedTitle = NSAttributedString(string: b.title, attributes: [.foregroundColor: onAccent, .font: Fonts.control])
        } else {
            b.bezelColor = nil; b.contentTintColor = b.isEnabled ? nil : secondaryText
            b.attributedTitle = NSAttributedString(string: b.title, attributes: [.foregroundColor: b.isEnabled ? text : secondaryText, .font: Fonts.control])
        }
    }
    /// Ana işlem (Kopyala) — cam zemin üstündeki düz biçim (panel/popover `PrimaryButton`).
    static func primary(_ b: NSButton) { flatButton(b, prominent: true) }
    /// İkincil işlem — düz biçim.
    static func secondary(_ b: NSButton) { flatButton(b, prominent: false) }
    /// Kenarlıksız ikon düğmesi: sembol + araç ipucu + VoiceOver etiketi (etiket görünmez ama okunur).
    static func iconButton(_ b: NSButton, symbol: String, label: String, pointSize: CGFloat = 13, color: NSColor = secondaryText) {
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?.withSymbolConfiguration(.init(pointSize: pointSize, weight: .medium))
        b.imagePosition = .imageOnly; b.isBordered = false; b.bezelStyle = .inline; b.title = ""
        b.contentTintColor = color; b.toolTip = label; b.setAccessibilityLabel(label)
    }
    /// Kenarlıksız bağlantı görünümlü düğme; varsayılan renk vurgu (tek vurgu rengi: mavi sistem bağlantısı yok).
    static func link(_ b: NSButton, color: NSColor = accent) {
        b.bezelStyle = .inline; b.isBordered = false; b.font = Fonts.control; b.contentTintColor = color
        b.attributedTitle = NSAttributedString(string: b.title, attributes: [.foregroundColor: color, .font: Fonts.control])
    }
    static func label(_ t: NSTextField, font: NSFont = Fonts.body, color: NSColor = text) { t.font = font; t.textColor = color }
}

/// Ana işlem düğmesi: etkin/pasif değişiminde stilini kendisi yeniler. Vurgu dolgusunu `PrimaryButtonCell` çizer:
/// AppKit `bezelColor`'ı pencere anahtar/ana değilken (arkadaki panel, uygulama etkin değil) bırakıp açık gri zemin çizer,
/// beyaz yazı okunmaz olurdu (~1,3:1). Dolgu her durumda kalır; yazı ve simge `onAccent` (açık 6,0:1, koyu 8,4:1).
final class PrimaryButton: NSButton {
    override class var cellClass: AnyClass? { get { PrimaryButtonCell.self } set {} }
    override var isEnabled: Bool { didSet { ShotmoriStyle.primary(self) } }
    override var title: String { didSet { ShotmoriStyle.primary(self) } }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); ShotmoriStyle.primary(self) }
}

/// `PrimaryButton` hücresi: etkinken yerel `.rounded` biçim ölçüsünde (24 pt yükseklik) vurgu dolgusu ve `onAccent` simge;
/// pencerenin etkin olup olmamasından bağımsız. Pasif (devre dışı) düğme sistemin çizimine kalır.
final class PrimaryButtonCell: NSButtonCell {
    override func drawBezel(withFrame frame: NSRect, in controlView: NSView) {
        guard isEnabled else { super.drawBezel(withFrame: frame, in: controlView); return }
        let r = frame.insetBy(dx: 0, dy: max(0, (frame.height - 24) / 2))
        let p = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
        let fill = isHighlighted ? (ShotmoriStyle.accent.blended(withFraction: 0.18, of: .black) ?? ShotmoriStyle.accent) : ShotmoriStyle.accent
        fill.setFill(); p.fill()
    }
    override func drawImage(_ image: NSImage, withFrame frame: NSRect, in controlView: NSView) {
        guard isEnabled, image.isTemplate else { super.drawImage(image, withFrame: frame, in: controlView); return }
        var tint = NSColor.white
        controlView.effectiveAppearance.performAsCurrentDrawingAppearance { tint = NSColor(cgColor: ShotmoriStyle.onAccent.cgColor) ?? .white }
        let tinted = NSImage(size: image.size, flipped: false) { r in image.draw(in: r); tint.set(); r.fill(using: .sourceAtop); return true }
        tinted.isTemplate = false
        super.drawImage(tinted, withFrame: frame, in: controlView)
    }
}

/// Düz renkli, köşeli, isteğe bağlı kenarlıklı yüzey; rengi görünümle birlikte yeniden çizilir (katman rengi sabitlemez).
final class SurfaceView: NSView {
    var fill: NSColor { didSet { needsDisplay = true } }
    var border: NSColor? { didSet { needsDisplay = true } }
    var radius: CGFloat { didSet { needsDisplay = true } }
    init(fill: NSColor, border: NSColor? = nil, radius: CGFloat) { self.fill = fill; self.border = border; self.radius = radius; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
    override var mouseDownCanMoveWindow: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5); let p = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
        fill.setFill(); p.fill()
        if let b = border { b.setStroke(); p.lineWidth = ShotmoriStyle.increaseContrast ? 1.5 : 1; p.stroke() }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

/// Küçük metin rozeti ("6 görüntü", "esc"): yükseltilmiş yüzey + ayırıcı kenar.
final class ChipView: NSView {
    private let label = NSTextField(labelWithString: "")
    /// Metin değişince VoiceOver etiketi de güncellenir; özel etiket gerekiyorsa (popover sayacı) metinden sonra atanır.
    var text: String { get { label.stringValue } set { label.stringValue = newValue; label.sizeToFit(); invalidateIntrinsicContentSize(); needsDisplay = true; setAccessibilityLabel(newValue) } }
    init(_ text: String, font: NSFont = ShotmoriStyle.Fonts.secondary, color: NSColor = ShotmoriStyle.secondaryText) {
        super.init(frame: .zero)
        label.font = font; label.textColor = color; label.stringValue = text; label.sizeToFit(); label.alignment = .center
        addSubview(label); setAccessibilityElement(true); setAccessibilityRole(.staticText); setAccessibilityLabel(text)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var intrinsicContentSize: NSSize { NSSize(width: label.frame.width + 14, height: 20) }
    override func layout() { super.layout(); label.frame = NSRect(x: 7, y: (bounds.height - label.frame.height) / 2, width: bounds.width - 14, height: label.frame.height) }
    override func draw(_ dirtyRect: NSRect) {
        let p = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
        ShotmoriStyle.elevated.setFill(); p.fill(); ShotmoriStyle.separator.setStroke(); p.lineWidth = 1; p.stroke()
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override var mouseDownCanMoveWindow: Bool { true }
}

extension NSColor {
    convenience init(hex: Int) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// SwiftUI tarafı (Ayarlar, Boyutlandır, Kurulum) aynı rolleri kullanır.
extension Color {
    static let smSurface = Color(nsColor: ShotmoriStyle.surface)
    static let smElevated = Color(nsColor: ShotmoriStyle.elevated)
    static let smText = Color(nsColor: ShotmoriStyle.text)
    static let smSecondary = Color(nsColor: ShotmoriStyle.secondaryText)
    static let smAccent = Color(nsColor: ShotmoriStyle.accent)
    static let smOnAccent = Color(nsColor: ShotmoriStyle.onAccent)
    static let smAccentFill = Color(nsColor: ShotmoriStyle.accentFill)
    static let smSelection = Color(nsColor: ShotmoriStyle.selectionFill)
    static let smSeparator = Color(nsColor: ShotmoriStyle.separator)
    static let smDestructive = Color(nsColor: ShotmoriStyle.destructiveText)
}
