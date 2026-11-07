#if SHOTMORI_CLOUD // Bulut kodu SHOTMORI_CLOUD bayrağıyla derlenir (Debug ve Release 1.0'da açık, bkz. Features.swift); bayrak kaldırılırsa derlenmez.
import Foundation

/// Otomatik yedek: izlenen klasöre düşen her ekran görüntüsü seçili servise kuyruğa alınır.
/// Yedekler her zaman özel yüklenir (Drive "yalnızca ben", S3 imzalı link / özel ACL); paylaşım linki ayarı yalnız paylaşım görevlerine uygulanır.
/// Yerel dosya yalnız şu koşulların TAMAMINDA Çöp'e taşınır: seçenek açık, görev amacı yedek,
/// sunucu kopyası yerel MD5 ile doğrulandı, dosya görev alındığından beri değişmedi, dosya izlenen klasörde.
final class BackupCoordinator {
    private let prefs: Preferences
    private let queue: UploadQueue
    private let store: ShelfStore
    private let providers: (CloudProviderID) -> CloudProvider?
    private let trash: (URL) throws -> Void
    private let notify: (String) -> Void
    /// Ana iş parçacığında okunur (`AppController.folder` yalnız orada yazılır).
    var watchedFolder: () -> URL? = { nil }

    init(prefs: Preferences, queue: UploadQueue, store: ShelfStore, providers: @escaping (CloudProviderID) -> CloudProvider?,
         trash: @escaping (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }, notify: @escaping (String) -> Void = { _ in }) {
        self.prefs = prefs; self.queue = queue; self.store = store; self.providers = providers; self.trash = trash; self.notify = notify
    }

    /// Yeni kare: yedek hedefi varsa kuyruğa al (pano/türev yalnız seçenekle).
    func screenshotArrived(_ item: ShelfItem) { screenshotsArrived([item]) }
    /// Toplu geliş: uygun karelerin görevleri tek seferde eklenir (kuyruk bir kez yazılır, raf bir kez yenilenir).
    func screenshotsArrived(_ items: [ShelfItem]) {
        guard let target = prefs.backupProvider else { return }
        let tasks = items.filter { item in
            (item.source == .screenshot || (item.source == .derivative && prefs.backupIncludesDerivatives))
                && item.exists && !queue.tasks(for: item.id).contains(where: { $0.provider == target })
        }.map { UploadTask.make(for: $0, provider: target, template: prefs.cloudTemplate(for: target), access: prefs.backupAccess(for: target), purpose: .backup) }
        guard !tasks.isEmpty else { return }
        queue.enqueue(contentsOf: tasks)
        queue.kick()
    }

    /// Teslim sonrası: koşullar sağlanırsa yerel dosya Çöp'e. Sonuç: taşındı mı.
    @discardableResult
    func handleUploaded(task: UploadTask, object: CloudObject) async -> Bool {
        guard task.purpose == .backup, prefs.trashLocalAfterBackup else { return false }
        guard let provider = providers(task.provider) else { return false }
        let url = URL(fileURLWithPath: task.filePath)
        guard Self.fileUnchanged(url, size: task.fileSize, modified: task.fileModified) else { Log.info("Yedek sonrası Çöp atlandı: dosya değişti"); return false }
        // Klasör bilinmiyorsa (sandbox'ta seçilmemiş) Çöp yok: yalnız izlenen klasörün içindeki dosya taşınır.
        let folderLookup = watchedFolder
        let watched = await MainActor.run { folderLookup() }
        guard let folder = watched, ImageResizer.isInside(url, folder: folder) else { Log.info("Yedek sonrası Çöp atlandı: izlenen klasör dışında"); return false }
        guard (try? await provider.verify(object, localFile: url)) == true else { Log.info("Yedek sonrası Çöp atlandı: doğrulama başarısız"); return false }
        do { try trash(url) } catch { Log.error("Yedek sonrası Çöp'e taşıma başarısız: \(Log.describe(error))"); return false }
        // Raf ve bildirim yalnız ana iş parçacığında (gözlemciler şeridi/paneli günceller).
        let store = store, notify = notify, itemID = task.itemID
        await MainActor.run {
            store.markLocalTrashed(itemID: itemID)
            notify(S.cloudTrashedAfterBackup)
        }
        return true
    }
    static func fileUnchanged(_ url: URL, size: Int, modified: Date) -> Bool {
        guard let a = try? FileManager.default.attributesOfItem(atPath: url.path), let s = a[.size] as? Int, let m = a[.modificationDate] as? Date else { return false }
        return s == size && abs(m.timeIntervalSince(modified)) < 1
    }
}

/// Sağlayıcıya göre şablon ve erişim (paylaşım ve yedek aynı kaynaktan okur).
extension Preferences {
    func cloudTemplate(for id: CloudProviderID) -> String { id == .googleDrive ? driveFolderTemplate : s3PathTemplate }
    /// Paylaşım ("Drive'a yükle" / "S3'e yükle", Kestirmeler): kullanıcının Paylaşım bölümünde seçtiği link erişimi.
    func shareAccess(for id: CloudProviderID) -> LinkAccess { id == .googleDrive ? driveLinkAccess : s3LinkAccess }
    /// Otomatik yedek: paylaşım ayarından bağımsız, her zaman özel (Drive yalnızca ben; S3 ACL'siz, imzalı link).
    func backupAccess(for id: CloudProviderID) -> LinkAccess { id == .googleDrive ? .ownerOnly : .presigned(seconds: s3PresignSeconds) }
}
#endif
