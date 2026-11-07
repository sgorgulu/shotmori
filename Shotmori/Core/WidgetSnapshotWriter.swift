import AppKit
import ImageIO
import UniformTypeIdentifiers
import WidgetKit

/// Rafın widget'a giden küçük anlık görüntüsü: grup konteynerine `widget-snapshot.json` + sabit adlı en çok 3 küçük resim
/// (`thumb-0.png` … `thumb-2.png`, 160 px PNG). Dosyalar atomik olarak üzerine yazılır; hiçbir dosya silinmez — boşalan yuvanın
/// (3'ten az kare ya da küçük resmi üretilemeyen kaynak) dosyası 1×1 saydam PNG ile ezilir, kaldırılan karenin küçük resmi kalmaz.
/// Dosya adı, OCR/metin ya da tam çözünürlük görsel yazılmaz. Widget zaman çizelgesi yalnız bir şey gerçekten değiştiyse yenilenir.
/// İş parçacığı: `scheduleWrite`/`writeNow` ana iş parçacığından çağrılır (raf okunur); küçük resim + yazım arka kuyrukta.
final class WidgetSnapshotWriter {
    private weak var store: ShelfStore?
    let container: URL?
    private let debounce: TimeInterval
    private let reload: () -> Void
    /// Ana uygulamanın dil tercihi (nil = sistem); anlık görüntüye yazılır.
    private let language: () -> String?
    private let io = DispatchQueue(label: "dev.shotmori.widget-snapshot", qos: .utility)
    private var pending: DispatchWorkItem?
    /// Tamamlanan yazım geçişi sayısı (değişmeyen anlık görüntü dahil). Yalnız ana iş parçacığı.
    private(set) var writeCount = 0
    /// Zamanlanmış her yazım geçişinden sonra ana iş parçacığında (test kancası).
    var onWrite: (() -> Void)?
    // `io` kuyruğu durumu: son yazılan JSON ve her thumb yuvasının kaynağı (yol|değişiklik zamanı|boyut).
    private var lastJSON: Data?
    private var thumbKeys: [String?] = Array(repeating: nil, count: WidgetSnapshot.maxItems)

