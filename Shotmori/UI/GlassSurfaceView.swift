import AppKit

/// Zemin türü: macOS 26+ Liquid Glass, altı sistem Material.
enum GlassBacking: Equatable { case glass, material }

/// Kontrol katmanı için cam yüzey (yüzen panel, pencere içi kontrol kabı).
/// 26+: `NSGlassEffectView`; 14–15: `NSVisualEffectView` (`.behindWindow`) + köşe maskesi.
/// Alt görünümler **yalnız** `contentView`'a eklenir: cam yalnız `contentView`'ı efektin içinde tutmayı garanti eder (SDK notu).
/// İçerik (küçük resim, tuval, liste) için kullanılmaz; cam üstüne cam konmaz.
final class GlassSurfaceView: NSView {
    let contentView = NSView()
    private(set) var backing: GlassBacking
    private let host: NSView
    /// Material yolunda Increase Contrast için ince kenarlık (cam yolunda sistem çizer).
    private let contrastBorder = ContrastBorderView()
    var cornerRadius: CGFloat { didSet { applyRadius() } }
    /// Test: Material yolundaki görsel efekt görünümü (cam yolunda nil).
    var materialViewForTesting: NSVisualEffectView? { host as? NSVisualEffectView }

    static var isGlassAvailable: Bool { if #available(macOS 26, *) { return true } else { return false } }
    static func backing(available: Bool) -> GlassBacking { available ? .glass : .material }

    /// `forceMaterial`: 14–15 yolunu 26+ makinede de kurmak için (test ve görsel kontrol).
    init(cornerRadius: CGFloat, material: NSVisualEffectView.Material = .hudWindow, forceMaterial: Bool = false) {
        self.cornerRadius = cornerRadius
        backing = forceMaterial ? .material : Self.backing(available: Self.isGlassAvailable)
        if #available(macOS 26, *), backing == .glass {
            let g = NSGlassEffectView(); g.style = .regular; g.contentView = contentView; host = g
        } else {
            // Köşe: layer köşesi `.behindWindow` karışımında güvenilir değil; maske görüntüsü (9 dilim) kullanılır.
            let v = NSVisualEffectView(); v.material = material; v.blendingMode = .behindWindow; v.state = .active
            v.addSubview(contentView); host = v
        }
        super.init(frame: .zero)
        host.autoresizingMask = [.width, .height]; addSubview(host)
        contentView.autoresizingMask = [.width, .height]
        if backing == .material { contrastBorder.autoresizingMask = [.width, .height]; addSubview(contrastBorder) }
        applyRadius()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func applyRadius() {
        if #available(macOS 26, *), let g = host as? NSGlassEffectView { g.cornerRadius = cornerRadius }
        else if let v = host as? NSVisualEffectView { v.maskImage = Self.roundedMask(radius: cornerRadius) }
        contrastBorder.radius = cornerRadius
    }
    /// Yuvarlak köşeli 9 dilimli maske: kenarlar esner, köşeler sabit kalır.
    static func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let img = NSImage(size: NSSize(width: side, height: side), flipped: false) { r in NSColor.black.setFill(); NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill(); return true }
        img.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius); img.resizingMode = .stretch
        return img
    }
    override func layout() {
        super.layout()
        host.frame = bounds; contrastBorder.frame = bounds
        if backing == .material { contentView.frame = host.bounds }
    }
    /// Panel sürüklemesi: boş alandan pencere taşınır (içerik görünümleri kendi kararını verir).
    override var mouseDownCanMoveWindow: Bool { true }
}

/// Material yolunda Increase Contrast açıkken 1,5 pt ayırıcı renkli kenarlık; kapalıyken hiçbir şey çizmez.
final class ContrastBorderView: NSView {
    var radius: CGFloat = 16 { didSet { needsDisplay = true } }
    override var mouseDownCanMoveWindow: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard ShotmoriStyle.increaseContrast else { return }
        let p = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.75, dy: 0.75), xRadius: radius, yRadius: radius)
        ShotmoriStyle.separator.setStroke(); p.lineWidth = 1.5; p.stroke()
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}
