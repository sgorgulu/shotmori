import AppKit

/// Raf sekmeleri: "Ad · N" çipleri + "+" çipi. Tıklama seçer, çift tık yerinde yeniden adlandırır, sağ tık menü açar.
/// Çizim ve renkler A rollerinden; pencereyi taşımaz (tıklama sekmeye aittir).
final class ShelfTabBar: NSView {
    struct Entry: Equatable { let id: UUID; let name: String; let count: Int; let detached: Bool }
    static let height: CGFloat = 24
    static let maxDisplayChars = 12

    /// Kimlik listesi değişince çipler yeniden kurulur; yalnız ad/sayı değiştiyse yerinde güncellenir (süren adlandırma kaybolmaz).
    var entries: [Entry] = [] { didSet { guard entries != oldValue else { return }; if Self.needsRebuild(old: oldValue, new: entries) { rebuild() } else { refreshChips() } } }
    var activeID: UUID? { didSet { if activeID != oldValue { refreshStates() } } }
    var canAdd = true { didSet { addChip.isHidden = !canAdd } }
    var onSelect: ((UUID) -> Void)?
    var onAdd: (() -> Void)?
    var onRename: ((UUID, String) -> Void)?
    var onCloseRequest: ((UUID) -> Void)?
    var onDetach: ((UUID) -> Void)?
    /// (öğe kimlikleri, hedef raf, sürükleme kaynağı — başka panelden geliyorsa aktarım sayılmaması için)
    var onDropItems: ((Set<UUID>, UUID, Any?) -> Void)?

    private var chips: [TabChip] = []
    private let addChip = TabChip(title: "+", isAdd: true)
    private var editor: NSTextField?

