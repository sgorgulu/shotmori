import AppKit

/// Panelin tüm davranışı: gösterme/gizleme, seçim, sürükleme kaynağı, klavye, favori çubuğu.
/// Şerit ve kaydırma alanı: boşluğa basmak pencereyi taşımasın (yalnızca başlık alanı taşır).
final class NonMovingView: NSView { override var mouseDownCanMoveWindow: Bool { false } }

final class ShelfPanelController: NSObject, NSDraggingSource, ShelfPresenting {
    /// `.main`: sekmeler, kısayol, etkin raf. `.detached(id)`: tek raf kendi yüzen panelinde — sekme yok, başlıkta raf adı + "Geri tak",
    /// iğne gizli ve zorunlu açık; Esc/Gizle paneli kapatıp rafı sekmeye geri takar (`onReattach`).
    enum Mode: Equatable { case main, detached(UUID) }
    let mode: Mode
    let store: ShelfStore
    let registry: ActionRegistry
    let prefs: Preferences
    let panel = ShelfPanel()

    /// Zemin: cam (26+) / Material (14–15); tüm alt görünümler `background.contentView`'a eklenir. Cam zemin üstünde düğmeler düz.
    private let background = GlassSurfaceView(cornerRadius: ShotmoriStyle.Metric.glassRadius)
    private var content: NSView { background.contentView }
    private let titleLabel = NSTextField(labelWithString: S.shelfTitle)
    private let titleIcon = NSImageView(image: NSApp.applicationIconImage)
    private let countChip = ChipView("")
    private let hideButton = NSButton()
    private let emptyIcon = NSImageView(image: NSImage(systemSymbolName: "tray", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 30, weight: .regular).applying(.init(hierarchicalColor: ShotmoriStyle.accent))) ?? NSImage())
    private let emptyTitle = NSTextField(labelWithString: S.emptyShelfTitle)
    /// İzlenen klasör (AppController verir); nil dönerse boş raf "klasör seçin" der. Atanmamışsa klasör var sayılır.
    var watchedFolder: (() -> URL?)?
    /// Öğe erişim kapsamında mı (sandbox): dışındakiler "eksik" görünür. Atanmamışsa erişilebilir sayılır.
    var itemAccessible: ((ShelfItem) -> Bool)?
    private let emptyChip = ChipView(ScreenshotHotKeys.area, font: ShotmoriStyle.Fonts.control, color: ShotmoriStyle.text)
    /// Klasör yokken boş rafta kısayol rozeti yerine "Klasör Seç…" bağlantısı; AppController `chooseWatchedFolder` bağlar.
    private let emptyChooseButton = NSButton(title: S.chooseFolder, target: nil, action: nil)
    var onChooseFolder: (() -> Void)?
    private let scroll = NSScrollView()
    private let strip = NonMovingView()
    private let favoritesBar = NSStackView()
    private let tabBar = ShelfTabBar(frame: .zero)
    private let toastBox = SurfaceView(fill: ShotmoriStyle.elevated, border: ShotmoriStyle.separator, radius: ShotmoriStyle.Metric.groupRadius)
    private let toast = NSTextField(labelWithString: "")
    /// Yerleşim (v2): kenar 14 · başlık 20 · 8 · sekmeler 24 · 6 · şerit 122 · 18 · favoriler 28 · kenar 14 → 254; ayrılmış panelde sekme satırı yok → 224.
    static func panelHeight(showsTabs: Bool) -> CGFloat { showsTabs ? 254 : 254 - ShelfTabBar.height - 6 }
    private var panelHeight: CGFloat { Self.panelHeight(showsTabs: showsTabs) }
    private static let edge: CGFloat = 14
    private var itemViews: [ThumbnailItemView] = []
    private var sel = ShelfSelection()
    var selection: Set<UUID> { sel.ids }
    private var order: [UUID] { itemViews.map(\.item.id) }
    private var outsideClickMonitor: Any?
    /// Oturum içi iğne; başlangıç değeri tercihten gelir ve iğne düğmesi tercihi de günceller.
    private var pinnedOpen = false
    private let pinButton = NSButton(image: NSImage(systemSymbolName: "pin", accessibilityDescription: nil) ?? NSImage(), target: nil, action: nil)
    private var status = StatusCenter()
    #if SHOTMORI_CLOUD
    weak var cloud: CloudCenter?
    #endif
    private var overflowFavorites: [ShelfAction] = []
    /// Favori çubuğundaki İşlemler düğmesi: ⌘K menüyü buna çapalar.
    private var moreButton: NSButton?
    /// Kurulu favori düğmeleri (`registry.favorites` sırasıyla) ve kuruldukları liste.
    private var favoriteButtons: [NSButton] = []
    private var favoriteIDs: [String] = []
    private let toastClose = NSButton()
    private let toastRetry = NSButton(title: "", target: nil, action: nil)
    /// Kalıcı bildirimin eylem bağlantısı (başlık eylemden); nil → düğme gizli.
    private var noticeAction: NoticeAction?
    private var keyObservers: [Any] = []
    /// Uygulama içi sürükleme yükü: öğe kimlikleri (JSON [UUID]).
    static let internalItemsType = NSPasteboard.PasteboardType("dev.shotmori.shelf-items")
    private(set) var internalDropHandled = false
    /// Sekmeye bırakma gerçekleşti: bayrak sürüklemeyi başlatan panelde (ayrılmış pencere olabilir) işaretlenir; o panel aktarım saymaz.
    func noteInternalDrop(from source: Any?) { ((source as? ShelfPanelController) ?? self).internalDropHandled = true }
    var isBusy: Bool { status.isBusy }
    private var storeObserver: UUID?
    /// Ayrılmış panel kapanınca (Esc / Geri tak) çağrılır; AppController rafı sekmeye geri takar.
    var onReattach: (() -> Void)?
    /// Ana panel: pencerede duran raflar (sekmede soluk + "pencerede" rozeti; tıklanınca pencere öne gelir).
    var detachedShelves: Set<UUID> = [] { didSet { if detachedShelves != oldValue { refreshTabs() } } }
    var onDetachRequest: ((UUID) -> Void)?
    var onDetachedTabClicked: ((UUID) -> Void)?
    var showsTabs: Bool { mode == .main }
    var isPinned: Bool { pinnedOpen }
    /// Gösterilen raf: ana panelde etkin raf, ayrılmış panelde kendi rafı.
    var displayedShelfID: UUID { if case .detached(let id) = mode { return id }; return store.activeShelfID }
    private var displayedShelf: Shelf? { store.shelves.first { $0.id == displayedShelfID } }
    var displayedItems: [ShelfItem] { displayedShelf?.items ?? [] }

    init(store: ShelfStore, registry: ActionRegistry, prefs: Preferences, mode: Mode = .main) {
        self.store = store; self.registry = registry; self.prefs = prefs; self.mode = mode
        super.init()
        panel.controller = self
        buildUI()
        // Panel gizliyken depo değişimi çizilmez; bir sonraki `show` her zaman yeniden kurar.
        storeObserver = store.addObserver { [weak self] in self?.reload() }
        rebuild() // ilk kurulum (başlık, boş durum) görünmeden de hazır olsun
        // Klavye odağı halkası: panel key iken seçim çapasında görünür, değilken kaybolur (seçimden ayrı).
        for n in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            keyObservers.append(NotificationCenter.default.addObserver(forName: n, object: panel, queue: .main) { [weak self] _ in self?.applyFocusRing() })
        }
    }
    deinit { if let t = storeObserver { store.removeObserver(t) }; keyObservers.forEach { NotificationCenter.default.removeObserver($0) }; removeOutsideClickMonitor() }
    private func applyFocusRing() { let key = panel.isKeyWindow; itemViews.forEach { $0.isKeyboardFocused = key && $0.item.id == sel.anchor } }

    // MARK: UI kurulumu
    private func buildUI() {
        panel.contentView = background
        ShotmoriStyle.label(titleLabel, font: ShotmoriStyle.Fonts.title)
        titleIcon.imageScaling = .scaleProportionallyUpOrDown
        pinButton.isBordered = false; pinButton.imagePosition = .imageOnly; pinButton.target = self; pinButton.action = #selector(pinTapped); pinButton.setButtonType(.toggle)
        pinButton.alternateImage = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil); pinButton.toolTip = S.shelfPinHelp; pinButton.setAccessibilityLabel(S.shelfPin)
        pinnedOpen = showsTabs ? prefs.keepShelfOpen : true; pinButton.state = pinnedOpen ? .on : .off; pinButton.isHidden = !showsTabs
        // Gizle / Geri tak: ikon düğmesi (xmark / arrow.uturn.backward), adı ve Esc araç ipucu + VoiceOver'da
        ShotmoriStyle.iconButton(hideButton, symbol: showsTabs ? "xmark" : "arrow.uturn.backward", label: "\(showsTabs ? S.hideShelf : S.shelfReattach) (Esc)", pointSize: 12)
        hideButton.target = self; hideButton.action = #selector(hideTapped); tabBar.isHidden = !showsTabs
        ShotmoriStyle.label(emptyTitle, font: ShotmoriStyle.Fonts.title)
        ShotmoriStyle.link(emptyChooseButton, color: ShotmoriStyle.accent); emptyChooseButton.target = self; emptyChooseButton.action = #selector(chooseFolderTapped); emptyChooseButton.sizeToFit(); emptyChooseButton.isHidden = true
        ShotmoriStyle.label(toast, font: ShotmoriStyle.Fonts.emphasis); toast.alignment = .center; toast.lineBreakMode = .byTruncatingTail
        toastClose.isBordered = false; toastClose.imagePosition = .imageOnly; toastClose.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: S.noticeDismiss)?.withSymbolConfiguration(.init(pointSize: 9, weight: .bold))
        toastClose.contentTintColor = ShotmoriStyle.secondaryText; toastClose.target = self; toastClose.action = #selector(dismissNotice); toastClose.setAccessibilityLabel(S.noticeDismiss); toastClose.toolTip = S.noticeDismiss
        ShotmoriStyle.link(toastRetry, color: ShotmoriStyle.accent); toastRetry.target = self; toastRetry.action = #selector(noticeActionTapped); toastRetry.isHidden = true
        toastBox.addSubview(toast); toastBox.addSubview(toastClose); toastBox.addSubview(toastRetry); toastBox.alphaValue = 0

        scroll.hasHorizontalScroller = true; scroll.hasVerticalScroller = false; scroll.drawsBackground = false
        scroll.scrollerStyle = .overlay; scroll.horizontalScrollElasticity = .allowed; scroll.verticalScrollElasticity = .none
        scroll.documentView = strip
        scroll.contentView.postsBoundsChangedNotifications = true
        keyObservers.append(NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { [weak self] _ in self?.refreshQuickNumbers() })

        wireTabBar()
        favoritesBar.orientation = .horizontal; favoritesBar.spacing = ShotmoriStyle.Metric.space8; favoritesBar.alignment = .centerY; favoritesBar.distribution = .fill
        [titleIcon, titleLabel, countChip, pinButton, hideButton, tabBar, emptyIcon, emptyTitle, emptyChip, emptyChooseButton, scroll, favoritesBar, toastBox].forEach { content.addSubview($0) }
        background.setAccessibilityElement(true); background.setAccessibilityRole(.group); background.setAccessibilityLabel(S.shelfTitle)
        layout()
    }
    private func layout() {
        let b = background.bounds, e = Self.edge
        let titleY = b.height - e - 20
        titleIcon.frame = NSRect(x: e, y: titleY, width: 20, height: 20)
        titleLabel.sizeToFit(); titleLabel.frame.origin = NSPoint(x: titleIcon.frame.maxX + 8, y: titleY + 2)
        let chipSize = countChip.intrinsicContentSize; countChip.frame = NSRect(x: titleLabel.frame.maxX + 8, y: titleY, width: chipSize.width, height: 20)
        hideButton.frame = NSRect(x: b.width - e - 24, y: titleY - 2, width: 24, height: 24)
        pinButton.frame = NSRect(x: hideButton.frame.minX - 6 - 24, y: titleY - 2, width: 24, height: 24); pinButton.contentTintColor = pinnedOpen ? ShotmoriStyle.accent : ShotmoriStyle.secondaryText
        tabBar.frame = NSRect(x: e, y: titleY - 8 - ShelfTabBar.height, width: b.width - 2 * e, height: ShelfTabBar.height)
        let stripH = ThumbnailItemView.shelfSize.height + 4
        let stripTop = showsTabs ? tabBar.frame.minY - 6 : titleY - 8
        scroll.frame = NSRect(x: e - 6, y: stripTop - stripH, width: b.width - 2 * (e - 6), height: stripH)
        // Boş durum: ikon · başlık · kısayol rozeti ya da (klasör yokken) "Klasör Seç…" (şerit alanının içinde, dikey ortalı); açıklama simgenin araç ipucunda
        emptyTitle.sizeToFit()
        let textW = emptyTitle.frame.width; let cs = emptyChip.intrinsicContentSize, bs = emptyChooseButton.frame.size
        let blockW = 40 + 16 + textW + 24 + (emptyChooseButton.isHidden ? cs.width : bs.width); let x0 = max(e, (b.width - blockW) / 2); let cy = scroll.frame.midY
        emptyIcon.frame = NSRect(x: x0, y: cy - 20, width: 40, height: 40)
        emptyTitle.frame.origin = NSPoint(x: x0 + 56, y: cy - emptyTitle.frame.height / 2)
        emptyChip.frame = NSRect(x: x0 + 56 + textW + 24, y: cy - 11, width: cs.width, height: 22)
        emptyChooseButton.frame.origin = NSPoint(x: x0 + 56 + textW + 24, y: cy - bs.height / 2)
        favoritesBar.frame = NSRect(x: e, y: e, width: b.width - 2 * e, height: ShotmoriStyle.Metric.control)
        toastBox.frame = NSRect(x: b.midX - toastBox.frame.width / 2, y: scroll.frame.midY - 14, width: toastBox.frame.width, height: 28)
    }
    @objc private func hideTapped() { hide(reason: "Gizle düğmesi") }
    @objc private func chooseFolderTapped() { onChooseFolder?() }
    /// İğne: açıkken dışarı tıklama ve kabul edilen bırakma rafı kapatmaz; tercih olarak kalıcıdır.
    @objc private func pinTapped() { guard showsTabs else { return }; pinnedOpen = pinButton.state == .on; prefs.keepShelfOpen = pinnedOpen; prefs.notifyChanged(); pinButton.contentTintColor = pinnedOpen ? ShotmoriStyle.accent : ShotmoriStyle.secondaryText; AXAnnounce.post(pinnedOpen ? S.shelfPinOn : S.shelfPinOff) }
    /// Tercih dışarıdan değişince (Ayarlar) iğneyi eşitle.
    func syncPinFromPrefs() { guard showsTabs else { return }; pinnedOpen = prefs.keepShelfOpen; pinButton.state = pinnedOpen ? .on : .off; pinButton.contentTintColor = pinnedOpen ? ShotmoriStyle.accent : ShotmoriStyle.secondaryText }
    static func shouldHideOnOutsideClick(pinned: Bool) -> Bool { !pinned }
    /// Etkin raf pencereye ayrılınca ana panelin yeni etkin rafı: ayrılmamış ilk komşu (önce önceki, yoksa sonraki); hepsi pencerede → nil.
    static func nextActive(after removed: UUID, in order: [UUID], detached: Set<UUID>) -> UUID? {
        guard let i = order.firstIndex(of: removed) else { return nil }
        let candidates = order[..<i].reversed() + order[(i + 1)...]
        return candidates.first { !detached.contains($0) && $0 != removed }
    }
    /// Raf pencereye ayrılabilir mi: zaten pencerede değil ve ana panelde en az bir takılı raf kalıyor.
    static func canDetach(_ id: UUID, in order: [UUID], detached: Set<UUID>) -> Bool {
        !detached.contains(id) && order.contains(id) && nextActive(after: id, in: order, detached: detached) != nil
    }
    /// ⌘N ile istenen raf sırası geçerli mi (0…count-1); değilse nil, seçim bozulmaz.
    static func shelfToActivate(index: Int, count: Int) -> Int? { (0..<count).contains(index) ? index : nil }

    // MARK: Raf sekmeleri
    private func wireTabBar() {
        tabBar.onSelect = { [weak self] id in self?.selectTab(id) }
        tabBar.onDetach = { [weak self] id in self?.onDetachRequest?(id) }
        tabBar.onAdd = { [weak self] in guard let self = self, let sh = self.store.addShelf() else { return }; self.activateShelf(sh.id); self.tabBar.startRename(sh.id) }
        tabBar.onRename = { [weak self] id, name in self?.store.renameShelf(id: id, to: name) }
        tabBar.onCloseRequest = { [weak self] id in self?.requestCloseShelf(id) }
        tabBar.onDropItems = { [weak self] ids, shelfID, source in
            guard let self = self, let t = self.store.shelves.first(where: { $0.id == shelfID }) else { return }
            self.noteInternalDrop(from: source); let n = self.store.move(ids: ids, to: t.id); self.showToast(n > 0 ? S.moveTrimmedToast(n) : S.movedToShelfToast(ids.count, t.name))
        }
    }
    /// Sekme tıklaması / ⌘N: pencerede duran raf öne getirilir, diğerleri etkinleştirilir.
    private func selectTab(_ id: UUID) { if detachedShelves.contains(id) { onDetachedTabClicked?(id) } else { activateShelf(id) } }
    /// Raf değişimi: seçim sıfırlanır, en yeni kare seçilir, VoiceOver duyurur.
    func activateShelf(_ id: UUID) {
        guard id != store.activeShelfID, let sh = store.shelves.first(where: { $0.id == id }) else { return }
        sel = ShelfSelection(); store.setActiveShelf(id: id) // onChange → reload
        selectNewestIfEmpty(); applyFocusRing()
        AXAnnounce.post(S.shelfSwitchedAX(sh.name))
    }
    private func refreshTabs() {
        guard showsTabs else { return }
        tabBar.entries = store.shelves.map { ShelfTabBar.Entry(id: $0.id, name: $0.name, count: $0.items.count, detached: detachedShelves.contains($0.id)) }
        tabBar.activeID = store.activeShelfID; tabBar.canAdd = store.shelves.count < ShelfStore.maxShelves
    }
    private func requestCloseShelf(_ id: UUID) { Self.confirmCloseShelf(id, store: store, from: panel) { [weak self] in self?.showToast($0) } }
    /// Rafı kapatma (yüzen panel ve üst şerit ortak): boş raf doğrudan; dolu rafta onay (Vazgeç · komşuya taşı · listeden düşür). Dosyalara dokunulmaz.
    /// `window`: onaydan önce key olan yüzey; onaydan sonra klavye ona döner. `notify`: hedef sınırı aşınca kırpılan sayı.
    static func confirmCloseShelf(_ id: UUID, store: ShelfStore, from window: NSWindow?, notify: ((String) -> Void)? = nil) {
        guard let sh = store.shelves.first(where: { $0.id == id }) else { return }
        let ids = store.shelves.map(\.id)
        let opts = ShelfCloseDecision.options(shelfIDs: ids, closing: id, itemCount: sh.items.count)
        if opts.isEmpty { if ShelfCloseDecision.neighbor(shelfIDs: ids, closing: id) != nil { store.removeShelf(id: id, movingItemsTo: nil) }; return }
        guard case .move(let neighborID) = opts[1], let neighbor = store.shelves.first(where: { $0.id == neighborID }) else { return }
        let snapshot = Set(sh.items.map(\.id)) // dialog açıkken gelen kareler düşmez, komşuya taşınır
        let wasKey = window?.isKeyWindow == true
        ForegroundHelper.withActivation { done in
            let a = NSAlert(); a.alertStyle = .warning; a.messageText = S.shelfCloseTitle(sh.name); a.informativeText = S.shelfCloseBody(sh.items.count)
            ConfirmDialog.configure(a, safe: S.cancel, proceed: S.shelfCloseMove(neighbor.name), destructive: false, symbol: "tray")
            let dropButton = a.addButton(withTitle: S.shelfCloseDrop); dropButton.keyEquivalent = ""
            let r = ConfirmDialog.run(a); done()
            switch ShelfCloseDecision.option(for: r, options: opts) {
            case .cancel: break
            case .move(let t): let n = store.removeShelf(id: id, movingItemsTo: t); if n > 0 { notify?(S.moveTrimmedToast(n)) } // hedef sınırı aştıysa kırpılan sayı bildirilir
            case .drop: store.removeShelf(id: id, movingItemsTo: nil, droppingOnly: snapshot)
            }
            if wasKey, let w = window, w.isVisible { w.makeKey() }
        }
    }
    static func shouldHideAfterDrop(hideAfterDrop: Bool, optionHeld: Bool, pinned: Bool) -> Bool { hideAfterDrop && !optionHeld && !pinned }
    /// Yalnız dışarıya kabul edilen bırakma aktarım sayılır; sekmeye bırakma (uygulama içi .move) sayılmaz.
    static func shouldCountAsHandoff(operation: NSDragOperation, internalDropHandled: Bool) -> Bool { !operation.isEmpty && !internalDropHandled }

    // MARK: Veri
    /// Yalnız görünürken yeniden kurar; gizli panelde iş `show`a kalır (bulut/tercih/depo olaylarında boşuna kurulum yok).
    func reload() { guard panel.isVisible else { return }; rebuild() }
    private func rebuild() {
        let items = displayedItems
        let newIDs = Set(store.itemsSinceLastHandoff(shelfID: displayedShelfID).map(\.id))
        if !showsTabs { let name = displayedShelf?.name ?? ""; titleLabel.stringValue = name; panel.title = name; background.setAccessibilityLabel(name) }
        sel.reconcile(existing: items.map(\.id))
        itemViews.forEach { $0.removeFromSuperview() }
        itemViews = items.map { item in
            let v = ThumbnailItemView(item: item, size: ThumbnailItemView.shelfSize)
            let accessible = itemAccessible?(item)
            v.isMissing = !item.exists || accessible == false
            #if SHOTMORI_CLOUD
            v.cloudBadge = cloud?.badge(for: item)
            #endif
            v.isNew = newIDs.contains(item.id)
            v.isSelected = selection.contains(item.id)
            v.image = ThumbnailCache.shared.cached(item.url)
            if Self.requestsThumbnail(cached: v.image != nil, isMissing: v.isMissing, accessible: accessible) { ThumbnailCache.shared.thumbnail(for: item.url) { [weak v] img in v?.image = img } }
            v.onMouseDown = { [weak self] view, ev in self?.handleClick(view, ev) }
            v.onDrag = { [weak self] view, ev in self?.beginDrag(from: view, event: ev) }
            v.onMouseUpWithoutDrag = { [weak self] view, ev in self?.handleClickRelease(view, ev) }
            v.onContextMenu = { [weak self] view, ev in self?.showContextMenu(view, ev) }
            v.onDoubleClick = { [weak self] view in guard let self = self else { return }; self.run("copy-image", items: self.selectedOr(view), anchor: view) } // popover ve şeritle aynı: çift tık kopyalar
            v.onAccessibilityPress = { [weak self] view in guard let self = self else { return }; self.sel.selectOnly(view.item.id); self.applySelection(); self.announceSelection(view.item.id) }
            v.onAccessibilityCopy = v.onDoubleClick
            v.onAccessibilityActions = { [weak self] view in self?.showActionsMenu(for: view) }
            v.onRemoveTapped = { [weak self] view in
                guard let self = self else { return }
                // ✕ yalnızca bu kareyi kaldırır; seçim ve modifier'lar dikkate alınmaz. Dosya korunur.
                let targets = self.sel.closeTargets(for: view.item.id).compactMap { id in self.displayedItems.first { $0.id == id } }
                Log.info("✕: öğe \(view.item.id.uuidString.prefix(8)) (seçimde \(self.sel.count) öğe vardı)")
                self.run("remove-from-shelf", items: targets, anchor: view)
            }
            return v
        }
        // Şerit: en yeni solda; grup ayracı olan öğeden önce boşluk.
        let itemW = ThumbnailItemView.shelfSize.width
        var x: CGFloat = 0
        for v in itemViews {
            if v.item.startsGroup, x > 0 { x += 14 }
            v.frame.origin = NSPoint(x: x, y: 2); strip.addSubview(v)
            x += itemW
        }
        // Panel genişliği: 4 kare tam görünür (favori çubuğu için taban); 5+ karede 660 pt, sağda kısmi kare kaydırmayı ima eder.
        // Ekranın görünür alanını aşmaz; 660 her durumda zorlanmaz.
        let base = 4 * itemW + 2 * Self.edge
        var width: CGFloat = items.count > 4 ? max(base, 660) : base
        // Görünürken panelin kendi ekranı; gizliyken (gösterim öncesi) imlecin ekranı — `positionNearMouse` oraya yerleştirir.
        let vis = (panel.isVisible ? panel.screen : nil) ?? (NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main)
        if let v = vis?.visibleFrame { width = min(width, v.width - 40) }
        strip.frame = NSRect(x: 0, y: 0, width: max(x, width - 2 * Self.edge + 12), height: ThumbnailItemView.shelfSize.height + 4)
        var f = panel.frame; let oldMaxY = f.maxY; f.size = NSSize(width: width, height: panelHeight); f.origin.y = oldMaxY - f.height
        if panel.isVisible, let v = vis?.visibleFrame { f.origin.x = Self.clampedOriginX(f.origin.x, width: f.width, visible: v) } // genişleyen panel sağ kenardan taşmaz
        panel.setFrame(f, display: true)
        emptyChip.text = ScreenshotHotKeys.area
        let noFolder = watchedFolder.map { $0() == nil } ?? false
        if let wf = watchedFolder { emptyIcon.toolTip = FolderPrompt.emptyBody(folder: wf(), otherwise: S.emptyShelfBody) } else { emptyIcon.toolTip = S.emptyShelfBody }
        [emptyIcon, emptyTitle, emptyChip].forEach { $0.isHidden = !items.isEmpty }; scroll.isHidden = items.isEmpty
        if noFolder { emptyChip.isHidden = true } // kısayol ipucu klasör yokken yanıltır; yerine klasör seçme bağlantısı
        emptyChooseButton.isHidden = !(items.isEmpty && noFolder)
        countChip.text = S.imageCount(items.count); countChip.isHidden = items.isEmpty
        refreshTabs()
        layout()
        rebuildFavorites()
        refreshQuickNumbers()
        applyFocusRing() // yeni kartlar odak halkasız doğar
    }
    /// Panel genişleyince sağ kenarı görünür alanda kalır (sol kenar da taşmaz); `positionNearMouse` ile aynı 8 pt pay.
    static func clampedOriginX(_ x: CGFloat, width: CGFloat, visible v: NSRect) -> CGFloat { max(min(x, v.maxX - width - 8), v.minX + 8) }
    /// Favori düğmeleri yalnız favori listesi değişince kurulur; seçim değişiminde durum (etkin, ipucu, kopyala sayısı) güncellenir,
    /// sonra taşma yeniden hesaplanır (kopyala başlığının genişliği değişebilir).
    private func rebuildFavorites() {
        let favs = registry.favorites
        if favs.map(\.id) != favoriteIDs {
            favoriteIDs = favs.map(\.id)
            favoriteButtons = favs.map { a in
                let isCopy = a.id == "copy-image"
                let img = NSImage(systemSymbolName: a.symbolName, accessibilityDescription: a.title) ?? NSImage()
                let btn: NSButton = isCopy ? PrimaryButton(title: a.title, image: img, target: self, action: #selector(favoriteTapped(_:))) : NSButton(title: a.title, image: img, target: self, action: #selector(favoriteTapped(_:)))
                btn.imagePosition = .imageLeading; btn.identifier = NSUserInterfaceItemIdentifier(a.id)
                if isCopy { ShotmoriStyle.primary(btn) } else { ShotmoriStyle.secondary(btn) }
                btn.setAccessibilityLabel(a.title)
                return btn
            }
        }
        let items = selectedItems()
        for (a, btn) in zip(favs, favoriteButtons) {
            if a.id == "copy-image" { btn.title = S.copyShortCount(items.count) }
            let av = a.availability(for: items); btn.isEnabled = av.isAvailable; btn.toolTip = av.reason ?? a.permission.label
            btn.setAccessibilityHelp(av.reason)
        }
        layoutFavorites()
    }
    /// Taşma: sığmayan favoriler aynı sırayla İşlemler menüsüne; tercih listesi değişmez.
    private func layoutFavorites() {
        favoritesBar.arrangedSubviews.forEach { favoritesBar.removeArrangedSubview($0); $0.removeFromSuperview() }
        let more = moreButton ?? {
            let b = NSButton(title: S.moreActions, image: NSImage(systemSymbolName: "ellipsis", accessibilityDescription: S.moreActions) ?? NSImage(), target: self, action: #selector(moreTapped(_:)))
            b.imagePosition = .imageLeading; ShotmoriStyle.secondary(b); b.sizeToFit(); b.toolTip = S.actionsMenuShortcutHelp
            moreButton = b; return b
        }()
        favoriteButtons.forEach { $0.sizeToFit() }
        let visible = FavoritesLayout.visibleCount(widths: favoriteButtons.map { $0.fittingSize.width }, available: favoritesBar.frame.width, spacing: favoritesBar.spacing, reserved: more.fittingSize.width + 16)
        overflowFavorites = Array(registry.favorites.dropFirst(visible))
        favoriteButtons.prefix(visible).forEach { favoritesBar.addArrangedSubview($0) }
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal); favoritesBar.addArrangedSubview(spacer)
        more.setAccessibilityHelp(overflowFavorites.isEmpty ? nil : S.favoritesOverflowHeader + ": " + overflowFavorites.map(\.title).joined(separator: ", "))
        favoritesBar.addArrangedSubview(more)
    }
    /// Test: favori çubuğundaki düğmeler (seçim değişiminde aynı nesneler kalır).
    var favoriteButtonsForTesting: [NSButton] { favoriteButtons }
    /// Test: raftaki kart görünümleri (gizliyken yeniden kurulmadığı doğrulanır).
    var itemViewsForTesting: [ThumbnailItemView] { itemViews }
    @objc private func favoriteTapped(_ sender: NSButton) { guard let id = sender.identifier?.rawValue else { return }; run(id, items: selectedItems(), anchor: sender) }
    @objc private func moreTapped(_ sender: NSButton) {
        let menu = registry.menu(for: selectedItems(), store: store, anchor: sender, panel: self)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }
    /// Uygunluk tek yürütme noktasında (`ActionRegistry.execute`, X-03).
    func run(_ id: String, items: [ShelfItem], anchor: NSView?) {
        guard registry.action(id) != nil else { return }
        status.actionWillRun(); if status.current == nil { toastBox.alphaValue = 0 } // kalıcı mesaj sonraki işlemle yenilenir
        if case .unavailable(let reason) = registry.execute(id, ctx: ActionContext(items: items, anchorView: anchor, store: store, panel: self)) { showToast(reason) }
    }

    // MARK: Seçim
    func selectedItems() -> [ShelfItem] { displayedItems.filter { selection.contains($0.id) } }
    private func selectedOr(_ v: ThumbnailItemView) -> [ShelfItem] { selection.contains(v.item.id) ? selectedItems() : [v.item] }
    private func handleClick(_ v: ThumbnailItemView, _ ev: NSEvent) {
        sel.mouseDown(on: v.item.id, order: order, command: ev.modifierFlags.contains(.command), shift: ev.modifierFlags.contains(.shift))
        applySelection()
    }
    private func handleClickRelease(_ v: ThumbnailItemView, _ ev: NSEvent) {
        let before = sel.count
        sel.mouseUpWithoutDrag(on: v.item.id, command: ev.modifierFlags.contains(.command), shift: ev.modifierFlags.contains(.shift))
        if sel.count != before { applySelection() }
    }
    private func applySelection() {
        itemViews.forEach { $0.isSelected = selection.contains($0.item.id) }; applyFocusRing(); rebuildFavorites()
        if ShelfQuickLook.shared.isOpen, ShelfQuickLook.shared.isHosted(by: panel) { let (u, i) = quickLookTargets(); ShelfQuickLook.shared.update(urls: u, index: i) } // önizleme seçimi izler
    }
    func selectAll() { sel.selectAll(order: order); applySelection() }
    /// Yeni kare için kendiliğinden açılışta: en yeni kare tek seçili olur (eski seçim kalmaz).
    func selectNewest() { if let f = displayedItems.first { sel.selectOnly(f.id); applySelection() } }
    func selectNewestIfEmpty() { if sel.isEmpty, let f = displayedItems.first { sel.selectOnly(f.id); applySelection() } }
    private func moveSelection(by delta: Int, extend: Bool) {
        guard let id = sel.move(by: delta, order: order, extend: extend), let v = itemViews.first(where: { $0.item.id == id }) else { return }
        applySelection(); scroll.contentView.scrollToVisible(v.frame)
        announceSelection(id)
    }
    private func announceSelection(_ id: UUID) {
        guard let v = itemViews.first(where: { $0.item.id == id }) else { return }
        AXAnnounce.post("\(v.item.fileName), \(S.selectedCount(sel.count))")
    }
    private func showContextMenu(_ v: ThumbnailItemView, _ ev: NSEvent) {
        if !sel.contains(v.item.id) { sel.selectOnly(v.item.id); applySelection() }
        let menu = registry.menu(for: selectedItems(), store: store, anchor: v, panel: self)
        NSMenu.popUpContextMenu(menu, with: ev, for: v)
    }
    /// VoiceOver "İşlemler…" özel eylemi: sağ tık menüsünün olaysız eşi, kartın altına açılır.
    private func showActionsMenu(for v: ThumbnailItemView) {
        if !sel.contains(v.item.id) { sel.selectOnly(v.item.id); applySelection() }
        registry.menu(for: selectedItems(), store: store, anchor: v, panel: self).popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: v)
    }

    // MARK: Klavye (panel key iken) — eşleme `ShelfKeyboard`'da (üst şeritle ortak), yürütme burada.
    func handleKey(_ ev: NSEvent) -> Bool {
        guard let c = ShelfKeyboard.command(keyCode: ev.keyCode, characters: ev.charactersIgnoringModifiers, flags: ev.modifierFlags,
                                            editingText: panel.firstResponder is NSTextView) else { return false }
        return perform(c)
    }
    /// Komutu yürütür; yüzeye uymayan komutta (ayrılmış panelde raf geçişi) false döner, olay sisteme kalır.
    @discardableResult func perform(_ c: ShelfKeyCommand) -> Bool {
        switch c {
        case .move(let d, let extend): moveSelection(by: d, extend: extend) // ← soldaki (daha yeni), → sağdaki (daha eski)
        case .first: moveSelection(by: -order.count, extend: false)
        case .last: moveSelection(by: order.count, extend: false)
        case .selectAll: selectAll()
        case .selectNumber(let n):
            guard let id = quickNumbers.first(where: { $0.value == n })?.key else { NSSound.beep(); return true }
            sel.selectOnly(id); applySelection(); announceSelection(id)
        case .quickLook: toggleQuickLook()
        case .actionsMenu: if let b = moreButton { moreTapped(b) } else { NSSound.beep() }
        case .nextShelf, .previousShelf:
            guard showsTabs else { return false }
            if let id = Self.cycledShelf(from: store.activeShelfID, order: store.shelves.map(\.id), detached: detachedShelves, forward: c == .nextShelf) { activateShelf(id) }
        case .shelfIndex(let i):
            guard showsTabs else { return false }
            if let idx = Self.shelfToActivate(index: i, count: store.shelves.count) { selectTab(store.shelves[idx].id) }
        case .copyAndClose:
            let items = selectedItems(); let ok = registry.action("copy-image")?.availability(for: items).isAvailable == true
            run("copy-image", items: items, anchor: nil)
            if Self.shouldHideAfterCopy(copyAvailable: ok, pinned: pinnedOpen) { hide(reason: "kopyala") }
        case .copy: run("copy-image", items: selectedItems(), anchor: nil)
        case .open: run("open", items: selectedItems(), anchor: nil)
        case .reveal: run("reveal-in-finder", items: selectedItems(), anchor: nil)
        case .edit, .copyText:
            let items = selectedItems(); guard items.count == 1 else { NSSound.beep(); return true }
            run(c == .edit ? "edit" : "copy-text", items: items, anchor: nil)
        case .remove: run("remove-from-shelf", items: selectedItems(), anchor: nil) // ⌫: seçilenleri raftan kaldır (Çöp yalnızca menüden)
        case .close: if ShelfQuickLook.shared.isOpen, ShelfQuickLook.shared.isHosted(by: panel) { ShelfQuickLook.shared.close() } else { hide(reason: "kısayol") } // önizleme açıksa önce o kapanır
        }
        return true
    }
    /// ↩: kopyalama yapıldıysa ve iğne kapalıysa gizlenir (ayrılmış panel zorunlu iğneli); kopyalanamadıysa neden görünür kalır.
    static func shouldHideAfterCopy(copyAvailable: Bool, pinned: Bool) -> Bool { copyAvailable && !pinned }
    /// Tab / ⇧Tab: pencerede durmayan raflar arasında döngü; tek takılı rafta nil.
    static func cycledShelf(from current: UUID, order: [UUID], detached: Set<UUID>, forward: Bool) -> UUID? {
        let cands = order.filter { !detached.contains($0) || $0 == current }
        guard cands.count > 1, let i = cands.firstIndex(of: current) else { return nil }
        return cands[(i + (forward ? 1 : cands.count - 1)) % cands.count]
    }
    /// Boşluk: seçili (diskte olan) karelerin önizlemesi, çapadaki kareden; açıksa kapatır. Panel önce key yapılır (sorumlu zinciri).
    private func toggleQuickLook() {
        let (urls, index) = quickLookTargets()
        if !panel.isKeyWindow { panel.makeKey() }
        ShelfQuickLook.shared.toggle(urls: urls, index: index, host: panel)
    }
    private func quickLookTargets() -> ([URL], Int) {
        let items = selectedItems().filter(\.exists)
        return (items.map(\.url), items.firstIndex { $0.id == sel.anchor } ?? 0)
    }

    // MARK: Hızlı numaralar (1–9): görünen ilk dokuz kare, gösterim sırasıyla; kaydırma ve yeniden yüklemede yeniden hesaplanır.
    private var quickNumbers: [UUID: Int] = [:]
    private func refreshQuickNumbers() {
        let visible = scroll.contentView.documentVisibleRect
        quickNumbers = ShelfKeyboard.quickNumbers(visible: itemViews.filter { $0.frame.intersects(visible) }.map(\.item.id))
        itemViews.forEach { $0.quickNumber = quickNumbers[$0.item.id] }
    }

    // MARK: Sürükleme kaynağı: gerçek dosya URL'leri (promise yok, geçici kopya yok)
    private func beginDrag(from view: ThumbnailItemView, event: NSEvent) {
        if !sel.contains(view.item.id) { sel.selectOnly(view.item.id); applySelection() }
        let pairs = selectedItems().compactMap { it in Self.dragWriter(for: it).map { (it, $0) } }
        let items = pairs.map(\.0)
        Log.info("sürükleme hazırlığı: seçim=\(selection.count) öğe=\(items.count)")
        guard !items.isEmpty else { showToast(S.reasonMissing); return }
        internalDropHandled = false
        let allIDs = items.map(\.id)
        let dragItems: [NSDraggingItem] = pairs.enumerated().map { i, pair in
            let it = pair.0
            let d = NSDraggingItem(pasteboardWriter: ShelfDragWriter(base: pair.1, itemIDs: allIDs))
            let img = (ThumbnailCache.shared.cached(it.url) ?? NSWorkspace.shared.icon(forFile: it.path)).withCountBadge(i == 0 ? items.count : 1)
            let off = CGFloat(i) * 5
            let base = view.convert(view.bounds.insetBy(dx: 10, dy: 20), to: nil)
            d.setDraggingFrame(NSRect(x: base.minX + off, y: base.minY - off, width: base.width, height: base.height), contents: img)
            return d
        }
        Log.info("Sürükleme başladı: \(items.count) dosya")
        // Sürükleme panel koordinatlarında başlar; kaynak görünüm pencere içinde.
        view.beginDraggingSession(with: dragItems, event: event, source: self)
    }
    /// Sürükleme yükü: yerel dosya varsa dosya URL'si (değişmez); yerel kopya Çöp'teyse bulut linki; ikisi de yoksa hiçbiri.
    static func dragWriter(for item: ShelfItem) -> NSPasteboardWriting? {
        if item.exists { return item.url as NSURL }
        if item.localTrashed, let l = item.cloud.compactMap(\.link).first { return l as NSURL }
        return nil
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        Self.dragOperationMask(outside: context == .outsideApplication, allowsInternalMove: true) // uygulama içi: yalnız sekmeye taşıma
    }
    /// Dışarıya yalnız kopya: `.generic`/`.move` Finder'da aynı diskte taşıma sayılır ve orijinal klasörden çıkar. İçeride yalnız izin verilen yerde `.move`.
    static func dragOperationMask(outside: Bool, allowsInternalMove: Bool) -> NSDragOperation { outside ? .copy : (allowsInternalMove ? .move : []) }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let accepted = !operation.isEmpty
        Log.info("Sürükleme bitti: \(accepted ? "kabul (\(operation.rawValue))" : "reddedildi/iptal"), dahili=\(internalDropHandled)")
        let countsAsHandoff = Self.shouldCountAsHandoff(operation: operation, internalDropHandled: internalDropHandled); internalDropHandled = false
        guard countsAsHandoff else { return }
        store.markHandoff(shelfID: displayedShelfID)
        if Self.shouldHideAfterDrop(hideAfterDrop: prefs.hideAfterDrop, optionHeld: NSEvent.modifierFlags.contains(.option), pinned: pinnedOpen) { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.hide(reason: "bırakma kabul edildi") } }
    }

    /// Küçük resim istenir mi. `accessible == nil`: erişim kapısı henüz bağlanmadı (`init`teki ilk reload, klasör kapsamı
    /// açılmadan). O anda istek sandbox'ta EPERM ile boş döner ve aynı dosyayı isteyen şerit kartları bu isteğe katılıp boş kalır.
    /// `show` her açılışta yeniden kurduğu için atlanan istek kaybolmaz.
    static func requestsThumbnail(cached: Bool, isMissing: Bool, accessible: Bool?) -> Bool {
        !cached && !isMissing && accessible == true
    }

    // MARK: Göster / gizle
    var isVisible: Bool { panel.isVisible }
    func toggle() { isVisible ? hide(reason: "kısayol") : show(takeKey: true) }
    /// `takeKey`: kısayolla çağrıldığında klavye bize gelir (Esc/oklar). Yeni kare geldiğinde `takeKey: false` ile çağrılır; odak çalınmaz.
    func show(takeKey: Bool) {
        rebuild(); selectNewestIfEmpty()
        positionNearMouse()
        panel.orderFrontRegardless()
        if takeKey { panel.makeKey() }
        installOutsideClickMonitor()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            Log.info("Panel gösterildi; appActive=\(NSApp.isActive), key=\(self.panel.isKeyWindow)")
        }
    }
    func hide(reason: String) {
        guard panel.isVisible else { return }
        ShelfQuickLook.shared.close(ifHostedBy: panel)
        panel.orderOut(nil); removeOutsideClickMonitor()
        Log.info(showsTabs ? "Panel gizlendi (\(reason))" : "Ayrılmış raf paneli kapandı, sekmeye döndü (\(reason))")
        if !showsTabs { onReattach?() }
    }
    private func positionNearMouse() {
        let m = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(m, $0.frame, false) } ?? NSScreen.main
        guard let vis = screen?.visibleFrame else { return }
        var f = panel.frame
        f.origin.x = min(max(m.x - 60, vis.minX + 8), vis.maxX - f.width - 8)
        var y = m.y - f.height - 18
        if y < vis.minY + 8 { y = min(m.y + 18, vis.maxY - f.height - 8) }
        f.origin.y = y
        panel.setFrame(f, display: true)
    }
    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self, Self.shouldHideOnOutsideClick(pinned: self.pinnedOpen) else { return }
            self.hide(reason: "dışarı tık")
        }
    }
    private func removeOutsideClickMonitor() { if let m = outsideClickMonitor { NSEvent.removeMonitor(m); outsideClickMonitor = nil } }

    private func placeToast(_ text: String, closable: Bool) {
        toast.stringValue = text; toast.sizeToFit()
        if let a = noticeAction { toastRetry.title = a.title; ShotmoriStyle.link(toastRetry, color: ShotmoriStyle.accent); toastRetry.setAccessibilityLabel(a.title) }
        toastRetry.sizeToFit(); let retryW: CGFloat = noticeAction == nil ? 0 : toastRetry.frame.width + 8
        toastRetry.isHidden = noticeAction == nil
        let extra: CGFloat = (closable ? 26 : 0) + retryW
        let w = min(toast.frame.width + 28 + extra, background.bounds.width - 2 * Self.edge)
        toastBox.frame = NSRect(x: background.bounds.midX - w / 2, y: scroll.frame.midY - 14, width: w, height: 28)
        toast.frame = NSRect(x: 12, y: (28 - toast.frame.height) / 2 - 1, width: w - 24 - extra, height: toast.frame.height)
        toastClose.isHidden = !closable; toastClose.frame = NSRect(x: w - 26, y: 2, width: 24, height: 24)
        toastRetry.frame = NSRect(x: w - 26 - retryW, y: 4, width: max(retryW - 8, 0), height: 20)
        toastBox.alphaValue = 1
    }
    private func present(_ m: StatusMessage) {
        if m.kind != .persistent { noticeAction = nil } // eylem bağlantısı yalnız kalıcı bildirimde (şeritteki `showsAction` ile aynı)
        status.show(m); placeToast(m.text, closable: m.kind == .persistent)
        AXAnnounce.post(m.text, high: m.kind == .persistent)
        if let d = StatusCenter.autoDismissDelay(m.kind) {
            DispatchQueue.main.asyncAfter(deadline: .now() + d) { [weak self] in guard let self = self, self.status.current == m else { return }; self.status.dismiss(); ShotmoriStyle.fade(self.toastBox, to: 0) }
        }
    }
    /// Kısa süreli geri bildirim (rutin başarı). Reduce Motion'da anlık kaybolur.
    func showToast(_ text: String) { noticeAction = nil; present(StatusMessage(text: text, kind: .success)) }
    /// Kalıcı bildirim (hata, boş OCR sonucu): kullanıcı kapatana veya bir sonraki işleme kadar kalır.
    func showNotice(_ text: String) { noticeAction = nil; present(StatusMessage(text: text, kind: .persistent)) }
    /// Kalıcı bildirim + eylem bağlantısı (yükleme hatasında "Yeniden dene"); başlık eylemden.
    func showNotice(_ text: String, action: NoticeAction) { noticeAction = action; present(StatusMessage(text: text, kind: .persistent)) }
    /// Eş: `StripController.dismissNotice/noticeActionTapped`; kapatma ve eylem `noticeAction`ı her zaman temizler (eski eylem sonraki bildirimde görünmez).
    @objc private func noticeActionTapped() { let a = noticeAction; dismissNotice(); a?.run() }
    @objc private func dismissNotice() { status.dismiss(); noticeAction = nil; ShotmoriStyle.fade(toastBox, to: 0) }
    /// Test: bildirimdeki eylem bağlantısının başlığı (görünmüyorsa nil).
    var noticeActionTitleForTesting: String? { toastRetry.isHidden ? nil : toastRetry.title }
    /// Uzun süren yerel işlem (OCR) için meşgul metni; `nil` kapatır. Arayüz kullanılabilir kalır; aynı işlem yeniden tetiklenmez.
    func setBusy(_ text: String?) {
        if let t = text { present(StatusMessage(text: t, kind: .busy)) } else { status.busyEnded(); if status.current == nil { toastBox.alphaValue = 0 } }
    }
}

