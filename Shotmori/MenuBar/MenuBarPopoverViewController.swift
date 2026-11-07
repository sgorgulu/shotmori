import AppKit

/// Menü çubuğu popover'ı: aynı ShelfStore, son görüntülerin gerçek küçük resimleri, sürükleme kaynağı,
/// seçili görüntü için Kopyala / Paylaş / Diğer İşlemler, Rafı Göster, küçük Ayarlar / Yardım / Çık.
final class MenuBarPopoverViewController: NSViewController, NSDraggingSource {
    weak var app: AppController?
    /// Popover genişliğine sığan kart sayısı: uzlaştırma, görünümler ve küçük resimler yalnız bu kadar öğeyle yapılır (görünmeyen kart seçili kalmaz).
    static let visibleThumbs = 3
    private var sel = ShelfSelection()
    private var itemViews: [ThumbnailItemView] = []
    private let titleLabel = NSTextField(labelWithString: S.appName)
    private let countChip = ChipView("")
    private let strip = NonMovingView()
    private let emptyTitle = NSTextField(labelWithString: S.popoverEmptyTitle)
    private let moreCountButton = NSButton(title: "", target: nil, action: nil)
    private let copyButton = PrimaryButton(title: S.actionCopyImage, target: nil, action: nil)
    private let shareButton = NSButton(title: S.actionShare, target: nil, action: nil)
    private let moreButton = NSButton()
    private let showShelfButton = NSButton()
    private let settingsButton = NSButton()
    private let helpButton = NSButton()
    private let quitButton = NSButton(title: S.quitShort, target: nil, action: nil)
    /// Raf seçici: yalnız 2+ rafta görünür; seçim etkin rafı değiştirir (panel ve rozet de izler).
    private let shelfPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    var onDragStateChanged: ((Bool) -> Void)?
    var onRequestClose: (() -> Void)?

    private let emptyIcon = NSImageView()
    private let emptyChip = ChipView(ScreenshotHotKeys.area, font: ShotmoriStyle.Fonts.control, color: ShotmoriStyle.text)
    /// Klasör yokken kısayol rozeti yerine "Klasör Seç…" bağlantısı.
    private let emptyChooseButton = NSButton(title: S.chooseFolder, target: nil, action: nil)
    /// Yerleşim (üstten): kenar 16 · başlık 28 · 12 · şerit 122 · 10 · düğme sırası 28 · 10 · alt bilgi 20 · kenar 16 = 262.
    static let W: CGFloat = 400, H: CGFloat = 262
    private static let edge: CGFloat = 16
    /// İkon düğmeleri (test: hepsinin etiketi ve araç ipucu var).
    var iconButtonsForTesting: [NSButton] { [showShelfButton, settingsButton, helpButton] }
    /// Test: boş durum başlığı (VoiceOver yardımı).
    var emptyTitleForTesting: NSTextField { emptyTitle }
    /// Sayaç kapsülü: "3" ya da "3 · 2 yeni"; tam cümle (`countText`) VoiceOver içindir.
    static func pillText(total: Int, newCount: Int) -> String { newCount > 0 ? "\(total) · \(S.newCount(newCount))" : "\(total)" }

