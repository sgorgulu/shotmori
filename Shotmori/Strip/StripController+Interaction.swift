import AppKit

/// Şerit: görünüm olayları, seçim, eylemler, sağ kapsül, klavye ve Quick Look.
extension StripController {
    func makeActions() -> StripViewActions {
        var a = StripViewActions()
        a.select = { [weak self] id, flags in self?.cardClicked(id, flags) }
        a.doubleClick = { [weak self] id in self?.cardDoubleClicked(id) }
        a.longPress = { [weak self] id in self?.cardLongPressed(id) }
        a.forceClick = { [weak self] id in self?.cardForceClicked(id) }
        a.remove = { [weak self] id in self?.removeTapped(id) }
        a.contextMenu = { [weak self] id, e, v in self?.showContextMenu(id, e, v) }
        a.beginDrag = { [weak self] id, e, v in self?.beginDrag(id, event: e, view: v) }
        // Üzerine gelme yalnız kartın kendi görünümünü etkiler (denetleyiciye gitmez); çekilme imleç bölgesine bakar.
        a.capsule = { [weak self] e, v in self?.invokeCapsule(e, anchor: v) }
        a.capsuleAccessibility = { [weak self] e in self?.invokeCapsule(e, anchor: nil) }
        a.tab = { [weak self] id in self?.selectTab(id) }
        a.tabMenu = { [weak self] id, e, v in self?.showTabMenu(id, e, v) }
        a.renameTab = { [weak self] id in self?.renameTab(id) }
        a.closeTab = { [weak self] id in self?.closeTab(id) }
        a.detachTab = { [weak self] id in self?.detachTab(id) }
        a.dropOnTab = { [weak self] shelfID, ids, source in self?.dropItems(ids, onShelf: shelfID, source: source) ?? false }
        a.addShelf = { [weak self] in self?.addShelfTapped() }
        a.chooseFolder = { [weak self] in self?.onChooseFolder?() }
        a.dismissNotice = { [weak self] in self?.dismissNotice() }
        a.retry = { [weak self] in self?.noticeActionTapped() }
        return a
    }

    // MARK: Seçim
    var order: [UUID] { model.items.map(\.id) }
    func selectedItems() -> [ShelfItem] { displayedItems.filter { sel.contains($0.id) } }
    func item(_ id: UUID) -> ShelfItem? { displayedItems.first { $0.id == id } }

    func applySelection() {
        model.selection = sel.ids
        rebuildCapsule()
        if ShelfQuickLook.shared.isOpen, ShelfQuickLook.shared.isHosted(by: panel) { // önizleme seçimi izler
            let (u, i) = quickLookTargets(); ShelfQuickLook.shared.update(urls: u, index: i)
        }
    }
    /// Kartla etkileşim klavyeyi şeride verir (odak çalmayan panel; ön uygulama değişmez).
    private func takeKeyboard() {
        panel.keyboardFocusAllowed = true
        if !panel.isKeyWindow { panel.makeKey() }
    }
    /// Tık bırakışta (⌘/⇧ basışta) gelir: ⌘ aç/kapat, ⇧ aralık, düz tık yalnız o kart.
    func cardClicked(_ id: UUID, _ flags: NSEvent.ModifierFlags) {
        let cmd = flags.contains(.command), shift = flags.contains(.shift)
        sel.mouseDown(on: id, order: order, command: cmd, shift: shift)
        sel.mouseUpWithoutDrag(on: id, command: cmd, shift: shift)
        applySelection(); takeKeyboard()
    }
    func cardDoubleClicked(_ id: UUID) {
        guard let it = item(id) else { return }
        sel.selectOnly(id); applySelection()
        run("copy-image", items: [it], anchor: nil)
    }
    /// Basılı tutma: tek görüntüyü düzenle.
    func cardLongPressed(_ id: UUID) {
        guard let it = item(id) else { return }
        sel.selectOnly(id); applySelection()
        run("edit", items: [it], anchor: nil)
    }
    func cardForceClicked(_ id: UUID) {
        if !sel.contains(id) { sel.selectOnly(id); applySelection() }
        toggleQuickLook()
    }
    /// ✕: seçimden bağımsız, yalnız bu kart. Dosya korunur.
    func removeTapped(_ id: UUID) {
        guard let it = item(id) else { return }
        Log.info("✕: öğe \(id.uuidString.prefix(8)) (seçimde \(sel.count) öğe vardı)")
        run("remove-from-shelf", items: [it], anchor: nil)
    }

