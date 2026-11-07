import AppKit

/// Tek kare (v2, 26.10.2026): görüntü kartı doldurur; altta yarı saydam şeritte yalnız saat (düzenlenmişte "Düzenlendi · saat");
/// dosya adı araç ipucu + VoiceOver etiketinde; "Yeni" = sol üst vurgu noktası (VoiceOver değeri "Yeni" der); seçim halkası + onay.
/// Seçim (halka + onay) ile klavye odağı (dış halka) ayrı çizilir. ✕ yalnızca bu kareyi raftan kaldırır; dosya korunur. Kart asla cam değildir.
final class ThumbnailItemView: NSView {
    /// Raf: 146 pt (134 pt kart + 12 pt aralık). Popover: 124 pt (üç kare 400 pt'e sığar). Yükseklik ortak: 118 (açıklama satırları kalktı).
    static let shelfSize = NSSize(width: 146, height: 118)
    static let popoverSize = NSSize(width: 124, height: 118)
    /// Alt şerit: 18 pt, `badge` rengi; Reduce Transparency'de daha opak.
    static let footerHeight: CGFloat = ShotmoriStyle.Metric.footer
    static func footerAlpha(reduceTransparency: Bool) -> CGFloat { reduceTransparency ? 0.9 : 0.7 }
    /// Şerit metni: saat; düzenlenmiş kopyada "Düzenlendi · saat"; kayıp kartta yalnız saat.
    static func footerText(capturedAt: Date, isDerivative: Bool, isMissing: Bool, editedCaption: String) -> String {
        let t = timeFmt.string(from: capturedAt)
        return (isDerivative && !isMissing) ? "\(editedCaption) · \(t)" : t
    }

    let item: ShelfItem
    var image: NSImage? { didSet { needsDisplay = true } }
    var isSelected = false { didSet { needsDisplay = true; setAccessibilitySelected(isSelected) } }
    var isNew = false { didSet { needsDisplay = true; updateAX() } }
    var isMissing = false { didSet { needsDisplay = true; updateAX() } }
    /// Klavye odağı: seçimden bağımsız dış halka.
    var isKeyboardFocused = false { didSet { needsDisplay = true } }
    /// Hızlı numara (1–9): yalnız pencere key iken sol altta çizilir; VoiceOver değerine eklenmez.
    var quickNumber: Int? { didSet { if quickNumber != oldValue { needsDisplay = true } } }
    #if SHOTMORI_CLOUD
    /// Bulut durumu (sağ alt rozet): bekliyor · yükleniyor · yüklendi · hata.
    var cloudBadge: CloudBadge? { didSet { needsDisplay = true; updateAX() } }
    #endif
    var onMouseDown: ((ThumbnailItemView, NSEvent) -> Void)?
    var onDrag: ((ThumbnailItemView, NSEvent) -> Void)?
    var onDoubleClick: ((ThumbnailItemView) -> Void)?
    var onContextMenu: ((ThumbnailItemView, NSEvent) -> Void)?
    var onMouseUpWithoutDrag: ((ThumbnailItemView, NSEvent) -> Void)?
    var onRemoveTapped: ((ThumbnailItemView) -> Void)?
    /// VoiceOver: basma (VO-Space) kartı tek seçer; özel eylemler Kopyala · Raftan kaldır · İşlemler… (atanmamış olan listelenmez).
    var onAccessibilityPress: ((ThumbnailItemView) -> Void)?
    var onAccessibilityCopy: ((ThumbnailItemView) -> Void)?
    var onAccessibilityActions: ((ThumbnailItemView) -> Void)?
    private let removeButton = NSButton()
    /// Hover çizimi etkilemez (yalnız ✕ düğmesi belirir); kart yeniden çizilmez.
    private var hovering = false { didSet { if hovering != oldValue { ShotmoriStyle.fade(removeButton, to: hovering ? 1 : 0) } } }
    private var trackingArea: NSTrackingArea?
    private var mouseDownPoint: NSPoint?
    /// Saat biçimi bölgeye göre (12/24 saat): "jmm" şablonu.
    static func makeTimeFormatter(locale: Locale = .current) -> DateFormatter { let f = DateFormatter(); f.locale = locale; f.setLocalizedDateFormatFromTemplate("jmm"); return f }
    private static let timeFmt = makeTimeFormatter()

