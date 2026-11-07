import AppIntents
import AppKit
import UniformTypeIdentifiers

// Kestirmeler/Spotlight eylemleri. Hepsi ana uygulama sürecinde çalışır; `AppController.ready()` başlatmayı bekler (10 sn → `notReady`).
// İş mantığı `ShelfIntentCore`te; burada yalnız `IntentFile` ↔ dosya dönüşümü ve sonuç biçimi. Günlüğe yol/ad yazılmaz.

/// Görüntüleri rafa ekler: dosyalar `Gelen/`e kopyalanır, özgün dosyaya dokunulmaz. Panel açılmaz.
struct AddToShelfIntent: AppIntent {
    static let title: LocalizedStringResource = "intentAddTitle"
    static let description = IntentDescription("intentAddDesc")
    static let openAppWhenRun = false
    static let isDiscoverable = true

    @Parameter(title: "paramFiles", supportedTypeIdentifiers: ["public.image"])
    var files: [IntentFile]
    @Parameter(title: "paramShelf")
    var shelf: ShelfEntity?

    static var parameterSummary: some ParameterSummary { Summary("Add \(\.$files) to \(\.$shelf)") }

    func perform() async throws -> some IntentResult & ReturnsValue<[ShotEntity]> {
        let c = try await AppController.ready()
        let count = files.count, shelfID = shelf?.id
        let problem = await MainActor.run { ShelfIntentCore.precheck(count: count, shelfID: shelfID, store: c.store) }
        if let problem { throw problem }
        let staged = try IntentFileStaging.urls(for: files)
        defer { staged.stopAccess() }
        let items = try await ShelfIntentCore.add(urls: staged.urls, shelfID: shelfID, controller: c)
        // Toplu sonuç (en çok 20): küçük resimsiz, dosyalar yeniden çözülmez.
        let entities = await MainActor.run { items.map { ShotEntity($0, store: c.store) } }
        return .result(value: entities)
    }
}

/// Raftaki görüntüleri dosya olarak verir (özgün veri ve ad). "Yalnız yeni olanlar" açıkken verilenler teslim edilmiş sayılır.
struct GetShelfItemsIntent: AppIntent {
    static let title: LocalizedStringResource = "intentGetTitle"
    static let description = IntentDescription("intentGetDesc")
    static let openAppWhenRun = false
    static let isDiscoverable = true

    @Parameter(title: "paramShelf")
    var shelf: ShelfEntity?
    @Parameter(title: "paramOnlyNew", default: false)
    var onlyNew: Bool
    @Parameter(title: "paramLimit", default: 10, inclusiveRange: (1, 100))
    var limit: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Get \(\.$limit) images from \(\.$shelf)") { \.$onlyNew }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> {
        .result(value: try await Self.files(shelfID: shelf?.id, onlyNew: onlyNew, limit: limit))
    }

    static func files(shelfID: UUID?, onlyNew: Bool, limit: Int) async throws -> [IntentFile] {
        let c = try await AppController.ready()
        let pick: ShelfIntentCore.Pick? = try await MainActor.run {
            _ = try ShelfIntentCore.shelf(store: c.store, id: shelfID)
            return ShelfIntentCore.pick(store: c.store, shelfID: shelfID, onlyNew: onlyNew, limit: limit)
        }
        guard let pick else { return [] }
        // Okuma ana aktör dışında. Okunamayan (dışarıda silinmiş, disk çıkarılmış) kare atlanır; bayt bütçesi dolunca durur.
        let loaded = ShelfIntentCore.load(pick.readOrder)
        // Teslim işareti yalnız verilen karelere göre (hiçbiri okunamadıysa değişmez).
        await MainActor.run { ShelfIntentCore.markDelivered(loaded.map(\.item), of: pick, store: c.store) }
        let files = loaded.sorted { $0.item.addedAt > $1.item.addedAt }.map {
            IntentFile(data: $0.data, filename: $0.item.fileName, type: UTType(filenameExtension: $0.item.url.pathExtension) ?? .image)
        }
        Log.info("Kestirme: \(files.count)/\(pick.items.count) görüntü verildi")
        return files
    }
}

/// "Yeni görüntüleri al": `GetShelfItemsIntent` "Yalnız yeni olanlar" açık. App Shortcut ön ayarlı parametreyi meta veriye taşımadığı
/// için ayrı eylem (App Shortcut eylemi görünür olmak zorunda).
struct GetNewShelfItemsIntent: AppIntent {
    static let title: LocalizedStringResource = "intentGetNewTitle"
    static let description = IntentDescription("intentGetNewDesc")
    static let openAppWhenRun = false
    static let isDiscoverable = true

