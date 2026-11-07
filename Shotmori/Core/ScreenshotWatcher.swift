import Foundation
import CoreServices

/// FSEvents ile klasörü izler; tamamlanmış ekran görüntülerini tekilleştirerek bildirir.
final class ScreenshotWatcher {
    let folder: URL
    var onNewScreenshot: ((URL) -> Void)?
    var onRemoved: ((URL) -> Void)?
    /// İzlenen klasörün kendisi taşındı/yeniden adlandırıldı/silindi (`WatchRoot`); AppController yeniden çözer.
    var onRootChanged: (() -> Void)?

    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "dev.shotmori.watcher")
    private let queueKey = DispatchSpecificKey<Void>() // örneğe özel: yalnız bu izleyicinin kuyruğunda mıyız
    /// stop() sonrası ana kuyruğa geç ulaşan bildirimler düşer (eski klasörden `ingest` gelmez). Yalnız ana iş parçacığında okunur/yazılır.
    private var stopped = false
    private var pending: [String: DispatchWorkItem] = [:]
    private var seenPaths: [String: Date] = [:]
    private let debounce: TimeInterval = 0.15
    private let settle: TimeInterval = 0.25

    /// Kökün standart ve bağlantısı çözülmüş yolu bir kez hesaplanır (olay başına çözümleme yok; kök değişince izleyici yeniden kurulur).
    private let rootPath: String
    private let resolvedRootPath: String

    init(folder: URL) {
        self.folder = folder; rootPath = folder.standardizedFileURL.path; resolvedRootPath = folder.resolvingSymlinksInPath().path
        queue.setSpecific(key: queueKey, value: ())
    }
    /// Son bırakma kuyruğun kendisinde olabilir (boyut denetimi bloğu `self`i tutar): orada `queue.sync` kilitlenir, bu yüzden stop() çağrılmaz.
    /// Kuyruk dışındaysak uçuştaki FSEvents geri çağrısı (sahipsiz `self` işaretçisi) bitsin diye boş bir senkron geçiş yapılır.
    deinit {
        guard let s = stream else { return }
        FSEventStreamStop(s); FSEventStreamInvalidate(s); FSEventStreamRelease(s)
        if DispatchQueue.getSpecific(key: queueKey) == nil { queue.sync {} }
    }

    /// Tek kullanımlık: durdurulan izleyici yeniden başlatılmaz (AppController yenisini kurar).
    func start() {
        guard stream == nil, !stopped else { return }
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagWatchRoot)
        guard let s = FSEventStreamCreate(nil, { _, info, n, paths, eventFlags, _ in
            guard let info = info else { return }
            let me = Unmanaged<ScreenshotWatcher>.fromOpaque(info).takeUnretainedValue()
            let ps = unsafeBitCast(paths, to: NSArray.self) as! [String]
            for i in 0..<n { me.handle(path: ps[i], flags: eventFlags[i]) }
        }, &ctx, [folder.path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.05, flags) else {
            Log.error("FSEventStream oluşturulamadı"); return
        }
        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
        stream = s
        Log.info("İzleme başladı")
    }
    func stop() {
        dispatchPrecondition(condition: .notOnQueue(queue)) // kuyruğun içinden `queue.sync` kilitlenir
        stopped = true
        guard let s = stream else { return }
        FSEventStreamStop(s); FSEventStreamInvalidate(s); FSEventStreamRelease(s); stream = nil
        queue.sync { pending.values.forEach { $0.cancel() }; pending.removeAll() } // uçuştaki geri çağrılar bitsin; yalnız ana iş parçacığından çağrılır
    }

    enum Delivery { case new(URL), removed(URL), rootChanged }
    /// Ana kuyruğa tek teslim yolu: kuyruğa girdikten sonra stop() çağrılmışsa bildirim düşer.
    func deliver(_ d: Delivery) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.stopped else { return }
            switch d {
            case .new(let u): self.onNewScreenshot?(u)
            case .removed(let u): self.onRemoved?(u)
            case .rootChanged: self.onRootChanged?()
            }
        }
    }

    enum EventKind { case candidate, removed, ignore }
    /// Yalnız izlenen klasörün doğrudan alt öğesi (alt klasör ve klasörün kendisi değil).
    static func isDirectChild(_ path: String, of folder: URL) -> Bool {
        isDirectChild(path, root: folder.standardizedFileURL.path, resolvedRoot: folder.resolvingSymlinksInPath().path)
    }
    /// `root` standart kök yolu, `resolvedRoot` bağlantısı çözülmüş kök yolu; üst klasör yalnız düz eşleşme yoksa çözülür.
    static func isDirectChild(_ path: String, root: String, resolvedRoot: String) -> Bool {
        let parent = ((path as NSString).standardizingPath as NSString).deletingLastPathComponent
        return parent == root || URL(fileURLWithPath: parent).resolvingSymlinksInPath().path == resolvedRoot
    }
    /// Bayraklardan olay türü: salt metaveri → yok say; silindi/yeniden adlandı + dosya yok → kaldırıldı; silinip aynı adla geri geldi → aday.
    static func eventKind(flags: FSEventStreamEventFlags, existsNow: Bool) -> EventKind {
        func has(_ f: Int) -> Bool { flags & FSEventStreamEventFlags(f) != 0 }
        if has(kFSEventStreamEventFlagItemRemoved) { return existsNow ? .candidate : .removed }
        if has(kFSEventStreamEventFlagItemRenamed) { return existsNow ? .candidate : .removed }
        if has(kFSEventStreamEventFlagItemCreated) { return .candidate }
        return .ignore // yalnız Modified/XattrMod/InodeMetaMod/FinderInfoMod (ve bilinmeyenler)
    }

    private func handle(path: String, flags: FSEventStreamEventFlags) {
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0 { deliver(.rootChanged); return }
        // Ucuz süzgeçler önce: alt klasörlerdeki yoğun olaylarda (ör. `npm install`) ad süzgeci yol çözümlemesinden önce eler.
        guard flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsFile) != 0,
              ScreenshotFileInspector.isCandidateFileName((path as NSString).lastPathComponent),
              Self.isDirectChild(path, root: rootPath, resolvedRoot: resolvedRootPath) else { return }
        switch Self.eventKind(flags: flags, existsNow: FileManager.default.fileExists(atPath: path)) {
        case .ignore: return
        case .removed:
            pending[path]?.cancel(); pending[path] = nil
            deliver(.removed(URL(fileURLWithPath: path)))
        case .candidate:
            pending[path]?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.evaluate(path: path, attempt: 0) }
            pending[path] = work
            queue.asyncAfter(deadline: .now() + debounce, execute: work)
        }
    }

    private func evaluate(path: String, attempt: Int) {
        pending[path] = nil
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else { return }
        guard ScreenshotFileInspector.hasScreenCaptureMarker(url) else { return } // ekran görüntüsü değil
        guard ScreenshotFileInspector.isCompleteImage(url) else {
            if attempt < 6 { queue.asyncAfter(deadline: .now() + settle) { [weak self] in self?.evaluate(path: path, attempt: attempt + 1) } }
            else { Log.error("Görsel tamamlanmadı, atlandı") }
            return
        }
        // Boyut kararlılığı: kısa bekleyip tekrar oku.
        let size1 = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? -1
        queue.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            let size2 = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? -2
            guard size1 == size2 else { self.evaluate(path: path, attempt: attempt + 1); return }
            // Tekilleştirme: yol, 10 sn pencere (yeniden adlandırılan dosya yeni yolda yeniden bildirilir; öğeyi AppController yerinde tutar)
            let now = Date()
            self.seenPaths = self.seenPaths.filter { now.timeIntervalSince($0.value) < 10 }
            if self.seenPaths[path] != nil { return }
            self.seenPaths[path] = now
            self.deliver(.new(url))
        }
    }

    /// Uygulama kapalıyken gelenleri yakalamak için: klasördeki son ekran görüntüleri (en yeni önce).
    static func recentScreenshots(in folder: URL, limit: Int, newerThan: Date? = nil) -> [(url: URL, date: Date)] {
        let keys: Set<URLResourceKey> = [.creationDateKey, .isRegularFileKey, .nameKey]
        guard let items = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else { return [] }
        var dated: [(URL, Date)] = []
        for u in items {
            guard ScreenshotFileInspector.isCandidateFileName(u.lastPathComponent),
                  let rv = try? u.resourceValues(forKeys: keys), rv.isRegularFile == true, let d = rv.creationDate else { continue }
            if let n = newerThan, d <= n { continue }
            dated.append((u, d))
        }
        dated.sort { $0.1 > $1.1 }
        var out: [(URL, Date)] = []
        for (u, d) in dated where ScreenshotFileInspector.hasScreenCaptureMarker(u) {
            out.append((u, d)); if out.count >= limit { break }
        }
        return out
    }
}
