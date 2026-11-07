import SwiftUI
import AppKit

final class SettingsModel: ObservableObject {
    let app: AppController
    @Published var tab: SettingsPage = .general
    /// İzlenen klasör; nil → seçilmedi.
    @Published var folderURL: URL?
    @Published var maxItems: Int
    @Published var hideAfterDrop: Bool
    @Published var keepShelfOpen: Bool
    @Published var showShelfOnNewScreenshot: Bool
    @Published var shelfStyle: ShelfStyle
    @Published var newCaptureStripMode: NewCaptureStripMode
    @Published var stripRevealFromMenuBar: Bool
    @Published var favorites: [String]
    @Published var hotKeyCode: UInt32
    @Published var hotKeyModifiers: NSEvent.ModifierFlags
    @Published var launchAtLogin: Bool
    @Published var uiLanguage: String // "" = sistem
    @Published var languageChanged = false
    /// Ayarlar › Genel › Otomasyon: `shotmori://` komutlarına izin.
    @Published var urlSchemeEnabled: Bool
    private var p: Preferences { app.prefs }
    private var prefsObserver: NSObjectProtocol?
    /// Kendi `notifyChanged` yayınımız sırasında gelen bildirim yok sayılır (yankı yok).
    private var saving = false
    /// Adımlayıcıdan sonra bekleyen (henüz yazılmamış) öğe sınırı; onay diyaloğu açıkken yeniden girilmez.
    private var pendingMaxItems: DispatchWorkItem?
    private var confirmingMaxItems = false
    static let maxItemsCommitDelay: TimeInterval = 0.8

