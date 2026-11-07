import Foundation

/// Farklı Kaydet / çıktı yazımı için dosya güvenliği (G):
/// - Kaynak ile hedef aynı dosyaysa (aynı yol, normalize/sembolik bağ yolu veya aynı dosya kimliği) asla silinmez/üstüne yazılmaz.
/// - Var olan hedef yalnızca başarılı yazım sonrasında, sistemin değiştirme dizinindeki geçici dosya + `replaceItemAt` ile değiştirilir;
///   hata olursa eski veri kalır. Geçici dosya hedefin yanına yazılmaz: sandbox'ta Farklı kaydet izni yalnız seçilen dosyayı kapsar.
enum SafeFileCopy {
    enum Failure: LocalizedError, Equatable {
        case sameFile
        case destinationExists
        var errorDescription: String? {
            switch self { case .sameFile: return S.saveAsSameFileBody; case .destinationExists: return S.saveAsSkipReasonExists }
        }
    }

    /// Yol normalizasyonu + (her iki dosya da varsa) dosya sistemi kimliği karşılaştırması.
    static func isSameFile(_ a: URL, _ b: URL) -> Bool {
        let pa = a.standardizedFileURL.resolvingSymlinksInPath().path, pb = b.standardizedFileURL.resolvingSymlinksInPath().path
        if pa == pb { return true }
        let fm = FileManager.default
        guard fm.fileExists(atPath: a.path), fm.fileExists(atPath: b.path) else { return false }
        let ia = try? a.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
        let ib = try? b.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
        if let ia = ia as? NSObject, let ib = ib as? NSObject { return ia.isEqual(ib) }
        return false
    }

    /// Kaynağı hedefe kopyalar. `replace == false` iken var olan hedefe dokunmaz (`destinationExists`).
    static func copy(_ src: URL, to dst: URL, replace: Bool) throws {
        if isSameFile(src, dst) { throw Failure.sameFile }
        let fm = FileManager.default
        guard fm.fileExists(atPath: dst.path) else { try fm.copyItem(at: src, to: dst); return }
        guard replace else { throw Failure.destinationExists }
        try replacing(dst) { tmp in try fm.copyItem(at: src, to: tmp) }
    }

    /// Veriyi hedefe yazar; `source` verilmişse hedefin kaynakla aynı dosya olmasını reddeder.
    static func write(_ data: Data, to dst: URL, source: URL?) throws {
        if let s = source, isSameFile(s, dst) { throw Failure.sameFile }
        guard FileManager.default.fileExists(atPath: dst.path) else { try data.write(to: dst, options: .atomic); return }
        try replacing(dst) { tmp in try data.write(to: tmp, options: .atomic) }
    }

    /// Sistemin değiştirme dizini (`itemReplacementDirectory`, hedefle aynı birimde). Testler başarısız bir sağlayıcı verebilir.
    static func systemReplacementDirectory(_ dst: URL) throws -> URL {
        try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: dst, create: true)
    }
    static var replacementDirectory: (URL) throws -> URL = systemReplacementDirectory
    /// Hedefle aynı birimde, değiştirme dizininde benzersiz geçici yol.
    static func replacementTemporaryURL(for dst: URL) throws -> URL {
        try replacementDirectory(dst).appendingPathComponent("\(UUID().uuidString.prefix(8))-\(dst.lastPathComponent)")
    }
    /// Geçici dosyaya üretir, sonra hedefle değiştirir. Üretim veya değiştirme başarısızsa hedef eski hâliyle kalır.
    /// Değiştirme dizini verilemezse (ör. bazı dış diskler) hedefin yanındaki gizli geçici dosyaya düşülür; sandbox'ta
    /// bu da reddedilirse hata fırlar ve hedef yine korunur.
    private static func replacing(_ dst: URL, produce: (URL) throws -> Void) throws {
        let fm = FileManager.default
        let tmp: URL, cleanup: URL
        if let t = try? replacementTemporaryURL(for: dst) { tmp = t; cleanup = t.deletingLastPathComponent() }
        else { tmp = dst.deletingLastPathComponent().appendingPathComponent(".\(dst.lastPathComponent).shotmori-\(UUID().uuidString.prefix(8)).tmp"); cleanup = tmp }
        defer { try? fm.removeItem(at: cleanup) }
        try produce(tmp)
        _ = try fm.replaceItemAt(dst, withItemAt: tmp, backupItemName: nil, options: [.usingNewMetadataOnly])
    }

    // MARK: Çoklu kopyalama planı (klasöre "Buraya Kopyala")
    struct BatchResult: Equatable {
        var copied: [URL] = []
        var skipped: [(URL, Failure)] = []
        static func == (l: BatchResult, r: BatchResult) -> Bool { l.copied == r.copied && l.skipped.map { $0.0 } == r.skipped.map { $0.0 } && l.skipped.map { $0.1 } == r.skipped.map { $0.1 } }
    }
    /// Her kaynağı hedef klasöre kendi adıyla kopyalar. Aynı dosya veya var olan hedef sessizce ezilmez; atlanır ve raporlanır.
    static func copyAll(_ sources: [URL], into dir: URL) -> BatchResult {
        var r = BatchResult()
        for src in sources {
            let dst = dir.appendingPathComponent(src.lastPathComponent)
            do { try copy(src, to: dst, replace: false); r.copied.append(src) }
            catch let f as Failure { r.skipped.append((src, f)) }
            catch { r.skipped.append((src, .destinationExists)) }
        }
        return r
    }
}
