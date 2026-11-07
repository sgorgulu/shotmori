import AppKit
import SwiftUI

/// Üst şeridin davranışı: pencere (`StripPanel`) + SwiftUI görünümü (`StripView`), raf yüzeyi sözleşmesi,
/// iniş/çekiliş, 30 Hz imleç tıkı (geçirgenlik + otomatik çekilme; gizliyken yalnız imleç menü çubuğu bandındayken, bekleme için),
/// rüzgâr, dışarı tıklama ve ekran değişimi.
/// Seçim/eylemler `+Interaction`, sürükleme `+Drag`, sekmeler `+Tabs` dosyalarında.
/// Odak: yalnız kısayolla (`show(takeKey: true)`) klavyeyi alır; diğer yollar hiçbir uygulamayı etkinleştirmez.
@MainActor
final class StripController: NSObject, @preconcurrency ShelfPresenting {
    typealias RevealReason = StripRevealReason

    let store: ShelfStore
    let registry: ActionRegistry
    let prefs: Preferences
    let detachedShelves: () -> Set<UUID>
    let onDetachedTabClicked: (UUID) -> Void
    let watchedFolder: () -> URL?
    /// Sekme menüsü › Ayrı pencerede aç (AppController bağlar; ayrı pencere her zaman yüzen paneldir).
    var onDetachRequest: ((UUID) -> Void)?
    /// Boş şeritte "Klasör Seç…" (AppController bağlar).
    var onChooseFolder: (() -> Void)?

    let model: StripModel
    let panel: StripPanel
    let hosting: NSHostingView<StripView>
    private let reduceMotion: () -> Bool

    // Durum (uzantılar da kullanır)
    var sel = ShelfSelection()
    var status = StatusCenter()
    /// Kalıcı bildirimin eylem bağlantısı ("Yeniden dene"); başlık şerit modeline yansır.
    var noticeAction: NoticeAction? { didSet { model.noticeActionTitle = noticeAction?.title } }
    var pinnedOpen: Bool
    var overflowFavorites: [ShelfAction] = []
    /// Açık menü, onay penceresi ya da adlandırma balonu sayısı: varken şerit kendiliğinden çekilmez.
    var modalDepth = 0
    var internalDropHandled = false
    var renameSession: StripRenameSession?
    /// Şu an çalışan kopyalama eyleminin öğeleri: "Kopyalandı" rozeti yalnız bunlardan şeritte görüneni işaretler.
    var copyingIDs: [UUID] = []
    /// Kabul edilen bırakmadan sonra bekleyen çekilme; 0,35 sn içinde yeniden inişte iptal edilir.
    var pendingDropHide: DispatchWorkItem?

    private(set) var shown = false
    private(set) var reason: RevealReason = .shortcut
    private(set) var revealedAt = Date()
    private var pointerAwaySince: Date?
    /// İmlecin şeridin bölgesinde son görüldüğü an (iniş de sayılır): rüzgâr yalnız yakın zamanda etkileşim varken sürer.
    private var lastPointerVisit = Date()
    /// Görev 10/11: imleç şeridin bölgesinde mi (şeridin alt kenarından ekranın tepesine kadar).
    private(set) var pointerInside = false
    private var screenID: NSNumber?
    /// İmleç izleyicisi: görünürken 30 Hz; gizliyken (menü çubuğundan indirme açıksa) hareket olayı izler, 30 Hz yalnız bantta (`updateTracking`).
    private(set) lazy var pointerTracker = StripPointerTracker { [weak self] p in self?.tick(mouse: p, now: Date()) }
    private var dwell = MenuBarDwell()
    /// Ayarlar ya da kurulum penceresi açıkken true: menü çubuğunda bekleme şeridi indirmez (AppController bağlar).
    var suppressMenuBarReveal: () -> Bool = { false }
    private var gustTimer: Timer?
    /// Global + yerel fare basma izleyicisi (menü çubuğu tıkı ve dışarı tık); izleyiciyle birlikte kurulur.
    private var clickMonitors: [Any] = []
    private var observers: [Any] = []
    private var storeObserver: UUID?
    private var needsReload = false
    private var copiedGeneration = 0