    @Parameter(title: "paramShelf")
    var shelf: ShelfEntity?
    @Parameter(title: "paramLimit", default: 10, inclusiveRange: (1, 100))
    var limit: Int

    static var parameterSummary: some ParameterSummary { Summary("Get \(\.$limit) new images from \(\.$shelf)") }

    func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> {
        .result(value: try await GetShelfItemsIntent.files(shelfID: shelf?.id, onlyNew: true, limit: limit))
    }
}

/// Panodaki görseli PNG olarak etkin rafa ekler.
struct AddClipboardIntent: AppIntent {
    static let title: LocalizedStringResource = "intentClipboardTitle"
    static let description = IntentDescription("intentClipboardDesc")
    static let openAppWhenRun = false
    static let isDiscoverable = true

    static var parameterSummary: some ParameterSummary { Summary("intentClipboardTitle") }

    func perform() async throws -> some IntentResult & ReturnsValue<ShotEntity> {
        let c = try await AppController.ready()
        let url: URL? = await withCheckedContinuation { cont in
            DispatchQueue.main.async { ClipboardImport.importImage { cont.resume(returning: $0) } }
        }
        guard let url else { throw IntentError.clipboardEmpty }
        let found: (entity: ShotEntity, url: URL)? = await MainActor.run {
            let item = ClipboardImport.shelfItem(for: url)
            c.store.add(item)
            // Aynı görsel zaten raftaysa (yol/dosya kimliği) raftaki öğe döner.
            return c.store.existingItem(matching: item).map { (ShotEntity($0, store: c.store), $0.url) }
        }
        guard let found else { throw IntentError.clipboardEmpty }
        return .result(value: ShotEntity.withThumbnails([found])[0])
    }
}

/// Raftaki en yeni görüntüyü panoya kopyalar (menüdeki "Son görüntüyü kopyala" ile aynı). Teslim işaretine dokunmaz.
struct CopyLatestIntent: AppIntent {
    static let title: LocalizedStringResource = "intentCopyLatestTitle"
    static let description = IntentDescription("intentCopyLatestDesc")
    static let openAppWhenRun = false
    static let isDiscoverable = true

    static var parameterSummary: some ParameterSummary { Summary("intentCopyLatestTitle") }

    func perform() async throws -> some IntentResult & ReturnsValue<ShotEntity> {
        let c = try await AppController.ready()
        let found: (entity: ShotEntity, url: URL)? = await MainActor.run {
            guard let item = ShelfIntentCore.latest(store: c.store) else { return nil }
            c.shelf.run("copy-image", items: [item], anchor: nil)
            return (ShotEntity(item, store: c.store), item.url)
        }
        guard let found else { throw IntentError.noImages }
        return .result(value: ShotEntity.withThumbnails([found])[0])
    }
}

/// Rafı gösterir (uygulamayı öne getirir); raf verilirse önce o raf etkinleşir.
struct ShowShelfIntent: AppIntent {
    static let title: LocalizedStringResource = "intentShowTitle"
    static let openAppWhenRun = true
    static let isDiscoverable = true

    @Parameter(title: "paramShelf")
    var shelf: ShelfEntity?

    static var parameterSummary: some ParameterSummary { Summary("Show \(\.$shelf)") }

    func perform() async throws -> some IntentResult {
        let c = try await AppController.ready()
        try await MainActor.run {
            if let id = shelf?.id { _ = try ShelfIntentCore.shelf(store: c.store, id: id); c.shelf.activateShelf(id) }
            c.shelf.show(takeKey: true)
        }
        return .result()
    }
}

/// Rafı gizler.
struct HideShelfIntent: AppIntent {
    static let title: LocalizedStringResource = "intentHideTitle"
    static let openAppWhenRun = false
    static let isDiscoverable = true

    static var parameterSummary: some ParameterSummary { Summary("intentHideTitle") }

    func perform() async throws -> some IntentResult {
        let c = try await AppController.ready()
        await MainActor.run { c.shelf.hide(reason: "kestirme") }
        return .result()
    }
}

/// Rafı listeden boşaltır; dosyalar diskte kalır. Kestirmeler onay ister; yalnız onay anında görülen öğeler düşer.
struct ClearShelfIntent: AppIntent {
    static let title: LocalizedStringResource = "intentClearTitle"
    static let description = IntentDescription("intentClearDesc")
    static let openAppWhenRun = false
    static let isDiscoverable = true

