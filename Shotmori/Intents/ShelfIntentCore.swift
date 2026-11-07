import Foundation

/// Kestirmeler eylemlerinin saf çekirdeği: raf üstünde ekle / al / temizle / son görüntü. `IntentFile` ve sistem sarmalayıcıları
/// `ShelfIntents.swift`te; burası testlenebilir (bellek içi `ShelfStore`). Raf ana iş parçacığında yaşar.
@MainActor
enum ShelfIntentCore {
    static let limitRange = 1...100

    // MARK: Raf

    /// `id` nil → etkin raf; verilen kimlik yoksa `IntentError.shelfNotFound`.
    static func shelf(store: ShelfStore, id: UUID?) throws -> Shelf {
        guard let id else { return store.activeShelf }
        guard let sh = store.shelves.first(where: { $0.id == id }) else { throw IntentError.shelfNotFound }
        return sh
    }

    // MARK: Rafa ekle

    /// Kopyalamadan önceki denetim: raf var mı, en az bir ve en çok `InboundImport.maxCount` dosya mı.
    static func precheck(count: Int, shelfID: UUID?, store: ShelfStore) -> IntentError? {
        if let id = shelfID, !store.shelves.contains(where: { $0.id == id }) { return .shelfNotFound }
        if count == 0 { return .noImages }
        if count > InboundImport.maxCount { return .tooMany }
        return nil
    }

    /// Uygulamadaki giriş: izlenen klasör denetleyiciden alınır.
    static func add(urls: [URL], shelfID: UUID?, controller: AppController, completion: @escaping (Result<[ShelfItem], IntentError>) -> Void) {
        add(urls: urls, shelfID: shelfID, store: controller.store, watchedFolder: controller.folder, completion: completion)
    }

    /// Kestirme eylemleri için bekleyen biçim.
    static func add(urls: [URL], shelfID: UUID?, controller: AppController) async throws -> [ShelfItem] {
        try await withCheckedThrowingContinuation { cont in
            add(urls: urls, shelfID: shelfID, controller: controller) { cont.resume(with: $0.mapError { $0 as Error }) }
        }
    }

    /// Dosyalar tek giriş kapısından (`InboundImport`, kopya `Gelen/`e) verilen rafa (nil → etkin raf) eklenir. Panel açılmaz, bildirim yok.
    /// Döndürür: istenen dosyaların raftaki öğeleri (önce yeni kopyalar, sonra zaten raftakiler). Hiçbiri eklenemezse: yalnız boyut reddi
    /// varsa `tooLarge`, değilse `fileRejected`. Açık istek olduğu için raftan kaldırılmış görüntü yeniden eklenir (kaldırma izi aşılır).
    static func add(urls: [URL], shelfID: UUID?, store: ShelfStore, watchedFolder: URL?, into folder: URL? = nil,
                    completion: @escaping (Result<[ShelfItem], IntentError>) -> Void) {
        if let e = precheck(count: urls.count, shelfID: shelfID, store: store) { completion(.failure(e)); return }
        InboundImport.importFiles(urls, source: .intent, watchedFolder: watchedFolder, into: folder) { result in
            let urls = result.added + result.alreadyPresent
            guard !urls.isEmpty else { completion(.failure(result.oversized > 0 && result.rejected == 0 ? .tooLarge : .fileRejected)); return }
            let items = urls.map { u in
                ShelfItem(path: u.path, fileID: ScreenshotFileInspector.fileIdentifier(u), capturedAt: ScreenshotFileInspector.creationDate(u) ?? Date(),
                          source: AppController.shelfSource(for: u, watchedFolder: watchedFolder))
            }
            // Raf silinmişse (kopya sürerken) etkin rafa düşer; `add` yinelenenleri atlar, kırpma eskileri düşürür.
            let target = store.shelves.contains { $0.id == shelfID } ? shelfID : nil
            let inserted = store.add(items.sorted { $0.capturedAt < $1.capturedAt }, to: target, overrideDismissed: true)
            Log.info("Kestirme: \(inserted.count) öğe rafa eklendi, \(result.rejected) reddedildi")
            // Zaten raftakiler dahil: yol ya da dosya kimliğiyle eşleşen raf öğesi (hangi rafta olursa olsun).
            let resolved = items.compactMap { store.existingItem(matching: $0) }
            completion(.success(resolved))
        }
    }

