#if SHOTMORI_CLOUD // Bulut kodu SHOTMORI_CLOUD bayrağıyla derlenir (Debug ve Release 1.0'da açık, bkz. Features.swift); bayrak kaldırılırsa derlenmez.
import Foundation
import Network

/// Kuyruktaki bir yükleme görevi; diske yazılır, uygulama yeniden başlayınca kalır.
struct UploadTask: Codable, Identifiable, Equatable {
    let id: UUID
    let itemID: UUID
    /// Konteyner göçünde yeniden bağlanabilir (`UploadQueue.rebasePaths`).
    var filePath: String
    let provider: CloudProviderID
    let remotePath: String
    let access: LinkAccess
    let purpose: UploadPurpose
    /// Görev alındığı andaki dosya boyutu ve değişim zamanı; teslimde dosyanın değişmediğini kanıtlar.
    let fileSize: Int
    let fileModified: Date
    var attempts: Int = 0
    var nextAttemptAt: Date
    /// Sessiz paylaşım (Kestirmeler › Buluta yükle): bitince link panoya yazılmaz, tost yok; panoyu intent kendisi yönetir.
    /// İsteğe bağlı: eski kuyruk dosyalarında alan yok (nil = sessiz değil).
    var silent: Bool?
    var exhausted: Bool { attempts >= UploadQueue.maxAttempts }
    init(id: UUID = UUID(), itemID: UUID, filePath: String, provider: CloudProviderID, remotePath: String, access: LinkAccess, purpose: UploadPurpose,
         silent: Bool = false, now: Date = Date()) {
        self.id = id; self.itemID = itemID; self.filePath = filePath; self.provider = provider; self.remotePath = remotePath; self.access = access; self.purpose = purpose
        self.silent = silent ? true : nil
        let attrs = try? FileManager.default.attributesOfItem(atPath: filePath)
        fileSize = attrs?[.size] as? Int ?? 0; fileModified = attrs?[.modificationDate] as? Date ?? now; nextAttemptAt = now
    }
    /// Raf öğesinden görev: uzak yol şablondan, çekim tarihine göre (paylaşım ve yedek aynı kurulumu kullanır).
    static func make(for item: ShelfItem, provider: CloudProviderID, template: String, access: LinkAccess, purpose: UploadPurpose, silent: Bool = false) -> UploadTask {
        let remote = PathTemplate.render(template, fileName: item.fileName, date: item.capturedAt)
        return UploadTask(itemID: item.id, filePath: item.path, provider: provider, remotePath: remote, access: access, purpose: purpose, silent: silent)
    }
}

/// Seri yükleme kuyruğu: kalıcı, çevrimdışıyken bekler, hatada üstel geri çekilme (30 s → 1 dk → 5 dk → 30 dk).
/// Görevler başarısız denemelerde silinmez; `maxAttempts` sonrası kullanıcı "Yeniden dene"ye basana kadar beklemede kalır.
/// Durum (`tasks`, `activeTaskID`) yalnız ana iş parçacığında değişir; ağ işi sağlayıcıların izolasyonsuz async metotlarında yürür.
final class UploadQueue {
    static let maxAttempts = 5
    enum Outcome: Equatable { case uploaded(UploadTask, CloudObject), failed(UploadTask, CloudError), skippedOffline, idle }

    private let file: JSONFile<[UploadTask]>
    private let providers: (CloudProviderID) -> CloudProvider?
    private let isOnline: () -> Bool
    private let now: () -> Date
    private(set) var tasks: [UploadTask] = []
    private(set) var activeTaskID: UUID?
    var onChange: (() -> Void)?
    var onUploaded: ((UploadTask, CloudObject) -> Void)?
    var onFailed: ((UploadTask, CloudError) -> Void)?
    private var timer: Timer?
    private var monitor: NWPathMonitor?
    private var running = false

    init(fileURL: URL?, providers: @escaping (CloudProviderID) -> CloudProvider?, isOnline: @escaping () -> Bool, now: @escaping () -> Date = Date.init) {
        file = JSONFile(url: fileURL); self.providers = providers; self.isOnline = isOnline; self.now = now
        tasks = file.load() ?? []
    }
    static func backoff(attempt: Int) -> TimeInterval { [30, 60, 300, 1800][min(max(attempt - 1, 0), 3)] }