    init(item: ShelfItem, size: NSSize = ThumbnailItemView.shelfSize) {
        self.item = item
        super.init(frame: NSRect(origin: .zero, size: size))
        toolTip = item.fileName
        setAccessibilityElement(true); setAccessibilityRole(.image); setAccessibilityLabel(item.fileName)
        configureRemoveButton(); updateAX()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Geometri
    /// Kart: yanlarda 6 pt aralık payı, üstte/altta 4 pt; açıklama satırı yok.
    var imageArea: NSRect { bounds.insetBy(dx: 6, dy: 4) }
    /// Sol üst "Yeni" noktası (8 pt + 1 pt halka).
    private var newDotRect: NSRect { NSRect(x: imageArea.minX + 8, y: imageArea.maxY - 8 - 8, width: 8, height: 8) }
    /// Bulut rozeti: sağ altta, alt şeridin üstünde (şerit rozeti örtmez).
    static func cloudBadgeRect(in area: NSRect) -> NSRect { NSRect(x: area.maxX - 6 - 20, y: area.minY + footerHeight + 4, width: 20, height: 20) }
    /// Hızlı numara rozeti: sol altta 16 pt daire, alt şeridin üstünde (bulut rozetinin aynası).
    static func quickNumberRect(in area: NSRect) -> NSRect { NSRect(x: area.minX + 6, y: area.minY + footerHeight + 4, width: 16, height: 16) }
    static func showsQuickNumber(_ n: Int?, windowIsKey: Bool) -> Bool { n != nil && windowIsKey }
    /// ✕ tıklama hedefi en az 24×24 pt (görünür daire 22 pt); kartın sağ üst köşesinde.
    var closeButtonRect: NSRect { NSRect(x: imageArea.maxX - 6 - ShotmoriStyle.Metric.hitTarget, y: imageArea.maxY - 6 - ShotmoriStyle.Metric.hitTarget, width: ShotmoriStyle.Metric.hitTarget, height: ShotmoriStyle.Metric.hitTarget) }
    private var badgeRect: NSRect { NSRect(x: imageArea.minX + 6, y: imageArea.maxY - 6 - 22, width: 22, height: 22) }

    private func configureRemoveButton() {
        removeButton.frame = closeButtonRect
        removeButton.isBordered = false; removeButton.imagePosition = .imageOnly
        removeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: S.removeAXLabel)?.withSymbolConfiguration(.init(pointSize: 10, weight: .bold))
        removeButton.contentTintColor = .white
        removeButton.wantsLayer = true
        removeButton.layer?.backgroundColor = ShotmoriStyle.badge.cgColor
        removeButton.layer?.cornerRadius = ShotmoriStyle.Metric.hitTarget / 2
        removeButton.toolTip = S.removeHint
        removeButton.setAccessibilityLabel(S.removeAXLabel); removeButton.setAccessibilityHelp(S.removeAXHelp)
        removeButton.target = self; removeButton.action = #selector(removeTapped)
        removeButton.alphaValue = 0 // hover'da görünür; erişilebilirlik ağacında kalır
        addSubview(removeButton)
    }
    @objc private func removeTapped() { onRemoveTapped?(self) }
    private var statusText: String { Self.footerText(capturedAt: item.capturedAt, isDerivative: item.source == .derivative, isMissing: isMissing, editedCaption: S.editedCaption) }
    /// Kayıp kartın metni: yerel kopyası doğrulanmış yedekten sonra Çöp'e taşınan öğe "bulutta" der (yalnız bulutlu derleme).
    private var missingText: String {
        #if SHOTMORI_CLOUD
        if item.localTrashed { return S.cloudLocalTrashed }
        #endif
        return S.missingFile
    }
    /// Kayıp kartın simgesi `missingText` ile aynı koşulda: bulut simgesi yalnız bulutlu derlemede (Debug'da yazılmış `localTrashed` Release'te "photo").
    static func missingSymbol(localTrashed: Bool) -> String {
        #if SHOTMORI_CLOUD
        return localTrashed ? "icloud" : "photo"
        #else
        return "photo"
        #endif
    }
    private func updateAX() {
        var v = isMissing ? "\(S.missingFile) · \(statusText)" : (isNew ? "\(S.newBadge) · \(statusText)" : statusText)
        #if SHOTMORI_CLOUD
        if isMissing, item.localTrashed { v = S.cloudLocalTrashed }
        if let b = cloudBadge { v += " · " + b.axText }
        #endif
        setAccessibilityValue(v); setAccessibilityHelp(item.source == .derivative ? "\(item.fileName), \(S.editedBadge)" : nil)
    }

