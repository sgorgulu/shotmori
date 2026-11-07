#if SHOTMORI_CLOUD // Bulut kodu SHOTMORI_CLOUD bayrağıyla derlenir (Debug ve Release 1.0'da açık, bkz. Features.swift); bayrak kaldırılırsa derlenmez.
import AppKit

/// Bulut özelliğinin merkezi: sağlayıcılar, kuyruk, geçmiş, link üretimi, teslim sonrası raf güncellemesi.
/// Sağlayıcılar tercihlerden kurulur; gizli bilgiler Anahtar Zinciri'nden okunur.
final class CloudCenter {
    let prefs: Preferences
    let keychain: KeychainStore
    let store: ShelfStore
    let queue: UploadQueue
    let history: UploadHistoryStore
    weak var panel: ShelfPresenting?
    private(set) var drive: GoogleDriveProvider?
    private(set) var driveOAuth: GoogleOAuth?
    private(set) var s3: S3Provider?
    /// Test/QA: sağlayıcıları dışarıdan ver.
    var providerOverride: ((CloudProviderID) -> CloudProvider?)?
    var backup: BackupCoordinator!
    /// Rozet/raf yenilemesi: aynı ana döngü turundaki değişiklikler tek çağrıda birleştirilir (`scheduleChange`).
    var onChange: (() -> Void)?

    /// Bulut kapalıyken (`Features.cloud == false`; bayrak kaldırılmış derleme ya da test): sağlayıcı kurulmaz (Anahtar Zinciri okunmaz), rozet yok.
    let enabled: Bool
    init(prefs: Preferences, keychain: KeychainStore = KeychainStore(), store: ShelfStore, dataDir: URL = AppPaths.applicationSupport, isOnline: @escaping () -> Bool = { true }, enabled: Bool = Features.cloud) {
        self.prefs = prefs; self.keychain = keychain; self.store = store; self.enabled = enabled
        history = UploadHistoryStore(fileURL: dataDir.appendingPathComponent("uploads.json"))
        var providerLookup: ((CloudProviderID) -> CloudProvider?)!
        queue = UploadQueue(fileURL: dataDir.appendingPathComponent("uploads-queue.json"), providers: { providerLookup($0) }, isOnline: isOnline)
        providerLookup = { [weak self] id in self?.provider(id) }
        rebuildProviders(force: true)
        // Kuyruk durumu ana aktörde değişir (`UploadQueue.processNext`); geri bildirimler yine de `onMain` ile güvenceye alınır.
        queue.onUploaded = { [weak self] task, obj in Self.onMain { self?.handleUploaded(task, obj) } }
        queue.onFailed = { [weak self] task, err in Self.onMain { self?.handleFailed(task, err) } }
        queue.onChange = { [weak self] in Self.onMain { self?.scheduleChange() } }
        backup = BackupCoordinator(prefs: prefs, queue: queue, store: store, providers: { [weak self] in self?.provider($0) }, notify: { [weak self] msg in Self.onMain { self?.panel?.showToast(msg) } })
        NotificationCenter.default.addObserver(forName: Preferences.didChange, object: nil, queue: .main) { [weak self] _ in self?.rebuildProviders() }
    }

    /// Sağlayıcıları kuran tercih imzası: istemci kimliği ve S3 yapılandırması. Gizli anahtar değişimi `saveDrive/saveS3/clearS3` ile zorlanır.
    private struct ProviderInputs: Equatable { let driveClientID: String; let s3: S3Config? }
    private var lastInputs: ProviderInputs?
    /// Bulutla ilgisiz tercih değişiminde (iğne, şerit, kısayol…) sağlayıcılar yeniden kurulmaz, Anahtar Zinciri okunmaz, raf yenilenmez.
    func rebuildProviders(force: Bool = false) {
        guard enabled else { driveOAuth = nil; drive = nil; s3 = nil; return }
        let inputs = ProviderInputs(driveClientID: prefs.driveClientID, s3: prefs.s3Config)
        guard force || inputs != lastInputs else { return }
        let initial = lastInputs == nil
        lastInputs = inputs
        // Kullanıcının kendi istemcisi öncelikli; yoksa uygulamaya gömülü geliştirici istemcisi (tek tık "Google ile giriş yap").
        if let c = CloudDefaults.effectiveDriveClient(customID: prefs.driveClientID, customSecret: keychain.get(CloudAccount.driveClientSecret)) {
            let o = GoogleOAuth(clientID: c.id, clientSecret: c.secret, keychain: keychain)
            o.onSessionExpired = { [weak self] in Self.onMain { Log.info("Drive oturumu geçersiz: belirteçler silindi"); self?.scheduleChange() } }
            driveOAuth = o; drive = GoogleDriveProvider(oauth: o)
        } else { driveOAuth = nil; drive = nil }
        if let cfg = prefs.s3Config { let k = keychain; s3 = S3Provider(config: cfg, secretProvider: { k.get(CloudAccount.s3Secret) }) } else { s3 = nil }
        if !initial { scheduleChange() } // açılıştaki ilk kurulum rafı yenilemez
    }
    private var changePending = false
    /// Değişiklikleri birleştirir: aynı turda gelen enqueue/etkin/silme bildirimleri tek `onChange` olur.
    private func scheduleChange() {
        guard !changePending else { return }
        changePending = true
        DispatchQueue.main.async { [weak self] in guard let self else { return }; self.changePending = false; self.onChange?() }
    }
    func provider(_ id: CloudProviderID) -> CloudProvider? {
        if let o = providerOverride { return o(id) }
        switch id { case .googleDrive: return drive; case .s3: return s3 }
    }
    func isConnected(_ id: CloudProviderID) -> Bool { provider(id)?.isConnected ?? false }
    var linkFormat: LinkFormat { prefs.linkFormat }