    override func loadView() {
        let W = Self.W, H = Self.H, e = Self.edge
        let v = NonMovingView(frame: NSRect(x: 0, y: 0, width: W, height: H)); view = v // saydam: sistem popover camı görünür
        ShotmoriStyle.label(titleLabel, font: ShotmoriStyle.Fonts.title)
        ShotmoriStyle.label(emptyTitle, font: ShotmoriStyle.Fonts.emphasis); emptyTitle.alignment = .center
        // Başlık satırı: ikon, ad, sayaç kapsülü; sağda raf seçici + "Rafı göster" ikonu
        let icon = NSImageView(image: NSApp.applicationIconImage); icon.imageScaling = .scaleProportionallyUpOrDown; icon.setAccessibilityElement(false) /* süs: ad başlıkta */; icon.frame = NSRect(x: e, y: H - e - 24, width: 24, height: 24)
        titleLabel.sizeToFit(); titleLabel.frame.origin = NSPoint(x: e + 32, y: H - e - 20)
        countChip.frame = NSRect(x: titleLabel.frame.maxX + 8, y: H - e - 22, width: 40, height: ShotmoriStyle.Metric.chipHeight)
        ShotmoriStyle.iconButton(showShelfButton, symbol: "rectangle.stack", label: S.popoverShowShelf, pointSize: 15, color: ShotmoriStyle.text)
        showShelfButton.target = self; showShelfButton.action = #selector(showShelfTapped); showShelfButton.frame = NSRect(x: W - e - 28, y: H - e - 26, width: 28, height: 28)
        shelfPicker.controlSize = .small; shelfPicker.font = ShotmoriStyle.Fonts.secondary; shelfPicker.target = self; shelfPicker.action = #selector(shelfPicked); shelfPicker.isHidden = true
        shelfPicker.setAccessibilityLabel(S.popoverShelfPicker); shelfPicker.toolTip = S.popoverShelfPicker
        // Şerit: `visibleThumbs` kart
        let stripH = ThumbnailItemView.popoverSize.height + 4
        strip.frame = NSRect(x: e - 6, y: H - e - 28 - 12 - stripH, width: CGFloat(Self.visibleThumbs) * ThumbnailItemView.popoverSize.width, height: stripH)
        // Boş durum: hiyerarşik sembol + tek satır + kısayol kapsülü / Klasör Seç…; ikinci cümle araç ipucunda
        emptyIcon.image = NSImage(systemSymbolName: "photo.badge.plus", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 28, weight: .regular).applying(.init(hierarchicalColor: ShotmoriStyle.accent)))
        emptyIcon.frame = NSRect(x: W / 2 - 18, y: strip.frame.maxY - 44, width: 36, height: 36); emptyIcon.toolTip = S.popoverEmptyBody; emptyIcon.setAccessibilityElement(false) /* süs; açıklama başlığın yardımında */
        emptyTitle.frame = NSRect(x: e, y: strip.frame.maxY - 70, width: W - 2 * e, height: 18)
        let cs = emptyChip.intrinsicContentSize; emptyChip.frame = NSRect(x: W / 2 - cs.width / 2, y: strip.frame.maxY - 100, width: cs.width, height: 22)
        ShotmoriStyle.link(emptyChooseButton); emptyChooseButton.target = self; emptyChooseButton.action = #selector(chooseFolderTapped); emptyChooseButton.sizeToFit()
        emptyChooseButton.frame.origin = NSPoint(x: W / 2 - emptyChooseButton.frame.width / 2, y: emptyChip.frame.midY - emptyChooseButton.frame.height / 2); emptyChooseButton.isHidden = true
        // Düğme sırası (düz düğmeler; popover gövdesi zaten cam): Kopyala (ana) · Paylaş · İşlemler (ikon)
        let by = strip.frame.minY - 10 - ShotmoriStyle.Metric.control, bh = ShotmoriStyle.Metric.control
        for b in [copyButton, shareButton] { b.target = self; b.imagePosition = .imageLeading }
        copyButton.action = #selector(copyTapped); copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil); ShotmoriStyle.primary(copyButton)
        shareButton.action = #selector(shareTapped); shareButton.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil); ShotmoriStyle.secondary(shareButton)
        // İşlemler: kenarlıklı düz düğme, yalnız ikon; adı araç ipucu + VoiceOver'da
        moreButton.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: S.popoverMore)?.withSymbolConfiguration(.init(pointSize: 14, weight: .medium)); moreButton.imagePosition = .imageOnly; moreButton.title = ""
        ShotmoriStyle.secondary(moreButton); moreButton.toolTip = S.popoverMore; moreButton.setAccessibilityLabel(S.popoverMore); moreButton.target = self; moreButton.action = #selector(moreTapped)
        let moreW: CGFloat = 44, gap: CGFloat = 8
        let flexW = (W - 2 * e - moreW - 2 * gap) / 2
        copyButton.frame = NSRect(x: e, y: by, width: flexW, height: bh); shareButton.frame = NSRect(x: e + flexW + gap, y: by, width: flexW, height: bh)
        moreButton.frame = NSRect(x: e + 2 * (flexW + gap), y: by, width: moreW, height: bh)
        // Alt bilgi: Ayarlar (ikon) · Yardım (ikon) · "N daha ›" · Çık
        let fy = e
        ShotmoriStyle.iconButton(settingsButton, symbol: "gearshape", label: S.menuSettings, pointSize: 14); settingsButton.target = self; settingsButton.action = #selector(settingsTapped); settingsButton.frame = NSRect(x: e - 4, y: fy - 2, width: 26, height: 24)
        ShotmoriStyle.iconButton(helpButton, symbol: "questionmark.circle", label: S.menuHelp, pointSize: 14); helpButton.target = self; helpButton.action = #selector(helpTapped); helpButton.frame = NSRect(x: settingsButton.frame.maxX + 6, y: fy - 2, width: 26, height: 24)
        ShotmoriStyle.link(quitButton, color: ShotmoriStyle.secondaryText); quitButton.target = self; quitButton.action = #selector(quitTapped); quitButton.sizeToFit(); quitButton.setAccessibilityLabel(S.menuQuit)
        quitButton.frame.origin = NSPoint(x: W - e - quitButton.frame.width, y: fy)
        ShotmoriStyle.link(moreCountButton); moreCountButton.target = self; moreCountButton.action = #selector(showShelfTapped); moreCountButton.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil); moreCountButton.imagePosition = .imageTrailing
        [icon, titleLabel, countChip, shelfPicker, showShelfButton, strip, emptyIcon, emptyTitle, emptyChip, emptyChooseButton, moreCountButton, copyButton, shareButton, moreButton, settingsButton, helpButton, quitButton].forEach { v.addSubview($0) }
        v.setAccessibilityLabel(S.appName)
    }
    override func viewWillAppear() { super.viewWillAppear(); reload() }

    /// Popover'da gösterilen (ve seçilebilen) öğeler: etkin rafın en yeni `visibleThumbs` öğesi.
    static func visibleItems(_ items: [ShelfItem]) -> [ShelfItem] { Array(items.prefix(visibleThumbs)) }

    func reload() {
        guard let app = app else { return }
        let items = Self.visibleItems(app.store.items)
        let newIDs = Set(app.store.itemsSinceLastHandoff().map(\.id))
        sel.reconcile(existing: items.map(\.id))
        if sel.isEmpty, let f = items.first { sel.selectOnly(f.id) }
        itemViews.forEach { $0.removeFromSuperview() }
        itemViews = items.map { item in
            let v = ThumbnailItemView(item: item, size: ThumbnailItemView.popoverSize); v.isMissing = !item.exists || !app.isAccessible(item); v.isNew = newIDs.contains(item.id); v.isSelected = sel.contains(item.id)
            #if SHOTMORI_CLOUD
            v.cloudBadge = app.cloud.badge(for: item)
            #endif
            v.image = ThumbnailCache.shared.cached(item.url); if v.image == nil, !v.isMissing { ThumbnailCache.shared.thumbnail(for: item.url) { [weak v] i in v?.image = i } }
            v.onMouseDown = { [weak self] view, ev in guard let self = self else { return }; self.sel.mouseDown(on: view.item.id, order: self.itemViews.map(\.item.id), command: ev.modifierFlags.contains(.command), shift: ev.modifierFlags.contains(.shift)); self.applySelection() }
            v.onMouseUpWithoutDrag = { [weak self] view, ev in guard let self = self else { return }; let n = self.sel.count; self.sel.mouseUpWithoutDrag(on: view.item.id, command: ev.modifierFlags.contains(.command), shift: ev.modifierFlags.contains(.shift)); if n != self.sel.count { self.applySelection() } }
            v.onDrag = { [weak self] view, ev in self?.beginDrag(from: view, event: ev) }
            v.onDoubleClick = { [weak self] _ in self?.copyTapped() }
            v.onContextMenu = { [weak self] view, ev in self?.contextMenu(view, ev) }
            v.onRemoveTapped = { [weak self] view in self?.run("remove-from-shelf", items: [view.item], anchor: view) }
            return v
        }
        var x: CGFloat = 0
        // Popover genişliğine sığdır: en yeni `visibleThumbs` kare görünür; tam raf "N görüntü daha ›" ile açılır, görünmeyen dosyalar kaybolmaz.
        for v in itemViews { v.frame.origin = NSPoint(x: x, y: 2); strip.addSubview(v); x += ThumbnailItemView.popoverSize.width }
        let total = app.store.items.count, hidden = total - min(total, Self.visibleThumbs)
        moreCountButton.isHidden = hidden <= 0
        if hidden > 0 {
            moreCountButton.title = S.popoverMoreCount(hidden); ShotmoriStyle.link(moreCountButton); moreCountButton.sizeToFit()
            moreCountButton.frame = NSRect(x: quitButton.frame.minX - 16 - moreCountButton.frame.width - 4, y: Self.edge - 2, width: moreCountButton.frame.width + 4, height: 20)
        }
        countChip.text = Self.pillText(total: total, newCount: app.store.newCountAll); countChip.setAccessibilityLabel(Self.countText(total: total, newCount: app.store.newCountAll))
        countChip.frame.size.width = countChip.intrinsicContentSize.width
        reloadShelfPicker(app)
        let empty = items.isEmpty
        emptyChip.text = ScreenshotHotKeys.area
        let emptyBody = FolderPrompt.emptyBody(folder: app.folder, otherwise: S.popoverEmptyBody)
        emptyIcon.toolTip = emptyBody; emptyTitle.setAccessibilityHelp(emptyBody) // VoiceOver: araç ipucundaki açıklama boş durum başlığında
        [emptyIcon, emptyTitle, emptyChip].forEach { $0.isHidden = !empty }; strip.isHidden = empty
        if app.folder == nil { emptyChip.isHidden = true } // kısayol ipucu klasör yokken yanıltır; yerine klasör seçme bağlantısı
        emptyChooseButton.isHidden = !(empty && app.folder == nil)
        applySelection()
    }
    /// Sayaç: etkin raftaki görüntü sayısı + tüm raflardaki "yeni" toplamı (menü çubuğu rozetiyle aynı sayı);
    /// etkin raf boşken bile başka rafta yeni varsa "Raf boş · N yeni" denir, rozet 3 derken popover 0 demez.
    static func countText(total: Int, newCount: Int) -> String {
        let base = total == 0 ? S.popoverCount(0) : S.imageCount(total)
        return newCount > 0 ? "\(base) · \(S.newCount(newCount))" : base
    }
    private func reloadShelfPicker(_ app: AppController) {
        let shelves = app.store.shelves
        shelfPicker.isHidden = shelves.count < 2
        guard shelves.count >= 2 else { return }
        shelfPicker.removeAllItems()
        for sh in shelves { shelfPicker.addItem(withTitle: sh.items.isEmpty ? sh.name : "\(sh.name) · \(sh.items.count)"); shelfPicker.lastItem?.representedObject = sh.id }
        if let i = shelves.firstIndex(where: { $0.id == app.store.activeShelfID }) { shelfPicker.selectItem(at: i) }
        shelfPicker.sizeToFit()
        // Sayaç kapsülü kesilmez; yer darsa raf seçici daralır (adı kendisi kısaltır).
        let room = showShelfButton.frame.minX - 8 - (countChip.frame.maxX + 8)
        let w = max(min(max(shelfPicker.frame.width, 90), 150, room), 70)
        shelfPicker.frame = NSRect(x: showShelfButton.frame.minX - 8 - w, y: showShelfButton.frame.minY + 2, width: w, height: 24)
    }
    @objc private func shelfPicked() {
        guard let app = app, let id = shelfPicker.selectedItem?.representedObject as? UUID, id != app.store.activeShelfID else { return }
        sel = ShelfSelection(); app.store.setActiveShelf(id: id); reload()
        if let sh = app.store.shelves.first(where: { $0.id == id }) { AXAnnounce.post(S.shelfSwitchedAX(sh.name)) }
    }
    private func applySelection() {
        itemViews.forEach { $0.isSelected = sel.contains($0.item.id) }
        let items = selectedItems()
        let n = items.count
        copyButton.isEnabled = !items.isEmpty && items.allSatisfy(\.exists); copyButton.toolTip = items.isEmpty ? S.popoverNoSelection : (n > 1 ? S.appliesToSelection : nil)
        shareButton.isEnabled = copyButton.isEnabled; shareButton.toolTip = copyButton.toolTip
        moreButton.isEnabled = !items.isEmpty
        copyButton.title = S.copyShortCount(n)
    }
    /// Eylemler yalnız görünen kartlara uygulanır: seçim görünmeyen bir kareye kaymış olsa bile (COR-06).
    func selectedItems() -> [ShelfItem] { Self.visibleItems(app?.store.items ?? []).filter { sel.contains($0.id) } }
    private func run(_ id: String, items: [ShelfItem], anchor: NSView?) { guard let app = app else { return }; app.shelf.run(id, items: items, anchor: anchor) }

    @objc private func copyTapped() { run("copy-image", items: selectedItems(), anchor: copyButton) }
    @objc private func shareTapped() { run("share", items: selectedItems(), anchor: shareButton) }
    @objc private func moreTapped() { guard let app = app else { return }; let m = app.registry.menu(for: selectedItems(), store: app.store, anchor: moreButton, panel: app.shelf); m.popUp(positioning: nil, at: NSPoint(x: 0, y: moreButton.bounds.height + 4), in: moreButton) }
    @objc private func showShelfTapped() { onRequestClose?(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.app?.shelf.show(takeKey: true) } }
    @objc private func settingsTapped() { onRequestClose?(); app?.openSettings() }
    @objc private func helpTapped() { guard let app = app else { return }; Self.helpMenu(hasFolder: app.folder != nil, popover: self, app: app).popUp(positioning: nil, at: NSPoint(x: 0, y: helpButton.bounds.height + 4), in: helpButton) } // düğmeye bağlı: klavye/VoiceOver ile açılınca da imlecin yerinde değil
    /// Yardım menüsü: klasör yoksa en üstte "İzlenen klasörü seç…"; "Panodan ekle" (sağ tık menüsündeki eylem popover'dan da bulunur); kurulum, günlük, hakkında.
    static func helpMenu(hasFolder: Bool, popover: AnyObject?, app: AnyObject?) -> NSMenu {
        let m = NSMenu(); m.autoenablesItems = false
        func add(_ t: String, _ sel: Selector, _ target: AnyObject?) { let i = NSMenuItem(title: t, action: sel, keyEquivalent: ""); i.target = target; m.addItem(i) }
        if !hasFolder { add(S.menuChooseFolder, #selector(chooseFolderTapped), popover) }
        add(S.menuAddFromClipboard, #selector(addFromClipboardTapped), popover); m.addItem(.separator())
        add(S.menuRerunSetup, #selector(AppController.rerunOnboarding), app); add(S.menuShowLog, #selector(AppController.showLog), app)
        m.addItem(.separator()); add(S.menuAbout, #selector(AppController.showAbout), app)
        return m
    }
    @objc private func chooseFolderTapped() { onRequestClose?(); app?.chooseWatchedFolder() }
    @objc private func addFromClipboardTapped() { onRequestClose?(); app?.addFromClipboard() }
    @objc private func quitTapped() { NSApp.terminate(nil) }
    private func contextMenu(_ v: ThumbnailItemView, _ ev: NSEvent) { if !sel.contains(v.item.id) { sel.selectOnly(v.item.id); applySelection() }; guard let app = app else { return }; NSMenu.popUpContextMenu(app.registry.menu(for: selectedItems(), store: app.store, anchor: v, panel: app.shelf), with: ev, for: v) }

    // Sürükleme kaynağı: gerçek dosya URL'leri; popover sürükleme bitene kadar açık tutulur.
    private func beginDrag(from view: ThumbnailItemView, event: NSEvent) {
        if !sel.contains(view.item.id) { sel.selectOnly(view.item.id); applySelection() }
        let pairs = selectedItems().compactMap { it in ShelfPanelController.dragWriter(for: it).map { (it, $0) } }; guard !pairs.isEmpty else { return }
        let items = pairs.map(\.0)
        let dragItems: [NSDraggingItem] = pairs.enumerated().map { i, pair in
            let it = pair.0
            let d = NSDraggingItem(pasteboardWriter: pair.1)
            let img = (ThumbnailCache.shared.cached(it.url) ?? NSWorkspace.shared.icon(forFile: it.path)).withCountBadge(i == 0 ? items.count : 1)
            let base = view.convert(view.bounds.insetBy(dx: 10, dy: 20), to: nil); let off = CGFloat(i) * 5
            d.setDraggingFrame(NSRect(x: base.minX + off, y: base.minY - off, width: base.width, height: base.height), contents: img); return d
        }
        onDragStateChanged?(true)
        Log.info("Popover sürükleme başladı: \(items.count) dosya")
        view.beginDraggingSession(with: dragItems, event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { ShelfPanelController.dragOperationMask(outside: context == .outsideApplication, allowsInternalMove: false) }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let accepted = !operation.isEmpty
        Log.info("Popover sürükleme bitti: \(accepted ? "kabul" : "reddedildi/iptal")")
        onDragStateChanged?(false)
        if accepted { app?.store.markHandoff(); onRequestClose?() }
    }
}