/// Sürükleme yükü: temel yazıcının (dosya URL'si / bulut linki) tüm türleri aynen + uygulama içi öğe kimlikleri.
/// Dış uygulamalar yalnız bildikleri türleri okur; sekme çubuğu yalnız kimlik türünü okur.
final class ShelfDragWriter: NSObject, NSPasteboardWriting {
    let base: NSPasteboardWriting; let itemIDs: [UUID]
    init(base: NSPasteboardWriting, itemIDs: [UUID]) { self.base = base; self.itemIDs = itemIDs }
    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] { base.writableTypes(for: pasteboard) + [ShelfPanelController.internalItemsType] }
    func writingOptions(forType type: NSPasteboard.PasteboardType, pasteboard: NSPasteboard) -> NSPasteboard.WritingOptions {
        type == ShelfPanelController.internalItemsType ? [] : (base.writingOptions?(forType: type, pasteboard: pasteboard) ?? [])
    }
    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        if type == ShelfPanelController.internalItemsType { return try? JSONEncoder().encode(itemIDs.map(\.uuidString)) }
        return base.pasteboardPropertyList(forType: type)
    }
    static func itemIDs(from pb: NSPasteboard) -> Set<UUID> {
        guard let d = pb.data(forType: ShelfPanelController.internalItemsType), let s = try? JSONDecoder().decode([String].self, from: d) else { return [] }
        return Set(s.compactMap(UUID.init(uuidString:)))
    }
}

#if DEBUG
extension ShelfPanelController {
    /// Yalnız QA (`SHOTMORI_QA_SELECT`, mağaza görüntüleri): görüntülenen raftaki ilk n kartı seçer.
    func qaSelectFirst(_ n: Int) {
        let ids = displayedItems.prefix(n).map(\.id)
        sel.set(Set(ids), anchor: ids.first); applySelection()
    }
}
#endif