    init(store: ShelfStore, registry: ActionRegistry, prefs: Preferences, detachedShelves: @escaping () -> Set<UUID>,
         onDetachedTabClicked: @escaping (UUID) -> Void, watchedFolder: @escaping () -> URL?,
         reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }) {
        self.store = store; self.registry = registry; self.prefs = prefs
        self.detachedShelves = detachedShelves; self.onDetachedTabClicked = onDetachedTabClicked; self.watchedFolder = watchedFolder
        self.reduceMotion = reduceMotion
        let model = StripModel(reduceMotion: reduceMotion)
        self.model = model
        hosting = NSHostingView(rootView: StripView(model: model, actions: StripViewActions()))
        hosting.sizingOptions = []
        panel = StripPanel(content: hosting, reduceMotion: reduceMotion)
        pinnedOpen = prefs.keepShelfOpen
        super.init()
        model.actionInfo = { [weak registry] id in registry?.action(id).map { (symbol: $0.symbolName, title: $0.title) } }
        hosting.rootView = StripView(model: model, actions: makeActions())
        panel.onKey = { [weak self] ev in self?.handleKey(ev) ?? false }
        panel.onScroll = { [weak self] dx, dy, precise in self?.handleScroll(dx: dx, dy: dy, precise: precise) }
        storeObserver = store.addObserver { [weak self] in
            guard let self else { return }
            if self.shown { self.reload() } else { self.needsReload = true }
        }
        let nc = NotificationCenter.default
        for n in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            observers.append(nc.addObserver(forName: n, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.model.keyboardFocused = self?.panel.isKeyWindow == true }
            })
        }
        observers.append(nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        })
        reload()
    }

    deinit {
        MainActor.assumeIsolated {
            if let t = storeObserver { store.removeObserver(t) }
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            gustTimer?.invalidate() // izleyici kendi deinit'inde durur; lazy özelliğe burada dokunulmaz (zayıf başvuru kurulamaz)
            clickMonitors.forEach { NSEvent.removeMonitor($0) }
        }
    }

    // MARK: ShelfPresenting
    var isVisible: Bool { shown }
    var isBusy: Bool { status.isBusy }
    var displayedShelfID: UUID { store.activeShelfID }
    var showsTabs: Bool { true }
    var displayedItems: [ShelfItem] { store.activeShelf.items }

    func toggle() { shown ? hide(reason: "kısayol") : show(takeKey: true) }
    /// Kısayol ve odak alan girişler `.shortcut`; diğerleri odak almadan `.external` (yeni kare ayarına uyar).
    func show(takeKey: Bool) { reveal(on: nil, reason: takeKey ? .shortcut : .external) }

    /// Şeridi `screen` (yoksa imlecin ekranı) üstüne indirir. Görünürken çağrılırsa kısayol nedeni korunur, süre yeniden başlar.
    func reveal(on screen: NSScreen?, reason: RevealReason) {
        let wasShown = shown
        pendingDropHide?.cancel(); pendingDropHide = nil
        if !wasShown || reason == .shortcut || self.reason != .shortcut { self.reason = reason }
        revealedAt = Date(); pointerAwaySince = nil; lastPointerVisit = revealedAt
        // Önce yerleşim: numaralar (1–9) ve kaydırma sınırı pencerenin gerçek genişliğiyle hesaplanır
        // (ilk inişte pencere henüz `StripPanel.init`in 800 pt'lik genişliğindedir).
        let target = screen ?? Self.screenUnderMouse() ?? NSScreen.main
        var placed = false
        if let target, !wasShown || Self.id(of: target) != screenID {
            screenID = Self.id(of: target)
            panel.place(on: target, height: StripLayout.stripHeight)
            placed = true
        }
        if !wasShown || needsReload { reload() } else if placed {
            model.scrollOffset = clampedOffset(model.scrollOffset, count: model.items.count)
            refreshQuickNumbers()
        }
        if !wasShown { selectNewestIfEmpty() }
        if self.reason == .shortcut { panel.keyboardFocusAllowed = true }
        shown = true
        panel.orderFrontRegardless()
        if !wasShown { panel.setRevealed(true) }
        if reason == .shortcut { panel.makeKey() }
        panel.updatePassThrough(mouseLocation: NSEvent.mouseLocation)
        startGust(); updateTracking()
        if !wasShown { Log.info("Şerit indi (\(Self.logName(reason)))") }
    }

    func hide(reason: String) {
        guard shown else { return }
        shown = false
        ShelfQuickLook.shared.close(ifHostedBy: panel)
        renameSession?.close()
        stopGust(); updateTracking()
        panel.keyboardFocusAllowed = false
        model.pressedID = nil
        pointerInside = false
        // Ters çevrilen çekilişin tamamlaması çalışmaz (StripPanel sözleşmesi): yeniden inişte pencere ekranda kalır.
        panel.setRevealed(false) { [weak self] in
            guard let self, !self.shown else { return }
            self.panel.orderOut(nil)
        }
        Log.info("Şerit çekildi (\(reason))")
    }

    func reload() {
        needsReload = false
        let items = displayedItems
        model.items = items
        model.newIDs = Set(store.itemsSinceLastHandoff(shelfID: displayedShelfID).map(\.id))
        sel.reconcile(existing: items.map(\.id))
        model.selection = sel.ids
        model.fallingIDs.formIntersection(items.map(\.id))
        model.scrollOffset = clampedOffset(model.scrollOffset, count: items.count)
        let detached = detachedShelves()
        model.tabs = store.shelves.map {
            StripTab(id: $0.id, title: $0.name, count: $0.items.count, active: $0.id == store.activeShelfID, detached: detached.contains($0.id),
                     canDetach: canDetachShelf($0.id, detached: detached))
        }
        model.emptyState = watchedFolder() == nil ? .noFolder : (items.isEmpty ? .empty(hotKey: ScreenshotHotKeys.area) : .none)
        rebuildCapsule()
        refreshQuickNumbers()
    }

    func selectNewest() {
        if needsReload { reload() }
        if let f = displayedItems.first { sel.selectOnly(f.id); applySelection() }
    }
    func selectNewestIfEmpty() { if sel.isEmpty { selectNewest() } }

    func activateShelf(_ id: UUID) {
        guard id != store.activeShelfID, let sh = store.shelves.first(where: { $0.id == id }) else { return }
        sel = ShelfSelection(); model.scrollOffset = 0
        store.setActiveShelf(id: id) // gözlemci → reload
        if needsReload { reload() }
        selectNewestIfEmpty()
        AXAnnounce.post(S.shelfSwitchedAX(sh.name))
    }

    func syncPinFromPrefs() { pinnedOpen = prefs.keepShelfOpen; rebuildCapsule() }

    // MARK: Durum mesajları (sağ kapsülün altında)
    /// Şeritte "Kopyalandı" kartın üstündeki kapsülle gösterilir; rutin toast yutulur (spec §7.4a).
    /// Rozet yalnız şeridin `run` ile kopyaladığı ve şu an şeritte görünen karta konur; diğer kopyalamalarda (son kare,
    /// Kestirmeler, bulut bağlantısı) olağan bildirim gösterilir.
    func showToast(_ text: String) {
        if text == S.copiedToast, let id = Self.copiedBadgeTarget(copying: copyingIDs, displayed: model.items.map(\.id), shown: shown) {
            flashCopied(id); return
        }
        noticeAction = nil; present(StatusMessage(text: text, kind: .success))
    }
    func showNotice(_ text: String) { noticeAction = nil; present(StatusMessage(text: text, kind: .persistent)) }
    func showNotice(_ text: String, action: NoticeAction) { noticeAction = action; present(StatusMessage(text: text, kind: .persistent)) }
    func setBusy(_ text: String?) {
        if let t = text { present(StatusMessage(text: t, kind: .busy)) } else { status.busyEnded(); model.notice = status.current }
    }
    /// Eş: `ShelfPanelController.dismissNotice/noticeActionTapped`; burada kapatma ve eylem `noticeAction`ı her zaman temizler.
    func dismissNotice() { status.dismiss(); model.notice = nil; noticeAction = nil }
    func noticeActionTapped() { let a = noticeAction; noticeAction = nil; dismissNotice(); a?.run() }
    private func present(_ m: StatusMessage) {
        status.show(m); model.notice = m
        AXAnnounce.post(m.text, high: m.kind == .persistent)
        if let d = StatusCenter.autoDismissDelay(m.kind) {
            DispatchQueue.main.asyncAfter(deadline: .now() + d) { [weak self] in
                guard let self, self.status.current == m else { return }
                self.dismissNotice()
            }
        }
    }
    /// Kopyalanan öğelerden şeritte görünen ilki; şerit gizliyse ya da hiçbiri görünmüyorsa nil (bildirim gösterilir).
    static func copiedBadgeTarget(copying: [UUID], displayed: [UUID], shown: Bool) -> UUID? {
        guard shown else { return nil }
        let shownIDs = Set(displayed)
        return copying.first { shownIDs.contains($0) }
    }
    func flashCopied(_ id: UUID) {
        copiedGeneration += 1; let gen = copiedGeneration
        model.copiedID = id
        AXAnnounce.post(S.copiedToast)
        DispatchQueue.main.asyncAfter(deadline: .now() + StripMotion.copyBadgeDuration) { [weak self] in
            guard let self, self.copiedGeneration == gen else { return }
            self.model.copiedID = nil
        }
    }

    // MARK: Kaydırma
    private func handleScroll(dx: CGFloat, dy: CGFloat, precise: Bool) {
        let d = abs(dx) >= abs(dy) ? dx : dy // fare tekerleği dikey kaydırır; şerit yataydır
        scroll(by: precise ? d : d * 12, width: panel.frame.width)
    }
    /// `delta` > 0 içeriği sağa (yeniye doğru) kaydırır; ofset [0, maximumOffset] içinde kalır.
    func scroll(by delta: CGFloat, width: CGFloat) {
        let max = StripLayout.maximumOffset(count: model.items.count, width: width)
        let next = min(Swift.max(model.scrollOffset - delta, 0), max)
        guard next != model.scrollOffset else { return }
        model.scrollOffset = next
        refreshQuickNumbers()
    }
    func clampedOffset(_ offset: CGFloat, count: Int) -> CGFloat {
        min(max(offset, 0), StripLayout.maximumOffset(count: count, width: panel.frame.width))
    }
    /// 1–9: ekranda görünen ilk dokuz kart.
    func refreshQuickNumbers() {
        let width = panel.frame.width, half = StripLayout.cardWidth / 2
        let range = StripLayout.visibleRange(count: model.items.count, width: width, offset: model.scrollOffset)
        let visible = range.filter {
            let x = StripLayout.x(index: $0, scrollOffset: model.scrollOffset)
            return x + half > 0 && x - half < width
        }
        model.quickNumbers = ShelfKeyboard.quickNumbers(visible: visible.map { model.items[$0].id })
    }

    // MARK: İmleç tıkı (`StripPointerTracker`)
    /// Boşta CPU %0 (spec §9): gizliyken yalnız Üst şerit seçili ve menü çubuğundan indirme açıkken izlenir.
    /// Görünür şerit her zaman izlenir (geçirgenlik ve çekilme izleyiciye bağlı; stil değişimi şeridi zaten çeker).
    static func shouldTrack(style: ShelfStyle, revealFromMenuBar: Bool, visible: Bool) -> Bool {
        visible || (style == .strip && revealFromMenuBar)
    }
    /// İzleyiciyi ve tık izleyicilerini tercihe ve görünürlüğe göre başlatır/durdurur (iniş, çekiliş, tercih değişimi).
    /// Görünürken 30 Hz sürekli; gizliyken izleyici yalnız fare hareketini dinler, 30 Hz tık imleç menü çubuğu bandına girince başlar
    /// (boşta, imleç kıpırdamazken uygulama hiç uyanmaz).
    func updateTracking() {
        guard Self.shouldTrack(style: prefs.shelfStyle, revealFromMenuBar: prefs.stripRevealFromMenuBar, visible: shown) else {
            pointerTracker.stop(); removeClickMonitors(); dwell = MenuBarDwell()
            return
        }
        if shown { pointerTracker.start() } else { pointerTracker.watch(hot: { Self.inMenuBarBand($0) }) }
        installClickMonitors()
    }

    /// Tek tık girişi. Gizliyken menü çubuğunda bekleme; görünürken geçirgenlik, imleç bölgesi ve otomatik çekilme kararı.
    func tick(mouse: NSPoint, now: Date) {
        guard shown else { tickHidden(mouse: mouse, now: now); return }
        _ = dwell.tick(inMenuBar: Self.inMenuBarBand(mouse), now: now) // görünürken de sayılır: imleç bantta kalırken çekilen şerit hemen geri inmez
        panel.hitRects = Array(model.hitRects.values)
        panel.updatePassThrough(mouseLocation: mouse)
        pointerInside = zone().contains(mouse)
        if pointerInside { lastPointerVisit = now; startGust() } // boşta duran esinti imleç dönünce yeniden başlar
        var s = retractState(now: now)
        let statusNow = s.persistentNotice || s.busy
        // Kalıcı bildirim / meşgul kapanınca 2,5 sn kuralı yeniden başlar (spec §7.4a).
        if statusHeld && !statusNow { revealedAt = now }
        statusHeld = statusNow
        // Durdurucu sürerken uzaklık sayılmaz: menü/sürükleme/bildirim bitince 0,5 sn yeniden başlar.
        let heldOpen = s.dragging || s.menuOpen || s.pressing || s.quickLookOpen || s.editorOpen || statusNow
        if pointerInside || heldOpen { pointerAwaySince = nil } else if pointerAwaySince == nil { pointerAwaySince = now }
        s.secondsSinceReveal = now.timeIntervalSince(revealedAt)
        s.secondsPointerAway = pointerAwaySince.map { now.timeIntervalSince($0) } ?? 0
        if StripRetract.shouldRetract(s) { hide(reason: "kendiliğinden") }
    }
    private var statusHeld = false

    /// Gizliyken: imleç bir ekranın menü çubuğu bandında 0,25 sn durunca şerit o ekranda odak almadan iner (spec §7.1).
    private func tickHidden(mouse: NSPoint, now: Date) {
        guard prefs.shelfStyle == .strip, prefs.stripRevealFromMenuBar, !suppressMenuBarReveal() else { dwell = MenuBarDwell(); return }
        let screens = NSScreen.screens
        let index = Self.menuBarScreenIndex(mouse, screens: screens.map { ($0.frame, $0.visibleFrame) })
        if dwell.tick(inMenuBar: index != nil, now: now), let index { reveal(on: screens[index], reason: .menuBar) }
    }

    func retractState(now: Date) -> StripRetractState {
        StripRetractState(reason: reason, mode: prefs.newCaptureStripMode, pinned: pinnedOpen, pointerInside: pointerInside,
                          dragging: model.draggingID != nil, menuOpen: modalDepth > 0 || renameSession != nil || SharePickerTracker.isOpen || otherWindowHoldsOpen(),
                          pressing: model.pressedID != nil, quickLookOpen: ShelfQuickLook.shared.isOpen,
                          editorOpen: EditorWindowController.current != nil || ResizeWindowController.current != nil,
                          persistentNotice: status.isPersistent, busy: status.isBusy,
                          secondsSinceReveal: now.timeIntervalSince(revealedAt),
                          secondsPointerAway: pointerAwaySince.map { now.timeIntervalSince($0) } ?? 0)
    }

    /// Paylaşım seçicisi, menü, dosya paneli ya da sayfa açık mı (şeridin kendi penceresi ve uçuş katmanları hariç).
    private func otherWindowHoldsOpen() -> Bool {
        StripRetract.otherWindowHoldsOpen(NSApp.windows.map { w in
            StripWindowSnapshot(level: w.level.rawValue, visible: w.isVisible, isFilePanel: w is NSSavePanel, isSheet: w.isSheet,
                                hasAttachedSheet: w.attachedSheet != nil, excluded: w === panel || w.level == CaptureFlight.windowLevel)
        })
    }

    /// Şeridin bölgesi: pencerenin alt kenarından ekranın tepesine (menü çubuğu dahil).
    private func zone() -> NSRect {
        var r = panel.frame
        if let top = panel.screen?.frame.maxY { r.size.height = top - r.minY }
        return r
    }

    // MARK: Rüzgâr (görünürken, kart varken, sürükleme yokken; hareket azaltmada yok)
    /// Esinti etkileşime bağlıdır: imleç `gustIdleLimit` boyunca şeride uğramadıysa (iğneli ya da "kapatana kadar açık" şerit
    /// boşta) zamanlayıcı yeniden kurulmaz; imleç şeride dönünce (`tick`) yeniden başlar. Pencere örtülüyse esinti atlanır.
    private func startGust() {
        guard gustTimer == nil else { return }
        let t = Timer(timeInterval: Double.random(in: StripMotion.gustInterval), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.gustTimer = nil
                guard self.shown, Self.keepsGusting(idleSeconds: Date().timeIntervalSince(self.lastPointerVisit)) else { return }
                if Self.shouldGust(hasItems: !self.model.items.isEmpty, dragging: self.model.draggingID != nil, reduceMotion: self.reduceMotion(),
                                   windowVisible: self.panel.occlusionState.contains(.visible)) { self.model.gust += 1 }
                self.startGust()
            }
        }
        t.tolerance = 1 // süs animasyonu: sistem uyanmayı birleştirebilir
        RunLoop.main.add(t, forMode: .common)
        gustTimer = t
    }
    /// Esinti zamanlayıcısı yeniden kurulsun mu: imleç son `gustIdleLimit` sn içinde şeride uğradıysa.
    static func keepsGusting(idleSeconds: TimeInterval) -> Bool { idleSeconds < StripMotion.gustIdleLimit }
    /// Bu esinti oynasın mı: kart var, sürükleme yok, Hareket azaltma kapalı, pencere ekranda görünür.
    static func shouldGust(hasItems: Bool, dragging: Bool, reduceMotion: Bool, windowVisible: Bool) -> Bool {
        hasItems && !dragging && !reduceMotion && windowVisible
    }
    var isGustScheduled: Bool { gustTimer != nil }
    private func stopGust() { gustTimer?.invalidate(); gustTimer = nil }

    // MARK: Menü çubuğu ve dışarı tıklama
    /// Global izleyici başka uygulamalara (menü çubuğu dahil), yerel izleyici Shotmori'nin kendi pencerelerine gelen basmaları görür.
    /// Yerelde yalnız menü çubuğu bandı sayılır (durum öğesi); şeridin kendi penceresi ve diğer Shotmori pencereleri sayılmaz.
    private func installClickMonitors() {
        guard clickMonitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] ev in
            MainActor.assumeIsolated { self?.handleMouseDown(at: Self.screenLocation(of: ev)) }
        }) { clickMonitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] ev in
            MainActor.assumeIsolated {
                guard let self, ev.window !== self.panel else { return }
                let p = Self.screenLocation(of: ev)
                if Self.inMenuBarBand(p) { self.handleMouseDown(at: p) }
            }
            return ev
        }) { clickMonitors.append(l) }
    }
    /// Basmanın ekran koordinatı (olayın kendi konumu; imleç olaydan sonra kaymış olabilir). Global olaylarda pencere yoktur.
    private static func screenLocation(of ev: NSEvent) -> NSPoint {
        ev.window.map { $0.convertPoint(toScreen: ev.locationInWindow) } ?? ev.locationInWindow
    }
    private func removeClickMonitors() { clickMonitors.forEach { NSEvent.removeMonitor($0) }; clickMonitors = [] }

    /// Menü çubuğuna basma bekleme sayacını bastırır (imleç banttan çıkana dek inmez) ve iğnesizken şeridi çeker;
    /// başka yere basma yalnız kısayolla / "kapatana kadar" inişte çeker.
    func handleMouseDown(at p: NSPoint) {
        let menuBar = Self.inMenuBarBand(p)
        if menuBar { dwell.menuBarClicked() }
        guard shown else { return }
        if Self.hidesOnClick(inMenuBar: menuBar, reason: reason, mode: prefs.newCaptureStripMode, pinned: pinnedOpen) {
            hide(reason: menuBar ? "menü çubuğu tık" : "dışarı tık")
        }
    }
    /// İğne her tıktan önce gelir (menü çubuğu dahil, spec §7.2); menü çubuğu bandı iğnesizken her inişte çeker.
    static func hidesOnClick(inMenuBar: Bool, reason: RevealReason, mode: NewCaptureStripMode, pinned: Bool) -> Bool {
        guard !pinned else { return false }
        if inMenuBar { return true }
        switch reason {
        case .shortcut: return true
        case .newCapture, .external: return mode == .stay
        case .menuBar: return false
        }
    }
    typealias ScreenFrames = [(frame: NSRect, visible: NSRect)]
    /// Nokta bir ekranın menü çubuğu bandında mı (`MenuBarBand`).
    static func inMenuBarBand(_ p: NSPoint, screens: ScreenFrames = NSScreen.screens.map { ($0.frame, $0.visibleFrame) },
                              thickness: CGFloat = NSStatusBar.system.thickness) -> Bool {
        menuBarScreenIndex(p, screens: screens, thickness: thickness) != nil
    }
    /// Noktanın menü çubuğu bandında bulunduğu ekranın sırası; bant dışındaysa nil. Bandın alt kenarı (görünür alanın tepesi) dahil.
    static func menuBarScreenIndex(_ p: NSPoint, screens: ScreenFrames, thickness: CGFloat = NSStatusBar.system.thickness) -> Int? {
        guard let i = screens.firstIndex(where: { NSMouseInRect(p, $0.frame, false) }) else { return nil }
        let band = MenuBarBand.rect(screenFrame: screens[i].frame, visibleFrame: screens[i].visible, statusBarThickness: thickness)
        return p.y >= band.minY && p.y <= band.maxY ? i : nil
    }

    // MARK: Ekran
    private func screensChanged() {
        guard shown else { return }
        let target = NSScreen.screens.first { Self.id(of: $0) == screenID } ?? Self.screenUnderMouse() ?? NSScreen.main
        guard let target else { return }
        screenID = Self.id(of: target)
        panel.place(on: target, height: StripLayout.stripHeight)
        model.scrollOffset = clampedOffset(model.scrollOffset, count: model.items.count)
        refreshQuickNumbers()
    }
    static func screenUnderMouse() -> NSScreen? { NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } }
    private static func id(of s: NSScreen) -> NSNumber? { s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber }
    private static func logName(_ r: RevealReason) -> String {
        switch r { case .shortcut: "kısayol"; case .newCapture: "yeni kare"; case .menuBar: "menü çubuğu"; case .external: "dış yol" }
    }
}
