import AppKit

// MARK: - Tuval

/// Önizleme üzerinde kırpma / gizleme dikdörtgenlerini çizer ve düzenler.
/// Görünüm koordinatı = önizleme pikseli (nokta). Model her zaman görüntü pikselinde; `transform` ile çevrilir.
final class EditorCanvasView: NSView {
    enum Tool { case crop, redact }
    enum Handle: CaseIterable { case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left }
    private enum Drag { case none, creating(anchor: CGPoint), moving(start: CGPoint, rect0: CGRect, target: Target), resizing(handle: Handle, rect0: CGRect, target: Target) }
    private enum Target { case crop, redaction(Int) }

    let doc: EditDocument
    private let preview: CGImage
    let transform: CanvasTransform
    var tool: Tool = .crop { didSet { needsDisplay = true; doc.select(nil) } }
    var aspect: CropAspect = .free
    var onSelectionInfo: ((String) -> Void)?
    private var drag: Drag = .none
    private var dragChanged = false

    init(doc: EditDocument, preview: CGImage) {
        self.doc = doc; self.preview = preview
        transform = CanvasTransform(scale: CGFloat(preview.width) / doc.imageSize.width, origin: .zero)
        super.init(frame: NSRect(x: 0, y: 0, width: preview.width, height: preview.height))
        wantsLayer = true
        setAccessibilityElement(true); setAccessibilityRole(.image); setAccessibilityLabel(S.editTitle)
        doc.onChange = { [weak self] in self?.invalidateChanges(); self?.publishInfo() }
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: preview.width, height: preview.height) }
    private var magnification: CGFloat { enclosingScrollView?.magnification ?? 1 }
    private var handleSize: CGFloat { 9 / magnification }

    // MARK: Çizim
    /// Son çizime istenen durum: sürüklemede yalnız eski ∪ yeni dikdörtgen yeniden çizilir (2048 px önizleme her karede baştan çizilmez).
    private var drawnState = EditState()
    enum Invalidation: Equatable { case none, full, rect(CGRect) }
    /// Görüntü pikselinde değişen alan: kırpma görünüp kaybolursa dış karartma her yeri etkiler (tam); aksi hâlde değişen kırpma,
    /// gizleme alanları ve seçim çerçevelerinin eski ∪ yeni dikdörtgeni.
    static func invalidation(old: EditState, new: EditState) -> Invalidation {
        if (old.crop == nil) != (new.crop == nil) { return .full }
        var u: CGRect?
        func add(_ r: CGRect?) { guard let r = r else { return }; u = u.map { $0.union(r) } ?? r }
        if old.crop != new.crop { add(old.crop); add(new.crop) }
        let o = old.redactions, n = new.redactions
        for i in 0..<max(o.count, n.count) {
            let a = o.indices.contains(i) ? o[i] : nil, b = n.indices.contains(i) ? n[i] : nil
            if a != b { add(a); add(b) }
        }
        if old.selectedRedaction != new.selectedRedaction {
            add(old.selectedRedaction.flatMap { o.indices.contains($0) ? o[$0] : nil })
            add(new.selectedRedaction.flatMap { n.indices.contains($0) ? n[$0] : nil })
        }
        return u.map { .rect($0) } ?? .none
    }
    private func invalidateChanges() {
        switch Self.invalidation(old: drawnState, new: doc.state) {
        case .none: break
        case .full: needsDisplay = true
        case .rect(let r): let pad = handleSize + 2 / magnification; setNeedsDisplay(transform.toView(r).insetBy(dx: -pad, dy: -pad)) // tutamaklar ve çerçeve çizgisi dikdörtgenin dışına taşar
        }
        drawnState = doc.state
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState(); ctx.translateBy(x: 0, y: bounds.height); ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high; ctx.draw(preview, in: bounds); ctx.restoreGState()
        // Gizleme alanları: opak siyah (önizlemede de altı görünmez)
        NSColor.black.setFill()
        for (i, r) in doc.state.redactions.enumerated() {
            let v = transform.toView(r); v.fill()
            if doc.state.selectedRedaction == i { drawFrame(v, color: ShotmoriStyle.accent, handles: true) } // tek vurgu rengi (sistem mavisi değil)
        }
        if let c = doc.state.crop {
            let v = transform.toView(c)
            NSColor.black.withAlphaComponent(0.45).setFill()
            let outside = NSBezierPath(rect: bounds); outside.append(NSBezierPath(rect: v)); outside.windingRule = .evenOdd; outside.fill()
            drawFrame(v, color: .white, handles: tool == .crop)
            // üçte bir kılavuzu
            NSColor.white.withAlphaComponent(0.35).setStroke(); let g = NSBezierPath(); g.lineWidth = 1 / magnification
            for f in [1.0 / 3.0, 2.0 / 3.0] as [CGFloat] { g.move(to: NSPoint(x: v.minX + v.width * f, y: v.minY)); g.line(to: NSPoint(x: v.minX + v.width * f, y: v.maxY)); g.move(to: NSPoint(x: v.minX, y: v.minY + v.height * f)); g.line(to: NSPoint(x: v.maxX, y: v.minY + v.height * f)) }
            g.stroke()
        }
    }
    private func drawFrame(_ v: NSRect, color: NSColor, handles: Bool) {
        color.setStroke(); let p = NSBezierPath(rect: v); p.lineWidth = 1.5 / magnification; p.stroke()
        guard handles else { return }
        for h in Handle.allCases { let hp = handlePoint(h, in: v); let hr = NSRect(x: hp.x - handleSize / 2, y: hp.y - handleSize / 2, width: handleSize, height: handleSize); NSColor.white.setFill(); hr.fill(); color.setStroke(); NSBezierPath(rect: hr).stroke() }
    }
    private func handlePoint(_ h: Handle, in r: NSRect) -> NSPoint {
        switch h {
        case .topLeft: return NSPoint(x: r.minX, y: r.minY); case .top: return NSPoint(x: r.midX, y: r.minY); case .topRight: return NSPoint(x: r.maxX, y: r.minY); case .right: return NSPoint(x: r.maxX, y: r.midY)
        case .bottomRight: return NSPoint(x: r.maxX, y: r.maxY); case .bottom: return NSPoint(x: r.midX, y: r.maxY); case .bottomLeft: return NSPoint(x: r.minX, y: r.maxY); case .left: return NSPoint(x: r.minX, y: r.midY)
        }
    }
    private func hitHandle(_ p: NSPoint, in v: NSRect) -> Handle? {
        let tol = handleSize
        for h in Handle.allCases { let hp = handlePoint(h, in: v); if abs(hp.x - p.x) <= tol && abs(hp.y - p.y) <= tol { return h } }
        return nil
    }

    // MARK: Fare
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        let ip = transform.toImage(p)
        dragChanged = false; doc.beginChange()
        switch tool {
        case .crop:
            if let c = doc.state.crop {
                let v = transform.toView(c)
                if let h = hitHandle(p, in: v) { drag = .resizing(handle: h, rect0: c, target: .crop); return }
                if v.contains(p) { drag = .moving(start: ip, rect0: c, target: .crop); return }
            }
            drag = .creating(anchor: ip)
        case .redact:
            if let s = doc.state.selectedRedaction, doc.state.redactions.indices.contains(s) {
                let v = transform.toView(doc.state.redactions[s])
                if let h = hitHandle(p, in: v) { drag = .resizing(handle: h, rect0: doc.state.redactions[s], target: .redaction(s)); return }
            }
            if let i = doc.state.redactions.lastIndex(where: { transform.toView($0).contains(p) }) { doc.select(i); drag = .moving(start: ip, rect0: doc.state.redactions[i], target: .redaction(i)); return }
            doc.select(nil); drag = .creating(anchor: ip)
        }
    }
    override func mouseDragged(with event: NSEvent) {
        let ip = transform.toImage(convert(event.locationInWindow, from: nil))
        switch drag {
        case .none: return
        case .creating(let a):
            let r = EditDocument.rect(from: a, to: clampPoint(ip), aspect: tool == .crop ? aspect : .free)
            if tool == .crop { doc.setCrop(r) }
            else if let ci = creatingIndex, doc.state.redactions.indices.contains(ci) { doc.updateRedaction(ci, r) }
            else { doc.addRedaction(r); creatingIndex = doc.state.selectedRedaction }
        case .moving(let start, let r0, let target):
            var r = r0.offsetBy(dx: (ip.x - start.x).rounded(), dy: (ip.y - start.y).rounded())
            r.origin.x = min(max(r.minX, 0), doc.imageSize.width - r.width); r.origin.y = min(max(r.minY, 0), doc.imageSize.height - r.height)
            apply(r, target)
        case .resizing(let h, let r0, let target):
            apply(resized(r0, handle: h, to: clampPoint(ip), keepAspect: tool == .crop ? aspect : .free), target)
        }
        dragChanged = true
    }
    private var creatingIndex: Int?
    override func mouseUp(with event: NSEvent) {
        if case .creating = drag, tool == .redact { creatingIndex = nil }
        drag = .none
        if !dragChanged { doc.cancelChange() } // yalnız seçim değişti: undo kaydı tutulmaz
        publishInfo()
    }
    private func apply(_ r: CGRect, _ t: Target) { switch t { case .crop: doc.setCrop(r); case .redaction(let i): doc.updateRedaction(i, r) } }
    private func clampPoint(_ p: CGPoint) -> CGPoint { CGPoint(x: min(max(p.x, 0), doc.imageSize.width), y: min(max(p.y, 0), doc.imageSize.height)) }
    private func resized(_ r: CGRect, handle: Handle, to p: CGPoint, keepAspect: CropAspect) -> CGRect {
        var minX = r.minX, minY = r.minY, maxX = r.maxX, maxY = r.maxY
        switch handle {
        case .topLeft: minX = p.x; minY = p.y; case .top: minY = p.y; case .topRight: maxX = p.x; minY = p.y; case .right: maxX = p.x
        case .bottomRight: maxX = p.x; maxY = p.y; case .bottom: maxY = p.y; case .bottomLeft: minX = p.x; maxY = p.y; case .left: minX = p.x
        }
        var out = CGRect(x: min(minX, maxX), y: min(minY, maxY), width: abs(maxX - minX), height: abs(maxY - minY))
        if let ratio = keepAspect.ratio, out.width > 0, out.height > 0 {
            // Sabit köşe: tutamacın karşısı. Genişliği orana göre türet.
            let anchorX = [.topLeft, .left, .bottomLeft].contains(handle) ? r.maxX : r.minX
            let anchorY = [.topLeft, .top, .topRight].contains(handle) ? r.maxY : r.minY
            var w = out.width, h = out.height
            if [.top, .bottom].contains(handle) { w = h * ratio } else if [.left, .right].contains(handle) { h = w / ratio } else if w / ratio >= h { h = w / ratio } else { w = h * ratio }
            let x = [.topLeft, .left, .bottomLeft].contains(handle) ? anchorX - w : ([.top, .bottom].contains(handle) ? r.midX - w / 2 : anchorX)
            let y = [.topLeft, .top, .topRight].contains(handle) ? anchorY - h : ([.left, .right].contains(handle) ? r.midY - h / 2 : anchorY)
            out = CGRect(x: x, y: y, width: w, height: h)
        }
        return out
    }

    // MARK: Klavye
    override func keyDown(with event: NSEvent) {
        let shift = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 51, 117: deleteSelection(); return // ⌫ / ⌦
        case 123, 124, 125, 126: nudge(code: event.keyCode, step: shift ? 10 : 1); return
        default: super.keyDown(with: event)
        }
    }
    // Ana menü Düzen › Geri al / Yinele (yanıt zinciri)
    @objc func undo(_ sender: Any?) { doc.undo() }
    @objc func redo(_ sender: Any?) { doc.redo() }
    @objc func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action { case #selector(undo(_:)): return doc.canUndo; case #selector(redo(_:)): return doc.canRedo; default: return true }
    }
    func deleteSelection() {
        doc.beginChange()
        if tool == .redact, let s = doc.state.selectedRedaction { doc.removeRedaction(s) } else if tool == .crop, doc.state.crop != nil { doc.setCrop(nil) } else { doc.cancelChange() }
    }
    private func nudge(code: UInt16, step: CGFloat) {
        let d: CGPoint = code == 123 ? CGPoint(x: -step, y: 0) : code == 124 ? CGPoint(x: step, y: 0) : code == 126 ? CGPoint(x: 0, y: -step) : CGPoint(x: 0, y: step)
        let target: CGRect?
        if tool == .redact, let s = doc.state.selectedRedaction, doc.state.redactions.indices.contains(s) { target = doc.state.redactions[s] }
        else if tool == .crop { target = doc.state.crop } else { target = nil }
        guard let r = target else { return }
        let moved = Self.nudged(r, by: d, in: doc.imageSize)
        guard moved != r else { return } // kenarda: boyut korunur, boş geri alma kaydı tutulmaz
        doc.beginChange()
        if tool == .redact, let s = doc.state.selectedRedaction { doc.updateRedaction(s, moved) } else { doc.setCrop(moved) }
    }
    /// Ok tuşu kaydırması: boyut korunur, köken `0...görüntü - boyut` aralığında kalır (fare taşımasıyla aynı sınırlama).
    static func nudged(_ r: CGRect, by d: CGPoint, in size: CGSize) -> CGRect {
        var o = r.offsetBy(dx: d.x, dy: d.y)
        o.origin.x = min(max(o.minX, 0), max(size.width - r.width, 0)); o.origin.y = min(max(o.minY, 0), max(size.height - r.height, 0))
        return o
    }
    /// Oran değişince kırpma: yükseklik genişlikten türetilir; görüntünün altına taşarsa yukarı kaydırılır, görüntüden yüksekse
    /// yükseklik görüntüye, genişlik orana göre küçülür. Sonuç her zaman seçilen oranda kalır.
    static func fitAspect(_ c: CGRect, ratio r: CGFloat, in size: CGSize) -> CGRect {
        var w = c.width, h = w / r
        if h > size.height { h = size.height; w = h * r }
        return CGRect(x: c.minX, y: max(min(c.minY, size.height - h), 0), width: w, height: h)
    }
    func publishInfo() {
        if tool == .redact {
            let sel = doc.state.selectedRedaction.flatMap { doc.state.redactions.indices.contains($0) ? doc.state.redactions[$0] : nil }
            onSelectionInfo?(S.editInfoRedact(doc.state.redactions.count, sel.map { S.editSizeLabel(Int($0.width), Int($0.height)) }))
        } else if let c = doc.state.crop { onSelectionInfo?(S.editInfoCrop(S.editSizeLabel(Int(c.width), Int(c.height)))) }
        else { onSelectionInfo?("\(S.editInfoNoCrop) · \(S.editSizeLabel(Int(doc.imageSize.width), Int(doc.imageSize.height)))") }
    }
}

