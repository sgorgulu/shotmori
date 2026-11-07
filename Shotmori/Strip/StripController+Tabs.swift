import AppKit

/// Şerit: sol kapsüldeki raf sekmeleri (seç, adlandır, kapat, ayrı pencerede aç, yeni raf).
extension StripController {
    /// Sekme tıklaması / ⌘N: pencerede duran raf öne getirilir, diğerleri etkinleştirilir.
    func selectTab(_ id: UUID) {
        if detachedShelves().contains(id) { onDetachedTabClicked(id) } else { activateShelf(id) }
    }

    func addShelfTapped() {
        guard let sh = store.addShelf() else { return }
        activateShelf(sh.id)
        // Yeni sekmenin görünümü bir sonraki çizimde oluşur: balon sol kapsülün altına açılır.
        DispatchQueue.main.async { [weak self] in
            guard let self, let r = self.model.hitRects["left"] else { return }
            self.beginRename(sh.id, anchor: self.hosting, rect: self.hostingRect(r))
        }
    }

    func showTabMenu(_ id: UUID, _ event: NSEvent, _ view: NSView) {
        let m = NSMenu(); m.autoenablesItems = false
        let rename = NSMenuItem(title: S.shelfRename, action: #selector(renameFromMenu(_:)), keyEquivalent: "")
        rename.target = self; rename.representedObject = TabMenuTarget(id: id, view: view); m.addItem(rename)
        let detach = NSMenuItem(title: S.shelfDetach, action: #selector(detachFromMenu(_:)), keyEquivalent: "")
        detach.target = self; detach.representedObject = id
        detach.isEnabled = canDetachShelf(id)
        m.addItem(detach)
        m.addItem(.separator())
        let close = NSMenuItem(title: S.shelfClose, action: #selector(closeFromMenu(_:)), keyEquivalent: "")
        close.target = self; close.representedObject = id; close.isEnabled = store.shelves.count > 1; m.addItem(close)
        withModal { NSMenu.popUpContextMenu(m, with: event, for: view) }
    }
    @objc private func renameFromMenu(_ s: NSMenuItem) {
        guard let t = s.representedObject as? TabMenuTarget, let v = t.view, v.window != nil else { return }
        beginRename(t.id, anchor: v, rect: v.bounds)
    }
    @objc private func detachFromMenu(_ s: NSMenuItem) { if let id = s.representedObject as? UUID { detachTab(id) } }
    @objc private func closeFromMenu(_ s: NSMenuItem) { if let id = s.representedObject as? UUID { closeTab(id) } }

    /// Ayrı pencerede açılabilir mi: bağlantı kurulu ve son takılı raf değil.
    func canDetachShelf(_ id: UUID, detached: Set<UUID>? = nil) -> Bool {
        onDetachRequest != nil && ShelfPanelController.canDetach(id, in: store.shelves.map(\.id), detached: detached ?? detachedShelves())
    }

    // MARK: Sekme eylemleri (sağ tık menüsü ve VoiceOver eylemleri ortak)
    /// VoiceOver "Yeniden adlandır": balon sol kapsülün altına açılır (tık görünümü yok).
    func renameTab(_ id: UUID) {
        guard let r = model.hitRects["left"] else { NSSound.beep(); return }
        beginRename(id, anchor: hosting, rect: hostingRect(r))
    }
    /// Rafı kapat: yüzen panelle ortak onay (`confirmCloseShelf`; dosyalar korunur).
    func closeTab(_ id: UUID) {
        guard store.shelves.count > 1 else { NSSound.beep(); return }
        withModal { ShelfPanelController.confirmCloseShelf(id, store: store, from: panel) { [weak self] in self?.showToast($0) } }
    }
    func detachTab(_ id: UUID) {
        guard canDetachShelf(id) else { NSSound.beep(); return }
        onDetachRequest?(id)
    }

    /// Küçük balonda ad alanı (en çok `ShelfStore.maxNameLength` karakter). ↩ kaydeder, Esc vazgeçer; dışarı tık ve şeridin
    /// çekilmesi de kaydeder (boş ad yok sayılır: `ShelfStore.renameShelf`), böylece yazılan ad kaybolmaz.
    /// Yazmak için uygulama kısa süre öne alınır; balon kapanınca önceki uygulama yalnız Shotmori hâlâ öndeyse geri getirilir
    /// (kullanıcı başka uygulamaya tıkladıysa o uygulama önde kalır, spec §4).
    func beginRename(_ id: UUID, anchor: NSView, rect: NSRect) {
        guard let sh = store.shelves.first(where: { $0.id == id }) else { return }
        renameSession?.close()
        let previous = NSWorkspace.shared.frontmostApplication
        let previousIsOther = previous.map { $0.bundleIdentifier != Bundle.main.bundleIdentifier } ?? false
        NSApp.activate(ignoringOtherApps: true)
        let s = StripRenameSession(name: sh.name) { [weak self] name in
            if let name { self?.store.renameShelf(id: id, to: name) }
            self?.renameSession = nil
            // Başka uygulamaya tıklamanın etkinleştirmesi bu sürece biraz gecikmeli ulaşır: karar bir sonraki turda.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard self?.renameSession == nil else { return } // yeni balon açıldı: odak onda kalır
                if Self.shouldRestorePreviousApp(appStillActive: NSApp.isActive, previousIsOther: previousIsOther) { previous?.activate(options: []) }
            }
        }
        renameSession = s
        s.show(relativeTo: rect, of: anchor)
    }
    /// Adlandırma bitince önceki uygulama geri getirilsin mi: yalnız Shotmori hâlâ etkinse (kullanıcı başka yere geçmediyse)
    /// ve önceki uygulama Shotmori değilse.
    static func shouldRestorePreviousApp(appStillActive: Bool, previousIsOther: Bool) -> Bool { appStillActive && previousIsOther }
}

private final class TabMenuTarget: NSObject {
    let id: UUID; weak var view: NSView?
    init(id: UUID, view: NSView) { self.id = id; self.view = view }
}

/// Raf adlandırma balonu (şerit sekmeleri).
final class StripRenameSession: NSObject, NSPopoverDelegate, NSTextFieldDelegate {
    private let popover = NSPopover()
    let field: NSTextField
    private var cancelled = false
    private var finished = false
    private let onEnd: (String?) -> Void

    init(name: String, onEnd: @escaping (String?) -> Void) {
        self.onEnd = onEnd
        field = NSTextField(string: name)
        super.init()
        field.font = ShotmoriStyle.Fonts.secondary; field.isBezeled = true; field.bezelStyle = .roundedBezel
        field.delegate = self; field.setAccessibilityLabel(S.shelfRename)
        field.frame = NSRect(x: 10, y: 10, width: 180, height: 22)
        let vc = NSViewController(); vc.view = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 42)); vc.view.addSubview(field)
        popover.contentViewController = vc; popover.behavior = .transient; popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.delegate = self
    }

    func show(relativeTo rect: NSRect, of view: NSView) {
        popover.show(relativeTo: rect, of: view, preferredEdge: view.isFlipped ? .maxY : .minY)
        field.window?.makeKey(); field.window?.makeFirstResponder(field); field.currentEditor()?.selectAll(nil)
    }
    /// Şerit çekilirken: yazılan ad kaydedilir (vazgeçme yalnız Esc).
    func close() { popover.performClose(nil); finish() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.insertNewline(_:)) { popover.performClose(nil); return true }
        if sel == #selector(NSResponder.cancelOperation(_:)) { cancelled = true; popover.performClose(nil); return true }
        return false
    }
    func controlTextDidChange(_ obj: Notification) {
        guard field.stringValue.count > ShelfStore.maxNameLength else { return }
        field.stringValue = String(field.stringValue.prefix(ShelfStore.maxNameLength))
    }
    func popoverDidClose(_ notification: Notification) { finish() }
    private func finish() {
        guard !finished else { return }
        finished = true
        onEnd(cancelled ? nil : field.stringValue)
    }
}