    init(app: AppController) {
        self.app = app
        folderURL = app.folder
        maxItems = app.prefs.maxItems; hideAfterDrop = app.prefs.hideAfterDrop; keepShelfOpen = app.prefs.keepShelfOpen; showShelfOnNewScreenshot = app.prefs.showShelfOnNewScreenshot
        shelfStyle = app.prefs.shelfStyle; newCaptureStripMode = app.prefs.newCaptureStripMode; stripRevealFromMenuBar = app.prefs.stripRevealFromMenuBar
        favorites = app.prefs.favoriteActionIDs
        hotKeyCode = app.prefs.hotKeyCode; hotKeyModifiers = app.prefs.hotKeyModifiers
        launchAtLogin = app.launchAtLogin
        uiLanguage = app.prefs.uiLanguage ?? ""
        urlSchemeEnabled = app.prefs.urlSchemeEnabled
        // Panel iğnesi, onboarding kısayolu gibi dış değişiklikler açık pencereye yansır; eski değer sonraki kayıtla geri yazılmaz.
        prefsObserver = NotificationCenter.default.addObserver(forName: Preferences.didChange, object: app.prefs, queue: nil) { [weak self] _ in
            guard let self = self, !self.saving else { return }; self.reloadFromPrefs()
        }
    }
    deinit { if let o = prefsObserver { NotificationCenter.default.removeObserver(o) } }
    /// Modeli tercihlerden yeniden okur (pencere açılışı ve dış değişiklik). Yalnız farklı değerler atanır: `onChange → save` yankısı olmaz.
    /// Bekleyen/onay bekleyen öğe sınırı korunur.
    func reloadFromPrefs() {
        func sync<T: Equatable>(_ kp: ReferenceWritableKeyPath<SettingsModel, T>, _ v: T) { if self[keyPath: kp] != v { self[keyPath: kp] = v } }
        sync(\.folderURL, app.folder)
        if pendingMaxItems == nil && !confirmingMaxItems { sync(\.maxItems, p.maxItems) }
        sync(\.hideAfterDrop, p.hideAfterDrop); sync(\.keepShelfOpen, p.keepShelfOpen); sync(\.showShelfOnNewScreenshot, p.showShelfOnNewScreenshot); sync(\.shelfStyle, p.shelfStyle); sync(\.newCaptureStripMode, p.newCaptureStripMode); sync(\.stripRevealFromMenuBar, p.stripRevealFromMenuBar); sync(\.favorites, p.favoriteActionIDs)
        sync(\.hotKeyCode, p.hotKeyCode); sync(\.hotKeyModifiers, p.hotKeyModifiers)
        sync(\.launchAtLogin, app.launchAtLogin); sync(\.uiLanguage, p.uiLanguage ?? "")
        sync(\.urlSchemeEnabled, p.urlSchemeEnabled)
    }
    private func notify() { saving = true; p.notifyChanged(); saving = false }
    /// `save()` ile yazılan değerler; tercihlerdekiyle aynıysa yazma ve bildirim yapılmaz.
    struct Snapshot: Equatable {
        var hideAfterDrop: Bool, keepShelfOpen: Bool, favorites: [String], hotKeyCode: UInt32, hotKeyModifiers: NSEvent.ModifierFlags
        var showShelfOnNewScreenshot: Bool = true
        var shelfStyle: ShelfStyle = .floating, newCaptureStripMode: NewCaptureStripMode = .peek, stripRevealFromMenuBar: Bool = true
    }
    var snapshot: Snapshot { Snapshot(hideAfterDrop: hideAfterDrop, keepShelfOpen: keepShelfOpen, favorites: favorites, hotKeyCode: hotKeyCode, hotKeyModifiers: hotKeyModifiers, showShelfOnNewScreenshot: showShelfOnNewScreenshot, shelfStyle: shelfStyle, newCaptureStripMode: newCaptureStripMode, stripRevealFromMenuBar: stripRevealFromMenuBar) }
    static func needsSave(model: Snapshot, stored: Snapshot) -> Bool { model != stored }
    /// Öğe sınırı burada yazılmaz: yalnız `commitMaxItems` (onay yolu) yazar.
    /// Dış değişiklik (panel iğnesi) `reloadFromPrefs` → `onChange` → `save` yankısı aynı değerleri getirir: yazılmaz, `prefsChanged` ikinci kez koşmaz.
    func save() {
        guard Self.needsSave(model: snapshot, stored: Snapshot(prefs: p)) else { return }
        p.hideAfterDrop = hideAfterDrop; p.keepShelfOpen = keepShelfOpen; let styleChanged = p.shelfStyle != shelfStyle
        p.showShelfOnNewScreenshot = showShelfOnNewScreenshot; p.shelfStyle = shelfStyle; p.newCaptureStripMode = newCaptureStripMode; p.stripRevealFromMenuBar = stripRevealFromMenuBar; app.shelf.syncPinFromPrefs(); p.favoriteActionIDs = favorites; p.hotKeyCode = hotKeyCode; p.hotKeyModifiers = hotKeyModifiers; notify()
        if styleChanged { NotificationCenter.default.post(name: .shelfStyleChanged, object: p) }
    }
    enum MaxItemsCommit: Equatable { case none, apply, confirm(dropped: Int) }
    /// Değişiklik yok → yazma yok; listeden öğe düşecekse onay; değilse doğrudan uygula.
    static func decide(model: Int, stored: Int, dropped: Int) -> MaxItemsCommit { model == stored ? .none : dropped > 0 ? .confirm(dropped: dropped) : .apply }
    /// Adımlayıcı yalnız modeli değiştirir; 0,8 sn sessizlikten sonra (ya da pencere kapanınca) `commitMaxItems`.
    func stepMaxItems(_ n: Int) {
        maxItems = n; pendingMaxItems?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.commitMaxItems() }; pendingMaxItems = w
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.maxItemsCommitDelay, execute: w)
    }
    /// Sınırı uygular. Listeden öğe düşecekse onay ister (Return/Esc → Vazgeç: değer eski hâline döner); dosyalara dokunulmaz.
    func commitMaxItems() {
        pendingMaxItems?.cancel(); pendingMaxItems = nil
        guard !confirmingMaxItems else { return }
        switch Self.decide(model: maxItems, stored: p.maxItems, dropped: maxItems == p.maxItems ? 0 : app.store.droppedCount(ifMaxItems: maxItems)) {
        case .none: return
        case .apply: break
        case .confirm(let dropped):
            confirmingMaxItems = true; defer { confirmingMaxItems = false }
            var proceed = false
            ForegroundHelper.withActivation { done in
                let a = NSAlert(); a.alertStyle = .warning; a.messageText = S.maxItemsConfirmTitle(dropped); a.informativeText = S.maxItemsConfirmBody
                ConfirmDialog.configure(a, safe: S.cancel, proceed: S.maxItemsConfirmButton, destructive: false, symbol: "tray")
                proceed = ConfirmDialog.shouldProceed(ConfirmDialog.run(a)); done()
            }
            guard proceed else { maxItems = p.maxItems; return }
        }
        p.maxItems = maxItems; notify()
    }
    /// Bekleyen öğe sınırı önce uygulanır: onayı açık seçim panelinin içine gömülmez.
    func chooseFolder() {
        commitMaxItems()
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.prompt = S.choosePrompt
        if case .needsSelection(let s) = FolderAccess(prefs: p).resolve() { panel.directoryURL = s } else { panel.directoryURL = folderURL }
        guard panel.runModal() == .OK, let u = panel.url else { return }
        do { try app.chooseFolder(u); folderURL = app.folder } catch { Log.error("Klasör kaydedilemedi: \((error as NSError).code)"); FolderPrompt.showError(S.folderSaveFailed) }
    }
    func revealFolder() { if let f = folderURL { NSWorkspace.shared.activateFileViewerSelecting([f]) } }
    /// Öğe sınırı da varsayılana döner ama adımlayıcıyla aynı onay yolundan geçer; Vazgeç'te eski sınır kalır.
    func resetShelf() {
        let kept = p.maxItems; p.resetScreenshotsSection(); if p.maxItems != kept { p.maxItems = kept }
        hideAfterDrop = p.hideAfterDrop; keepShelfOpen = p.keepShelfOpen; showShelfOnNewScreenshot = p.showShelfOnNewScreenshot
        let styleChanged = shelfStyle != p.shelfStyle
        shelfStyle = p.shelfStyle; newCaptureStripMode = p.newCaptureStripMode; stripRevealFromMenuBar = p.stripRevealFromMenuBar; app.shelf.syncPinFromPrefs(); notify()
        if styleChanged { NotificationCenter.default.post(name: .shelfStyleChanged, object: p) }
        maxItems = Preferences.defaultMaxItems; commitMaxItems()
    }
    func resetActions() { p.resetActionsSection(); favorites = p.favoriteActionIDs; notify() }
    func resetGeneral() { let had = p.uiLanguage != nil; p.resetGeneralSection(); hotKeyCode = p.hotKeyCode; hotKeyModifiers = p.hotKeyModifiers; uiLanguage = ""; urlSchemeEnabled = p.urlSchemeEnabled; if had { languageChanged = true }; notify() }
    /// Anahtara dokunmak açık bir seçimdir: ilk dış istekte ayrıca sorulmaz.
    func setURLSchemeEnabled(_ v: Bool) {
        guard v != p.urlSchemeEnabled || !p.urlSchemeAsked else { urlSchemeEnabled = v; return }
        p.urlSchemeEnabled = v; p.urlSchemeAsked = true; urlSchemeEnabled = v; notify()
    }
    func setLanguage(_ code: String) { uiLanguage = code; p.uiLanguage = code.isEmpty ? nil : code; languageChanged = true }
    /// Yeni bir örnek başlatıp bu örnekten çıkar; dil tercihi yeni örnekte okunur.
    /// Sandbox uyumlu: kabuk süreci yok, yeni örneği NSWorkspace açar.
    func relaunch() {
        commitMaxItems() // bekleyen sınır çıkıştan önce uygulanır (gerekirse onayla)
        let cfg = NSWorkspace.OpenConfiguration(); cfg.createsNewApplicationInstance = true
        cfg.arguments = [RelaunchGate.argument, String(getpid())] // yeni örnek bu örnek kapanana kadar bekler
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: cfg) { _, error in
            DispatchQueue.main.async {
                if let e = error { Log.error("Yeniden başlatılamadı: \((e as NSError).code)"); FolderPrompt.showError(S.relaunchFailed); return }
                NSApp.terminate(nil)
            }
        }
    }
    func toggleLaunchAtLogin(_ v: Bool) { app.launchAtLogin = v; launchAtLogin = app.launchAtLogin }
    func toggleFavorite(_ id: String, on: Bool) { if on { if !favorites.contains(id) { favorites.append(id) } } else { favorites.removeAll { $0 == id } }; save() }
    func moveFavorites(from: IndexSet, to: Int) { favorites.move(fromOffsets: from, toOffset: to); save() }
    /// Klavye/düğme ile bir sıra yukarı/aşağı; sınırlarda hareket etmez. SwiftUI `move` hedef indeksi kaldırma öncesi dizinedir.
    func moveFavorite(at i: Int, by delta: Int) {
        let j = i + delta; guard favorites.indices.contains(i), favorites.indices.contains(j) else { return }
        moveFavorites(from: IndexSet(integer: i), to: delta < 0 ? j : j + 1)
        AXAnnounce.post("\(app.registry.action(favorites[j])?.title ?? ""), \(j + 1)/\(favorites.count)")
    }
    var version: String { "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] ?? "?"))" }
}

