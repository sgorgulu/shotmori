import Foundation

enum ShelfItemSource: String, Codable { case screenshot, clipboard, derivative, imported }

struct ShelfItem: Codable, Identifiable, Equatable {
    let id: UUID
    var path: String
    var fileID: String?
    var capturedAt: Date
    var addedAt: Date
    var source: ShelfItemSource
    /// Kullanıcının elle koyduğu grup ayracı: bu öğe yeni bir grubun ilk karesidir.
    var startsGroup: Bool = false
    /// Buluttaki kopyalar (sağlayıcı başına en çok bir); eski JSON'larda yok → boş.
    var cloud: [CloudObject] = []
    /// Doğrulanmış yedek sonrası kullanıcı seçimiyle yerel dosya Çöp'e taşındı; öğe rafta kalır, sürükleme linki taşır.
    var localTrashed: Bool = false
    var url: URL { URL(fileURLWithPath: path) }
    var fileName: String { url.lastPathComponent }
    var exists: Bool { FileManager.default.fileExists(atPath: path) }

    init(id: UUID = UUID(), path: String, fileID: String?, capturedAt: Date, addedAt: Date = Date(), source: ShelfItemSource = .screenshot) {
        self.id = id; self.path = path; self.fileID = fileID; self.capturedAt = capturedAt; self.addedAt = addedAt; self.source = source
    }
    private enum CodingKeys: String, CodingKey { case id, path, fileID, capturedAt, addedAt, source, startsGroup, cloud, localTrashed }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); path = try c.decode(String.self, forKey: .path); fileID = try c.decodeIfPresent(String.self, forKey: .fileID)
        capturedAt = try c.decode(Date.self, forKey: .capturedAt); addedAt = try c.decode(Date.self, forKey: .addedAt); source = try c.decode(ShelfItemSource.self, forKey: .source)
        startsGroup = try c.decodeIfPresent(Bool.self, forKey: .startsGroup) ?? false
        do { cloud = try c.decodeIfPresent([CloudObject].self, forKey: .cloud) ?? [] }
        catch { cloud = []; (decoder.userInfo[ShelfStore.decodeLossKey] as? ShelfStore.DecodeLoss)?.count += 1 } // bilinmeyen sağlayıcı → boş (özgün yedeklenir)
        localTrashed = try c.decodeIfPresent(Bool.self, forKey: .localTrashed) ?? false
    }
}

/// Adlandırılmış raf: kronolojik öğe listesi, en yeni başta; "yeni" vurgusu raf başına izlenir.
/// Ad: kullanıcının verdiği (`customName`) ya da varsayılan "Raf N" — varsayılan ad kalıcı yazılmaz, her gösterimde o anki dilde üretilir.
struct Shelf: Codable, Identifiable, Equatable {
    let id: UUID
    /// Kullanıcının verdiği ad; nil = varsayılan ad (`defaultNumber`).
    private(set) var customName: String?
    /// Varsayılan addaki numara ("Raf 2" → 2).
    private(set) var defaultNumber: Int
    var createdAt: Date
    var items: [ShelfItem] = []
    var lastHandoffAt: Date?
    /// Görünen ad: özel ad ya da o anki dilde "Raf N"/"Shelf N".
    var name: String { customName ?? S.shelfDefaultName(defaultNumber) }
    /// `name` nil → varsayılan ad (`number`).
    init(id: UUID = UUID(), name: String? = nil, number: Int = 1, createdAt: Date = Date(), items: [ShelfItem] = [], lastHandoffAt: Date? = nil) {
        self.id = id; self.customName = name; self.defaultNumber = number; self.createdAt = createdAt; self.items = items; self.lastHandoffAt = lastHandoffAt
    }
    mutating func rename(to name: String) { customName = name }

    /// Eski sürümlerin kalıcı yazdığı varsayılan ad ("Raf N" ya da "Shelf N"; `gen_strings.py` › `shelfDefaultName`): numarası, değilse nil.
    static func defaultNumber(inLegacyName name: String) -> Int? {
        for prefix in ["Raf ", "Shelf "] where name.hasPrefix(prefix) {
            let rest = name.dropFirst(prefix.count)
            if !rest.isEmpty, rest.count <= 3, rest.first != "0", rest.allSatisfy({ $0.isASCII && $0.isNumber }), let n = Int(rest) { return n }
        }
        return nil
    }