    // MARK: Eylemler
    /// Uygunluk `ActionRegistry`'de (X-03): önce `authorize` (düşme animasyonu başlamadan), yürütme `execute` ile (uygunluk yeniden denetlenir).
    func run(_ id: String, items: [ShelfItem], anchor: NSView?) {
        let (action, auth) = registry.authorize(id, items: items)
        guard let a = action else { return }
        status.actionWillRun(); model.notice = status.current // kalıcı mesaj sonraki işlemle yenilenir
        if case .unavailable(let reason) = auth { showToast(reason); return }
        if id == "remove-from-shelf" { removeWithFall(items, action: a); return }
        if id == "copy-image" { copyingIDs = items.map(\.id) } // eylem `showToast`'u eşzamanlı çağırır
        defer { copyingIDs = [] }
        registry.execute(a, ctx: ActionContext(items: items, anchorView: anchor, store: store, panel: self))
    }
    /// Raftan kaldırma: kart yerinde gizlenir, aynı görüntü tüm ekranı kaplayan katmanda ipten düşer (`fall`, spec §5.7),
    /// `fallRemoveDelay` sonra listeden çıkar. Hareket azaltmada ya da şerit gizliyken düşme yok, hemen kalkar.
    private func removeWithFall(_ items: [ShelfItem], action: ShelfAction) {
        let ids = Set(items.map(\.id))
        let perform = { [weak self] in
            guard let self else { return }
            self.model.fallingIDs.subtract(ids)
            self.registry.execute(action, ctx: ActionContext(items: items, anchorView: nil, store: self.store, panel: self))
        }
        guard shown, StripMotion.duration(StripMotion.fallRemoveDelay, reduceMotion: model.reduceMotion()) > 0 else { perform(); return }
        fall(items)
        model.fallingIDs.formUnion(ids)
        DispatchQueue.main.asyncAfter(deadline: .now() + StripMotion.fallRemoveDelay) { perform() }
    }
    /// Menüdeki "Raftan kaldır" (düşme) ve "Kopyala" (kart üstü rozet) şeridin `run` yolundan geçer.
    static let stripRoutedActions: Set<String> = ["remove-from-shelf", "copy-image"]
    func routeThroughStrip(_ menu: NSMenu) {
        for mi in menu.items {
            if let sub = mi.submenu { routeThroughStrip(sub) }
            guard let inv = mi.representedObject as? ActionInvocation, Self.stripRoutedActions.contains(inv.action.id) else { continue }
            mi.target = self; mi.action = #selector(menuRun(_:))
        }
    }
    @objc private func menuRun(_ sender: NSMenuItem) {
        guard let inv = sender.representedObject as? ActionInvocation else { return }
        run(inv.action.id, items: inv.ctx.items, anchor: inv.ctx.anchorView)
    }
    /// Menüyü eşzamanlı açar; açıkken şerit kendiliğinden çekilmez.
    func withModal(_ body: () -> Void) { modalDepth += 1; body(); modalDepth -= 1 }

    func showContextMenu(_ id: UUID, _ event: NSEvent, _ view: NSView) {
        if !sel.contains(id) { sel.selectOnly(id); applySelection() }
        let menu = registry.menu(for: selectedItems(), store: store, anchor: view, panel: self)
        routeThroughStrip(menu)
        withModal { NSMenu.popUpContextMenu(menu, with: event, for: view) }
    }