    func enqueue(_ t: UploadTask) { enqueue(contentsOf: [t]) }
    /// Toplu ekleme: kuyruk bir kez yazılır, `onChange` bir kez yayınlanır.
    func enqueue(contentsOf new: [UploadTask]) {
        guard !new.isEmpty else { return }
        tasks.append(contentsOf: new); persist(); onChange?()
    }
    /// Aynı öğe + sağlayıcı için tükenmiş görevleri atar (yeni paylaşım ya da başarılı yükleme sonrası eski "başarısız" rozeti kalmasın).
    func dropExhausted(itemID: UUID, provider: CloudProviderID) {
        let before = tasks.count
        tasks.removeAll { $0.itemID == itemID && $0.provider == provider && $0.exhausted }
        if tasks.count != before { persist(); onChange?() }
    }
    func retryNow(id: UUID) { guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }; tasks[i].attempts = 0; tasks[i].nextAttemptAt = now(); persist(); onChange?() }
    func tasks(for itemID: UUID) -> [UploadTask] { tasks.filter { $0.itemID == itemID } }
    var pendingCount: Int { tasks.filter { !$0.exhausted }.count }

    /// Sıradaki uygun görevi işler. Testlerde doğrudan çağrılır; üretimde `start()` döngüsü çağırır.
    /// Ana aktörde: `tasks`/`activeTaskID` yalnız ana iş parçacığında değişir (enqueue, share, rozet de orada).
    /// Ağ işi sağlayıcının izolasyonsuz async metodunda yürür; `await` süresince ana iş parçacığı serbesttir.
    @MainActor
    func processNext() async -> Outcome {
        guard isOnline() else { return .skippedOffline }
        let t0 = now()
        guard let idx = tasks.firstIndex(where: { !$0.exhausted && $0.nextAttemptAt <= t0 }) else { return .idle }
        let task = tasks[idx]
        guard let provider = providers(task.provider), provider.isConnected else { return fail(task, .notConnected) }
        let file = URL(fileURLWithPath: task.filePath)
        // Yerel dosya yok (kullanıcı sildi/taşıdı): görev atılır, kullanıcıya "Yeniden dene"siz bildirilir; döngü sıradakine geçer.
        guard FileManager.default.fileExists(atPath: task.filePath) else { return dropMissing(task) }
        activeTaskID = task.id; onChange?()
        defer { activeTaskID = nil }
        do {
            // Paylaşımda EXIF/GPS üst verisi atılır; yedek orijinal baytlarla gider (doğrulama yerel dosyayla eşleşmeli).
            let obj = try await provider.upload(file: file, remotePath: task.remotePath, access: task.access, stripMetadata: task.purpose == .share, progress: { _ in })
            // Başarı: aynı öğe + sağlayıcının tükenmiş eski görevleri de gider (rozet "başarısız"da kalmasın).
            tasks.removeAll { $0.id == task.id || ($0.itemID == task.itemID && $0.provider == task.provider && $0.exhausted) }; persist(); onChange?()
            onUploaded?(task, obj)
            return .uploaded(task, obj)
        } catch CloudError.localFileMissing {
            // Dosya ön kontrolle okuma arasında kayboldu: ön kontroldeki yol izlenir (bildirim "Yeniden dene"siz, görev kuyrukta kalmaz).
            return dropMissing(task)
        } catch let e as CloudError {
            return fail(task, e)
        } catch {
            return fail(task, .network(error.localizedDescription))
        }
    }
    /// Yerel dosyası olmayan görevi atar ve bildirir. `CloudCenter.handleFailed` bu hatada "Yeniden dene" göstermez; tutarlılık için
    /// `.localFileMissing` yalnız bu yoldan (görev kuyruktan çıkmışken) yayınlanır.
    private func dropMissing(_ task: UploadTask) -> Outcome {
        tasks.removeAll { $0.id == task.id }; persist(); onChange?()
        onFailed?(task, .localFileMissing)
        return .failed(task, .localFileMissing)
    }
    private func fail(_ task: UploadTask, _ e: CloudError) -> Outcome {
        guard let i = tasks.firstIndex(where: { $0.id == task.id }) else { return .failed(task, e) }
        tasks[i].attempts += 1
        tasks[i].nextAttemptAt = now().addingTimeInterval(Self.backoff(attempt: tasks[i].attempts))
        persist(); onChange?(); onFailed?(tasks[i], e)
        return .failed(tasks[i], e)
    }

    // MARK: Döngü
    /// Kuyruk boşken ya da yalnız tükenmiş görev varken zamanlayıcı ve ağ izleyicisi yoktur. Bekleyen görev varsa tek seferlik
    /// zamanlayıcı en erken `nextAttemptAt` anına kurulur (toleranslı) ve ağ değişimi izlenir. `kick` her turdan sonra yeniden planlar.
    func start() {
        guard !running else { return }; running = true
        kick()
    }
    private var working = false
    func kick() {
        guard running, !working else { return }
        working = true
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            var guardCount = 0, offline = false
            while guardCount < 50 {
                let r = await self.processNext(); guardCount += 1
                if case .uploaded = r { continue }
                if case .failed(_, .localFileMissing) = r { continue } // görev atıldı; sıradaki beklemesin
                offline = r == .skippedOffline
                break
            }
            self.working = false
            self.reschedule(offline: offline)
        }
    }
    /// Sıradaki uyanma gecikmesi: bekleyen görev yoksa nil. Vadesi geçmiş görevde en az 1 sn (sıkı döngü yok);
    /// çevrimdışıyken en az 60 sn (bağlantı gelince ağ izleyicisi zaten uyandırır).
    static func nextWake(tasks: [UploadTask], now: Date, offline: Bool = false) -> TimeInterval? {
        guard let next = tasks.filter({ !$0.exhausted }).map(\.nextAttemptAt).min() else { return nil }
        return max(next.timeIntervalSince(now), offline ? 60 : 1)
    }
    var isWakeScheduled: Bool { timer != nil }
    var isWatchingNetwork: Bool { monitor != nil }
    var isProcessing: Bool { working }
    deinit { timer?.invalidate(); monitor?.cancel() }
    private func reschedule(offline: Bool = false) {
        timer?.invalidate(); timer = nil
        guard running, let delay = Self.nextWake(tasks: tasks, now: now(), offline: offline) else { stopMonitor(); return }
        startMonitor()
        let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in self?.kick() }
        t.tolerance = min(max(delay * 0.1, 1), 60)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
    private func startMonitor() {
        guard monitor == nil else { return }
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] path in guard path.status == .satisfied else { return }; DispatchQueue.main.async { self?.kick() } }
        m.start(queue: DispatchQueue(label: "dev.shotmori.upload.net")); monitor = m
    }
    private func stopMonitor() { monitor?.cancel(); monitor = nil }

    // MARK: Kalıcılık
    /// Sandbox'a ilk geçiş: Shotmori'nin kendi klasöründeki (Türevler/Pano) görev yolları konteynere bağlanır. Döndürür: değişen sayı.
    @discardableResult
    func rebasePaths(from oldRoot: String, to newRoot: String) -> Int {
        guard oldRoot != newRoot else { return 0 }
        let prefix = oldRoot.hasSuffix("/") ? oldRoot : oldRoot + "/", target = newRoot.hasSuffix("/") ? newRoot : newRoot + "/"
        var n = 0
        for i in tasks.indices where tasks[i].filePath.hasPrefix(prefix) { tasks[i].filePath = target + tasks[i].filePath.dropFirst(prefix.count); n += 1 }
        if n > 0 { persist(); onChange?() }
        return n
    }
    private func persist() { file.save(tasks) }
}