    // `name` eski sürümler için (geri dönüşte okunabilsin) o anki dilde yine yazılır; `defaultNumber` varsa ad varsayılandır.
    private enum CodingKeys: String, CodingKey { case id, name, defaultNumber, createdAt, items, lastHandoffAt }
    private struct Skip: Decodable {}
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name)
        if customName == nil { try c.encode(defaultNumber, forKey: .defaultNumber) }
        try c.encode(createdAt, forKey: .createdAt); try c.encode(items, forKey: .items)
        try c.encodeIfPresent(lastHandoffAt, forKey: .lastHandoffAt)
    }
    /// Öğeler tek tek çözülür: okunamayan (ör. gelecek sürümün bilinmeyen alanı) atlanır, raf düşmez.
    /// `defaultNumber` yoksa (eski dosya) "Raf N"/"Shelf N" adı varsayılan sayılır; dil değişince o da değişir.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); createdAt = try c.decode(Date.self, forKey: .createdAt)
        let stored = try c.decode(String.self, forKey: .name)
        if let n = try? c.decodeIfPresent(Int.self, forKey: .defaultNumber), n > 0 { customName = nil; defaultNumber = n }
        else if let n = Self.defaultNumber(inLegacyName: stored) { customName = nil; defaultNumber = n }
        else { customName = stored; defaultNumber = 1 }
        lastHandoffAt = try c.decodeIfPresent(Date.self, forKey: .lastHandoffAt)
        var list: [ShelfItem] = []; var skipped = 0
        if c.contains(.items) {
            var u = try c.nestedUnkeyedContainer(forKey: .items)
            while !u.isAtEnd {
                if let it = try? u.decode(ShelfItem.self) { list.append(it) } else { skipped += 1; _ = try? u.decode(Skip.self) }
            }
        }
        if skipped > 0 { Log.error("Raf dosyasında okunamayan \(skipped) öğe atlandı"); (decoder.userInfo[ShelfStore.decodeLossKey] as? ShelfStore.DecodeLoss)?.count += skipped }
        items = list
    }
}

