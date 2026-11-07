import Foundation
import CryptoKit

/// Dış giriş yolu (günlük ve test için; yol/ad taşımaz).
enum InboundSource: String { case intent, service, statusDrop, openWith, clipboard }

/// Tek giriş kapısı: Kestirmeler, Servisler, durum öğesine bırakma ve "Birlikte Aç" ile gelen dosyalar buradan girer.
/// Dış dosya yalnız olay süresince okunur; içerik `Gelen/` klasörüne kopyalanır, yol saklanmaz. Özgün dosya değişmez, taşınmaz, silinmez.
/// Aynı içerik (SHA-256) ikinci kez yazılmaz: `Gelen/index.json` (`hash → dosya adı`) mevcut kopyayı verir.
enum InboundImport {
    /// `AppPaths.applicationSupport/Gelen` (yoksa oluşturulur).
    static var folder: URL {
        let base = AppPaths.applicationSupport.appendingPathComponent("Gelen", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
    static let indexFileName = "index.json"
    /// Tekilleştirme indeksi; konteyner temizliği bunu Çöp'e taşımasın diye başvuru listesine eklenir.
    static func indexURL(in folder: URL? = nil) -> URL { (folder ?? Self.folder).appendingPathComponent(indexFileName) }
    static let maxCount = 20
    static let maxBytes = 50 * 1_048_576
    /// Veri girişinde bayt sınırı. Pano görselini uygulamanın kendisi PNG'ye çevirir (dış dosya değil): büyük fotoğraf kopyası
    /// (TIFF→PNG ≥ 50 MB) sınıra takılıp "Panoda görsel yok" diye reddedilmesin diye `.clipboard` sınırsız; dış kaynaklar `maxBytes`.
    static func byteLimit(for source: InboundSource) -> Int? { source == .clipboard ? nil : maxBytes }
    static let allowedExtensions: Set<String> = ImageFormats.extensions
    /// Kopyalama sırasındaki gizli geçici ad öneki (`.gelen-<UUID>.tmp`); çökme sonrası kalanları konteyner temizliği toplar.
    static let tempPrefix = ".gelen-"

    /// Görsel uzantısı, gizli/geçici olmayan ad ("." / "~" öneki reddedilir) ve var olan düzenli dosya.
    /// Sembolik bağlantıda ad/uzantı denetimi hem bağlantıya hem çözülmüş hedefe uygulanır; hedef düzenli dosya olmalı.
    static func accepts(_ url: URL) -> Bool {
        guard url.isFileURL, nameAccepted(url) else { return false }
        let target = url.resolvingSymlinksInPath()
        guard target.path == url.path || nameAccepted(target) else { return false }
        return isRegularFile(target)
    }
    private static func nameAccepted(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return !name.hasPrefix(".") && !name.hasPrefix("~") && allowedExtensions.contains(url.pathExtension.lowercased())
    }
    /// Bağlantı izlenmeden: yolun kendisi düzenli dosya mı (klasör, bağlantı, aygıt değil).
    private static func isRegularFile(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeRegular
    }

    /// `oversized`: görsel ama `maxBytes`'tan büyük (tür reddinden ayrı bildirilir).
    enum Outcome: Equatable { case added(URL), alreadyPresent(URL), rejected, limit, oversized }
    struct Result: Equatable {
        var added: [URL] = []
        var alreadyPresent: [URL] = []
        var rejected = 0
        var limited = 0
        var oversized = 0
        mutating func record(_ o: Outcome) {
            switch o {
            case .added(let u): added.append(u)
            case .alreadyPresent(let u): alreadyPresent.append(u)
            case .rejected: rejected += 1
            case .limit: limited += 1
            case .oversized: oversized += 1
            }
        }
    }

    /// İçe aktarmalar sırayla yürür: indeks ve ad çakışması kontrolü yarışmaz.
    private static let queue = DispatchQueue(label: "dev.shotmori.inbound", qos: .userInitiated)

    /// Kopya arka planda; tamamlanınca `completion` ana kuyrukta. `watchedFolder` ve konteyner içi dosyalar kopyalanmaz (URL olduğu gibi döner).
    /// En çok `maxCount` dosya işlenir (fazlası `limited`); `maxBytes`'tan büyük görsel `oversized`, kabul edilmeyen dosya `rejected`.
    static func importFiles(_ urls: [URL], source: InboundSource, watchedFolder: URL?, now: Date = Date(), into folder: URL? = nil, completion: @escaping (Result) -> Void) {
        queue.async {
            let dir = folder ?? Self.folder
            let container = AppPaths.applicationSupport
            var result = Result(), handled = 0
            var index = IndexFile(folder: dir)
            for u in urls {
                guard accepts(u) else { result.record(.rejected); continue }
                guard handled < maxCount else { result.record(.limit); continue }
                handled += 1
                if shortCircuit(u, watchedFolder: watchedFolder, container: container) || isInside(u, dir) { result.record(.added(u)); continue }
                result.record(copyFile(u, into: dir, now: now, index: &index))
            }
            index.saveIfChanged()
            Log.info("Gelen (\(source.rawValue)): \(result.added.count) eklendi, \(result.alreadyPresent.count) zaten var, \(result.rejected) reddedildi, \(result.limited) sınır dışı")
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Pasteboard görseli: veri `Gelen/`e (ya da `folder`a) yazılır (ad "Pano <tarih>.<uzantı>", çakışmada " (2)"); aynı veri zaten varsa mevcut kopya döner.
    /// Sonuç: `.added` yeni kopya, `.alreadyPresent` aynı veri zaten var, `.oversized` `byteLimit(for:)` üstü (pano hariç 50 MB), `.rejected` tür/yazım hatası.
    static func importDataOutcome(_ data: Data, fileExtension: String, source: InboundSource, now: Date = Date(), into folder: URL? = nil, completion: @escaping (Outcome) -> Void) {
        queue.async {
            let ext = fileExtension.lowercased()
            guard allowedExtensions.contains(ext), !data.isEmpty else {
                Log.info("Gelen (\(source.rawValue)): veri reddedildi (\(data.count) bayt)")
                DispatchQueue.main.async { completion(.rejected) }; return
            }
            if let limit = byteLimit(for: source), data.count > limit {
                Log.info("Gelen (\(source.rawValue)): veri sınırı aştı (\(data.count) bayt)")
                DispatchQueue.main.async { completion(.oversized) }; return
            }
            let dir = folder ?? Self.folder
            var index = IndexFile(folder: dir)
            let hash = SHA256.hash(data: data).hexString
            var out: URL?, existed = false
            if let existing = index.copy(for: hash) { out = existing; existed = true }
            else {
                do {
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    let base = S.clipboardFileName(ClipboardImport.fileStamp(now))
                    for _ in 0..<5 { // ad yarışında (dış yazar) yeniden dene; mevcut dosya asla ezilmez
                        let dest = uniqueDestination(for: "\(base).\(ext)", in: dir)
                        do { try data.write(to: dest, options: [.withoutOverwriting]); out = dest; break }
                        catch let e as CocoaError where e.code == .fileWriteFileExists { continue }
                    }
                    if let u = out { index.set(hash, u.lastPathComponent) }
                } catch { Log.error("Gelen: veri yazılamadı: \(Log.describe(error))") }
            }
            index.saveIfChanged()
            Log.info("Gelen (\(source.rawValue)): veri \(out == nil ? "yazılamadı" : "rafa hazır")")
            let result: Outcome = out.map { existed ? .alreadyPresent($0) : .added($0) } ?? .rejected
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Dosyanın SHA-256 özeti (küçük harf onaltılık); 1 MB parçalarla akış.
    static func sha256(of url: URL) throws -> String {
        let h = try FileHandle(forReadingFrom: url); defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try h.read(upToCount: 1_048_576), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().hexString
    }

    /// Klasörde boş ad: "ad.png", doluysa "ad (2).png", "ad (3).png"…
    static func uniqueDestination(for name: String, in folder: URL) -> URL {
        let fm = FileManager.default
        let first = folder.appendingPathComponent(name)
        if !fm.fileExists(atPath: first.path) { return first }
        let ext = (name as NSString).pathExtension, stem = (name as NSString).deletingPathExtension
        for n in 2...9_999 {
            let candidate = folder.appendingPathComponent(ext.isEmpty ? "\(stem) (\(n))" : "\(stem) (\(n)).\(ext)")
            if !fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return folder.appendingPathComponent(ext.isEmpty ? "\(stem) \(UUID().uuidString)" : "\(stem) \(UUID().uuidString).\(ext)")
    }

    /// İzlenen klasördeki ya da kendi konteynerimizdeki dosya kopyalanmaz (yol zaten erişilebilir; mükerrer kopya olmaz).
    static func shortCircuit(_ url: URL, watchedFolder: URL?, container: URL) -> Bool {
        if let w = watchedFolder, isInside(url, w) { return true }
        return isInside(url, container)
    }

    // MARK: İç

    /// Bileşen bazında kapsam: "/a/b" içinde "/a/b/c.png" var, "/a/b2/c.png" yok. Sembolik bağlantılar (`/var` ↔ `/private/var`) çözülür.
    private static func isInside(_ url: URL, _ folder: URL) -> Bool {
        let f = folder.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let u = url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        return u.count > f.count && Array(u.prefix(f.count)) == f
    }

    /// Tek dosya: bağlantı çözümü → boyut → özet → indeks → geçici gizli ada kopya → düzenli dosya doğrulaması → aynı klasörde son ada taşıma.
    /// Sembolik bağlantıda hedefin içeriği kopyalanır (bağlantı değil); boyut ve özet hedeften. Hata → `.rejected`, özgün dosyaya dokunulmaz.
    private static func copyFile(_ link: URL, into dir: URL, now: Date, index: inout IndexFile) -> Outcome {
        let fm = FileManager.default
        let src = link.resolvingSymlinksInPath()
        guard isRegularFile(src), let size = (try? fm.attributesOfItem(atPath: src.path)[.size] as? NSNumber)?.intValue else { return .rejected }
        guard size <= maxBytes else { return .oversized }
        let hash: String
        do { hash = try sha256(of: src) } catch { Log.error("Gelen: kaynak okunamadı: \(Log.describe(error))"); return .rejected }
        if let existing = index.copy(for: hash) { return .alreadyPresent(existing) }
        let tmp = dir.appendingPathComponent("\(tempPrefix)\(UUID().uuidString).tmp") // gizli: kabul süzgeci atlar; temizlik yalnız eski artıkları alır
        var moved = false
        // Son ada taşınamayan (hata, yarım kopya, ad tükenmesi) geçici kopya Gelen/'de kalmaz: Çöp'e (kalıcı silme yok).
        // `attributesOfItem` bağlantıyı izlemez: kopya bağlantıya dönüşmüşse de bağlantının kendisi taşınır.
        defer { if !moved, (try? fm.attributesOfItem(atPath: tmp.path)) != nil { try? fm.trashItem(at: tmp, resultingItemURL: nil) } }
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try fm.copyItem(at: src, to: tmp)
            // Kopya düzenli dosya değilse (yarışta değişen kaynak) yazılmaz: geçici öğe Çöp'e (defer), mtime yazımı hiç yapılmaz (bağlantı izlenip özgün dosya değişmesin).
            guard isRegularFile(tmp) else { Log.error("Gelen: kopya düzenli dosya değil"); return .rejected }
            // Kopyanın mtime'ı içe aktarma anı: konteyner temizliğinin 7 günlük saati buradan başlar (oluşturma tarihi korunur).
            try? fm.setAttributes([.modificationDate: now], ofItemAtPath: tmp.path)
            let name = link.lastPathComponent // kullanıcının bıraktığı ad (bağlantının adı)
            var dest = uniqueDestination(for: name, in: dir)
            for _ in 0..<5 {
                do { try fm.moveItem(at: tmp, to: dest); moved = true; break }
                catch let e as CocoaError where e.code == .fileWriteFileExists { dest = uniqueDestination(for: name, in: dir) }
            }
            guard moved else { Log.error("Gelen: kopya adlandırılamadı"); return .rejected }
            index.set(hash, dest.lastPathComponent)
            return .added(dest)
        } catch {
            Log.error("Gelen: kopyalanamadı: \(Log.describe(error))")
            return .rejected
        }
    }

    /// `Gelen/index.json`: `hash → dosya adı`; okunurken dosyası olmayan girdiler düşer; atomik yazım.
    private struct IndexFile {
        let folder: URL
        private(set) var map: [String: String]
        private var changed = false
        init(folder: URL) {
            self.folder = folder
            let raw = (try? Data(contentsOf: InboundImport.indexURL(in: folder))).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
            map = raw.filter { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0.value).path) }
            changed = map.count != raw.count
        }
        func copy(for hash: String) -> URL? {
            guard let name = map[hash] else { return nil }
            let u = folder.appendingPathComponent(name)
            return FileManager.default.fileExists(atPath: u.path) ? u : nil
        }
        mutating func set(_ hash: String, _ name: String) { map[hash] = name; changed = true }
        func saveIfChanged() {
            guard changed else { return }
            do {
                let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
                try enc.encode(map).write(to: InboundImport.indexURL(in: folder), options: [.atomic])
            } catch { Log.error("Gelen: indeks yazılamadı: \(Log.describe(error))") }
        }
    }
}

private extension Digest {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