/// Kenar çubuğu + sayfa: Sistem Ayarları deseni. Sayfalar gruplu form; açıklamalar araç ipucunda.
struct SettingsView: View {
    @ObservedObject var m: SettingsModel
    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            SettingsSidebar(selection: $m.tab, version: m.version)
                // Sütun genişliği tek başına uygulanmıyor (kenar çubuğu ~144 pt'ye iniyor, "Quick actions" kesiliyordu):
                // içerik de en az bu genişlikte istenir. 200 pt iki dilde en uzun sayfa adını büyük kenar çubuğu yazısında sığdırır.
                .frame(minWidth: 200)
                .navigationSplitViewColumnWidth(min: 200, ideal: 200, max: 200)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            detail.navigationTitle(m.tab.title).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 700, minHeight: 460)
        .tint(.smAccent)
    }
    @ViewBuilder private var detail: some View {
        switch m.tab {
        case .general: GeneralPane(m: m)
        case .shelf: ShelfPane(m: m)
        case .actions: ActionsPane(m: m)
        case .about: AboutPane(version: m.version)
        case .cloud:
            #if SHOTMORI_CLOUD
            CloudTab(cloud: m.app.cloud)
            #else
            GeneralPane(m: m)
            #endif
        }
    }

}

#if SHOTMORI_CLOUD
/// Bulut sekmesi kendi modelini tutar. SHOTMORI_CLOUD Debug ve Release 1.0'da açık; bayrak kaldırılmış derlemede sekme, model ve Anahtar Zinciri erişimi hiç yok.
private struct CloudTab: View {
    @StateObject private var model: CloudSettingsModel
    init(cloud: CloudCenter) { _model = StateObject(wrappedValue: CloudSettingsModel(cloud: cloud)) }
    var body: some View { CloudSettingsView(m: model) }
}
#endif