/// Yükleme geçmişi: "Son yüklemeler" menüsü için; en yeni başta, en çok 200 kayıt.
struct UploadRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let itemID: UUID?
    let fileName: String
    var object: CloudObject
    let purpose: UploadPurpose
    let date: Date
}
final class UploadHistoryStore {
    static let maxRecords = 200
    private let file: JSONFile<[UploadRecord]>
    private(set) var records: [UploadRecord] = []
    init(fileURL: URL?) { file = JSONFile(url: fileURL); records = file.load() ?? [] }
    func add(_ r: UploadRecord) { records.insert(r, at: 0); if records.count > Self.maxRecords { records.removeLast(records.count - Self.maxRecords) }; persist() }
    func update(_ r: UploadRecord) { if let i = records.firstIndex(where: { $0.id == r.id }) { records[i] = r; persist() } }
    func remove(id: UUID) { records.removeAll { $0.id == id }; persist() }
    func record(provider: CloudProviderID, remoteID: String) -> UploadRecord? { records.first { $0.object.provider == provider && $0.object.remoteID == remoteID } }
    private func persist() { file.save(records) }
}

/// Bulut durum dosyaları için ortak JSON kalıcılığı: ISO 8601 tarih, sıralı anahtar, atomik yazım. `url` nil → bellekte (testler).
struct JSONFile<Value: Codable> {
    let url: URL?
    func load() -> Value? {
        guard let u = url, let d = try? Data(contentsOf: u) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(Value.self, from: d)
    }
    func save(_ value: Value) {
        guard let u = url else { return }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.sortedKeys]
        try? enc.encode(value).write(to: u, options: .atomic)
    }
}
#endif
