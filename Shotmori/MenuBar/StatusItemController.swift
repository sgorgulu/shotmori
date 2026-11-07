import AppKit

/// Menü çubuğu: sol tık → kompakt popover; sağ tık → klasik menü. Rozet = son aktarımdan beri gelen sayısı.
final class StatusItemController: NSObject, NSMenuDelegate, NSPopoverDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    weak var app: AppController?
    private let menu = NSMenu()
    private let popover = NSPopover()
    private let popoverVC = MenuBarPopoverViewController()
    private var dragging = false

    init(app: AppController) {
        self.app = app
        super.init()
        item.button?.image = NSImage(named: "MenuBarIcon"); item.button?.image?.isTemplate = true; item.button?.image?.accessibilityDescription = S.appName
        item.button?.imagePosition = .imageLeading
        item.button?.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        item.button?.target = self; item.button?.action = #selector(statusTapped(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.setAccessibilityLabel(S.appName)
        menu.delegate = self
        popoverVC.app = app
        popover.contentViewController = popoverVC; popover.behavior = .transient; popover.delegate = self
        popoverVC.onDragStateChanged = { [weak self] d in self?.dragging = d; self?.popover.behavior = d ? .applicationDefined : .transient }
        popoverVC.onRequestClose = { [weak self] in self?.popover.performClose(nil) }
        updateBadge(0)
    }
    /// Rozet: başlıkta sayı; VoiceOver etiketi de sayıyı söyler (A11Y-05).
    func updateBadge(_ n: Int) {
        item.button?.title = n > 0 ? " \(n)" : ""
        item.button?.setAccessibilityLabel(Self.badgeAccessibilityLabel(n))
        if popover.isShown { popoverVC.reload() }
    }
    static func badgeAccessibilityLabel(_ n: Int) -> String { n > 0 ? "\(S.appName), \(S.newCount(n))" : S.appName }
    func reloadIfShown() { if popover.isShown { popoverVC.reload() } }

    @objc private func statusTapped(_ sender: NSStatusBarButton) {
        guard let ev = NSApp.currentEvent else { return }
        if ev.type == .rightMouseUp { item.menu = menu; sender.performClick(nil); item.menu = nil; return }
        if popover.isShown { popover.performClose(nil) }
        else { popover.appearance = NSApp.effectiveAppearance /* menü çubuğu değil, sistem/uygulama görünümü */; popover.animates = !ShotmoriStyle.reduceMotion /* Hareketi Azalt her açılışta okunur */; popoverVC.reload(); popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY); NSApp.activate(ignoringOtherApps: true) }
    }
    func popoverShouldClose(_ popover: NSPopover) -> Bool { !dragging }
    #if DEBUG
    /// QA: popover'ı program yoluyla açar (ekran görüntüsü).
    func showPopoverForQA() { guard let b = item.button, !popover.isShown else { return }; popover.appearance = NSApp.effectiveAppearance; popover.animates = !ShotmoriStyle.reduceMotion; popoverVC.reload(); popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY) }
    #endif

    /// "Son görüntüyü kopyala" tüm raflardaki en yeni, Çöp'e taşınmamış kareyi alır (`AppController.copyLastScreenshot`);
    /// etkinlik koşulu aynı ölçüte (`ShelfIntentCore.latest`) bakar, etkin rafa değil.
    static func copyLastEnabled(store: ShelfStore) -> Bool { MainActor.assumeIsolated { ShelfIntentCore.latest(store: store)?.exists == true } }

    // Sağ tık menüsü (klasik, kısa)
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let app = app else { return }
        func sym(_ n: String) -> NSImage? { NSImage(systemSymbolName: n, accessibilityDescription: nil) }
        // Klasör yokken (kurulum yarıda kaldı, klasör silindi) en üstte yol gösterilir.
        if let t = FolderPrompt.menuTitle(folder: app.folder) {
            let choose = NSMenuItem(title: t, action: #selector(AppController.chooseWatchedFolder), keyEquivalent: ""); choose.target = app; choose.image = sym("folder.badge.questionmark")
            menu.addItem(choose); menu.addItem(.separator())
        }
        let show = NSMenuItem(title: S.menuShowShelf, action: #selector(AppController.toggleShelf), keyEquivalent: ""); show.target = app; show.image = sym("rectangle.stack")
        // Kısayol göstergesi mevcut tercihten: tek karakterli tuşsa (etkin klavye düzeninden) native kısayol alanında, değilse başlığa eklenir.
        if let key = HotKeyCenter.keyEquivalent(app.prefs.hotKeyCode) { show.keyEquivalent = key; show.keyEquivalentModifierMask = app.prefs.hotKeyModifiers.intersection([.command, .control, .option, .shift]) }
        else { show.title = "\(S.menuShowShelf)   \(HotKeyCenter.display(keyCode: app.prefs.hotKeyCode, modifiers: app.prefs.hotKeyModifiers))" }
        menu.addItem(show)
        let copyLast = NSMenuItem(title: S.menuCopyLast, action: #selector(AppController.copyLastScreenshot), keyEquivalent: ""); copyLast.target = app; copyLast.image = sym("doc.on.doc"); copyLast.isEnabled = Self.copyLastEnabled(store: app.store); menu.addItem(copyLast)
        let fromClip = NSMenuItem(title: S.menuAddFromClipboard, action: #selector(AppController.addFromClipboard), keyEquivalent: ""); fromClip.target = app; fromClip.image = sym("photo.on.rectangle"); menu.addItem(fromClip)
        // Son yüklemeler ▸ (geçmiş boşsa pasif tek satır)
        #if SHOTMORI_CLOUD
        if Features.cloud {
            let recent = NSMenuItem(title: S.cloudRecentUploads, action: nil, keyEquivalent: ""); recent.image = sym("icloud.and.arrow.up")
            recent.submenu = RecentUploadsMenu.build(cloud: app.cloud); menu.addItem(recent)
        }
        #endif
        menu.addItem(.separator())
        let settings = NSMenuItem(title: S.menuSettings, action: #selector(AppController.openSettings), keyEquivalent: ","); settings.target = app; settings.image = sym("gearshape"); menu.addItem(settings)
        let help = NSMenuItem(title: S.menuHelp, action: nil, keyEquivalent: ""); let sub = NSMenu()
        for (t, sel) in [(S.menuRerunSetup, #selector(AppController.rerunOnboarding)), (S.menuShowLog, #selector(AppController.showLog)), (S.menuAbout, #selector(AppController.showAbout))] { let mi = NSMenuItem(title: t, action: sel, keyEquivalent: ""); mi.target = app; sub.addItem(mi) }
        help.submenu = sub; menu.addItem(help)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: S.menuQuit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.autoenablesItems = false
    }
}