    @Parameter(title: "paramShelf")
    var shelf: ShelfEntity?

    static var parameterSummary: some ParameterSummary { Summary("Clear \(\.$shelf)") }

    func perform() async throws -> some IntentResult {
        let c = try await AppController.ready()
        let target: Shelf = try await MainActor.run { try ShelfIntentCore.shelf(store: c.store, id: shelf?.id) }
        let ids = Set(target.items.map(\.id))
        guard !ids.isEmpty else { return .result() }
        let dialog = IntentDialog(LocalizedStringResource(stringLiteral: S.intentClearConfirm(target.name, ids.count)))
        if #available(macOS 15, *) { try await requestConfirmation(dialog: dialog) } else { try await (self as LegacyConfirmation).confirmLegacy(dialog) }
        await MainActor.run { _ = ShelfIntentCore.clear(store: c.store, shelfID: target.id, onlyIDs: ids) }
        return .result()
    }
}

/// macOS 14: onay diyaloğu yalnız eski (kullanımdan kalkmış) API ile verilir; protokol üzerinden çağrı uyarıyı bu tek yere sınırlar.
private protocol LegacyConfirmation { func confirmLegacy(_ dialog: IntentDialog) async throws }
extension ClearShelfIntent: LegacyConfirmation {
    @available(*, deprecated, message: "yalnız macOS 14; 15+ requestConfirmation(dialog:)")
    func confirmLegacy(_ dialog: IntentDialog) async throws { try await requestConfirmation(result: .result(dialog: dialog)) }
}

/// `IntentFile` → okunabilir dosya URL'leri. Dosya URL'si varsa güvenlik kapsamı olay süresince açılır; yalnız veri gelirse
/// geçici klasöre özgün adla yazılır (oradan `Gelen/`e kopyalanır). Yol saklanmaz. Sınır (`InboundImport.maxBytes`) üstü veri geçici
/// klasöre hiç yazılmaz; hepsi sınır üstüyse `tooLarge`. Geçici kopyalar silinmez (kalıcı silme yok; sandbox geçici klasörünü sistem temizler).
struct IntentFileStaging {
    let urls: [URL]
    private let scoped: [URL]

    static func urls(for files: [IntentFile], maxBytes: Int = InboundImport.maxBytes,
                     stageRoot: URL = FileManager.default.temporaryDirectory) throws -> IntentFileStaging {
        var urls: [URL] = [], scoped: [URL] = [], oversized = 0
        var stageDir: URL?
        do {
            for f in files {
                if let u = f.fileURL {
                    if u.startAccessingSecurityScopedResource() { scoped.append(u) }
                    urls.append(u); continue
                }
                guard f.data.count <= maxBytes else { oversized += 1; continue }
                let dir = try stageDir ?? {
                    let d = stageRoot.appendingPathComponent("Kestirme-\(UUID().uuidString)", isDirectory: true)
                    try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); return d
                }()
                stageDir = dir
                let dest = InboundImport.uniqueDestination(for: stagedName(filename: f.filename, typeExtension: f.type?.preferredFilenameExtension), in: dir)
                try f.data.write(to: dest, options: [.withoutOverwriting])
                urls.append(dest)
            }
        } catch {
            // Yarıda kalan hazırlık: açılan kapsamlar kapatılır (çağıranın `stopAccess`'i kurulmadı).
            for u in scoped { u.stopAccessingSecurityScopedResource() }
            throw error
        }
        if urls.isEmpty, oversized > 0 { throw IntentError.tooLarge }
        return IntentFileStaging(urls: urls, scoped: scoped)
    }
    /// Veri öğesinin geçici adı: yalnız son yol bileşeni; boş, gizli (".") ya da "~" ile başlayan ad "Kestirme"; uzantısız ada türün uzantısı
    /// (yoksa özgün adın uzantısı) eklenir.
    static func stagedName(filename: String, typeExtension: String?) -> String {
        let ext = typeExtension ?? (filename as NSString).pathExtension
        var name = (filename as NSString).lastPathComponent
        if name.isEmpty || name.hasPrefix(".") || name.hasPrefix("~") { name = "Kestirme" }
        if (name as NSString).pathExtension.isEmpty, !ext.isEmpty { name += ".\(ext)" }
        return name
    }
    func stopAccess() { for u in scoped { u.stopAccessingSecurityScopedResource() } }
}