    // MARK: Raftan al

    /// Seçilen parti. `items` yeniden eskiye. `complete`: yeni modda partide son teslimden beri gelenlerin hepsi var.
    /// `pickedAt`: seçim anı; işaret dosyalar okunduktan sonra konduğu için "şimdi" yerine bu an kullanılır (arada gelen kare yeni kalır).
    struct Pick {
        let shelfID: UUID
        let onlyNew: Bool
        let items: [ShelfItem]
        let complete: Bool
        let pickedAt: Date
        /// Okuma sırası: yeni modda eskiden yeniye (bayt bütçesi dolarsa daha yeniler sonraki çağrıya kalır), değilse yeniden eskiye.
        var readOrder: [ShelfItem] { onlyNew ? items.reversed() : items }
    }

    /// Kalıcı biçim milisaniye; bu aralıktaki iki an yeniden açılıştan sonra eşit okunabilir (teslim süzgeci katı `>`).
    nonisolated static let sameInstantTolerance: TimeInterval = 0.001
    nonisolated static func sameInstant(_ a: Date, _ b: Date) -> Bool { abs(a.timeIntervalSince(b)) < sameInstantTolerance }
    /// Sondan, dışarıda kalan `boundary` anına zincirle bağlı (her adımda son çıkarılanla karşılaştırılır) öğeleri çıkarır: x.0000,
    /// x.0004, x.0012 zincirinde x.0012 dışarıdaysa ikisi de çıkar (x.0004 tek başına x.0000'dan ayrılırsa diskte işaretle eşit okunur).
    nonisolated static func trimTrailingChain<T>(_ xs: inout [T], touching boundary: Date, addedAt: (T) -> Date) {
        var b = boundary
        while let last = xs.last, sameInstant(addedAt(last), b) { b = addedAt(xs.removeLast()) }
    }

    /// Raftaki görüntüleri seçer; teslim işaretine dokunmaz (`markDelivered`). `onlyNew`: yalnız son teslimden beri gelenler; sınırdan
    /// fazlaysa en eski yeni parti. Parti aynı anı taşıyan öğelerin ortasından bölünmez: sınıra zincirle bağlı eş zamanlı öğeler sonraki
    /// partiye kalır; parti baştan tek zincirse (toplu ekleme) zincirin hepsi verilir. Çöpe taşınmış öğeler verilmez. Raf yoksa nil.
    static func pick(store: ShelfStore, shelfID: UUID?, onlyNew: Bool, limit: Int, now: Date = Date()) -> Pick? {
        guard let sh = try? shelf(store: store, id: shelfID) else { return nil }
        let n = min(max(limit, limitRange.lowerBound), limitRange.upperBound)
        let pool = (onlyNew ? store.itemsSinceLastHandoff(shelfID: sh.id) : sh.items).filter { !$0.localTrashed }
        guard onlyNew else {
            return Pick(shelfID: sh.id, onlyNew: false, items: Array(pool.sorted { $0.addedAt > $1.addedAt }.prefix(n)), complete: false, pickedAt: now)
        }
        let sorted = pool.sorted { $0.addedAt < $1.addedAt }
        var batch = Array(sorted.prefix(n))
        if batch.count < sorted.count {
            trimTrailingChain(&batch, touching: sorted[batch.count].addedAt) { $0.addedAt }
            if batch.isEmpty {
                batch = [sorted[0]]
                for it in sorted.dropFirst() { guard sameInstant(it.addedAt, batch[batch.count - 1].addedAt) else { break }; batch.append(it) }
            }
        }
        return Pick(shelfID: sh.id, onlyNew: true, items: batch.reversed(), complete: batch.count == sorted.count, pickedAt: now)
    }

