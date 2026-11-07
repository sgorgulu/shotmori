import AppIntents
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Kestirmeler varlıkları: raf görüntüsü, raf ve bulut hizmeti. Sorgular `AppController.ready()` ile başlatmayı bekler; raf ana iş parçacığında okunur.

/// Raftaki bir görüntü. Görünen ad dosya adı; küçük resim 160 px PNG (tam görsel belleğe alınmaz), yalnız seçici ve tekil sonuçlarda.
struct ShotEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "entityShot")
    static let defaultQuery = ShotQuery()

    let id: UUID
    @Property(title: "entityFileName") var fileName: String
    @Property(title: "entityCapturedAt") var capturedAt: Date
    @Property(title: "entityShelf") var shelfName: String
    @Property(title: "entityNew") var isNew: Bool
    @Property(title: "entityCloudLink") var cloudLink: URL?
    /// Görünüm için; ana aktör dışında bir kez üretilir (`withThumbnails`), toplu sonuçlarda nil.
    let thumbnail: Data?

    init(id: UUID, fileName: String, capturedAt: Date, shelfName: String, isNew: Bool, cloudLink: URL?, thumbnail: Data?) {
        self.id = id; self.thumbnail = thumbnail
        self.fileName = fileName; self.capturedAt = capturedAt; self.shelfName = shelfName; self.isNew = isNew; self.cloudLink = cloudLink
    }

    var displayRepresentation: DisplayRepresentation {
        let date = capturedAt.formatted(date: .abbreviated, time: .shortened)
        let subtitle: LocalizedStringResource = isNew ? "\(S.entityNew) · \(date)" : "\(date)"
        return DisplayRepresentation(title: "\(fileName)", subtitle: subtitle, image: thumbnail.map { .init(data: $0) })
    }
}

extension ShotEntity {
    /// Raf öğesinden varlık (yalnız meta veri, ana aktörde): `isNew` öğenin rafındaki teslim işaretine göre, bulut linki son yüklemeden.
    /// Küçük resim burada üretilmez (dosya çözme ana iş parçacığını tutmasın); gerekiyorsa `withThumbnails` ile ana aktör dışında eklenir.
    @MainActor
    init(_ item: ShelfItem, store: ShelfStore) {
        let sh = store.shelf(containing: item.id)
        let isNew = sh.map { s in s.lastHandoffAt.map { item.addedAt > $0 } ?? true } ?? false
        self.init(id: item.id, fileName: item.fileName, capturedAt: item.capturedAt, shelfName: sh?.name ?? "", isNew: isNew,
                  cloudLink: item.cloud.last(where: { $0.link != nil })?.link, thumbnail: nil)
    }
    func with(thumbnail: Data?) -> ShotEntity {
        ShotEntity(id: id, fileName: fileName, capturedAt: capturedAt, shelfName: shelfName, isNew: isNew, cloudLink: cloudLink, thumbnail: thumbnail)
    }
    /// Meta veri ana aktörde toplanmış varlıklara küçük resim (çağıran ana aktörde değilken; Kestirmeler seçicisi ve tekil sonuçlar).
    static func withThumbnails(_ pairs: [(entity: ShotEntity, url: URL)]) -> [ShotEntity] {
        pairs.map { $0.entity.with(thumbnail: ShotThumbnail.png($0.url)) }
    }
}

/// Küçük resim: ImageIO ile en çok 160 px, PNG.
enum ShotThumbnail {
    static let maxPixel = 160
    static func png(_ url: URL) -> Data? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                                     kCGImageSourceCreateThumbnailWithTransform: true]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }
}

struct ShotQuery: EntityQuery {
    static let suggestedCount = 10

    /// Kimlikten çözümleme (kayıtlı kestirme parametreleri): küçük resimsiz; sayı sınırsız olabilir, dosya çözülmez.
    func entities(for identifiers: [UUID]) async throws -> [ShotEntity] {
        let c = try await AppController.ready()
        return await MainActor.run {
            let all = c.store.allItems
            return identifiers.compactMap { id in all.first { $0.id == id }.map { ShotEntity($0, store: c.store) } }
        }
    }
    /// Son eklenen 10 görüntü (tüm raflar), seçicide küçük resimle; resimler ana aktör dışında üretilir.
    func suggestedEntities() async throws -> [ShotEntity] {
        let c = try await AppController.ready()
        let pairs = await MainActor.run {
            c.store.allItems.filter { !$0.localTrashed }.sorted { $0.addedAt > $1.addedAt }.prefix(Self.suggestedCount)
                .map { (entity: ShotEntity($0, store: c.store), url: $0.url) }
        }
        return ShotEntity.withThumbnails(pairs)
    }
}

/// Raf (sekme). En çok 8; hepsi listelenir.
struct ShelfEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "entityShelf")
    static let defaultQuery = ShelfQuery()

    let id: UUID
    @Property(title: "entityShelf") var name: String
    @Property(title: "entityItemCount") var itemCount: Int

    init(id: UUID, name: String, itemCount: Int) { self.id = id; self.name = name; self.itemCount = itemCount }
    init(_ shelf: Shelf) { self.init(id: shelf.id, name: shelf.name, itemCount: shelf.items.count) }

    /// Alt başlık birimli ve çoğullu ("3 görüntü" / "3 images"), VoiceOver çıplak sayı okumasın.
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)", subtitle: "\(S.imageCount(itemCount))") }
}

struct ShelfQuery: EnumerableEntityQuery {
    func allEntities() async throws -> [ShelfEntity] {
        let c = try await AppController.ready()
        return await MainActor.run { c.store.shelves.map(ShelfEntity.init) }
    }
    func entities(for identifiers: [UUID]) async throws -> [ShelfEntity] {
        try await allEntities().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [ShelfEntity] { try await allEntities() }
}

/// Bulut hizmeti (kullanıcının kendi hesabı). Bulutsuz derlemede de tanımlı; yükleme eylemi yalnız `SHOTMORI_CLOUD` ile derlenir.
enum CloudProviderEnum: String, AppEnum {
    case drive, s3

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "paramProvider")
    static let caseDisplayRepresentations: [CloudProviderEnum: DisplayRepresentation] = [
        .drive: DisplayRepresentation(title: "Google Drive"),
        .s3: DisplayRepresentation(title: "S3"),
    ]
    var providerID: CloudProviderID { self == .drive ? .googleDrive : .s3 }
    /// Hata iletisinde görünen ad (marka; çevrilmez).
    var title: String { self == .drive ? "Google Drive" : "S3" }
}
