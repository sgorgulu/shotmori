#if SHOTMORI_CLOUD
import AppIntents
import AppKit

/// Görüntüleri kullanıcının kendi Google Drive / S3 hesabına yükler ve linkleri döndürür. Dosyalar önce rafa (tek giriş kapısı) girer.
/// Intent süresi 30 sn ile sınırlı: `perform()` girişinden 25 sn içinde bitmeyen yükleme sürer, link hazır olunca "Son yüklemeler"de (`uploadStillRunning`).
/// Bir deneme başarısız olursa (ya da dosya kaybolursa) beklemeden "Yükleme başarısız" (`UploadIntentError.failed`); kuyruk yeniden dener.
/// Panoya yalnız intent yazar ("Linki panoya kopyala" açıkken, tüm linkler birlikte); kuyruğun kendi pano/tost bildirimi kapalıdır.
struct UploadIntent: AppIntent {
    static let title: LocalizedStringResource = "intentUploadTitle"
    static let description = IntentDescription("intentUploadDesc")
    static let openAppWhenRun = false
    static let isDiscoverable = true
    static let waitLimit: TimeInterval = 25
    static let pollInterval: TimeInterval = 0.25

    @Parameter(title: "paramFiles", supportedTypeIdentifiers: ["public.image"])
    var files: [IntentFile]?
    @Parameter(title: "paramItems")
    var items: [ShotEntity]?
    @Parameter(title: "paramProvider", default: .drive)
    var provider: CloudProviderEnum
    @Parameter(title: "paramCopyLink", default: true)
    var copyLink: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Upload \(\.$files) to \(\.$provider)") {
            \.$items
            \.$copyLink
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<[URL]> {
        let begun = Date() // bekleme sınırı buradan: hazırlık ve kopyalama da 30 sn'lik intent süresine sayılır
        let c = try await AppController.ready()
        let pid = provider.providerID
        let connected = await MainActor.run { c.cloud.isConnected(pid) }
        guard connected else { throw IntentError.notConnected(provider.title) }

        var shelfItems: [ShelfItem] = []
        if let files, !files.isEmpty {
            let count = files.count
            let problem = await MainActor.run { ShelfIntentCore.precheck(count: count, shelfID: nil, store: c.store) }
            if let problem { throw problem }
            let staged = try IntentFileStaging.urls(for: files)
            defer { staged.stopAccess() }
            shelfItems = try await ShelfIntentCore.add(urls: staged.urls, shelfID: nil, controller: c)
        }
        if let ids = items?.map(\.id), !ids.isEmpty {
            let found = await MainActor.run { c.store.allItems.filter { ids.contains($0.id) } }
            shelfItems += found.filter { f in !shelfItems.contains { $0.id == f.id } }
        }
        shelfItems = shelfItems.filter(\.exists)
        guard !shelfItems.isEmpty else { throw IntentError.noImages }
        guard shelfItems.count <= InboundImport.maxCount else { throw IntentError.tooMany }

        let started = Date()
        let toUpload = shelfItems, ids = shelfItems.map(\.id)
        // Bu yüklemenin görevleri (yeni ya da zaten bekleyen) deneme sayılarıyla birlikte; hata, sayının artmasından anlaşılır.
        let watched: [UploadTask] = await MainActor.run {
            c.cloud.share(items: toUpload, to: pid, copyLinkOnFinish: false)
            return ids.flatMap { c.cloud.queue.tasks(for: $0) }.filter { $0.provider == pid && !$0.exhausted }
        }
        Log.info("Kestirme: \(ids.count) öğe yükleme kuyruğunda")

        // Bitiş gözlemi: her öğenin bu sağlayıcıdaki, başlangıçtan sonra yazılmış bulut kopyası (link) beklenir.
        let deadline = Self.deadline(begun: begun)
        while true {
            let (links, failed): ([URL]?, Bool) = await MainActor.run {
                let l = Self.links(for: ids, provider: pid, since: started, store: c.store)
                return (l, l == nil && Self.failed(watched, provider: pid, since: started, queue: c.cloud.queue.tasks,
                                                   activeTaskID: c.cloud.queue.activeTaskID, store: c.store))
            }
            // Deneme başarısız (kimlik, izin, ağ…) ya da dosya kayboldu: 25 sn beklemeden hata; ayrıntı ve "Yeniden dene" panel bildiriminde.
            if failed { throw UploadIntentError.failed }
            if let links {
                if copyLink, !links.isEmpty {
                    await MainActor.run {
                        let pb = NSPasteboard.general; pb.clearContents(); pb.setString(links.map(\.absoluteString).joined(separator: "\n"), forType: .string)
                    }
                }
                return .result(value: links)
            }
            guard Date() < deadline else { throw IntentError.uploadStillRunning }
            try await Task.sleep(nanoseconds: UInt64(Self.pollInterval * 1_000_000_000))
        }
    }

    /// Bekleme sınırı `perform()` girişinden `waitLimit` sn sonra (hazırlık süresi düşülür; sistem 30 sn'de keser).
    static func deadline(begun: Date) -> Date { begun.addingTimeInterval(waitLimit) }

    /// İzlenen görevlerden biri başarısız mı: deneme sayısı arttı (etkin deneme hariç) ya da görev kuyruktan link yazılmadan çıktı
    /// (yerel dosya kayboldu). Raftan düşen öğe sayılmaz. Bekleyen eski görevin önceki denemeleri hata sayılmaz.
    @MainActor
    static func failed(_ watched: [UploadTask], provider: CloudProviderID, since: Date, queue tasks: [UploadTask], activeTaskID: UUID?, store: ShelfStore) -> Bool {
        let all = store.allItems
        for w in watched {
            if let t = tasks.first(where: { $0.id == w.id }) {
                if t.attempts > w.attempts, t.id != activeTaskID { return true }
                continue
            }
            guard let it = all.first(where: { $0.id == w.itemID }) else { continue }
            if !it.cloud.contains(where: { $0.provider == provider && $0.uploadedAt >= since.addingTimeInterval(-1) }) { return true }
        }
        return false
    }

    /// Hepsi yüklendiyse linkler (öğe sırasıyla; linksiz yükleme atlanır), değilse nil. Raftan düşen öğe beklenmez.
    @MainActor
    static func links(for ids: [UUID], provider: CloudProviderID, since: Date, store: ShelfStore) -> [URL]? {
        let all = store.allItems
        var out: [URL] = []
        for id in ids {
            guard let it = all.first(where: { $0.id == id }) else { continue }
            guard let obj = it.cloud.last(where: { $0.provider == provider && $0.uploadedAt >= since.addingTimeInterval(-1) }) else { return nil }
            if let l = obj.link { out.append(l) }
        }
        return out
    }
}

/// Buluta yükle hatası. Ayrıntı (hizmet iletisi) ve "Yeniden dene" panel bildiriminde; Kestirmeler'e kısa genel ileti verilir.
enum UploadIntentError: Error, Equatable, LocalizedError, CustomLocalizedStringResourceConvertible {
    case failed
    var errorDescription: String? { S.cloudBadgeFailed }
    var localizedStringResource: LocalizedStringResource { LocalizedStringResource(stringLiteral: errorDescription ?? "") }
}
#endif
