import AppKit
import ServiceManagement

/// Uygulama omurgası: izleyici → raf → panel/menü. Tek örnek.
final class AppController: NSObject {
    let prefs = Preferences.shared
    let store: ShelfStore
    #if SHOTMORI_CLOUD
    let cloud: CloudCenter
    #endif
    let registry: ActionRegistry
    let panel: ShelfPanelController
    /// Üst şerit yüzeyi; ilk kullanımda kurulur (yüzen panel seçiliyken hiç kurulmaz).
    lazy var stripController: StripController = MainActor.assumeIsolated {
        let c = StripController(store: store, registry: registry, prefs: prefs,
                                detachedShelves: { [weak self] in Set(self?.detached.keys.map { $0 } ?? []) },
                                onDetachedTabClicked: { [weak self] id in self?.panel.onDetachedTabClicked?(id) },
                                watchedFolder: { [weak self] in self?.folder })
        c.onDetachRequest = { [weak self] id in self?.detach(id) }
        c.onChooseFolder = { [weak self] in self?.chooseWatchedFolder() }
        c.suppressMenuBarReveal = { [weak self] in self?.settingsOrOnboardingOpen ?? false }
        stripBuilt = true
        return c
    }
    /// Şerit denetleyicisi kuruldu mu (lazy): yüzen panel seçiliyken izleyiciyi durdurmak için kurmak gerekmez.
    private var stripBuilt = false
    /// Ayarlar ya da kurulum penceresi ekranda mı: menü çubuğunda bekleme şeridi indirmez.
    private var settingsOrOnboardingOpen: Bool { settingsWC?.window?.isVisible == true || onboardingWC?.window?.isVisible == true }
    /// Menü çubuğunda bekleme izleyicisi tercihe göre başlar/durur (açılış, Ayarlar kaydı, raf stili değişimi; spec §9).
    private func refreshStripTracking() {
        guard prefs.shelfStyle == .strip || stripBuilt else { return }
        MainActor.assumeIsolated { stripController.updateTracking() }
    }
    /// Kullanıcıya görünen ana raf yüzeyi: tercihe göre şerit ya da yüzen panel. Ayrılmış pencereler hep `panel` üzerinden.
    var shelf: ShelfPresenting { prefs.shelfStyle == .strip ? stripController : panel }
    /// Pencereye ayrılmış raflar (Aşama 2): raf kimliği → kendi paneli. Kalıcı değil; yeniden başlatınca hepsi sekme.
    private(set) var detached: [UUID: ShelfPanelController] = [:]
    private(set) var status: StatusItemController!
    private let hotKeys = HotKeyCenter()
    private var watcher: ScreenshotWatcher?
    /// Kaldırma olayı 1,5 sn ertelenir: bu sürede aynı dosya yeni adla gelirse (yeniden adlandırma) öğe yerinde kalır. Anahtar: eski yol.
    private var pendingRemovals: [String: DispatchWorkItem] = [:]
    private static let removalGrace: TimeInterval = 1.5
    /// İzlenen klasör; nil → kullanıcı henüz seçmedi ya da bookmark çözülemedi (sandbox'ta macOS ayarı okunamaz).
    private(set) var folder: URL?
    private var folderAccess: FolderAccess { FolderAccess(prefs: prefs) }
    /// En son çözülen bookmark verisi: tercih bildirimi yalnız bu değişince klasörü yeniden çözer (her ayar değişimi çözmesin).
    private var lastResolvedBookmark: Data?
    /// Güncel ve önceki klasörlerin security-scoped erişimi; izleme süresince açık kalır.
    private let folderSession = FolderAccessSession()
    private var settingsWC: SettingsWindowController?
    private(set) var onboardingWC: OnboardingWindowController?
    /// Kurulum sırasında algılanan son kare (deneme adımı).
    var onScreenshotDetected: ((URL) -> Void)?

    // MARK: Hazırlık (intent'ler ve dış yollar `start()` bitişini bekler)
    private static let readyGate = ReadyGate<AppController>()
    /// `start()` bitince atanır (zayıf); test ana bilgisayarında hiç atanmaz.
    static var shared: AppController? { readyGate.current }
    static func markReady(_ c: AppController) { readyGate.open(c) }
    /// `start()` bitmişse hemen döner; değilse 100 ms aralıkla bekler, `timeout` içinde hazır olmazsa `IntentError.notReady`.
    /// Kurulum penceresi bastırılmaz: kurulum bitmemişken de `start()` tamamlanır.
    static func ready(timeout: TimeInterval = 10) async throws -> AppController { try await readyGate.wait(timeout: timeout) }