// MARK: - Pencere

final class EditorWindowController: NSWindowController, NSWindowDelegate {
    static var current: EditorWindowController?
    private let item: ShelfItem
    private let store: ShelfStore
    private weak var panel: ShelfPresenting?
    private let doc: EditDocument
    private let canvas: EditorCanvasView
    private let scroll = NSScrollView()
    private let tools = NSSegmentedControl(labels: [S.editToolCrop, S.editToolRedact], trackingMode: .selectOne, target: nil, action: nil)
    private let aspectPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let undoButton = NSButton(), redoButton = NSButton()
    private let sizeLabel = NSTextField(labelWithString: "")
    private let formatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let progress = NSProgressIndicator()
    private var outputButtons: [NSButton] = []
    private var output = OutputSession<EditOutputSnapshot>()
    private let queue = DispatchQueue(label: "dev.shotmori.editor", qos: .userInitiated)
    private var magnifyToken: NSObjectProtocol?
    private var isClosed = false

    /// `sourceInfo` + önizleme arka planda okunur, pencere ana kuyrukta kurulur; bu sürede panel meşgul gösterilir. Okunamazsa nil.
    static func load(item: ShelfItem, store: ShelfStore, panel: ShelfPresenting?, completion: @escaping (EditorWindowController?) -> Void) {
        panel?.setBusy(S.preparingImage)
        DispatchQueue.global(qos: .userInitiated).async {
            let info = ImageResizer.sourceInfo(item.url), preview = try? EditRenderer.loadPreview(item.url)
            DispatchQueue.main.async {
                panel?.setBusy(nil)
                guard let info = info, let preview = preview else { completion(nil); return }
                completion(EditorWindowController(item: item, store: store, panel: panel, info: info, preview: preview))
            }
        }
    }
    private init(item: ShelfItem, store: ShelfStore, panel: ShelfPresenting?, info: ImageResizer.SourceInfo, preview: CGImage) {
        self.item = item; self.store = store; self.panel = panel
        doc = EditDocument(imageSize: CGSize(width: info.pixelSize.width, height: info.pixelSize.height))
        canvas = EditorCanvasView(doc: doc, preview: preview)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 656), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: w)
        w.minSize = NSSize(width: 560, height: 420); w.isReleasedWhenClosed = false
        w.level = .floating; w.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]; w.delegate = self; w.center()
        buildUI(isHEIF: ["heic", "heif"].contains(item.url.pathExtension.lowercased()))
    }
    required init?(coder: NSCoder) { fatalError() }

    private func symbolButton(_ name: String, _ label: String, _ action: Selector) -> NSButton {
        let img = NSImage(systemSymbolName: name, accessibilityDescription: label)?.withSymbolConfiguration(.init(paletteColors: [ShotmoriStyle.text])) ?? NSImage()
        let b = NSButton(image: img, target: self, action: action)
        b.bezelStyle = .texturedRounded; b.toolTip = label; b.setAccessibilityLabel(label); return b
    }
    private let infoIcon = NSImageView()
    private let zoomLabel = NSTextField(labelWithString: "")
    private let outputMenu = NSPopUpButton(frame: .zero, pullsDown: true)
    private var toolbarDelegate: EditorToolbar?
    private let lockButton = NSButton()
    private weak var rootRef: NSStackView?
    /// Test: kök yığın (başlık çubuğunun altına girmediği doğrulanır).
    var rootViewForTesting: NSView { rootRef ?? NSView() }
    private func separator() -> NSView { let v = SurfaceView(fill: ShotmoriStyle.separator, border: nil, radius: 0); v.translatesAutoresizingMaskIntoConstraints = false; v.heightAnchor.constraint(equalToConstant: 1).isActive = true; return v }
    private func buildUI(isHEIF: Bool) {
        guard let w = window, let content = w.contentView else { return }
        // Dosya adı ve ölçü/boyut başlık çubuğunda (title + subtitle); zemin sistemin (cam krom)
        let bytes = (try? FileManager.default.attributesOfItem(atPath: item.path)[.size] as? Int) ?? 0
        w.title = item.fileName
        // Araç çubuğu: Kırp/Gizle (ikon; etiket araç ipucu + VoiceOver), oran, geri/yinele · sağda yakınlaştırma — gerçek NSToolbar
        tools.target = self; tools.action = #selector(toolChanged); tools.selectedSegment = 0; tools.setAccessibilityLabel(S.editToolAX)
        tools.setImage(NSImage(systemSymbolName: "crop", accessibilityDescription: S.editToolCrop), forSegment: 0); tools.setImage(NSImage(systemSymbolName: "rectangle.fill", accessibilityDescription: S.editToolRedact), forSegment: 1)
        tools.setLabel("", forSegment: 0); tools.setLabel("", forSegment: 1); tools.setToolTip(S.editToolCrop, forSegment: 0); tools.setToolTip(S.editToolRedact, forSegment: 1); tools.setWidth(36, forSegment: 0); tools.setWidth(36, forSegment: 1)
        tools.segmentStyle = .rounded; tools.selectedSegmentBezelColor = ShotmoriStyle.accent; tools.toolTip = S.editToolAX
        for a in [CropAspect.free, .square, .wide16x9] { aspectPopup.addItem(withTitle: a.label) }
        aspectPopup.target = self; aspectPopup.action = #selector(aspectChanged); aspectPopup.toolTip = S.editAspect; aspectPopup.setAccessibilityLabel(S.editAspect)
        let undo = symbolButton("arrow.uturn.backward", S.editUndo, #selector(undoTapped)); let redo = symbolButton("arrow.uturn.forward", S.editRedo, #selector(redoTapped))
        let zoomOut = symbolButton("minus.magnifyingglass", S.editZoomOut, #selector(zoomOut)); let zoomIn = symbolButton("plus.magnifyingglass", S.editZoomIn, #selector(zoomIn))
        let zoomFit = NSButton(title: S.editZoomFit, target: self, action: #selector(zoomFit)); zoomFit.bezelStyle = .texturedRounded; zoomFit.font = ShotmoriStyle.Fonts.control; zoomFit.toolTip = S.editZoomFit
        ShotmoriStyle.label(zoomLabel, font: ShotmoriStyle.Fonts.digits, color: ShotmoriStyle.secondaryText); zoomLabel.alignment = .center; zoomLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true; zoomLabel.setAccessibilityLabel(S.editZoomAX)
        self.undoRef = undo; self.redoRef = redo
        let tb = EditorToolbar(views: .init(tools: tools, aspect: aspectPopup, undo: undo, redo: redo, zoomOut: zoomOut, zoomLabel: zoomLabel, zoomIn: zoomIn, zoomFit: zoomFit)); toolbarDelegate = tb
        w.applyGlassChrome(toolbarIdentifier: "editor", subtitle: S.editFileInfo(Int(doc.imageSize.width), Int(doc.imageSize.height), ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)), delegate: tb)
        // Tuval: esner; zemin orta koyu
        scroll.contentView = CenteringClipView(); scroll.documentView = canvas; scroll.hasHorizontalScroller = true; scroll.hasVerticalScroller = true; scroll.allowsMagnification = true; scroll.minMagnification = 0.05; scroll.maxMagnification = 8
        scroll.backgroundColor = ShotmoriStyle.canvasBackground; scroll.drawsBackground = true; scroll.borderType = .noBorder
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical); scroll.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        magnifyToken = NotificationCenter.default.addObserver(forName: NSScrollView.didEndLiveMagnifyNotification, object: scroll, queue: .main) { [weak self] _ in self?.updateZoomLabel() }
        // Alt çubuk (tek satır): biçim · kilit (ipucu: orijinal korunur) · seçim ölçüsü · … · Vazgeç · Kopyala (ana) + bitişik menü
        infoIcon.image = NSImage(systemSymbolName: "crop", accessibilityDescription: nil); infoIcon.contentTintColor = ShotmoriStyle.secondaryText; infoIcon.symbolConfiguration = .init(pointSize: 12, weight: .regular)
        ShotmoriStyle.label(sizeLabel, font: ShotmoriStyle.Fonts.control, color: ShotmoriStyle.secondaryText); sizeLabel.lineBreakMode = .byTruncatingTail
        for f in ImageOutputFormat.allCases { formatPopup.addItem(withTitle: f.label) }
        formatPopup.toolTip = S.editFormatLabel; formatPopup.setAccessibilityLabel(S.editFormatLabel); formatPopup.controlSize = .regular
        let lockHelp = isHEIF ? S.editOriginalHelp + " " + S.editHEIFNote : S.editOriginalHelp
        ShotmoriStyle.iconButton(lockButton, symbol: "lock", label: lockHelp, pointSize: 12); lockButton.isEnabled = true; lockButton.setAccessibilityRole(.staticText)
        // Tuval ipuçları (köşelerden ayarlama, ok tuşları / gizlenen alan siyaha döner) araç ipucu ve VoiceOver yardımında
        canvas.toolTip = S.editHintCrop; canvas.setAccessibilityHelp(S.editHintCrop)
        progress.style = .spinning; progress.controlSize = .small; progress.isHidden = true
        let cancel = NSButton(title: S.cancel, target: self, action: #selector(cancelTapped)); ShotmoriStyle.link(cancel); cancel.keyEquivalent = "\u{1b}"
        let copy = PrimaryButton(title: S.copyShort, image: NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil) ?? NSImage(), target: self, action: #selector(copyTapped)); copy.imagePosition = .imageLeading; ShotmoriStyle.primary(copy); copy.keyEquivalent = "\r"
        outputMenu.bezelStyle = .rounded; outputMenu.isBordered = true
        let menu = NSMenu(); menu.addItem(NSMenuItem(title: "", action: nil, keyEquivalent: "")) // pull-down başlık yuvası
        for (t, sel, sym) in [(S.copyShort, #selector(copyTapped), "doc.on.doc"), (S.resizeOutputAddToShelf, #selector(addTapped), "tray"), (S.resizeOutputSaveAs, #selector(saveTapped), "square.and.arrow.down")] {
            let mi = NSMenuItem(title: t, action: sel, keyEquivalent: ""); mi.target = self; mi.image = NSImage(systemSymbolName: sym, accessibilityDescription: nil); menu.addItem(mi)
        }
        outputMenu.menu = menu; outputMenu.setAccessibilityLabel(S.outputMenuLabel); outputMenu.toolTip = S.outputMenuLabel
        (outputMenu.cell as? NSPopUpButtonCell)?.arrowPosition = .arrowAtCenter; outputMenu.widthAnchor.constraint(equalToConstant: 30).isActive = true
        outputButtons = [copy, outputMenu]
        let ospacer = NSView(); ospacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let outRow = NSStackView(views: [formatPopup, lockButton, infoIcon, sizeLabel, ospacer, progress, cancel, copy, outputMenu]); outRow.orientation = .horizontal; outRow.spacing = 8; outRow.alignment = .centerY; outRow.edgeInsets = NSEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        outRow.setCustomSpacing(4, after: copy); outRow.setCustomSpacing(16, after: cancel); outRow.setCustomSpacing(12, after: lockButton); outRow.setCustomSpacing(4, after: infoIcon)
        let root = NSStackView(views: [scroll, separator(), outRow]); root.orientation = .vertical; root.spacing = 0; root.alignment = .width; root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root); rootRef = root
        // Üst kenar başlık çubuğunun altında (.fullSizeContentView): contentLayoutGuide
        NSLayoutConstraint.activate([root.topAnchor.constraint(equalTo: (w.contentLayoutGuide as! NSLayoutGuide).topAnchor), root.bottomAnchor.constraint(equalTo: content.bottomAnchor), root.leadingAnchor.constraint(equalTo: content.leadingAnchor), root.trailingAnchor.constraint(equalTo: content.trailingAnchor)])
        canvas.onSelectionInfo = { [weak self] t in self?.sizeLabel.stringValue = t; self?.refreshUndo() }
        canvas.publishInfo(); refreshUndo(); updateZoomLabel()
        DispatchQueue.main.async { self.zoomFit() }
    }
    private func updateZoomLabel() { zoomLabel.stringValue = S.zoomPercent(Int((scroll.magnification * 100).rounded())) }
    private weak var undoRef: NSButton?; private weak var redoRef: NSButton?
    private func refreshUndo() { undoRef?.isEnabled = doc.canUndo; redoRef?.isEnabled = doc.canRedo }

    @objc private func toolChanged() {
        canvas.tool = tools.selectedSegment == 0 ? .crop : .redact; aspectPopup.isEnabled = canvas.tool == .crop
        let h = canvas.tool == .crop ? S.editHintCrop : S.editHintRedact; canvas.toolTip = h; canvas.setAccessibilityHelp(h)
        infoIcon.image = NSImage(systemSymbolName: canvas.tool == .crop ? "crop" : "rectangle.fill", accessibilityDescription: nil); canvas.publishInfo()
    }
    @objc private func aspectChanged() {
        canvas.aspect = [CropAspect.free, .square, .wide16x9][aspectPopup.indexOfSelectedItem]
        guard let c = doc.state.crop, let r = canvas.aspect.ratio else { return }
        doc.beginChange(); doc.setCrop(EditorCanvasView.fitAspect(c, ratio: r, in: doc.imageSize))
        if doc.state.crop == c { doc.cancelChange() } // oran zaten tutuyordu: boş geri alma kaydı yok
    }
    @objc private func undoTapped() { doc.undo(); refreshUndo() }
    @objc private func redoTapped() { doc.redo(); refreshUndo() }
    @objc private func zoomIn() { scroll.magnification = min(scroll.magnification * 1.25, scroll.maxMagnification); updateZoomLabel() }
    @objc private func zoomOut() { scroll.magnification = max(scroll.magnification / 1.25, scroll.minMagnification); updateZoomLabel() }
    /// Görünür alan büyütmeden bağımsız ölçülür (`contentSize`); `contentView.bounds` büyütülmüş koordinattadır, ikinci "Sığdır" %100'e düşerdi.
    @objc private func zoomFit() {
        guard let m = EditorZoom.fitMagnification(visible: scroll.contentSize, content: canvas.intrinsicContentSize) else { return }
        scroll.magnification = m; updateZoomLabel()
    }
    func windowWillClose(_ notification: Notification) {
        isClosed = true
        if let t = magnifyToken { NotificationCenter.default.removeObserver(t); magnifyToken = nil }
    }

    // MARK: Çıktı
    private var format: ImageOutputFormat { ImageOutputFormat.allCases[formatPopup.indexOfSelectedItem] }
    /// Render anlık görüntüyle yapılır; teslim (`completion`) yalnızca belge o arada değişmediyse ve türev yazımı başarılıysa çağrılır.
    /// Çıktı biçimi render başlangıcındaki `fmt`tir; popup render sırasında değişse bile veri ile uzantı eşleşir.
    private func export(_ completion: @escaping (Data, URL?, ImageOutputFormat) -> Void, writeDerivative: Bool) {
        let state = doc.state, fmt = format, src = item.url
        output.begin(EditOutputSnapshot(state)); setBusy(true)
        queue.async {
            let result = Result { () throws -> Data in try EditRenderer.render(source: try EditRenderer.loadOriented(src), state: state, format: fmt) }
            DispatchQueue.main.async {
                guard !self.isClosed else { return }
                self.setBusy(false)
                guard self.output.canDeliver(current: EditOutputSnapshot(self.doc.state)) else { self.output.abort(); self.showError(S.outputStaleBody, title: S.outputStaleTitle); return }
                switch result {
                case .failure(let e): self.output.abort(); self.showError(e.localizedDescription)
                case .success(let data):
                    var url: URL? = nil
                    if writeDerivative {
                        let u = EditRenderer.derivativeURL(for: src, format: fmt)
                        do { try data.write(to: u, options: .atomic); url = u } catch { self.output.abort(); self.showError(error.localizedDescription); return }
                    }
                    completion(data, url, fmt)
                }
            }
        }
    }
    /// Çalışma boyunca çıktı düğmeleri ve biçim seçici kilitlenir; tuval görünür kalır.
    private func setBusy(_ b: Bool) { progress.isHidden = !b; if b { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }; outputButtons.forEach { $0.isEnabled = !b }; formatPopup.isEnabled = !b }
    private func showError(_ m: String, title: String = S.outputErrorTitle) {
        let a = NSAlert(); a.alertStyle = .warning; a.messageText = title; a.informativeText = title == S.outputErrorTitle ? S.outputErrorBody + "\n\n" + m : m
        a.addButton(withTitle: S.editKeepEditing); a.icon = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 30, weight: .regular))
        if let w = window { a.beginSheetModal(for: w) } else { a.runModal() }
    }
    @objc private func copyTapped() {
        export({ data, url, fmt in
            guard ClipboardPayload.make(edited: data, format: fmt, fileURL: url).write() else { self.output.abort(); self.showError(S.resizeErrorClipboard); return }
            self.panel?.showToast(S.editDone); self.finish()
        }, writeDerivative: true)
    }
    @objc private func addTapped() {
        export({ _, url, _ in
            guard let u = url else { self.output.abort(); self.showError(S.resizeErrorWrite); return }
            self.store.addDerivative(at: u, sourceItemID: self.item.id); self.panel?.showToast(S.editDone); self.finish()
        }, writeDerivative: true)
    }
    /// Farklı Kaydet: iptal veya yazma hatası pencereyi açık ve düzenlemeleri kirli bırakır; kaynağın kendisi hedef olamaz.
    @objc private func saveTapped() {
        export({ data, _, fmt in
            let p = NSSavePanel(); p.nameFieldStringValue = EditRenderer.derivativeURL(for: self.item.url, format: fmt).lastPathComponent; p.allowedContentTypes = [fmt.utType]
            p.beginSheetModal(for: self.window!) { r in
                guard r == .OK, let u = p.url else { self.output.abort(); return }
                do { try SafeFileCopy.write(data, to: u, source: self.item.url); self.finish() }
                catch SafeFileCopy.Failure.sameFile { self.output.abort(); self.showError(S.saveAsSameFileBody, title: S.saveAsSameFileTitle) }
                catch { self.output.abort(); self.showError(error.localizedDescription) }
            }
        }, writeDerivative: false)
    }
    @objc private func cancelTapped() { window?.performClose(nil) }
    /// Yalnızca gerçek teslimden sonra çağrılır.
    private func finish() { output.markDelivered(); close(); EditorWindowController.current = nil }

    // Kapatma güvenliği: kaydedilmemiş düzenleme varsa sor; iptalde hiçbir çıktı üretilmez.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard output.needsCloseConfirmation(hasEdits: doc.state.hasEdits) else { EditorWindowController.current = nil; return true }
        let a = NSAlert(); a.alertStyle = .warning; a.messageText = S.editUnsavedTitle; a.informativeText = S.editUnsavedBody
        ConfirmDialog.configure(a, safe: S.editKeepEditing, proceed: S.editDiscard, destructive: true, symbol: "exclamationmark.triangle") // Return/Esc → düzenlemeye dön
        if ConfirmDialog.shouldProceed(ConfirmDialog.run(a)) { EditorWindowController.current = nil; return true }
        return false
    }
    override func showWindow(_ sender: Any?) { super.showWindow(sender); window?.orderFrontRegardless(); window?.makeKey(); window?.makeFirstResponder(canvas) }
}