extension SettingsModel.Snapshot {
    init(prefs p: Preferences) { self.init(hideAfterDrop: p.hideAfterDrop, keepShelfOpen: p.keepShelfOpen, favorites: p.favoriteActionIDs, hotKeyCode: p.hotKeyCode, hotKeyModifiers: p.hotKeyModifiers, showShelfOnNewScreenshot: p.showShelfOnNewScreenshot, shelfStyle: p.shelfStyle, newCaptureStripMode: p.newCaptureStripMode, stripRevealFromMenuBar: p.stripRevealFromMenuBar) }
}

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let model: SettingsModel
    init(app: AppController) {
        let model = SettingsModel(app: app); self.model = model
        let host = NSHostingController(rootView: SettingsView(m: model))
        host.sizingOptions = [] // pencere boyutu SwiftUI'nin asgari ölçüsüne küçülmesin; 700×520 açılır, boyut hatırlanır
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 520), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.contentViewController = host; w.setContentSize(NSSize(width: 700, height: 520))
        w.isReleasedWhenClosed = false; w.minSize = NSSize(width: 700, height: 460) // başlık sayfadan gelir (navigationTitle); 700: 200 pt kenar çubuğu + 500 pt sayfa
        w.applyGlassChrome(toolbarIdentifier: "settings") // cam krom: .fullSizeContentView + boş araç çubuğu; kenar çubuğu başlığın altına uzanır
        w.level = .floating; w.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        if !AppPaths.isIsolated { w.setFrameAutosaveName("Settings") } // yalıtılmış QA örneği gerçek tercihlere pencere çerçevesi yazmaz
        super.init(window: w); w.delegate = self
        if !w.setFrameUsingName("Settings") { w.center() }
    }
    required init?(coder: NSCoder) { fatalError() }
    func select(page: SettingsPage) { model.tab = page }
    /// Pencere önbellekte kalır: klasör ve tercihler kapalıyken değişmiş olabilir, her açılışta güncel durum okunur.
    override func showWindow(_ sender: Any?) {
        model.reloadFromPrefs(); super.showWindow(sender); window?.orderFrontRegardless(); window?.makeKey()
        // AppKit ilk anahtar olan pencerede ilk metin alanını yanıtlayıcı yapıp metnin tamamını seçer (Bulut › klasör şablonu);
        // açılışta hiçbir alan odak almaz. Sekme (Tab) yine ilk alana gider.
        DispatchQueue.main.async { [weak self] in
            guard let w = self?.window, w.firstResponder is NSText else { return }
            w.makeFirstResponder(nil)
        }
    }
    /// Kapanırken bekleyen öğe sınırı uygulanır (gerekirse onayla); pencere onay sırasında görünür kalır.
    func windowShouldClose(_ sender: NSWindow) -> Bool { model.commitMaxItems(); return true }
}