    override init() {
        store = ShelfStore(fileURL: ShelfStore.defaultFileURL(), maxItems: prefs.maxItems)
        #if SHOTMORI_CLOUD
        cloud = CloudCenter(prefs: prefs, store: store)
        registry = ActionRegistry(prefs: prefs, cloud: Features.cloud ? cloud : nil)
        panel = ShelfPanelController(store: store, registry: registry, prefs: prefs)
        panel.cloud = cloud; cloud.panel = panel
        #else
        registry = ActionRegistry(prefs: prefs) // bulutsuz derleme: yükleme eylemleri ve bulut menüsü yok
        panel = ShelfPanelController(store: store, registry: registry, prefs: prefs)
        #endif
        super.init()
        wire(panel)
        status = StatusItemController(app: self)
        #if SHOTMORI_CLOUD
        cloud.backup.watchedFolder = { [weak self] in self?.folder }
        // Bulut olayları CloudCenter'da tek bildirime birleşir; gizli yüzey yeniden kurulmaz, gösterilince kurulur (PERF-05/18).
        cloud.onChange = { [weak self] in self?.shelf.setNeedsReload(); self?.detached.values.forEach { $0.setNeedsReload() }; self?.status?.reloadIfShown() }
        #endif
        store.addObserver { [weak self] in self?.refreshBadge(); self?.closePanelsOfRemovedShelves(); self?.reattachIfActiveIsDetached() }
        panel.onDetachRequest = { [weak self] id in self?.detach(id) }
        panel.onDetachedTabClicked = { [weak self] id in guard let p = self?.detached[id]?.panel else { return }; p.orderFrontRegardless(); p.makeKey() }
        #if SHOTMORI_CLOUD
        if prefs.shelfStyle == .strip { cloud.panel = shelf } // bulut bildirimleri görünen yüzeye
        #endif
        NotificationCenter.default.addObserver(self, selector: #selector(prefsChanged), name: Preferences.didChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(shelfStyleChanged), name: .shelfStyleChanged, object: nil)
        // İzlenen klasörün diski takılınca/çıkarılınca izleme yeniden kurulur (takılı olmayan klasör takılınca izlenmeye başlar); ilgisiz diskler (DMG, Time Machine) yok sayılır.
        for n in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(volumesChanged), name: n, object: nil)
        }
    }
    @objc private func volumesChanged(_ n: Notification) {
        guard Self.volumeChangeAffectsWatch(folder: folder, volume: n.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL) else { return }
        startWatching(restart: true)
    }
    /// Disk olayı izlemeyi etkiler mi: klasör bekleniyor (disk ya da seçim), disk bilinmiyor ya da klasör o diskte. Kök disk ("/") önekle eşleşmez.
    static func volumeChangeAffectsWatch(folder: URL?, volume: URL?) -> Bool {
        guard let folder, let volume else { return true }
        let f = folder.standardizedFileURL.path, v = volume.standardizedFileURL.path
        if f == v { return true }
        return v != "/" && f.hasPrefix(v.hasSuffix("/") ? v : v + "/")
    }
    /// Ana ve ayrılmış panellerin uygulamaya bağlantıları: izlenen klasör, klasör seçimi, öğe erişilebilirliği.
    private func wire(_ c: ShelfPanelController) {
        c.watchedFolder = { [weak self] in self?.folder }; c.onChooseFolder = { [weak self] in self?.chooseWatchedFolder() }
        c.itemAccessible = { [weak self] in self?.isAccessible($0) ?? true }
    }
    /// Kök değişiminde raf ve (bulutlu derlemede) yükleme kuyruğu yolları birlikte taşınır. Döndürür: değişen yol sayısı.
    private func rebaseAllPaths(from old: String, to new: String) -> Int {
        #if SHOTMORI_CLOUD
        return store.rebasePaths(from: old, to: new) + cloud.queue.rebasePaths(from: old, to: new)
        #else
        return store.rebasePaths(from: old, to: new)
        #endif
    }
    /// Açılışta budama yalnız klasör erişilebilirken: takılı olmayan disk ya da seçim beklerken hiçbir öğe "kayıp" sayılmaz.
    static func shouldPruneOnLaunch(_ state: FolderAccess.State) -> Bool { if case .ready = state { return true }; return false }

    func start() {
        Log.info("Shotmori başladı v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "?")")
        if !AppPaths.isIsolated { // konteyner göçü: Türevler/Pano yolları yeni köke (sandbox dışında iki kök aynı → iş yok)
            let old = AppPaths.legacyApplicationSupport.path, new = AppPaths.applicationSupport.path
            let n = rebaseAllPaths(from: old, to: new)
            if n > 0 { Log.info("Konteyner göçü: \(n) yol güncellendi") }
        }
        // Erişim kapsamları raf denetiminden önce açılır: kapsam dışındaki dosyanın durumu güvenilir okunmaz.
        // Bookmark'lar bir kez çözülür; aynı durum izleyiciye aktarılır (X-05: açılışta iki kez çözülmesin).
        let access = folderAccess
        let state = access.resolve()
        folderSession.activate(access.scopes(for: state))
        lastResolvedBookmark = prefs.folderBookmark
        // Klasör erişilemezken (takılı olmayan disk, seçim bekliyor) hiçbir öğe "kayıp" sayılmaz: budama yapılmaz.
        if Self.shouldPruneOnLaunch(state) { pruneMissingInBackground() }
        registerHotKey()
        #if SHOTMORI_CLOUD
        if Features.cloud { cloud.queue.start() }
        #endif
        if !prefs.onboardingDone { showOnboarding() }
        else if case .ready = state { startWatching(resolved: state); catchUp() }
        else { startWatching(resolved: state); showOnboarding(folderOnly: true) } // erişim kayboldu (göç, silinen klasör): yalnız klasör sayfası
        refreshBadge()
        sweepContainer()
        // Otomasyon yüzeyleri (her biri kendi dosyasında): URL şeması, Servisler, durum öğesine bırakma, widget anlık görüntüsü.
        installServices(); installStatusDrop(); installWidgetSnapshot() // URL şeması `application(_:open:)` → `handleOpen` üzerinden
        refreshStripTracking()
        Self.markReady(self)
        #if DEBUG
        QAOpen.apply(app: self)
        #endif
    }
    /// Kendi konteyner dosyalarımız (Türevler, Pano, Gelen): rafta ve yükleme kuyruğunda olmayan, 7 günden eski olanlar arka planda Çöp'e.
    /// Raf eksik yüklendiyse ya da bir raf yedeği okunamıyorsa hiç çalışmaz: kurtarılacak başvuruların dosyaları Çöp'e gitmesin.
    private func sweepContainer() {
        guard let shelfRefs = store.janitorReferences() else { Log.info("Konteyner temizliği atlandı: raf eksik yüklendi ya da yedek okunamadı (\(store.allItems.count) öğe)"); return }
        #if SHOTMORI_CLOUD
        let referenced = shelfRefs.union(cloud.queue.tasks.map(\.filePath))
        #else
        let referenced = shelfRefs
        #endif
        DispatchQueue.global(qos: .utility).async {
            // Gelen: içe aktarılan kopyalar; tekilleştirme indeksi rafta olmasa da korunur.
            let n = DerivativeJanitor.sweep(roots: [ImageResizer.derivativesFolder, ClipboardImport.folder, InboundImport.folder],
                                            referenced: referenced.union([InboundImport.indexURL().path]), olderThan: 7 * 86_400) { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
            if n > 0 { Log.info("Konteyner temizliği: \(n) eski dosya Çöp'e taşındı") }
        }
    }

    /// Açılış budaması (X-05): dosya varlığı yardımcı kuyrukta denetlenir (yavaş ağ diskinde ana iş parçacığı beklemez);
    /// sonuç ana iş parçacığında, yalnız eksik görünen ve kapsamdaki öğelere uygulanır (`pruneMissing` onları yeniden denetler).
    private func pruneMissingInBackground() {
        let paths = store.allItems.filter { !$0.localTrashed }.map(\.path)
        guard !paths.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let missing = Self.missingPaths(paths, exists: { FileManager.default.fileExists(atPath: $0) })
            guard !missing.isEmpty else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                let pruned = self.store.pruneMissing { missing.contains($0.path) && self.isAccessible($0) }
                if pruned > 0 { Log.info("Kayıp \(pruned) öğe listeden düştü") }
            }
        }
    }
    /// Var olmayan yollar (saf; test edilebilir).
    static func missingPaths(_ paths: [String], exists: (String) -> Bool) -> Set<String> { Set(paths.filter { !exists($0) }) }

    // MARK: İzleme
    /// `restart`: aynı klasör olsa da akışı yeniden kurar (kök taşındı/yeniden adlandırıldı, disk takıldı/çıkarıldı); sonra aradaki kareler toplanır.
    /// `resolved`: çağıran bookmark'ları az önce çözüp kapsamları açtıysa (açılış) aynı durum; yeniden çözülmez.
    func startWatching(restart: Bool = false, resolved: FolderAccess.State? = nil) {
        defer { shelf.setNeedsReload(); status?.reloadIfShown() } // boş raf metni klasör durumunu yansıtsın (gizliyse gösterilince)
        let previous = folder
        let state: FolderAccess.State
        if let resolved { state = resolved } else {
            let access = folderAccess
            lastResolvedBookmark = prefs.folderBookmark
            state = access.resolve()
            folderSession.activate(access.scopes(for: state)) // güncel kaybolsa da önceki klasörlerin kapsamı açık kalır
        }
        lastResolvedBookmark = prefs.folderBookmark // bayat bookmark yenilenmiş olabilir
        if restart { watcher?.stop(); watcher = nil }
        guard case .ready(let url) = state else {
            watcher?.stop(); watcher = nil; folder = nil
            Log.info("İzlenen klasör seçilmedi"); return
        }
        if let w = watcher, w.folder == url { return } // aynı klasör zaten izleniyor
        watcher?.stop(); watcher = nil
        // Kök taşındı/yeniden adlandırıldı: eski kökteki raf öğeleri yeni köke bağlanır (yoksa sonsuza dek "eksik" kalırlar, budama da kapsam dışı diye düşürmez).
        if let r = Self.rebaseRoot(previous: previous, current: url, restart: restart, previousExists: previous.map { FileManager.default.fileExists(atPath: $0.path) } ?? false) {
            let n = rebaseAllPaths(from: r.from, to: r.to)
            if n > 0 { Log.info("İzlenen klasör taşındı: \(n) yol güncellendi") }
        }
        folder = url
        guard FolderAccess.isReadable(url) else { Log.error("Klasör okunamıyor (izin?)"); return }
        let w = ScreenshotWatcher(folder: url)
        w.onNewScreenshot = { [weak self] url in self?.ingest(url) }
        w.onRemoved = { [weak self] url in self?.scheduleRemoval(url) }
        w.onRootChanged = { [weak self] in self?.startWatching(restart: true) }
        w.start(); watcher = w
        if restart { catchUp() } // disk yokken ya da eski izleyicinin yeniden deneme zincirindeyken gelen kareler
    }
    /// Kök değişimi: yalnız yeniden kurulumda, klasör farklıysa ve eski yol artık yoksa (kullanıcı başka klasör seçtiyse eski klasör durur).
    static func rebaseRoot(previous: URL?, current: URL, restart: Bool, previousExists: Bool) -> (from: String, to: String)? {
        guard restart, let previous, !previousExists else { return nil }
        let from = previous.standardizedFileURL.path, to = current.standardizedFileURL.path
        return from == to ? nil : (from, to)
    }
    /// Uygulama kapalıyken gelenler: son 24 saat, en çok 10. İlk kurulumda da son 24 saat alınır.
    private func catchUp(firstRun: Bool = false) {
        guard let folder else { return }
        let dayAgo = Date(timeIntervalSinceNow: -24 * 3600)
        let since = firstRun ? dayAgo : (prefs.lastSeenCaptureDate ?? dayAgo)
        // Klasör listesi ana kuyruğu bloklamasın (ağ/harici disk); ekleme ana kuyrukta, tek toplu `add` ile.
        // Dosya kimliği (stat) de burada: yavaş ağ diskinde ana kuyruk beklemesin.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let recent = ScreenshotWatcher.recentScreenshots(in: folder, limit: 10, newerThan: since)
            let items = Self.ingestItems(recent.map { ($0.url, ScreenshotFileInspector.fileIdentifier($0.url), $0.date) })
            DispatchQueue.main.async {
                guard let self = self, self.folder == folder, let newest = items.last else { return }
                _ = self.store.add(items)
                self.prefs.lastSeenCaptureDate = max(newest.capturedAt, since)
                Log.info("Kapalıyken gelen \(items.count) kare eklendi")
            }
        }
    }
    /// Dosya kayboldu: öğe hemen düşmez; `removalGrace` içinde aynı `fileID` yeni yolda gelirse `ingest` yolu günceller.
    private func scheduleRemoval(_ url: URL) {
        let path = url.path
        guard let item = store.allItems.first(where: { $0.path == path }), !item.localTrashed else { return }
        pendingRemovals[path]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.pendingRemovals[path] = nil
            if FileManager.default.fileExists(atPath: path) { return } // aynı adla geri geldi
            if self.store.allItems.first(where: { $0.path == path })?.localTrashed == true { return }
            self.store.remove(path: path)
        }
        pendingRemovals[path] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.removalGrace, execute: work)
    }
    /// Aynı dosya (fileID) başka yolda geldi ve eski yol artık yok → yeniden adlandırma: öğe yerinde kalır. Döndürür: ele alındı mı.
    private func followRename(to url: URL, fileID: String?) -> Bool {
        guard let old = Self.renameSource(fileID: fileID, newPath: url.path, items: store.allItems, exists: { FileManager.default.fileExists(atPath: $0) }) else { return false }
        pendingRemovals[old.path]?.cancel(); pendingRemovals[old.path] = nil
        store.updatePath(itemID: old.id, to: url.path)
        return true
    }
    /// Yeniden adlandırmanın kaynağı: aynı `fileID`, farklı yol ve eski yol artık yok (duruyorsa sabit bağ ya da kopyadır).
    static func renameSource(fileID: String?, newPath: String, items: [ShelfItem], exists: (String) -> Bool) -> ShelfItem? {
        guard let fid = fileID else { return nil }
        return items.first { $0.fileID == fid && $0.path != newPath && !exists($0.path) }
    }
    /// Toplu geliş: yeni kareler 0,3 sn biriktirilip tek `store.add` ile eklenir (300 karede 300 kayıt/yeniden çizim olmaz).
    /// Geliş anındaki dosya kimliğiyle saklanır: flush'ta yeniden `stat` yok (yalnız kimliği okunamamış girişler için).
    private var pendingIngest: [(url: URL, fileID: String?)] = []
    private static let ingestWindow: TimeInterval = 0.3
    private func ingest(_ url: URL) {
        let fid = ScreenshotFileInspector.fileIdentifier(url)
        pendingRemovals[url.path]?.cancel(); pendingRemovals[url.path] = nil // silinip aynı adla yeniden yazıldı
        if followRename(to: url, fileID: fid) { return }
        guard !pendingIngest.contains(where: { $0.url == url }) else { return }
        pendingIngest.append((url, fid))
        if pendingIngest.count == 1 { DispatchQueue.main.asyncAfter(deadline: .now() + Self.ingestWindow) { [weak self] in self?.flushIngest() } }
    }
    /// Pencerede bekleyen yollardan artık var olmayanları (yeniden adlandırılmış/silinmiş) eler; aynı `fileID` tek kez kalır (kimliği okunamayan hiç tekilleşmez).
    /// Saklı kimlik kullanılır; `fileID` yalnız kimliği nil olan girişler için yeniden hesaplanır.
    static func filterPending(_ entries: [(url: URL, fileID: String?)], exists: (URL) -> Bool, fileID: (URL) -> String?) -> [(url: URL, fileID: String?)] {
        var seen = Set<String>(); var out: [(url: URL, fileID: String?)] = []
        for e in entries where exists(e.url) {
            let f = e.fileID ?? fileID(e.url)
            if let f, !seen.insert(f).inserted { continue }
            out.append((e.url, f))
        }
        return out
    }
    /// Raf öğeleri eskiden yeniye: `store.add` her öğeyi başa koyar, böylece en yeni kare rafın başında kalır.
    static func ingestItems(_ entries: [(URL, String?, Date)]) -> [ShelfItem] {
        entries.map { ShelfItem(path: $0.0.path, fileID: $0.1, capturedAt: $0.2) }.sorted { $0.capturedAt < $1.capturedAt }
    }
    private func flushIngest() {
        let entries = Self.filterPending(pendingIngest, exists: { FileManager.default.fileExists(atPath: $0.path) }, fileID: { ScreenshotFileInspector.fileIdentifier($0) })
        pendingIngest = []
        guard !entries.isEmpty else { return }
        let items = Self.ingestItems(entries.map { ($0.url, $0.fileID, ScreenshotFileInspector.creationDate($0.url) ?? Date()) })
        let added = store.add(items)
        guard let newest = added.max(by: { $0.capturedAt < $1.capturedAt }) else { return }
        prefs.lastSeenCaptureDate = max(prefs.lastSeenCaptureDate ?? .distantPast, newest.capturedAt)
        Log.info("Yeni ekran görüntüsü eklendi (\(added.count))")
        #if SHOTMORI_CLOUD
        if Features.cloud { cloud.backup.screenshotsArrived(added) } // toplu: kuyruk bir kez yazılır
        #endif
        onScreenshotDetected?(newest.url)
        let mouseDown = NSEvent.pressedMouseButtons != 0
        if prefs.shelfStyle == .strip {
            MainActor.assumeIsolated { presentNewCaptureOnStrip(newest, mouseDown: mouseDown) }
        } else if Self.shouldAutoShowShelf(enabled: prefs.showShelfOnNewScreenshot, onboarding: onboardingVisible, panelVisible: shelf.isVisible, mouseDown: mouseDown) {
            shelf.show(takeKey: false); shelf.selectNewest(); Log.info("Panel yeni kare için açıldı")
        }
    }
    /// Üst şerit (spec §5.3, §7.1): gizliyse `shouldAutoShowShelf` koşuluyla yakalamanın ekranına odak almadan iner ve en yeni kart seçilir;
    /// zaten görünürse kısa gösterim süresi yeniden başlar, seçim değişmez. Her iki durumda kare yakalandığı yerden kartına uçar.
    @MainActor private func presentNewCaptureOnStrip(_ newest: ShelfItem, mouseDown: Bool) {
        let strip = stripController
        let step = StripPresentation.newCaptureStep(enabled: prefs.showShelfOnNewScreenshot, onboarding: onboardingVisible,
                                                    visible: strip.isVisible, mouseDown: mouseDown)
        guard step != .none else { return }
        let screens = NSScreen.screens
        let rect = CaptureRect.read(newest.url, mainScreenMaxY: screens.first?.frame.maxY ?? 0)
        var screen = StripPresentation.screen(containing: rect, screens: screens.map(\.frame)).map { screens[$0] }
        // Görünür şerit, sürükleme sürerken ya da yakalama yeri bilinmezken ekran değiştirmez.
        if step == .refresh, mouseDown || screen == nil { screen = strip.panel.screen }
        strip.presentNewCapture(newest, from: rect, on: screen)
        Log.info(step == .reveal ? "Şerit yeni kare için indi" : "Şerit yeni kare: kısa gösterim yenilendi")
    }
    /// Yeni kare gelince panel kendiliğinden açılsın mı: tercih açık, kurulum penceresi yok, panel zaten görünmüyor ve fare düğmesi basılı değil
    /// (sürükleme ya da tıklama sürerken araya girilmez). Kapalıyken gelenler (`catchUp`) ve dış yollar (Gelen/) bu yoldan geçmez.
    static func shouldAutoShowShelf(enabled: Bool, onboarding: Bool, panelVisible: Bool, mouseDown: Bool) -> Bool { enabled && !onboarding && !panelVisible && !mouseDown }
    private func refreshBadge() { status?.updateBadge(store.newCountAll) }

    // MARK: Ayrı pencere (Aşama 2)
    /// Rafı kendi yüzen paneline taşır: ana sekmede "pencerede" olarak kalır; etkin raf oysa ana panel ayrılmamış komşuya geçer.
    func detach(_ id: UUID) {
        let order = store.shelves.map(\.id)
        guard ShelfPanelController.canDetach(id, in: order, detached: Set(detached.keys)) else { return }
        if store.activeShelfID == id, let next = ShelfPanelController.nextActive(after: id, in: order, detached: Set(detached.keys)) { shelf.activateShelf(next) } // ayrılmış pencere düzeneği: görünen yüzeyin etkin rafı komşuya geçer
        let c = ShelfPanelController(store: store, registry: registry, prefs: prefs, mode: .detached(id))
        #if SHOTMORI_CLOUD
        c.cloud = cloud
        #endif
        wire(c)
        c.onReattach = { [weak self] in self?.reattach(id) }
        detached[id] = c; panel.detachedShelves = Set(detached.keys); refreshStripTabs()
        c.show(takeKey: true) // klavye (Esc → geri tak, oklar) pencereye gelsin
        Log.info("Raf ayrı pencerede açıldı (\(detached.count) pencere)")
    }
    /// Pencereyi kapatıp rafı sekmeye geri takar.
    func reattach(_ id: UUID) {
        guard let c = detached.removeValue(forKey: id) else { return }
        c.onReattach = nil; c.hide(reason: "geri tak")
        panel.detachedShelves = Set(detached.keys); refreshStripTabs()
        #if SHOTMORI_CLOUD
        if cloud.panel == nil || cloud.panel === c { cloud.panel = shelf } // bulut bildirimleri kapanan pencerede kalmasın
        #endif
        DispatchQueue.main.async { _ = c } // düğme/tuş işleyicisi yığındayken serbest bırakılmasın
    }
    /// Etkin raf pencerede olamaz (raf kapatma komşusu ya da popover seçici bunu seçmiş olabilir): raf ana panele geri döner.
    private func reattachIfActiveIsDetached() { if detached[store.activeShelfID] != nil { reattach(store.activeShelfID) } }
    /// Raf listeden düşünce açık penceresi de kapanır.
    private func closePanelsOfRemovedShelves() {
        let alive = Set(store.shelves.map(\.id))
        for id in detached.keys where !alive.contains(id) { reattach(id) }
    }
    /// Son kaydedilen kısayol: tercih bildirimi (iğne, şerit, bulut…) kısayolu yeniden kaydetmez; yalnız tuş ya da değiştiriciler değişince (X-06).
    private var registeredHotKey: (code: UInt32, modifiers: NSEvent.ModifierFlags)?
    static func hotKeyNeedsRegistration(registered: (code: UInt32, modifiers: NSEvent.ModifierFlags)?, code: UInt32, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard let r = registered else { return true }
        return r.code != code || r.modifiers != modifiers
    }
    private func registerHotKey() {
        let code = prefs.hotKeyCode, mods = prefs.hotKeyModifiers
        guard Self.hotKeyNeedsRegistration(registered: registeredHotKey, code: code, modifiers: mods) else { return }
        hotKeys.onPress = { [weak self] in self?.shelf.toggle() }
        hotKeys.register(keyCode: code, modifiers: mods); registeredHotKey = (code, mods)
    }
    @objc private func prefsChanged() {
        registerHotKey(); if store.maxItems != prefs.maxItems { store.setMaxItems(prefs.maxItems) } // her ayar değişiminde kırpma/kayıt yok
        if prefs.folderBookmark != lastResolvedBookmark { startWatching(); Log.info("Klasör değişti") } // yalnız bookmark değişince çöz
        shelf.setNeedsReload()
        refreshStripTracking() // `shelfStyleChanged` her dış yazımda yayınlanmaz: stil ve menü çubuğu tercihi burada da değerlendirilir
    }
    /// Raf stili değişince görünür olan yüzey gizlenir (yüzen panel ve şerit); bulut bildirimleri yeni yüzeye gider.
    @objc private func shelfStyleChanged() {
        panel.hide(reason: "stil"); (stripController as ShelfPresenting).hide(reason: "stil")
        refreshStripTracking()
        #if SHOTMORI_CLOUD
        cloud.panel = shelf
        #endif
    }
    /// Şerit sekmeleri ayrılmış rafları soluk gösterir; şerit seçiliyken pencere açılıp kapanınca yenilenir.
    private func refreshStripTabs() { if prefs.shelfStyle == .strip { shelf.setNeedsReload() } }

    // MARK: Menü eylemleri
    @objc func toggleShelf() { shelf.toggle() }
    /// Tüm raflarda en son eklenen, Çöp'e taşınmamış kare (`ShelfIntentCore.latest`: menü, Denetim Merkezi ve Kestirmeler aynı ölçütte).
    @objc func copyLastScreenshot() { if let f = MainActor.assumeIsolated({ ShelfIntentCore.latest(store: store) }) { shelf.run("copy-image", items: [f], anchor: nil) } }
    @objc func addFromClipboard() {
        ClipboardImport.importImage { [weak self] url in
            guard let self = self else { return }
            guard let url = url else { self.shelf.showToast(S.clipboardNoImage); self.shelf.show(takeKey: false); return }
            self.store.add(ClipboardImport.shelfItem(for: url))
            self.shelf.show(takeKey: false)
        }
    }
    @objc func openSettings() { openSettingsPage(nil) }
    /// `page` verilirse o sayfa açılır (QA, derin bağlantı); nil → son seçili sayfa.
    func openSettingsPage(_ page: SettingsPage?) {
        if settingsWC == nil { settingsWC = SettingsWindowController(app: self) }
        if let p = page { settingsWC?.select(page: p) }
        NSApp.activate(ignoringOtherApps: true); settingsWC?.showWindow(nil); settingsWC?.window?.makeKeyAndOrderFront(nil)
    }
    @objc func rerunOnboarding() { showOnboarding() }
    @objc func chooseWatchedFolder() { showOnboarding(folderOnly: true) }
    @objc func showLog() { NSWorkspace.shared.activateFileViewerSelecting([Log.fileURL]) }
    @objc func showAbout() { NSApp.activate(ignoringOtherApps: true); NSApp.orderFrontStandardAboutPanel(nil) }

    /// Kurulum penceresi ekranda mı. Yeni kare yolu buna bakar: ✕/⌘W ile kapatılan pencere rafın kendiliğinden açılmasını engellemez.
    var onboardingVisible: Bool { onboardingWC?.window?.isVisible == true }
    /// Kurulum yeniden istendiğinde: açık pencere aynı kipteyse öne gelir; açık tam akışa yalnız klasör isteği gelirse de öne gelir
    /// (tam akış klasör sayfasını içerir; değiştirilse Bitir kısayol ve deneme adımlarını atlayıp kurulumu bitmiş sayardı);
    /// açık yalnız klasör sayfasına tam akış isteği gelirse kapatılıp yenisi açılır; pencere yoksa yenisi açılır.
    enum OnboardingRequest: Equatable { case bringToFront, replace, open }
    static func onboardingRequest(visible: Bool, visibleFolderOnly: Bool, requestedFolderOnly: Bool) -> OnboardingRequest {
        guard visible else { return .open }
        return (visibleFolderOnly == requestedFolderOnly || requestedFolderOnly) ? .bringToFront : .replace
    }

    func showOnboarding(folderOnly: Bool = false) {
        switch Self.onboardingRequest(visible: onboardingVisible, visibleFolderOnly: onboardingWC?.folderOnly ?? false, requestedFolderOnly: folderOnly) {
        case .bringToFront: NSApp.activate(ignoringOtherApps: true); onboardingWC?.showWindow(nil); return
        case .replace: onboardingWC?.close() // `onClose` eski pencerenin durumunu temizler
        case .open: break
        }
        let wasOnboarded = prefs.onboardingDone // kurulum açılmadan okunur: yalnız gerçek ilk kurulum son 24 saati alır
        shelf.hide(reason: "kurulum")
        let wc = OnboardingWindowController(app: self, folderOnly: folderOnly) { [weak self] in
            guard let self = self else { return }
            self.prefs.onboardingDone = true
            self.onboardingWC = nil
            self.startWatching(); self.catchUp(firstRun: !wasOnboarded)
        }
        // ✕/⌘W ya da Bitir: yalnız bu pencere hâlâ güncel kurulumsa durum temizlenir (kurulum bitmiş sayılmaz).
        wc.onClose = { [weak self, weak wc] in
            guard let self, let wc, self.onboardingWC === wc else { return }
            self.onboardingWC = nil; self.onScreenshotDetected = nil
        }
        onboardingWC = wc
        NSApp.activate(ignoringOtherApps: true); wc.showWindow(nil)
    }

    /// Raf öğesi okunabilir mi: açık bir klasör kapsamında ya da Shotmori'nin kendi klasöründe (Türevler/Pano).
    func isAccessible(_ item: ShelfItem) -> Bool { folderSession.covers(item.path, extraRoots: [AppPaths.applicationSupport]) }

    /// Kurulum ve Ayarlar'daki NSOpenPanel seçimi: bookmark kaydedilir, izleme yeni klasöre geçer.
    func chooseFolder(_ url: URL) throws {
        try folderAccess.choose(url)
        startWatching(); Log.info("Klasör seçildi")
    }

    // MARK: Girişte başlat
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set { do { if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch { Log.error("Girişte başlat ayarlanamadı: \(Log.describe(error))") } }
    }
}