    // MARK: Sağ kapsül
    func rebuildCapsule() {
        let items = selectedItems()
        let favs = registry.favorites.map { (id: $0.id, available: $0.availability(for: items).isAvailable) }
        let r = StripCapsule.entries(selectionCount: sel.count, favorites: favs, pinned: pinnedOpen)
        model.capsule = r.entries
        overflowFavorites = r.overflow.compactMap { registry.action($0) }
    }
    /// Sağ kapsül düğmesi: tıkta `anchor` tıklanan görünümdür. VoiceOver basışında (`anchor` nil) tık görünümü yoktur:
    /// İşlemler menüsü düğmenin isabet dikdörtgenine, çapa isteyen eylem (Paylaş) şeridin barındırma görünümüne demirlenir.
    func invokeCapsule(_ entry: StripCapsuleEntry, anchor: NSView?) {
        switch entry {
        case .action(let id, _): run(id, items: selectedItems(), anchor: anchor ?? hosting)
        case .actionsMenu: openActionsMenu(from: anchor)
        case .pin: togglePin()
        case .selectionCount, .separator: break
        }
    }
    /// İşlemler menüsü İşlemler düğmesinin altına açılır: tıkta düğmenin kendisine, ⌘K ve VoiceOver'da düğmenin isabet
    /// dikdörtgenine (ilk çizimden beri bilinir; daha önce tıklanmış olması gerekmez).
    func openActionsMenu(from view: NSView? = nil) {
        let anchor = view.flatMap { $0.window === panel ? $0 : nil }
        let menu = registry.menu(for: selectedItems(), store: store, anchor: anchor ?? hosting, panel: self)
        routeThroughStrip(menu)
        withModal {
            if let a = anchor {
                menu.popUp(positioning: nil, at: NSPoint(x: 0, y: a.isFlipped ? a.bounds.height + 4 : -4), in: a)
            } else if let r = StripCapsule.actionsMenuAnchorRect(hitRects: model.hitRects) {
                menu.popUp(positioning: nil, at: hostingPoint(x: r.minX, topY: r.maxY + 4), in: hosting)
            } else { NSSound.beep() }
        }
    }
    /// SwiftUI küresel (sol üst) koordinatından barındırma görünümü koordinatına.
    func hostingPoint(x: CGFloat, topY: CGFloat) -> NSPoint {
        NSPoint(x: x, y: hosting.isFlipped ? topY : hosting.bounds.height - topY)
    }
    func hostingRect(_ r: CGRect) -> NSRect {
        hosting.isFlipped ? r : NSRect(x: r.minX, y: hosting.bounds.height - r.maxY, width: r.width, height: r.height)
    }
    /// İğne: açıkken dışarı tıklama, bırakma ve otomatik çekilme kapatmaz; tercih yüzen panelle ortaktır.
    func togglePin() {
        pinnedOpen.toggle()
        prefs.keepShelfOpen = pinnedOpen; prefs.notifyChanged()
        rebuildCapsule()
        AXAnnounce.post(pinnedOpen ? S.shelfPinOn : S.shelfPinOff)
    }