    /// `container` nil ise (grup entitlement'ı yok) yazıcı hiçbir şey yapmaz. Raf zayıf tutulur (gözlemci döngüsü yok).
    init(store: ShelfStore, container: URL?, debounce: TimeInterval = 0.5, language: @escaping () -> String? = { nil },
         reload: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() }) {
        self.store = store; self.container = container; self.debounce = debounce; self.language = language; self.reload = reload
    }

    /// Yalıtılmış (test/QA) veri kökü verilirse `<kök>/WidgetGroup` — gerçek widget bunu görmez; yoksa sistem grup konteyneri.
    static func containerURL(isolatedRoot: URL?) -> URL? { WidgetSnapshot.containerURL(isolated: isolatedRoot) }
    /// `SHOTMORI_DATA_DIR` kökü (yalnız Debug yalıtımında): `AppPaths.logs` = `<kök>/Logs`.
    static var isolatedRoot: URL? { AppPaths.isIsolated ? AppPaths.logs.deletingLastPathComponent() : nil }

    /// Widget'ta gösterilecek kareler: tüm raflardan eklenme zamanına göre en yeni 3 (yerelde çöpe atılanlar küçük resim veremez).
    static func recentItems(store: ShelfStore) -> [ShelfItem] {
        let sorted = store.allItems.filter { !$0.localTrashed }.sorted {
            $0.addedAt != $1.addedAt ? $0.addedAt > $1.addedAt : $0.capturedAt > $1.capturedAt
        }
        return Array(sorted.prefix(WidgetSnapshot.maxItems))
    }

    /// Saf anlık görüntü: sayılar + en yeni 3 kare; thumb adları yuva sırasıyla (`thumb-i.png`). Küçük resim üretilemezse yazım sırasında nil'lenir.
    /// Dosya adı yazılmaz (widget kullanmıyor; grup konteynerinde kişisel ad kalmasın): alan eski JSON uyumu için boş.
    static func build(store: ShelfStore, language: String? = nil) -> WidgetSnapshot {
        let items = recentItems(store: store).enumerated().map { i, it in
            WidgetSnapshot.Item(id: it.id, fileName: "", capturedAt: it.capturedAt, thumb: WidgetSnapshot.thumbName(i))
        }
        return WidgetSnapshot(version: WidgetSnapshot.version, totalCount: store.allItems.count, newCount: store.newCountAll, items: items, language: language)
    }

    /// ImageIO küçük resmi (en uzun kenar ≤ `maxPixel`, yön düzeltilmiş), PNG. Tam görsel belleğe alınmaz.
    static func thumbnailPNG(for url: URL, maxPixel: Int = 160) -> Data? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceShouldCacheImmediately: false,
                                     kCGImageSourceThumbnailMaxPixelSize: maxPixel]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    /// Raf değişti: `debounce` süresi içindeki istekler tek yazıma iner (sondaki istekten sonra).
    func scheduleWrite() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.fire() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: work)
    }

    /// Hemen, eşzamanlı yazım (ana iş parçacığı). Değişiklik varsa widget yenilenir.
    func writeNow() throws {
        guard let store, container != nil else { return }
        let snap = Self.build(store: store, language: language()), sources = Self.recentItems(store: store).map(\.path)
        let changed = try io.sync { try self.write(snap, sources: sources) }
        writeCount += 1
        if changed { reload() }
    }

    private func fire() {
        pending = nil
        guard let store, container != nil else { return }
        let snap = Self.build(store: store, language: language()), sources = Self.recentItems(store: store).map(\.path)
        io.async { [weak self] in
            guard let self else { return }
            let result = Result { try self.write(snap, sources: sources) }
            DispatchQueue.main.async {
                self.writeCount += 1
                switch result {
                case .success(let changed): if changed { self.reload() }
                case .failure(let e): Log.error("Widget anlık görüntüsü yazılamadı: \(Log.describe(e))")
                }
                self.onWrite?()
            }
        }
    }

    /// `io` kuyruğunda: değişen thumb yuvalarını ve (farklıysa) JSON'u atomik yazar. Bir şey yazıldıysa true.
    private func write(_ snapshot: WidgetSnapshot, sources: [String]) throws -> Bool {
        guard let container else { return false }
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        var snap = snapshot, changed = false
        for i in 0..<WidgetSnapshot.maxItems {
            let slot = container.appendingPathComponent(WidgetSnapshot.thumbName(i))
            // Boş yuva: eski küçük resim saydam PNG ile ezilir (silme yok); JSON anmadığı için widget yenilemesi gerekmez.
            let blank = { if self.thumbKeys[i] != Self.blankKey { try Self.blankPNG.write(to: slot, options: .atomic); self.thumbKeys[i] = Self.blankKey } }
            guard i < sources.count else { try blank(); continue }
            let url = URL(fileURLWithPath: sources[i])
            let key = Self.thumbKey(url)
            if let key, key == thumbKeys[i] { continue }
            guard key != nil, let data = Self.thumbnailPNG(for: url) else { snap.items[i].thumb = nil; try blank(); continue }
            try data.write(to: slot, options: .atomic)
            thumbKeys[i] = key; changed = true
        }
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let json = try enc.encode(snap)
        if json != lastJSON {
            try json.write(to: container.appendingPathComponent(WidgetSnapshot.fileName), options: .atomic)
            lastJSON = json; changed = true
        }
        return changed
    }

    /// Boşaltılmış yuvanın kimliği (`thumbKeys`): saydam PNG bir kez yazılır.
    private static let blankKey = "-"
    /// 1×1 tamamen saydam PNG (boşalan yuvanın yerine).
    static let blankPNG: Data = {
        let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        let out = NSMutableData()
        if let img = ctx?.makeImage(), let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, img, nil); _ = CGImageDestinationFinalize(dest)
        }
        return out as Data
    }()

    /// Thumb yuvasının kaynak kimliği: yol + değişiklik zamanı + boyut (yerinde düzenlenen dosya yeniden küçültülür). Dosya yoksa nil.
    private static func thumbKey(_ url: URL) -> String? {
        guard let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]), let size = v.fileSize else { return nil }
        return "\(url.path)|\(v.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0)|\(size)"
    }
}