    override init(frame: NSRect) {
        super.init(frame: frame)
        addChip.toolTip = S.shelfTabNewHelp; addChip.setAccessibilityLabel(S.shelfTabNew)
        addChip.onClick = { [weak self] in self?.onAdd?() }
        addSubview(addChip)
        registerForDraggedTypes([ShelfPanelController.internalItemsType])
        setAccessibilityElement(true); setAccessibilityRole(.tabGroup); setAccessibilityLabel(S.shelfTitle)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var mouseDownCanMoveWindow: Bool { false }

    /// Uzun adlar ortadan kısaltılır: 12 karakterden uzun → ilk 5 + … + son 5.
    static func displayName(_ name: String, max: Int = maxDisplayChars) -> String {
        guard name.count > max else { return name }
        let head = max / 2 - 1, tail = head // 12 → 5 + … + 5
        return String(name.prefix(head)) + "…" + String(name.suffix(tail))
    }

    /// Yeniden kurma yalnız raf kimlik listesi (sayı veya sıra) değişince gerekir; ad/sayı değişimi çipleri yerinde günceller.
    static func needsRebuild(old: [Entry], new: [Entry]) -> Bool { old.map(\.id) != new.map(\.id) }
    /// Yerinde adlandırma sürüyor mu.
    var isRenaming: Bool { editor != nil }

    private func rebuild() {
        endEditing(commit: false)
        chips.forEach { $0.removeFromSuperview() }
        chips = entries.map { e in
            let id = e.id // kapanışlar kimlikle güncel girdiye bakar; ad/sayı sonradan değişse de bayatlamaz
            let c = TabChip(title: Self.title(for: e), isAdd: false)
            c.onClick = { [weak self] in self?.onSelect?(id) }
            c.onDoubleClick = { [weak self] in self?.beginRename(id) }
            c.onContextMenu = { [weak self, weak c] ev in guard let self = self, let c = c, let e = self.entry(id) else { return }; self.showMenu(for: e, chip: c, event: ev) }
            addSubview(c); return c
        }
        refreshChips()
    }
    /// Başlık, ipucu, soluklaştırma ve VoiceOver özel eylemleri (Yeniden adlandır, Rafı kapat); çipler ve süren düzenleme yerinde kalır.
    private func refreshChips() {
        for (c, e) in zip(chips, entries) {
            c.title = Self.title(for: e); c.toolTip = e.name; c.isDetached = e.detached
            var ax = [NSAccessibilityCustomAction(name: S.shelfRename) { [weak self] in self?.beginRename(e.id); return true }]
            if entries.count > 1 { ax.append(NSAccessibilityCustomAction(name: S.shelfClose) { [weak self] in self?.onCloseRequest?(e.id); return true }) }
            c.setAccessibilityCustomActions(ax)
        }
        refreshStates(); needsLayout = true
    }
    private func entry(_ id: UUID) -> Entry? { entries.first { $0.id == id } }
    private func chip(for id: UUID) -> TabChip? { guard let i = entries.firstIndex(where: { $0.id == id }), chips.indices.contains(i) else { return nil }; return chips[i] }
    private static func title(for e: Entry) -> String {
        var t = displayName(e.name); if e.count > 0 { t += " · \(e.count)" }
        if e.detached { t += " · " + S.shelfInWindowBadge }
        return t
    }
    private func refreshStates() {
        for (c, e) in zip(chips, entries) {
            c.isActive = e.id == activeID
            c.setAccessibilityLabel(S.shelfTabAX(e.name, e.count) + (c.isActive ? ", " + S.shelfTabSelectedAX : ""))
        }
    }
    /// Taşma: toplam doğal genişlik alana sığmazsa yalnız geniş çipler orantılı daralır (en az `minimum`); sığıyorsa dokunulmaz.
    static func chipWidths(natural: [CGFloat], available: CGFloat, spacing: CGFloat, minimum: CGFloat) -> [CGFloat] {
        guard !natural.isEmpty else { return [] }
        let room = available - spacing * CGFloat(natural.count - 1)
        if natural.reduce(0, +) <= room { return natural }
        var widths = natural; var fixed = Set<Int>()
        // Yinelemeli: daraltma sonucu minimumun altına inen ya da zaten payından dar olanlar sabitlenir, kalan alan diğerlerine dağıtılır.
        for _ in 0..<natural.count {
            let flex = widths.indices.filter { !fixed.contains($0) }
            guard !flex.isEmpty else { break }
            let fixedSum = fixed.reduce(0) { $0 + widths[$1] }
            let share = max((room - fixedSum) / CGFloat(flex.count), minimum)
            var changed = false
            for i in flex where natural[i] <= share { widths[i] = natural[i]; fixed.insert(i); changed = true }
            if !changed { for i in flex { widths[i] = share }; break }
        }
        return widths
    }
    override func layout() {
        super.layout()
        let addW = canAdd ? addChip.intrinsicContentSize.width + 6 : 0
        let widths = Self.chipWidths(natural: chips.map { $0.intrinsicContentSize.width }, available: max(bounds.width - addW, 0), spacing: 6, minimum: 44)
        var x: CGFloat = 0
        for (c, w) in zip(chips, widths) { c.frame = NSRect(x: x, y: 0, width: w, height: bounds.height); x += w + 6 }
        addChip.frame = NSRect(x: x, y: 0, width: addChip.intrinsicContentSize.width, height: bounds.height)
        if let ed = editor, let c = chips.first(where: { $0.editingEntryID != nil }) { ed.frame = c.frame.insetBy(dx: 0, dy: 1) }
    }

    // MARK: Bırakma hedefi (uygulama içi kare sürüklemesi → başka rafa taşı)
    private var dropChip: TabChip? { didSet { if dropChip !== oldValue { oldValue?.isDropTarget = false; dropChip?.isDropTarget = true } } }
    private func chip(at p: NSPoint) -> (TabChip, Entry)? {
        for (c, e) in zip(chips, entries) where c.frame.contains(p) { return (c, e) }
        return nil
    }
    private func dropOperation(_ sender: NSDraggingInfo) -> NSDragOperation {
        let p = convert(sender.draggingLocation, from: nil)
        guard let (c, e) = chip(at: p), e.id != activeID, !e.detached else { dropChip = nil; return [] }
        dropChip = c; return .move
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { dropOperation(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { dropOperation(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { dropChip = nil }
    override func draggingEnded(_ sender: NSDraggingInfo) { dropChip = nil }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { dropChip = nil }
        let p = convert(sender.draggingLocation, from: nil)
        guard let (_, e) = chip(at: p), e.id != activeID else { return false }
        let ids = ShelfDragWriter.itemIDs(from: sender.draggingPasteboard)
        guard !ids.isEmpty else { return false }
        onDropItems?(ids, e.id, sender.draggingSource); return true
    }

    // MARK: Yerinde yeniden adlandırma
    /// Dışarıdan (yeni raf açılınca) adlandırmayı başlat.
    func startRename(_ id: UUID) { layoutSubtreeIfNeeded(); beginRename(id) }
    private func beginRename(_ id: UUID) { guard let e = entry(id), let c = chip(for: id) else { return }; beginRename(e, in: c) }
    private func beginRename(_ e: Entry, in chip: TabChip) {
        endEditing(commit: false)
        let ed = NSTextField(string: e.name)
        ed.font = ShotmoriStyle.Fonts.secondary; ed.isBezeled = true; ed.bezelStyle = .roundedBezel; ed.focusRingType = .default
        ed.delegate = self; ed.frame = chip.frame.insetBy(dx: 0, dy: 1); ed.frame.size.width = max(chip.frame.width, 110)
        ed.setAccessibilityLabel(S.shelfRename)
        chip.editingEntryID = e.id; addChip.isHidden = true // düzenleme alanı + çipinin üstüne taşmasın
        addSubview(ed); editor = ed
        window?.makeKey() // odak çalmayan panel key değilse tuşlar ön uygulamaya gitmesin
        window?.makeFirstResponder(ed)
    }
    private func endEditing(commit: Bool) {
        guard let ed = editor else { return }
        let id = chips.first(where: { $0.editingEntryID != nil })?.editingEntryID
        chips.forEach { $0.editingEntryID = nil }
        ed.removeFromSuperview(); editor = nil; addChip.isHidden = !canAdd
        if commit, let id = id { onRename?(id, ed.stringValue) }
        window?.makeFirstResponder(window?.contentView)
    }

    // MARK: Sağ tık menüsü
    private func showMenu(for e: Entry, chip: TabChip, event: NSEvent) {
        let m = NSMenu()
        let rename = NSMenuItem(title: S.shelfRename, action: #selector(renameFromMenu(_:)), keyEquivalent: ""); rename.target = self; rename.representedObject = e.id; m.addItem(rename)
        if onDetach != nil {
            let d = NSMenuItem(title: S.shelfDetach, action: #selector(detachFromMenu(_:)), keyEquivalent: ""); d.target = self; d.representedObject = e.id
            d.isEnabled = ShelfPanelController.canDetach(e.id, in: entries.map(\.id), detached: Set(entries.filter(\.detached).map(\.id))); m.addItem(d) // son takılı raf ayrılamaz
        }
        m.addItem(.separator())
        let close = NSMenuItem(title: S.shelfClose, action: #selector(closeFromMenu(_:)), keyEquivalent: ""); close.target = self; close.representedObject = e.id; close.isEnabled = entries.count > 1; m.addItem(close)
        NSMenu.popUpContextMenu(m, with: event, for: chip)
    }
    @objc private func renameFromMenu(_ s: NSMenuItem) { if let id = s.representedObject as? UUID { beginRename(id) } }
    @objc private func detachFromMenu(_ s: NSMenuItem) { if let id = s.representedObject as? UUID { onDetach?(id) } }
    @objc private func closeFromMenu(_ s: NSMenuItem) { if let id = s.representedObject as? UUID { onCloseRequest?(id) } }
}

extension ShelfTabBar: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.insertNewline(_:)) { endEditing(commit: true); return true }
        if sel == #selector(NSResponder.cancelOperation(_:)) { endEditing(commit: false); return true }
        return false
    }
    func controlTextDidEndEditing(_ obj: Notification) { endEditing(commit: true) }
    func controlTextDidChange(_ obj: Notification) {
        guard let ed = obj.object as? NSTextField, ed.stringValue.count > ShelfStore.maxNameLength else { return }
        ed.stringValue = String(ed.stringValue.prefix(ShelfStore.maxNameLength))
    }
}

/// Tek sekme çipi. Etkin: selectionFill zemin + accent metin; pasif: elevated zemin + secondaryText; "+" çipi daima pasif görünüm.
final class TabChip: NSView {
    private let label = NSTextField(labelWithString: "")
    private var textWidth: CGFloat = 0
    let isAdd: Bool
    /// Görünen başlık ("Ad · N"); değişince genişlik ve erişilebilirlik etiketi yenilenir, çip yerinde kalır.
    var title: String { didSet { guard title != oldValue else { return }; label.stringValue = title; label.sizeToFit(); textWidth = label.frame.width; setAccessibilityLabel(title); invalidateIntrinsicContentSize(); needsLayout = true } }
    var isActive = false { didSet { restyle() } }
    var isDetached = false { didSet { alphaValue = isDetached ? 0.6 : 1 } }
    var isDropTarget = false { didSet { needsDisplay = true } }
    var editingEntryID: UUID? { didSet { label.isHidden = editingEntryID != nil } }
    var onClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onContextMenu: ((NSEvent) -> Void)?

    init(title: String, isAdd: Bool) {
        self.isAdd = isAdd; self.title = title
        super.init(frame: .zero)
        label.font = ShotmoriStyle.Fonts.secondary; label.stringValue = title; label.alignment = .center; label.lineBreakMode = .byTruncatingMiddle; label.sizeToFit(); textWidth = label.frame.width
        addSubview(label); restyle()
        setAccessibilityElement(true); setAccessibilityRole(isAdd ? .button : .radioButton); setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var mouseDownCanMoveWindow: Bool { false }
    /// Odak çalmayan panelde (becomesKeyOnlyIfNeeded) sekmeye tıklama paneli key yapar; adlandırma tuşları başka uygulamaya gitmez.
    override var needsPanelToBecomeKey: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: textWidth + (isAdd ? 16 : 18), height: ShelfTabBar.height) }
    override func layout() { super.layout(); label.frame = NSRect(x: 6, y: (bounds.height - label.frame.height) / 2, width: max(bounds.width - 12, 0), height: label.frame.height) }
    private func restyle() { label.textColor = isActive ? ShotmoriStyle.accent : ShotmoriStyle.secondaryText; setAccessibilityValue(isActive ? 1 : 0); needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let p = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        (isActive ? ShotmoriStyle.selectionFill : ShotmoriStyle.elevated).setFill(); p.fill()
        (isDropTarget ? ShotmoriStyle.accent : (isActive ? ShotmoriStyle.selectionFill : ShotmoriStyle.separator)).setStroke(); p.lineWidth = isDropTarget ? 2 : 1; p.stroke()
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2, !isAdd { onDoubleClick?() } else if event.clickCount == 1 { onClick?() }
    }
    override func rightMouseDown(with event: NSEvent) { if !isAdd { onContextMenu?(event) } }
    override func accessibilityPerformPress() -> Bool { onClick?(); return true }
}