    /// Teslim işareti yalnız gerçekten verilen (okunabilen) karelere göre ilerler: hiçbiri verilmediyse değişmez (ör. harici disk çıkarılmış);
    /// verilenlerin en yenisinin anına konur, parti tamamsa ve en yeni kare de verildiyse seçim anına (sonradan gelen yeni sayılır).
    /// Okunamayıp verilen en yeni kareden eski kalanlar teslim edilmiş sayılır (tek bir an işareti küme tutmaz; sonsuz tekrar olmasın).
    /// Bütçe kesimi eş zamanlı grubu bölmez (`load`), böylece işaret de bölmez. İşaret geri gitmez: eşzamanlı iki çağrıdan geç biten
    /// (ya da arada rafı sürükleyerek teslim eden kullanıcı) verilmiş kareleri yeniden "yeni" yapmaz.
    static func markDelivered(_ delivered: [ShelfItem], of pick: Pick, store: ShelfStore) {
        guard pick.onlyNew, let sh = store.shelves.first(where: { $0.id == pick.shelfID }) else { return }
        let ids = Set(delivered.map(\.id))
        guard let newest = pick.items.filter({ ids.contains($0.id) }).max(by: { $0.addedAt < $1.addedAt }) else { return }
        let all = pick.complete && newest.id == pick.items.first?.id
        let at = all ? max(pick.pickedAt, newest.addedAt) : newest.addedAt
        if let current = sh.lastHandoffAt, at <= current { return }
        store.markHandoff(shelfID: pick.shelfID, at: at)
    }

    /// Seç ve (istenirse) hepsini verilmiş say. Döndürür: yeniden eskiye.
    static func items(store: ShelfStore, shelfID: UUID?, onlyNew: Bool, limit: Int, markHandoff: Bool) -> [ShelfItem] {
        guard let p = pick(store: store, shelfID: shelfID, onlyNew: onlyNew, limit: limit) else { return [] }
        if markHandoff { markDelivered(p.items, of: p, store: store) }
        return p.items
    }

    /// Kestirmeye verilecek toplam bayt üst sınırı: en çok 100 tam boy dosya birlikte belleğe alınmasın. İlk dosya her zaman verilir.
    nonisolated static let handoffByteBudget = 200 * 1_048_576
    /// Dosyaları sırayla okur; okunamayan atlanır, bütçe aşılacaksa durur (kalanlar verilmez, yeni modda yeni kalır). Ana aktörde değil.
    /// Kesim eş zamanlı grubun ortasına düşmez: dışarıda kalan kareye zincirle bağlı olanlar da verilmez (toplu eklenen kareler milisaniye
    /// altı aralıklı; kısmi işaret yeniden açılıştan sonra kalanları düşürürdü). Grup ilk kareden başlıyorsa kesim olduğu gibi kalır
    /// (hiç ilerlemeyip aynı kareleri her çağrıda vermesin; bu durumda kalanlar yalnız oturum içinde yeni kalır).
    nonisolated static func load(_ items: [ShelfItem], budget: Int = handoffByteBudget, read: (URL) -> Data? = { try? Data(contentsOf: $0) }) -> [(item: ShelfItem, data: Data)] {
        var out: [(item: ShelfItem, data: Data)] = [], total = 0
        var cut: Date?
        for it in items {
            let size = (try? it.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if !out.isEmpty, total + size > budget { cut = it.addedAt; break }
            guard let data = read(it.url) else { continue }
            if !out.isEmpty, total + data.count > budget { cut = it.addedAt; break }
            out.append((it, data)); total += data.count
        }
        if let cut {
            var kept = out
            trimTrailingChain(&kept, touching: cut) { $0.item.addedAt }
            if !kept.isEmpty { out = kept }
        }
        return out
    }

    // MARK: Temizle / son görüntü

    /// Rafı listeden boşaltır (dosyalar diskte kalır; aynı kare geri gelmez). `onlyIDs`: onay anında görülen öğeler; sonradan gelenler kalır.
    /// Döndürür: listeden düşen öğe sayısı.
    @discardableResult
    static func clear(store: ShelfStore, shelfID: UUID?, onlyIDs: Set<UUID>? = nil) -> Int {
        guard let sh = try? shelf(store: store, id: shelfID) else { return 0 }
        let ids = onlyIDs ?? Set(sh.items.map(\.id))
        let n = sh.items.filter { ids.contains($0.id) }.count
        guard n > 0 else { return 0 }
        store.clear(shelfID: sh.id, onlyIDs: ids)
        Log.info("Kestirme: raf temizlendi, \(n) öğe listeden düştü")
        return n
    }

    /// Tüm raflarda en son eklenen (menüdeki "Son görüntüyü kopyala" ile aynı ölçüt); Çöpe taşınmışlar sayılmaz.
    static func latest(store: ShelfStore) -> ShelfItem? {
        store.allItems.filter { !$0.localTrashed }.max { $0.addedAt < $1.addedAt }
    }
}
