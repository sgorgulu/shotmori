#if SHOTMORI_CLOUD // Bulut yalnız bulutlu (Debug) derlemede; Release test derlemesi de derlenebilsin.
import XCTest
@testable import Shotmori

/// Yedek sonrası yerel Çöp: yalnız tüm koşullar sağlanınca; aksi hâlde dosyaya dokunulmaz.
final class BackupCoordinatorTests: XCTestCase {
    var dir: URL!; var file: URL!; var prefs: Preferences!; var store: ShelfStore!; var provider: FakeProvider!; var trashed: [URL] = []; var suite = ""
    override func setUpWithError() throws {
        suite = "dev.shotmori.tests.backup.\(UUID().uuidString)"; let d = UserDefaults(suiteName: suite)!; d.removePersistentDomain(forName: suite); prefs = Preferences(defaults: d)
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("bk-\(UUID())", isDirectory: true); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        file = dir.appendingPathComponent("shot.png"); try Data(repeating: 9, count: 300).write(to: file)
        store = ShelfStore(fileURL: nil, maxItems: 10); provider = FakeProvider(id: .s3); trashed = []
    }
    override func tearDownWithError() throws { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: dir) }
    private func make() -> (BackupCoordinator, UploadQueue, ShelfItem) {
        let q = UploadQueue(fileURL: nil, providers: { _ in self.provider }, isOnline: { true })
        let c = BackupCoordinator(prefs: prefs, queue: q, store: store, providers: { _ in self.provider }, trash: { self.trashed.append($0) })
        c.watchedFolder = { self.dir }
        let item = ShelfItem(path: file.path, fileID: nil, capturedAt: Date()); _ = store.add(item)
        return (c, q, item)
    }
    private func uploadedObject() -> CloudObject { CloudObject(provider: .s3, remoteID: "k", remotePath: "k", link: nil, access: .publicObject, uploadedAt: Date(), size: 300, checksum: nil) }

    func testArrivalEnqueuesOnlyWhenBackupTargetSet() {
        let (c, q, item) = make()
        c.screenshotArrived(item); XCTAssertTrue(q.tasks.isEmpty, "hedef yokken kuyruk boş")
        prefs.backupProvider = .s3; c.screenshotArrived(item)
        XCTAssertEqual(q.tasks.count, 1); XCTAssertEqual(q.tasks.first?.purpose, .backup); XCTAssertTrue(q.tasks.first!.remotePath.hasPrefix("Shotmori/"))
        c.screenshotArrived(item); XCTAssertEqual(q.tasks.count, 1, "yinelenmez")
        let deriv = ShelfItem(path: file.path + ".d.png", fileID: nil, capturedAt: Date(), source: .derivative); c.screenshotArrived(deriv); XCTAssertEqual(q.tasks.count, 1, "türev varsayılan olarak yedeklenmez")
    }
    /// SEC-01: paylaşım için herkese açık seçilmiş olsa da yedek her zaman özel yüklenir.
    func testBackupIgnoresPublicShareAccess() {
        prefs.driveLinkAccess = .anyoneWithLink; prefs.s3LinkAccess = .publicObject; prefs.s3PresignSeconds = 3600
        let (c, q, item) = make()
        prefs.backupProvider = .s3; c.screenshotArrived(item)
        XCTAssertEqual(q.tasks.first?.access, .presigned(seconds: 3600), "S3 yedek: ACL'siz, imzalı")
        prefs.backupProvider = .googleDrive; c.screenshotArrived(item)
        XCTAssertEqual(q.tasks.last?.access, .ownerOnly, "Drive yedek: yalnızca ben")
        XCTAssertEqual(prefs.shareAccess(for: .googleDrive), .anyoneWithLink, "paylaşım ayarı paylaşıma uygulanır")
    }
    /// PERF-17: toplu gelişte görevler tek seferde eklenir.
    func testBatchArrivalEnqueuesOnce() throws {
        let (c, q, item) = make(); prefs.backupProvider = .s3
        let second = dir.appendingPathComponent("shot2.png"); try Data(repeating: 2, count: 10).write(to: second)
        let item2 = ShelfItem(path: second.path, fileID: nil, capturedAt: Date()); _ = store.add(item2)
        var changes = 0; q.onChange = { changes += 1 }
        c.screenshotsArrived([item, item2]); XCTAssertEqual(q.tasks.count, 2); XCTAssertEqual(changes, 1)
        c.screenshotsArrived([item, item2]); XCTAssertEqual(q.tasks.count, 2, "yinelenmez"); XCTAssertEqual(changes, 1)
    }
    func testTrashOnlyWhenEveryConditionHolds() async {
        let (c, _, item) = make()
        let task = UploadTask(itemID: item.id, filePath: file.path, provider: .s3, remotePath: "k", access: .publicObject, purpose: .backup)
        // 1) seçenek kapalı
        prefs.backupProvider = .s3; prefs.trashLocalAfterBackup = false
        var moved = await c.handleUploaded(task: task, object: uploadedObject()); XCTAssertFalse(moved); XCTAssertTrue(trashed.isEmpty)
        prefs.trashLocalAfterBackup = true
        // 2) paylaşım amaçlı görev
        let share = UploadTask(itemID: item.id, filePath: file.path, provider: .s3, remotePath: "k", access: .publicObject, purpose: .share)
        moved = await c.handleUploaded(task: share, object: uploadedObject()); XCTAssertFalse(moved); XCTAssertTrue(trashed.isEmpty)
        // 3) doğrulama başarısız
        provider.verifyResult = false
        moved = await c.handleUploaded(task: task, object: uploadedObject()); XCTAssertFalse(moved); XCTAssertTrue(trashed.isEmpty)
        provider.verifyResult = true
        // 4) dosya değişti
        try? Data(repeating: 1, count: 301).write(to: file)
        moved = await c.handleUploaded(task: task, object: uploadedObject()); XCTAssertFalse(moved); XCTAssertTrue(trashed.isEmpty)
        try? Data(repeating: 9, count: 300).write(to: file); let fresh = UploadTask(itemID: item.id, filePath: file.path, provider: .s3, remotePath: "k", access: .publicObject, purpose: .backup)
        // 5) izlenen klasör dışında
        c.watchedFolder = { self.dir.appendingPathComponent("baska", isDirectory: true) }
        moved = await c.handleUploaded(task: fresh, object: uploadedObject()); XCTAssertFalse(moved); XCTAssertTrue(trashed.isEmpty)
        c.watchedFolder = { self.dir }
        // 6) hepsi uygun
        moved = await c.handleUploaded(task: fresh, object: uploadedObject()); XCTAssertTrue(moved); XCTAssertEqual(trashed, [file])
        XCTAssertTrue(store.items.first { $0.id == item.id }!.localTrashed)
        XCTAssertEqual(store.pruneMissing { _ in true }, 0, "buluta taşınmış öğe raftan düşmez")
    }

    /// Yedek sonrası raf güncellemesi ve bildirim ana iş parçacığında (gözlemciler şeridi günceller; `CloudCenter` bildirimi ayrıca ana kuyruğa atar).
    func testTrashUpdateAndNotifyOnMainThread() async {
        prefs.backupProvider = .s3; prefs.trashLocalAfterBackup = true
        let q = UploadQueue(fileURL: nil, providers: { _ in self.provider }, isOnline: { true })
        var notifiedOnMain: [Bool] = []
        let c = BackupCoordinator(prefs: prefs, queue: q, store: store, providers: { _ in self.provider }, trash: { self.trashed.append($0) },
                                  notify: { _ in notifiedOnMain.append(Thread.isMainThread) })
        c.watchedFolder = { self.dir }
        let item = ShelfItem(path: file.path, fileID: nil, capturedAt: Date()); _ = store.add(item)
        var observedOnMain: [Bool] = []
        let token = store.addObserver { observedOnMain.append(Thread.isMainThread) }
        defer { store.removeObserver(token) }
        let task = UploadTask(itemID: item.id, filePath: file.path, provider: .s3, remotePath: "k", access: .publicObject, purpose: .backup)
        let moved = await Task.detached { await c.handleUploaded(task: task, object: self.uploadedObject()) }.value
        XCTAssertTrue(moved)
        XCTAssertEqual(notifiedOnMain, [true])
        XCTAssertEqual(observedOnMain, [true])
    }

    /// Sandbox'ta klasör seçilmemiş olabilir: izlenen klasör bilinmiyorsa yerel dosya Çöp'e taşınmaz.
    func testNoWatchedFolderSkipsTrash() async {
        let (c, _, item) = make()
        prefs.backupProvider = .s3; prefs.trashLocalAfterBackup = true
        c.watchedFolder = { nil }
        let task = UploadTask(itemID: item.id, filePath: file.path, provider: .s3, remotePath: "k", access: .publicObject, purpose: .backup)
        let moved = await c.handleUploaded(task: task, object: uploadedObject())
        XCTAssertFalse(moved); XCTAssertTrue(trashed.isEmpty)
    }
}
#endif
