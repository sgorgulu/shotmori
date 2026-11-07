import Foundation

/// Shotmori'nin kendi konteyner klasörlerinde (Türevler, Pano, Gelen) rafta olmayan ve `olderThan`'dan eski dosyaları Çöp'e taşır.
/// Kalıcı silme yok: `trash` üretimde `trashItem`; yalnız doğrudan alt dosyalar (alt klasör değil). Gizli dosyalardan yalnız
/// içe aktarmanın yarım kalmış geçici kopyaları (`.gelen-*.tmp`) alınır; yaşları öznitelik değişim zamanından (ctime) ölçülür,
/// çünkü kopya kaynağın eski mtime'ını taşıyabilir ve süren bir kopya Çöp'e gitmemeli. Tekilleştirme indeksi (`index.json`) hiç alınmaz.
enum DerivativeJanitor {
    /// Döner: Çöp'e taşınan dosya sayısı (başarısız `trash` sayılmaz).
    static func sweep(roots: [URL], referenced: Set<String>, olderThan: TimeInterval, now: Date = Date(), trash: (URL) throws -> Void) -> Int {
        let fm = FileManager.default, keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .attributeModificationDateKey]
        let refs = Set(referenced.flatMap { [$0, URL(fileURLWithPath: $0).resolvingSymlinksInPath().path] })
        let cutoff = now.addingTimeInterval(-olderThan)
        var n = 0
        for root in roots {
            guard let urls = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: keys, options: []) else { continue }
            for u in urls {
                let name = u.lastPathComponent, isTemp = isImportTemp(name)
                guard !name.hasPrefix(".") || isTemp, name != InboundImport.indexFileName else { continue } // tekilleştirme indeksi (Gelen/, Pano/) kalır
                guard let v = try? u.resourceValues(forKeys: Set(keys)), v.isRegularFile == true,
                      let m = isTemp ? v.attributeModificationDate : v.contentModificationDate, m < cutoff else { continue }
                if refs.contains(u.path) || refs.contains(u.resolvingSymlinksInPath().path) { continue }
                do { try trash(u); n += 1 } catch { Log.error("Konteyner temizliği: Çöp'e taşınamadı: \(Log.describe(error))") }
            }
        }
        return n
    }
    /// İçe aktarmanın geçici kopya adı: `.gelen-<UUID>.tmp`.
    static func isImportTemp(_ name: String) -> Bool { name.hasPrefix(InboundImport.tempPrefix) && name.hasSuffix(".tmp") }
}