    // MARK: Klavye (yalnız şerit key iken ya da kendi Quick Look'u açıkken)
    /// Adlandırma balonu açıkken hiçbir tuş (⌘ dahil) şeride gitmez: Esc vazgeçer, ↩ kaydeder, rakam ve harf ada yazılır.
    func handleKey(_ ev: NSEvent) -> Bool {
        let ql = ShelfQuickLook.shared.isOpen && ShelfQuickLook.shared.isHosted(by: panel)
        guard Self.acceptsKeys(isKey: panel.isKeyWindow, quickLookHosted: ql, renaming: renameSession != nil),
              let c = ShelfKeyboard.command(keyCode: ev.keyCode, characters: ev.charactersIgnoringModifiers, flags: ev.modifierFlags, editingText: false)
        else { return false }
        return perform(c)
    }
    /// Şerit tuşu alır mı: balon açıkken hiç; yoksa şerit key iken ya da kendi Quick Look'u açıkken.
    static func acceptsKeys(isKey: Bool, quickLookHosted: Bool, renaming: Bool) -> Bool {
        !renaming && (isKey || quickLookHosted)
    }
    /// Yüzen paneldeki `perform` ile aynı anlam; fark: gizleme şeridi çeker, ⌘K sağ kapsüle açılır, kalıcı bildirim varken
    /// Esc önce bildirimi kapatır ve ↩ "Yeniden dene"yi çalıştırır (bildirim düğmeleri klavyeyle odaklanamaz).
    /// Eş: `ShelfPanelController.perform` (ayrıca `announceSelection`, `quickLookTargets`, `showNotice`/`noticeActionTapped` iki yüzeyde
    /// neredeyse birebir); birinde değişen davranış ötekinde de gözden geçirilmeli. Ortak `ShelfKeyCommandRouter` gönderim sonrasına.
    @discardableResult func perform(_ c: ShelfKeyCommand) -> Bool {
        let ownQuickLook = ShelfQuickLook.shared.isOpen && ShelfQuickLook.shared.isHosted(by: panel)
        if let n = Self.noticeKeyAction(c, persistentNotice: status.isPersistent, hasRetry: noticeAction?.runsOnReturn == true, quickLookOpen: ownQuickLook) {
            if n == .retry { noticeActionTapped() } else { dismissNotice() }
            return true
        }
        switch c {
        case .move(let d, let extend): moveSelection(by: d, extend: extend)
        case .first: moveSelection(by: -order.count, extend: false)
        case .last: moveSelection(by: order.count, extend: false)
        case .selectAll: sel.selectAll(order: order); applySelection()
        case .selectNumber(let n):
            guard let id = model.quickNumbers.first(where: { $0.value == n })?.key else { NSSound.beep(); return true }
            sel.selectOnly(id); applySelection(); announceSelection(id)
        case .quickLook: toggleQuickLook()
        case .actionsMenu: openActionsMenu()
        case .nextShelf, .previousShelf:
            if let id = ShelfPanelController.cycledShelf(from: store.activeShelfID, order: store.shelves.map(\.id), detached: detachedShelves(), forward: c == .nextShelf) { activateShelf(id) }
        case .shelfIndex(let i):
            if let idx = ShelfPanelController.shelfToActivate(index: i, count: store.shelves.count) { selectTab(store.shelves[idx].id) }
        case .copyAndClose:
            let items = selectedItems(); let ok = registry.action("copy-image")?.availability(for: items).isAvailable == true
            run("copy-image", items: items, anchor: nil)
            if ShelfPanelController.shouldHideAfterCopy(copyAvailable: ok, pinned: pinnedOpen) { hide(reason: "kopyala") }
        case .copy: run("copy-image", items: selectedItems(), anchor: nil)
        case .open: run("open", items: selectedItems(), anchor: nil)
        case .reveal: run("reveal-in-finder", items: selectedItems(), anchor: nil)
        case .edit, .copyText:
            let items = selectedItems(); guard items.count == 1 else { NSSound.beep(); return true }
            run(c == .edit ? "edit" : "copy-text", items: items, anchor: nil)
        case .remove: run("remove-from-shelf", items: selectedItems(), anchor: nil)
        case .close:
            if ownQuickLook { ShelfQuickLook.shared.close() } else { hide(reason: "kısayol") }
        }
        return true
    }
    enum NoticeKeyAction: Equatable { case dismiss, retry }
    /// Kalıcı bildirim varken Esc (Quick Look açık değilse) bildirimi kapatır, ↩ yeniden denenebilen işte "Yeniden dene"dir.
    static func noticeKeyAction(_ c: ShelfKeyCommand, persistentNotice: Bool, hasRetry: Bool, quickLookOpen: Bool = false) -> NoticeKeyAction? {
        guard persistentNotice else { return nil }
        switch c {
        case .close: return quickLookOpen ? nil : .dismiss
        case .copyAndClose: return hasRetry ? .retry : nil
        default: return nil
        }
    }
    private func moveSelection(by delta: Int, extend: Bool) {
        guard let id = sel.move(by: delta, order: order, extend: extend) else { return }
        applySelection(); scrollToVisible(id); announceSelection(id)
    }
    /// Eş: `ShelfPanelController.announceSelection`.
    private func announceSelection(_ id: UUID) {
        guard let it = item(id) else { return }
        AXAnnounce.post("\(it.fileName), \(S.selectedCount(sel.count))")
    }
    /// Kartı görünür alana getirir (kenar boşluğuyla).
    func scrollToVisible(_ id: UUID) {
        guard let i = order.firstIndex(of: id) else { return }
        let width = panel.frame.width, half = StripLayout.cardWidth / 2 + StripLayout.edgePadding
        let x = StripLayout.x(index: i, scrollOffset: 0)
        var off = model.scrollOffset
        if x - half < off { off = x - half } else if x + half > off + width { off = x + half - width }
        let next = clampedOffset(off, count: order.count)
        if next != model.scrollOffset { model.scrollOffset = next; refreshQuickNumbers() }
    }

    // MARK: Quick Look
    /// Boşluk / force click: seçili (diskte olan) kartlar, çapadan. Şerit önce key yapılır ve önizlemenin sahibi olarak kaydedilir.
    func toggleQuickLook() {
        let (urls, index) = quickLookTargets()
        takeKeyboard()
        ShelfQuickLook.shared.toggle(urls: urls, index: index, host: panel)
    }
    /// Eş: `ShelfPanelController.quickLookTargets`.
    private func quickLookTargets() -> ([URL], Int) {
        let items = selectedItems().filter(\.exists)
        return (items.map(\.url), items.firstIndex { $0.id == sel.anchor } ?? 0)
    }
}