/// Raflar (v2). Eski tek liste API'si (`items`, `add`, `clear`, `markHandoff`…) etkin raf üzerinde çalışır.
/// Diskteki dosyalara dokunmaz; yalnızca liste tutar.
final class ShelfStore {
    struct State: Codable {
        var version: Int = 2
        var shelves: [Shelf]
        var activeShelfID: UUID
        /// Kaldırılan/kırpılan karelerin izi (en yeni `maxDismissed`); eski JSON'larda yok → boş.
        var dismissed: [DismissedKey] = []
        init(shelves: [Shelf], activeShelfID: UUID, dismissed: [DismissedKey] = []) { self.shelves = shelves; self.activeShelfID = activeShelfID; self.dismissed = dismissed }
        private enum CodingKeys: String, CodingKey { case version, shelves, activeShelfID, dismissed }
        private struct Skip: Decodable {}
        /// İz anahtarları tek tek çözülür (`Shelf` gibi): okunamayan (ör. bozuk tarih) atlanır, kalanlar korunur; kayıp sayılır, özgün yedeklenir.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 2
            shelves = try c.decode([Shelf].self, forKey: .shelves); activeShelfID = try c.decode(UUID.self, forKey: .activeShelfID)
            var keys: [DismissedKey] = []; var skipped = 0
            if c.contains(.dismissed), !((try? c.decodeNil(forKey: .dismissed)) ?? true) {
                if var u = try? c.nestedUnkeyedContainer(forKey: .dismissed) {
                    while !u.isAtEnd {
                        if let k = try? u.decode(DismissedKey.self) { keys.append(k) } else { skipped += 1; _ = try? u.decode(Skip.self) }
                    }
                } else { skipped += 1 } // dizi değil: iz boş başlar
            }
            if skipped > 0 { Log.error("Raf dosyasında okunamayan \(skipped) kaldırma izi atlandı"); (decoder.userInfo[ShelfStore.decodeLossKey] as? ShelfStore.DecodeLoss)?.count += skipped }
            dismissed = keys
        }
    }
    /// v1 şeması: tek liste.
    private struct StateV1: Codable { var items: [ShelfItem]; var lastHandoffAt: Date? }

    static let maxShelves = 8
    static let maxNameLength = 24
    static let maxDismissed = 500
    static let v1BackupName = "shelf-v1.bak.json"
    /// Okunamayan raf dosyası silinmez/ezilmez; bu önekle (`shelf.corrupt-<yyyyMMdd-HHmmss>.json`) yanına alınır.
    static let corruptBackupPrefix = "shelf.corrupt-"

    /// Yazım: ISO 8601 + kesirli saniye (alt saniye "yeni" vurgusunu korur). Okuma: kesirli ve eski kesirsiz biçim.
    static let dateEncoder: JSONEncoder.DateEncodingStrategy = .custom { d, enc in
        var c = enc.singleValueContainer(); try c.encode(isoFractional.string(from: d))
    }
    static let dateDecoder: JSONDecoder.DateDecodingStrategy = .custom { dec in
        let str = try dec.singleValueContainer().decode(String.self)
        if let d = isoFractional.date(from: str) ?? isoPlain.date(from: str) { return d }
        throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "Geçersiz tarih"))
    }
    // Biçimleyici üretimi pahalı (~0,18 ms); tek örnek paylaşılır (format/parse iş parçacığı güvenli).
    private static let isoFractional: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
    private static let isoPlain = ISO8601DateFormatter()
    /// Çözme sırasında kaybolan veriyi sayar (`decoder.userInfo`); sayı > 0 ise özgün dosya yedeklenir.
    final class DecodeLoss { var count = 0 }
    static let decodeLossKey = CodingUserInfoKey(rawValue: "shotmori.decodeLoss")!

    private(set) var state: State
    var maxItems: Int
    let fileURL: URL?
    /// Değişiklik dinleyicileri: ana panel, ayrılmış paneller ve AppController rozeti hepsi dinler (`addObserver` / `removeObserver`).
    private var observers: [UUID: () -> Void] = [:]
    /// v1'den yüklendiyse ilk kalıcı yazımdan önce yedeklenecek ham veri.
    private var pendingV1Backup: Data?
    /// Okunamayan dosya kenara alınamadıysa (tek kopya) kaydetme kapalı: ezmektense kaydetmemek yeğdir.
    private var persistBlocked = false
    /// Bu açılışta raf eksik yüklendi (dosya okunamadı/kenara alındı, öğe atlandı, kaydetme kapandı): kurtarılacak başvurular bellekte yok.
    private(set) var loadWasDegraded = false

    var shelves: [Shelf] { state.shelves }
    var activeShelfID: UUID { state.activeShelfID }
    var activeIndex: Int { state.shelves.firstIndex { $0.id == state.activeShelfID } ?? 0 }
    var activeShelf: Shelf { state.shelves[activeIndex] }
    /// Etkin rafın öğeleri.
    var items: [ShelfItem] { activeShelf.items }
    /// Tüm raflar, raf sırası → öğe sırası.
    var allItems: [ShelfItem] { state.shelves.flatMap(\.items) }

    init(fileURL: URL?, maxItems: Int) {
        self.fileURL = fileURL; self.maxItems = maxItems
        state = Self.emptyState()
        load()
    }
    static func defaultFileURL() -> URL {
        let base = AppPaths.applicationSupport
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("shelf.json")
    }
    static func defaultName(index: Int) -> String { S.shelfDefaultName(index) }
    /// Varsayılan ad için kullanılmayan en küçük numara (1'den başlar): "Raf 2" kapatılıp yeni raf açılınca ikinci "Raf 3" oluşmaz.
    static func nextDefaultNumber(existingNames: [String]) -> Int {
        let used = Set(existingNames); var n = 1
        while used.contains(defaultName(index: n)) { n += 1 }
        return n
    }
    private static func emptyState() -> State { let sh = Shelf(number: 1); return State(shelves: [sh], activeShelfID: sh.id) }
    /// v1 (`{"items":…,"lastHandoffAt":…}`) → tek raf "Raf 1". Şema uymuyorsa nil.
    static func migrateV1(_ data: Data) -> State? {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = dateDecoder
        guard let v1 = try? dec.decode(StateV1.self, from: data) else { return nil }
        let sh = Shelf(number: 1, items: v1.items, lastHandoffAt: v1.lastHandoffAt)
        return State(shelves: [sh], activeShelfID: sh.id)
    }

    // MARK: Gözlemciler
    /// Her değişiklikte çağrılır; döndürülen anahtarla `removeObserver` yapılır (paneller kapanırken).
    @discardableResult
    func addObserver(_ f: @escaping () -> Void) -> UUID { let t = UUID(); observers[t] = f; return t }
    func removeObserver(_ token: UUID) { observers[token] = nil }
    private func notify() { for f in observers.values { f() } }

    // MARK: Raflar
    func setActiveShelf(id: UUID) {
        guard state.shelves.contains(where: { $0.id == id }), id != state.activeShelfID else { return }
        state.activeShelfID = id; persist(); notify()
    }
    /// Yeni raf; sınır aşıldıysa nil. Ad verilmezse "Raf N" (kullanılmayan en küçük N; kapatılan rafın numarası yeniden kullanılır).
    @discardableResult
    func addShelf(name: String? = nil) -> Shelf? {
        guard state.shelves.count < Self.maxShelves else { return nil }
        let sh = Shelf(name: name.flatMap(Self.trimmedName), number: Self.nextDefaultNumber(existingNames: state.shelves.map(\.name)))
        state.shelves.append(sh); persist(); notify()
        return sh
    }
    func renameShelf(id: UUID, to name: String) {
        guard let i = state.shelves.firstIndex(where: { $0.id == id }), let t = Self.trimmedName(name), t != state.shelves[i].name else { return }
        state.shelves[i].rename(to: t); persist(); notify()
    }
    /// Rafı kapatır: son raf kapatılamaz. `target` verilirse öğeler oraya taşınır (hedefin başına); verilmezse listeden düşer; dosyalara dokunulmaz.
    /// `droppingOnly`: yalnız bu kimlikler düşer (onay dialoğu açıldığı andaki öğeler); sonradan gelenler komşu rafa taşınır, kaybolmaz.
    /// Etkin raf kapanıyorsa etkinlik komşuya (önceki, yoksa sonraki) geçer.
    /// Döndürür: hedef raf `maxItems`'ı aştığı için düşen (en eski) öğe sayısı; çağıran kullanıcıya bildirir.
    @discardableResult
    func removeShelf(id: UUID, movingItemsTo target: UUID?, droppingOnly snapshot: Set<UUID>? = nil) -> Int {
        guard state.shelves.count > 1, let i = state.shelves.firstIndex(where: { $0.id == id }) else { return 0 }
        let neighbor = i == 0 ? 1 : i - 1
        var survivors = state.shelves[i].items
        if target == nil, let snap = snapshot { dismiss(survivors.filter { snap.contains($0.id) }); survivors.removeAll { snap.contains($0.id) } }
        else if target == nil { dismiss(survivors); survivors.removeAll() }
        let ti = target.flatMap { t in t == id ? nil : state.shelves.firstIndex { $0.id == t } } ?? neighbor
        var trimmed = 0
        if !survivors.isEmpty { state.shelves[ti].items.insert(contentsOf: survivors, at: 0); trimmed = trim(shelfIndex: ti) }
        state.shelves.remove(at: i)
        if state.activeShelfID == id { state.activeShelfID = state.shelves[max(i - 1, 0)].id }
        persist(); notify()
        return trimmed
    }
    /// Öğeleri başka rafa taşır: hedefin başına, göreli sıra (raf sırası → öğe sırası) korunur. Hedefteki öğeler atlanır.
    /// Döndürür: hedef `maxItems`'ı aştığı için düşen (en eski) öğe sayısı.
    @discardableResult
    func move(ids: Set<UUID>, to shelfID: UUID) -> Int {
        guard let ti = state.shelves.firstIndex(where: { $0.id == shelfID }) else { return 0 }
        var moving: [ShelfItem] = []
        for si in state.shelves.indices where si != ti {
            let picked = state.shelves[si].items.filter { ids.contains($0.id) }
            if picked.isEmpty { continue }
            moving.append(contentsOf: picked); state.shelves[si].items.removeAll { ids.contains($0.id) }
        }
        guard !moving.isEmpty else { return 0 }
        state.shelves[ti].items.insert(contentsOf: moving, at: 0); let trimmed = trim(shelfIndex: ti)
        persist(); notify()
        return trimmed
    }
    func shelf(containing itemID: UUID) -> Shelf? { index(ofItem: itemID).map { state.shelves[$0.0] } }
    /// Tüm raflardaki "yeni" (son aktarımdan sonra eklenen) öğe sayısı.
    var newCountAll: Int { state.shelves.reduce(0) { $0 + itemsSinceLastHandoff(shelfID: $1.id).count } }
    private static func trimmedName(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : String(t.prefix(maxNameLength))
    }

    // MARK: Değişiklikler (etkin raf / tüm raflar)
    /// Verilen rafın dizini; nil ya da bulunamayan kimlik → etkin raf.
    private func shelfIndex(_ id: UUID?) -> Int { id.flatMap { id in state.shelves.firstIndex { $0.id == id } } ?? activeIndex }
    /// Aynı kare herhangi bir rafta var mı: aynı yol ya da aynı dosya kimliği (yeniden adlandırılmış/taşınmış dosya). Ekleme bu kuralla tekilleştirir.
    func existingItem(matching item: ShelfItem) -> ShelfItem? { allItems.first { Self.isSameFile($0, item) } }
    static func isSameFile(_ a: ShelfItem, _ b: ShelfItem) -> Bool { a.path == b.path || (a.fileID != nil && a.fileID == b.fileID) }
    private func index(ofItem id: UUID) -> (Int, Int)? {
        for (si, sh) in state.shelves.enumerated() { if let ii = sh.items.firstIndex(where: { $0.id == id }) { return (si, ii) } }
        return nil
    }
    /// Aynı yol veya aynı dosya kimliği herhangi bir rafta varsa eklemez; döndürür: eklendi mi. Hedef verilmezse etkin raf.
    /// `overrideDismissed`: kullanıcının açık içe aktarması (bırakma, Servis, Birlikte Aç, Kestirme) kaldırma izini aşar.
    @discardableResult
    func add(_ item: ShelfItem, to shelfID: UUID? = nil, overrideDismissed: Bool = false) -> Bool { !add([item], to: shelfID, overrideDismissed: overrideDismissed).isEmpty }
    /// Toplu ekleme: tek `persist()` + tek `notify()`. Yinelenenler (yol/dosya kimliği; parti içi dahil) atlanır; döndürür: eklenenler.
    /// Kaldırılmış kare (`dismissed`) izleyici/yakalama yolunda geri gelmez; `overrideDismissed` true ise eşleşen iz silinir ve kare eklenir.
    @discardableResult
    func add(_ items: [ShelfItem], to shelfID: UUID? = nil, overrideDismissed: Bool = false) -> [ShelfItem] {
        let si = shelfIndex(shelfID)
        var added: [ShelfItem] = []
        for item in items {
            if existingItem(matching: item) != nil { continue }
            if state.dismissed.contains(where: { $0.matches(item) }) {
                guard overrideDismissed else { continue } // kullanıcı kaldırdı: aynı kare kendiliğinden geri gelmez
                state.dismissed.removeAll { $0.matches(item) }
            }
            state.shelves[si].items.insert(item, at: 0); added.append(item)
        }
        guard !added.isEmpty else { return [] }
        trim(shelfIndex: si)
        persist(); notify()
        let kept = Set(state.shelves[si].items.map(\.id))
        return added.filter { kept.contains($0.id) } // kırpmanın düşürdükleri eklenmiş sayılmaz
    }
    /// Kullanıcının kaldırması (✕/⌫, Çöp'e taşı eylemi): kare izlenir, aynı yol+tarihle geri gelmez.
    func remove(ids: Set<UUID>) { drop(ids: ids, dismissing: true) }
    /// Dışarıda silinme (Finder'da Çöp, taşıma; izleyicinin `scheduleRemoval`'ı): öğe düşer ama izlenmez,
    /// dosya geri gelirse (Çöp › Geri koy, geri taşıma) yeniden eklenir.
    func remove(path: String) { let ids = Set(allItems.filter { $0.path == path }.map(\.id)); if !ids.isEmpty { drop(ids: ids, dismissing: false) } }
    private func drop(ids: Set<UUID>, dismissing: Bool) {
        if dismissing { dismiss(allItems.filter { ids.contains($0.id) }) }
        for i in state.shelves.indices { state.shelves[i].items.removeAll { ids.contains($0.id) } }
        persist(); notify()
    }
    func clear(shelfID: UUID? = nil) {
        let si = shelfIndex(shelfID)
        dismiss(state.shelves[si].items)
        state.shelves[si].items.removeAll(); persist(); notify()
    }
    /// Yalnız verilen kimlikleri düşürür (onay dialoğu açıldığındaki öğeler); sonradan gelenler kalır.
    func clear(shelfID: UUID?, onlyIDs: Set<UUID>) {
        let si = shelfIndex(shelfID)
        let before = state.shelves[si].items.count
        dismiss(state.shelves[si].items.filter { onlyIDs.contains($0.id) })
        state.shelves[si].items.removeAll { onlyIDs.contains($0.id) }
        if state.shelves[si].items.count != before { persist(); notify() }
    }
    func markHandoff(shelfID: UUID? = nil, at date: Date = Date()) {
        let si = shelfIndex(shelfID)
        state.shelves[si].lastHandoffAt = date; persist(); notify()
    }
    /// Bulut kopyasını kaydeder (aynı sağlayıcıdaki eskisinin yerine). Dosyaya dokunmaz. Öğe hangi rafta olursa olsun bulunur.
    func setCloud(itemID: UUID, _ object: CloudObject?, provider: CloudProviderID) {
        guard let (si, ii) = index(ofItem: itemID) else { return }
        state.shelves[si].items[ii].cloud.removeAll { $0.provider == provider }
        if let o = object { state.shelves[si].items[ii].cloud.append(o) }
        persist(); notify()
    }
    /// Yerel dosya kullanıcı seçimiyle Çöp'e taşındı; öğe rafta kalır.
    func markLocalTrashed(itemID: UUID) {
        guard let (si, ii) = index(ofItem: itemID) else { return }
        state.shelves[si].items[ii].localTrashed = true; persist(); notify()
    }
    /// Dosya aynı klasörde yeniden adlandırıldı: öğe rafında, sırasında ve grubunda yerinde kalır; yalnız yol değişir.
    func updatePath(itemID: UUID, to path: String) {
        guard let (si, ii) = index(ofItem: itemID), state.shelves[si].items[ii].path != path else { return }
        state.shelves[si].items[ii].path = path; persist(); notify()
    }
    func startGroup(at id: UUID) {
        guard let (si, ii) = index(ofItem: id) else { return }
        state.shelves[si].items[ii].startsGroup.toggle(); persist(); notify()
    }
    /// Diskten silinmiş dosyaları tüm raflardan düşürür; yalnız klasör kapsamı açık (`isCovered`) öğeler. Döndürür: düşürülen sayısı.
    @discardableResult
    func pruneMissing(isCovered: (ShelfItem) -> Bool) -> Int {
        let before = allItems.count
        for i in state.shelves.indices { state.shelves[i].items.removeAll { isCovered($0) && !$0.exists && !$0.localTrashed } } // buluta taşınmış öğeler rafta kalır
        let dropped = before - allItems.count
        if dropped > 0 { persist(); notify() }
        return dropped
    }
    /// Sandbox'a ilk geçişte `Türevler/` ve `Pano/` konteynere taşınır: bu kökün altındaki yollar yenisine bağlanır.
    /// Eşleşme dizin sınırında (`kök/`); ekran görüntüsü yolları değişmez. Döndürür: değişen öğe sayısı.
    @discardableResult
    func rebasePaths(from oldRoot: String, to newRoot: String) -> Int {
        guard oldRoot != newRoot else { return 0 }
        let prefix = oldRoot.hasSuffix("/") ? oldRoot : oldRoot + "/"
        let target = newRoot.hasSuffix("/") ? newRoot : newRoot + "/"
        var changed = 0
        for si in state.shelves.indices { for ii in state.shelves[si].items.indices where state.shelves[si].items[ii].path.hasPrefix(prefix) {
            state.shelves[si].items[ii].path = target + state.shelves[si].items[ii].path.dropFirst(prefix.count); changed += 1
        } }
        if changed > 0 { persist(); notify() }
        return changed
    }
    /// Son aktarımdan beri eklenenler ("yeni" vurgusu); raf verilmezse etkin raf.
    func itemsSinceLastHandoff(shelfID: UUID? = nil) -> [ShelfItem] {
        let sh = shelfID.flatMap { id in state.shelves.first { $0.id == id } } ?? activeShelf
        guard let h = sh.lastHandoffAt else { return sh.items }
        return sh.items.filter { $0.addedAt > h }
    }
    func setMaxItems(_ n: Int) { maxItems = n; for i in state.shelves.indices { trim(shelfIndex: i) }; persist(); notify() }
    /// Sınır `n` yapılırsa tüm raflardan listeden düşecek toplam öğe (yalnız hesap; Ayarlar onayı için).
    func droppedCount(ifMaxItems n: Int) -> Int { state.shelves.reduce(0) { $0 + max($1.items.count - n, 0) } }

    /// Rafı `maxItems`'a kırpar (en eskiler düşer); döndürür: düşen sayısı.
    @discardableResult
    private func trim(shelfIndex i: Int) -> Int {
        let over = state.shelves[i].items.count - maxItems
        guard over > 0 else { return 0 }
        dismiss(Array(state.shelves[i].items.suffix(over)))
        state.shelves[i].items.removeLast(over); return over
    }
    /// Düşen kareleri izler (en yeni `maxDismissed` tutulur); kaydetmeyi çağıran yapar.
    private func dismiss(_ items: [ShelfItem]) {
        guard !items.isEmpty else { return }
        state.dismissed.append(contentsOf: items.reversed().map(DismissedKey.init)) // raf listesi yeni→eski; eskiden yeniye eklenir, kırpma en eskileri atar
        if state.dismissed.count > Self.maxDismissed { state.dismissed.removeFirst(state.dismissed.count - Self.maxDismissed) }
    }

    // MARK: Kalıcılık (JSON, atomik yazım)
    private func load() {
        guard let u = fileURL else { return }
        let data: Data
        do { data = try Data(contentsOf: u) } catch {
            if (error as? CocoaError)?.code == .fileReadNoSuchFile || (error as NSError).code == NSFileNoSuchFileError { return } // dosya yok: ilk açılış
            Log.error("Raf dosyası okunamadı: \(Log.describe(error))")
            setAsideCorruptFile(u); return // okunamayan dosya yok sayılıp ezilmez
        }
        let loss = DecodeLoss()
        let dec = JSONDecoder(); dec.dateDecodingStrategy = Self.dateDecoder; dec.userInfo[Self.decodeLossKey] = loss
        if let s = try? dec.decode(State.self, from: data), !s.shelves.isEmpty {
            state = s
            if loss.count > 0 { copyAside(data, in: u) } // atlanan öğeler: eski sürüme dönülürse kaybolmasın
        } else if let s = Self.migrateV1(data) {
            state = s; pendingV1Backup = data
            Log.info("Raf dosyası v1'den v2'ye taşındı (\(s.shelves[0].items.count) öğe)")
        } else {
            // İki şema da çözülemedi: dosya ezilmesin, yanına alınsın (yalnız kendi konteyner dosyamız); boş durumla devam.
            loadWasDegraded = true
            if !data.isEmpty { setAsideCorruptFile(u) }
            return
        }
        if !state.shelves.contains(where: { $0.id == state.activeShelfID }) { state.activeShelfID = state.shelves[0].id }
        for i in state.shelves.indices { trim(shelfIndex: i) }
        if pendingV1Backup != nil { persist() } // göç hemen diske iner: önce v1 yedeği, sonra v2 dosyası
    }
    private func corruptBackupURL(in u: URL) -> URL {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyyMMdd-HHmmss"
        let dir = u.deletingLastPathComponent(); let stamp = f.string(from: Date())
        var dest = dir.appendingPathComponent("\(Self.corruptBackupPrefix)\(stamp).json"); var n = 2
        while FileManager.default.fileExists(atPath: dest.path) { dest = dir.appendingPathComponent("\(Self.corruptBackupPrefix)\(stamp)-\(n).json"); n += 1 }
        return dest
    }
    /// Okunamayan dosyayı yeniden adlandırır; olmazsa kaydetme kapanır (tek kopya ezilmez).
    private func setAsideCorruptFile(_ u: URL) {
        loadWasDegraded = true
        do { try FileManager.default.moveItem(at: u, to: corruptBackupURL(in: u)); Log.error("Okunamayan raf dosyası yedeğe alındı, boş durumla başlandı") }
        catch { persistBlocked = true; Log.error("Okunamayan raf dosyası yedeğe alınamadı, kaydetme kapatıldı: \(Log.describe(error))") }
    }
    /// Kısmen okunan dosyanın özgün baytlarını yedekler; olmazsa kaydetme kapanır.
    /// Aynı baytlar zaten bir `shelf.corrupt-*` yedeğindeyse yeniden yazılmaz (dosya değişene dek her açılış kısmi yükler; özgün başına tek yedek).
    private func copyAside(_ data: Data, in u: URL) {
        loadWasDegraded = true
        if Self.hasIdenticalBackup(of: data, in: u.deletingLastPathComponent()) { return }
        do { try data.write(to: corruptBackupURL(in: u), options: .atomic); Log.error("Raf dosyasında okunamayan veri var, özgün dosya yedeğe alındı") }
        catch { persistBlocked = true; Log.error("Raf dosyası yedeği yazılamadı, kaydetme kapatıldı: \(Log.describe(error))") }
    }
    private static func hasIdenticalBackup(of data: Data, in dir: URL) -> Bool {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return false }
        for n in names where n.hasPrefix(corruptBackupPrefix) {
            let f = dir.appendingPathComponent(n)
            guard let size = (try? FileManager.default.attributesOfItem(atPath: f.path))?[.size] as? NSNumber, size.intValue == data.count else { continue }
            if (try? Data(contentsOf: f)) == data { return true }
        }
        return false
    }
    /// Konteyner temizliğinin dokunmaması gereken yollar: raftaki öğeler + kenara alınmış raf yedeklerindeki `"path"` değerleri
    /// (geri yükleme / eski sürüme dönüşte başvurular canlı dosyayı göstersin). Eksik yükleme ya da okunamayan yedek → nil (temizlik yapılmaz).
    func janitorReferences() -> Set<String>? {
        guard !loadWasDegraded, !persistBlocked else { return nil }
        var refs = Set(allItems.map(\.path))
        guard let u = fileURL else { return refs }
        let dir = u.deletingLastPathComponent()
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return nil }
        for n in names where n.hasPrefix(Self.corruptBackupPrefix) {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(n)), let paths = Self.backupPaths(in: data) else { return nil }
            refs.formUnion(paths)
        }
        return refs
    }
    /// Yedekteki tüm `"path": "…"` dizgeleri; JSON kesik/bozuk olsa da tam yazılmış olanlar bulunur. UTF-8 değilse nil.
    static func backupPaths(in data: Data) -> Set<String>? {
        guard let text = String(data: data, encoding: .utf8), let re = try? NSRegularExpression(pattern: #""path"\s*:\s*"((?:[^"\\]|\\.)*)""#) else { return nil }
        var out = Set<String>()
        for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let r = Range(m.range(at: 1), in: text), let v = try? JSONDecoder().decode(String.self, from: Data("\"\(text[r])\"".utf8)) else { continue }
            out.insert(v)
        }
        return out
    }
    private func persist() {
        guard let u = fileURL, !persistBlocked else { return }
        if let raw = pendingV1Backup {
            // Yedek yazılamadıysa v1 dosyası ezilmez; bir sonraki yazımda yeniden denenir (günlüğe yol yazılmaz).
            let bak = u.deletingLastPathComponent().appendingPathComponent(Self.v1BackupName)
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: bak.path, isDirectory: &isDir)
            if !exists { do { try raw.write(to: bak, options: .atomic) } catch { Log.error("v1 raf yedeği yazılamadı: \(Log.describe(error))"); return } }
            else if isDir.boolValue { Log.error("v1 raf yedeği yazılamadı: yol bir dizin"); return }
            pendingV1Backup = nil
        }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = Self.dateEncoder; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        do { try enc.encode(state).write(to: u, options: .atomic) } catch { Log.error("Raf kaydedilemedi: \(Log.describe(error))") }
    }
}