    // MARK: VoiceOver eylemleri
    override func accessibilityPerformPress() -> Bool {
        guard let f = onAccessibilityPress else { return false }
        f(self); return true
    }
    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        var out: [NSAccessibilityCustomAction] = []
        func add(_ name: String, _ f: ((ThumbnailItemView) -> Void)?) {
            guard let f = f else { return }
            out.append(NSAccessibilityCustomAction(name: name) { [weak self] in guard let self = self else { return false }; f(self); return true })
        }
        add(S.copyShort, onAccessibilityCopy)
        add(S.actionRemoveFromShelf, onRemoveTapped)
        add(S.moreActions, onAccessibilityActions)
        return out.isEmpty ? nil : out
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(t); trackingArea = t
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    // MARK: Çizim
    override func draw(_ dirtyRect: NSRect) {
        let area = imageArea
        let path = NSBezierPath(roundedRect: area, xRadius: ShotmoriStyle.Metric.cardRadius, yRadius: ShotmoriStyle.Metric.cardRadius)
        (isSelected ? ShotmoriStyle.selectionFill : ShotmoriStyle.elevated).setFill(); path.fill()
        if let img = image, !isMissing {
            NSGraphicsContext.saveGraphicsState(); path.addClip()
            img.draw(in: aspectFit(img.size, in: area.insetBy(dx: 2, dy: 2)))
            NSGraphicsContext.restoreGraphicsState()
        } else if isMissing {
            // Kayıp kaynak (veya buluta taşınmış yerel): küçük resim yerine ikon + açıklama; dosya gerektiren işlemler pasif, raftan kaldırma açık kalır.
            let sym = NSImage(systemSymbolName: Self.missingSymbol(localTrashed: item.localTrashed), accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 20, weight: .regular))
            sym?.draw(in: NSRect(x: area.midX - 12, y: area.midY + 2, width: 24, height: 24), from: .zero, operation: .sourceOver, fraction: 0.5)
            let s = NSAttributedString(string: missingText, attributes: [.font: ShotmoriStyle.Fonts.secondary, .foregroundColor: ShotmoriStyle.secondaryText])
            let w = min(s.size().width, area.width - 8); s.draw(in: NSRect(x: area.midX - w / 2, y: area.midY - 16, width: w, height: 15))
        } else {
            let sym = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 22, weight: .regular))
            sym?.draw(in: NSRect(x: area.midX - 14, y: area.midY - 14, width: 28, height: 28), from: .zero, operation: .sourceOver, fraction: 0.45)
        }
        // Alt şerit: kartın alt kenarında yarı saydam grafit şerit üzerinde tek satır (saat / Düzenlendi · saat); kayıp kartta şerit yok.
        if !isMissing {
            NSGraphicsContext.saveGraphicsState(); path.addClip()
            ShotmoriStyle.badge.withAlphaComponent(Self.footerAlpha(reduceTransparency: ShotmoriStyle.reduceTransparency)).setFill()
            NSRect(x: area.minX, y: area.minY, width: area.width, height: Self.footerHeight).fill()
            NSGraphicsContext.restoreGraphicsState()
            let para = NSMutableParagraphStyle(); para.lineBreakMode = .byTruncatingTail
            let status = NSAttributedString(string: statusText, attributes: [.font: ShotmoriStyle.Fonts.caption, .foregroundColor: NSColor.white, .paragraphStyle: para])
            status.draw(in: NSRect(x: area.minX + 7, y: area.minY + 3, width: area.width - 14, height: 13))
        }
        // Kenar: seçiliyse 2 pt vurgu halkası, değilse 1 pt ayırıcı (kayıp kartta da: ⌫ hangi kartı kaldıracağını göstermeli)
        if isSelected { ShotmoriStyle.accent.setStroke(); path.lineWidth = ShotmoriStyle.Metric.ring; path.stroke() }
        else { ShotmoriStyle.separator.setStroke(); path.lineWidth = ShotmoriStyle.increaseContrast ? 1.5 : 1; path.stroke() }
        // Klavye odağı: seçimden ayrı dış halka
        if isKeyboardFocused {
            let ring = NSBezierPath(roundedRect: area.insetBy(dx: -3, dy: -3), xRadius: ShotmoriStyle.Metric.imageRadius + 3, yRadius: ShotmoriStyle.Metric.imageRadius + 3)
            ShotmoriStyle.focus.setStroke(); ring.lineWidth = ShotmoriStyle.Metric.ring; ring.stroke()
        }
        // Sol üst: seçiliyse onay rozeti; değilse yeni kare için "Yeni" rozeti (yalnız renkli nokta değil)
        if isSelected {
            ShotmoriStyle.accent.setFill(); NSBezierPath(ovalIn: badgeRect).fill()
            let check = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 11, weight: .bold))
            NSGraphicsContext.saveGraphicsState(); ShotmoriStyle.onAccent.set()
            check?.tinted(ShotmoriStyle.onAccent).draw(in: badgeRect.insetBy(dx: 5, dy: 5), from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
        } else if isNew {
            // "Yeni": metin yok, vurgu noktası + açık halka (VoiceOver değeri "Yeni" der)
            let ring = NSBezierPath(ovalIn: newDotRect.insetBy(dx: -1.5, dy: -1.5)); ShotmoriStyle.elevated.setFill(); ring.fill()
            ShotmoriStyle.accent.setFill(); NSBezierPath(ovalIn: newDotRect).fill()
        }
        #if SHOTMORI_CLOUD
        // Bulut rozeti: sağ alt, 18 pt daire + sembol; yüklendi vurgu, hata yıkıcı, bekliyor ikincil
        if let b = cloudBadge {
            let r = Self.cloudBadgeRect(in: area)
            let fill: NSColor; let symbol: String
            switch b { case .uploaded: fill = ShotmoriStyle.accent; symbol = "checkmark.icloud.fill"; case .failed: fill = ShotmoriStyle.destructiveText; symbol = "exclamationmark.icloud.fill"; case .uploading: fill = ShotmoriStyle.secondaryText; symbol = "arrow.up.circle.fill"; case .pending: fill = ShotmoriStyle.secondaryText; symbol = "icloud.fill" }
            ShotmoriStyle.elevated.setFill(); NSBezierPath(ovalIn: r).fill()
            NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))?.tinted(fill).draw(in: r.insetBy(dx: 3, dy: 3), from: .zero, operation: .sourceOver, fraction: 1)
        }
        #endif
        // Hızlı numara: kayıp kartta da (numara seçimi ona da gider)
        if Self.showsQuickNumber(quickNumber, windowIsKey: window?.isKeyWindow == true), let n = quickNumber {
            let r = Self.quickNumberRect(in: area)
            ShotmoriStyle.badge.setFill(); NSBezierPath(ovalIn: r).fill()
            let t = NSAttributedString(string: "\(n)", attributes: [.font: ShotmoriStyle.Fonts.control, .foregroundColor: NSColor.white])
            let ts = t.size(); t.draw(at: NSPoint(x: r.midX - ts.width / 2, y: r.midY - ts.height / 2))
        }
    }
    private func aspectFit(_ size: NSSize, in rect: NSRect) -> NSRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let s = min(rect.width / size.width, rect.height / size.height)
        let w = size.width * s, h = size.height * s
        return NSRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }

    // MARK: Fare
    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        if event.clickCount == 2 { onDoubleClick?(self); return }
        onMouseDown?(self, event)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let p = mouseDownPoint else { return }
        if hypot(event.locationInWindow.x - p.x, event.locationInWindow.y - p.y) > 4 { mouseDownPoint = nil; onDrag?(self, event) }
    }
    override func mouseUp(with event: NSEvent) { if mouseDownPoint != nil { onMouseUpWithoutDrag?(self, event) }; mouseDownPoint = nil }
    override func rightMouseDown(with event: NSEvent) { onContextMenu?(self, event) }
    override var acceptsFirstResponder: Bool { false }
    /// Saydam görünümlerde AppKit varsayılanı pencereyi taşımaktır; kare sürüklemesi pencereyi taşımamalı.
    override var mouseDownCanMoveWindow: Bool { false }
}

extension NSImage {
    /// Çoklu sürüklemede ön görüntünün sağ üstüne dosya sayısı rozeti (vurgu dolgusu, onAccent metin).
    func withCountBadge(_ n: Int) -> NSImage {
        guard n > 1 else { return self }
        let img = NSImage(size: size, flipped: false) { rect in
            self.draw(in: rect)
            let d: CGFloat = min(26, max(18, rect.width * 0.22)); let r = NSRect(x: rect.maxX - d - 2, y: rect.maxY - d - 2, width: d, height: d)
            ShotmoriStyle.accent.setFill(); NSBezierPath(ovalIn: r).fill()
            let t = NSAttributedString(string: "\(n)", attributes: [.font: NSFont.systemFont(ofSize: d * 0.55, weight: .semibold), .foregroundColor: ShotmoriStyle.onAccent])
            let ts = t.size(); t.draw(at: NSPoint(x: r.midX - ts.width / 2, y: r.midY - ts.height / 2)); return true
        }
        return img
    }
    func tinted(_ color: NSColor) -> NSImage {
        let img = NSImage(size: size, flipped: false) { rect in
            self.draw(in: rect); color.set(); rect.fill(using: .sourceAtop); return true
        }
        img.isTemplate = false; return img
    }
}