/// "Sığdır" hesabı (test edilebilir): kenar payı 8 pt, en çok %100.
enum EditorZoom {
    static func fitMagnification(visible: NSSize, content: NSSize) -> CGFloat? {
        guard visible.width > 16, visible.height > 16, content.width > 0, content.height > 0 else { return nil }
        return min(min((visible.width - 16) / content.width, (visible.height - 16) / content.height), 1)
    }
}

/// Görüntü görünür alandan küçükken tuvali ortalar (varsayılan klip görünümü sol-alta yaslar).
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var r = super.constrainBoundsRect(proposedBounds)
        guard let doc = documentView else { return r }
        if r.width > doc.frame.width { r.origin.x = (doc.frame.width - r.width) / 2 }
        if r.height > doc.frame.height { r.origin.y = (doc.frame.height - r.height) / 2 }
        return r
    }
}

#if DEBUG
extension EditorWindowController {
    /// Yalnız QA (`SHOTMORI_QA_EDIT`, mağaza görüntüleri): `crop=x,y,w,h;redact=x,y,w,h|x,y,w,h;tool=redact` (görüntü pikseli).
    /// Kullanıcının yapacağı düzenlemeyi modelde kurar; dosyaya yazılmaz.
    func qaApply(_ spec: String) {
        func rect(_ s: Substring) -> CGRect? { let v = s.split(separator: ",").compactMap { Double($0) }; return v.count == 4 ? CGRect(x: v[0], y: v[1], width: v[2], height: v[3]) : nil }
        var redactTool = false
        for part in spec.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1); guard kv.count == 2 else { continue }
            switch kv[0] {
            case "crop": if let r = rect(kv[1]) { doc.setCrop(r) }
            case "redact": kv[1].split(separator: "|").compactMap(rect).forEach { doc.addRedaction($0) }
            case "tool": redactTool = kv[1] == "redact"
            default: break
            }
        }
        if redactTool { tools.selectedSegment = 1; toolChanged() }
        if !doc.state.redactions.isEmpty { doc.select(doc.state.redactions.count - 1) }
    }
}
#endif