    // MARK: Hesaplar
    func connectDrive() async throws { guard let o = driveOAuth else { throw CloudError.notConnected }; try await o.signIn(); await MainActor.run { onChange?() } }
    func disconnectDrive() async { await driveOAuth?.signOut(); await MainActor.run { onChange?() } }
    /// Ana iş parçacığındaysa hemen, değilse ana kuyruğa atarak çalıştırır (testlerdeki eşzamanlı çağrılar aynı kalır).
    static func onMain(_ work: @escaping () -> Void) { if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) } }
    /// Kendi Google istemcisi. `clientSecret` nil → Anahtar Zinciri'ndeki gizli anahtara dokunulmaz (giriş öncesi yeniden kayıt onu silmez);
    /// boş metin ya da istemci kimliği boşaltılırsa (gömülü istemciye dönüş) kayıtlı gizli anahtar kaldırılır.
    func saveDrive(clientID: String, clientSecret: String?) {
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        prefs.driveClientID = id
        if id.isEmpty || clientSecret?.isEmpty == true { keychain.delete(CloudAccount.driveClientSecret) }
        else if let s = clientSecret { try? keychain.set(s, account: CloudAccount.driveClientSecret) }
        rebuildProviders(force: true)
    }
    var hasDriveClientSecret: Bool { keychain.get(CloudAccount.driveClientSecret) != nil }
    func saveS3(config: S3Config, secret: String?) { prefs.s3Config = config; if let s = secret, !s.isEmpty { try? keychain.set(s, account: CloudAccount.s3Secret) }; rebuildProviders(force: true) }
    func clearS3() { prefs.s3Config = nil; keychain.delete(CloudAccount.s3Secret); rebuildProviders(force: true) }
    func test(_ id: CloudProviderID) async throws { guard let p = provider(id) else { throw CloudError.notConnected }; try await p.testConnection() }

    // MARK: Yükleme (paylaşım)
    /// Seçili öğeleri kuyruğa alır; aynı öğe için bekleyen görev varsa yinelemez, tükenmiş eski görevin yerine yenisi geçer.
    /// `copyLinkOnFinish` false (Kestirmeler): kuyruk/bitiş tostu yok, link panoya yazılmaz; başarısızlık bildirimi yine gösterilir.
    func share(items: [ShelfItem], to id: CloudProviderID, copyLinkOnFinish: Bool = true) {
        var new: [UploadTask] = []
        for it in items where it.exists {
            if queue.tasks(for: it.id).contains(where: { $0.provider == id && !$0.exhausted }) { continue }
            queue.dropExhausted(itemID: it.id, provider: id)
            new.append(Self.shareTask(for: it, provider: id, template: prefs.cloudTemplate(for: id), access: prefs.shareAccess(for: id), silent: !copyLinkOnFinish))
        }
        queue.enqueue(contentsOf: new)
        if copyLinkOnFinish { panel?.showToast(S.cloudQueued) }
        queue.kick()
    }
    static func shareTask(for it: ShelfItem, provider id: CloudProviderID, template: String, access: LinkAccess, silent: Bool) -> UploadTask {
        UploadTask.make(for: it, provider: id, template: template, access: access, purpose: .share, silent: silent)
    }
    /// Bitişte panoya link yazılıp tost gösterilir mi: yalnız sessiz olmayan paylaşım.
    static func announcesOnFinish(_ task: UploadTask) -> Bool { task.purpose == .share && task.silent != true }
    func copyLink(_ obj: CloudObject, fileName: String) {
        guard let l = obj.link else { return }
        let pb = NSPasteboard.general; pb.clearContents(); pb.setString(linkFormat.render(l, name: fileName), forType: .string)
    }
    func changeAccess(item: ShelfItem, object: CloudObject, to access: LinkAccess) {
        guard let p = provider(object.provider) else { return }
        Task { @MainActor in
            do {
                let updated = try await p.setAccess(object, access: access)
                store.setCloud(itemID: item.id, updated, provider: object.provider)
                if var rec = history.record(provider: object.provider, remoteID: object.remoteID) { rec.object = updated; history.update(rec) }
                copyLink(updated, fileName: item.fileName); panel?.showToast(S.cloudAccessChanged)
            } catch { panel?.showNotice(S.cloudAccessChangeFailed(error.localizedDescription)) }
        }
    }
    /// Buluttan sil: Drive'da sunucu Çöp'üne taşır, S3'te nesneyi kaldırır. Yerel dosyaya dokunulmaz.
    func deleteRemote(item: ShelfItem?, object: CloudObject) {
        guard let p = provider(object.provider) else { return }
        Task { @MainActor in
            do {
                try await p.delete(object)
                if let it = item { store.setCloud(itemID: it.id, nil, provider: object.provider) }
                if let rec = history.record(provider: object.provider, remoteID: object.remoteID) { history.remove(id: rec.id) }
                onChange?()
            } catch { panel?.showNotice(S.cloudDeleteFailed(error.localizedDescription)) }
        }
    }

    // MARK: Kuyruk geri bildirimleri
    private func handleUploaded(_ task: UploadTask, _ obj: CloudObject) {
        store.setCloud(itemID: task.itemID, obj, provider: obj.provider)
        let name = (task.filePath as NSString).lastPathComponent
        history.add(UploadRecord(id: UUID(), itemID: task.itemID, fileName: name, object: obj, purpose: task.purpose, date: Date()))
        if Self.announcesOnFinish(task) {
            if obj.link != nil { copyLink(obj, fileName: name); panel?.showToast(S.cloudLinkCopied) } else { panel?.showToast(S.cloudUploadedNoLink) }
        }
        let backup = backup!
        Task { await backup.handleUploaded(task: task, object: obj) }
        Log.info("Bulut yükleme tamam: \(obj.provider.rawValue), amaç=\(task.purpose.rawValue)")
    }
    private func handleFailed(_ task: UploadTask, _ err: CloudError) {
        Log.error("Bulut yükleme hatası (\(task.provider.rawValue), deneme \(task.attempts)): \(err.logSummary)")
        let text = S.cloudFailed(err.errorDescription ?? "")
        // Dosyası kaybolan görev kuyruktan düştü: yeniden denenecek bir şey yok.
        if err == .localFileMissing { panel?.showNotice(text); return }
        if task.purpose == .share || task.exhausted { let id = task.id; panel?.showNotice(text, retry: { [weak self] in self?.queue.retryNow(id: id); self?.queue.kick() }) }
    }

    /// Küçük resim rozeti için öğe durumu: yükleniyor > bekliyor > başarısız > yüklendi.
    func badge(for item: ShelfItem) -> CloudBadge? {
        guard enabled else { return nil }
        let ts = queue.tasks(for: item.id)
        if let a = ts.first(where: { $0.id == queue.activeTaskID }) { return .uploading(a.provider) }
        if let p = ts.first(where: { !$0.exhausted && $0.attempts == 0 }) { return .pending(p.provider) }
        if let f = ts.first { return .failed(f.provider) }
        if let c = item.cloud.last { return .uploaded(c.provider) }
        return nil
    }
}

enum CloudBadge: Equatable { case pending(CloudProviderID), uploading(CloudProviderID), uploaded(CloudProviderID), failed(CloudProviderID)
    var provider: CloudProviderID { switch self { case .pending(let p), .uploading(let p), .uploaded(let p), .failed(let p): return p } }
    var axText: String { switch self { case .pending: return S.cloudBadgePending; case .uploading(let p): return S.cloudUploading(p.title); case .uploaded(let p): return S.cloudBadgeUploaded(p.title); case .failed: return S.cloudBadgeFailed } }
}
#endif
