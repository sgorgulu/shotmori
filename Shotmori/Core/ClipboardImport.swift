import AppKit

/// "Panodan Ekle": pano görselini Shotmori'nin kendi `Pano/` klasörüne PNG olarak yazar; dosya ömrü bize aittir.
/// Bu tür yalnız panoyu okur ve PNG'ye çevirir; yazım dış veri girişiyle aynı yoldan (`InboundImport.importDataOutcome`) geçer:
/// aynı görsel ikinci kez yazılmaz (SHA-256 indeksi, mevcut kopya döner) ve çakışmasız ad ("Pano <tarih> (2).png") ortak.
/// 50 MB sınırı panoya uygulanmaz (`InboundImport.byteLimit(for:)`): veri dış dosya değil, PNG'yi uygulama üretir.
enum ClipboardImport {
    static var folder: URL {
        let base = AppPaths.applicationSupport.appendingPathComponent("Pano", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
    /// Pano verisi ana kuyrukta okunur; PNG dönüşümü ve yazım arka planda. `completion` ana kuyrukta: yeni ya da zaten var olan kopya; görsel yoksa
    /// ya da yazılamazsa nil.
    static func importImage(from pb: NSPasteboard = .general, now: Date = Date(), into folder: URL? = nil, completion: @escaping (URL?) -> Void) {
        importImageOutcome(from: pb, now: now, into: folder) { o in
            switch o { case .added(let u), .alreadyPresent(let u): completion(u); default: completion(nil) }
        }
    }
    /// `importImage` sonucu türüyle; panoda görsel yoksa `.rejected`.
    static func importImageOutcome(from pb: NSPasteboard = .general, now: Date = Date(), into folder: URL? = nil, completion: @escaping (InboundImport.Outcome) -> Void) {
        let png = pb.data(forType: .png)
        let tiff = png == nil ? pb.data(forType: .tiff) : nil
        // Yalnız nesne ana kuyrukta okunur; tam çözünürlüklü tiffRepresentation dönüşümü arka planda (UI donmasın).
        let image = png == nil && tiff == nil ? (pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage])?.first : nil
        guard png != nil || tiff != nil || image != nil else { completion(.rejected); return }
        DispatchQueue.global(qos: .userInitiated).async {
            var data = png
            if data == nil, let t = tiff ?? image?.tiffRepresentation, let rep = NSBitmapImageRep(data: t) { data = rep.representation(using: .png, properties: [:]) }
            guard let data else { DispatchQueue.main.async { completion(.rejected) }; return }
            InboundImport.importDataOutcome(data, fileExtension: "png", source: .clipboard, now: now, into: folder ?? Self.folder, completion: completion)
        }
    }
    /// Pano kopyasının raf öğesi (menü "Panodan ekle", Kestirmeler, Denetim Merkezi aynı kurulumu kullanır).
    static func shelfItem(for url: URL, now: Date = Date()) -> ShelfItem {
        ShelfItem(path: url.path, fileID: ScreenshotFileInspector.fileIdentifier(url), capturedAt: now, source: .clipboard)
    }
    /// Dosya adı damgası: sistem takvimi (Budist, Japon…) ve yerel rakamlar yılı/rakamları değiştirmesin; saat dilimi yerel.
    static let fileStampFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.calendar = Calendar(identifier: .gregorian); f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"; return f
    }()
    static func fileStamp(_ date: Date) -> String { fileStampFormatter.string(from: date) }
}
