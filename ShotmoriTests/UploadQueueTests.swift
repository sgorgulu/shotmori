#if SHOTMORI_CLOUD // Bulut yalnız bulutlu (Debug) derlemede; Release test derlemesi de derlenebilsin.
import XCTest
@testable import Shotmori

/// Testler için sahte sağlayıcı: sonuçlar sırayla tüketilir.
final class FakeProvider: CloudProvider {
    let id: CloudProviderID
    var isConnected = true
    var results: [Result<CloudObject, CloudError>] = []
    var uploads: [(URL, String, LinkAccess)] = []
    var strips: [Bool] = []
    var verifyResult = true
    var deleted: [String] = []
    init(id: CloudProviderID = .s3) { self.id = id }
    func upload(file: URL, remotePath: String, access: LinkAccess, stripMetadata: Bool, progress: @escaping (Double) -> Void) async throws -> CloudObject {
        uploads.append((file, remotePath, access)); strips.append(stripMetadata); progress(1)
        guard !results.isEmpty else { return CloudObject(provider: id, remoteID: remotePath, remotePath: remotePath, link: URL(string: "https://x/\(remotePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)"), access: access, uploadedAt: Date(), size: CloudHTTP.fileSize(file), checksum: nil) }
        return try results.removeFirst().get()
    }
    func setAccess(_ object: CloudObject, access: LinkAccess) async throws -> CloudObject { var o = object; o.access = access; return o }
    func verify(_ object: CloudObject, localFile: URL) async throws -> Bool { verifyResult }
    func delete(_ object: CloudObject) async throws { deleted.append(object.remoteID) }
    func testConnection() async throws {}
}

final class UploadQueueTests: XCTestCase {
    var dir: URL!; var file: URL!; var clock = Date(timeIntervalSince1970: 1_800_000_000); var online = true
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("uq-\(UUID())", isDirectory: true); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        file = dir.appendingPathComponent("a.png"); try Data(repeating: 3, count: 100).write(to: file)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }
    private func queue(_ p: FakeProvider, persist: Bool = true) -> UploadQueue { UploadQueue(fileURL: persist ? dir.appendingPathComponent("queue.json") : nil, providers: { _ in p }, isOnline: { self.online }, now: { self.clock }) }
    private func task(_ purpose: UploadPurpose = .share) -> UploadTask { UploadTask(itemID: UUID(), filePath: file.path, provider: .s3, remotePath: "Shotmori/a.png", access: .publicObject, purpose: purpose, now: clock) }

    func testBackoffSchedule() { XCTAssertEqual([1, 2, 3, 4, 5, 9].map(UploadQueue.backoff), [30, 60, 300, 1800, 1800, 1800]) }
    func testPersistenceAcrossInstances() {
        let p = FakeProvider(); let q = queue(p); q.enqueue(task())
        let q2 = queue(p); XCTAssertEqual(q2.tasks.map(\.id), q.tasks.map(\.id), "kuyruk diskten geri okunur"); XCTAssertEqual(q2.tasks.first?.remotePath, "Shotmori/a.png"); XCTAssertEqual(q2.tasks.first?.purpose, .share)
    }
    func testOfflineSkipsWithoutCountingAttempt() async {
        let p = FakeProvider(); let q = queue(p); q.enqueue(task()); online = false
        let r = await q.processNext(); XCTAssertEqual(r, .skippedOffline); XCTAssertEqual(q.tasks.first?.attempts, 0); XCTAssertTrue(p.uploads.isEmpty)
    }
    func testSuccessRemovesTaskAndNotifies() async {
        let p = FakeProvider(); let q = queue(p); let t = task(); q.enqueue(t)
        var uploaded: (UploadTask, CloudObject)?; q.onUploaded = { uploaded = ($0, $1) }
        guard case .uploaded(let done, let obj) = await q.processNext() else { return XCTFail("yüklenmeliydi") }
        XCTAssertEqual(done.id, t.id); XCTAssertEqual(obj.remotePath, "Shotmori/a.png"); XCTAssertTrue(q.tasks.isEmpty); XCTAssertEqual(uploaded?.0.id, t.id)
        let idle = await q.processNext(); XCTAssertEqual(idle, .idle)
    }
    func testFailureKeepsTaskWithBackoffAndNeverDeletesAfterExhaustion() async {
        let p = FakeProvider(); p.results = [.failure(.server(500, "x")), .failure(.unauthorized), .failure(.network("n")), .failure(.forbidden), .failure(.server(503, "y"))]
        let q = queue(p); let t = task(); q.enqueue(t)
        for attempt in 1...5 {
            let r = await q.processNext(); guard case .failed(let ft, _) = r else { return XCTFail("hata beklenirdi (\(attempt))") }
            XCTAssertEqual(ft.attempts, attempt); XCTAssertEqual(ft.nextAttemptAt, clock.addingTimeInterval(UploadQueue.backoff(attempt: attempt)))
            XCTAssertEqual(q.tasks.count, 1, "görev silinmez")
            let early = await q.processNext(); XCTAssertEqual(early, .idle, "geri çekilme süresi dolmadan tekrar denenmez")
            clock = ft.nextAttemptAt
        }
        XCTAssertTrue(q.tasks.first!.exhausted); let r = await q.processNext(); XCTAssertEqual(r, .idle, "tükenmiş görev kullanıcı yeniden deneyene kadar bekler")
        q.retryNow(id: t.id); XCTAssertEqual(q.tasks.first?.attempts, 0)
        guard case .uploaded = await q.processNext() else { return XCTFail("yeniden denemede yüklenmeliydi") }
    }
    /// COR-24: dosyası kaybolan görev atılır ve bildirilir (yeniden denenecek bir şey yok).
    func testMissingLocalFileDropsTaskAndNotifies() async throws {
        let p = FakeProvider(); let q = queue(p); let t = task(); q.enqueue(t); try FileManager.default.removeItem(at: file)
        var failed: [CloudError] = []; q.onFailed = { failed.append($1) }
        guard case .failed(_, let e) = await q.processNext() else { return XCTFail() }; XCTAssertEqual(e, .localFileMissing); XCTAssertTrue(q.tasks.isEmpty)
        XCTAssertEqual(failed, [.localFileMissing])
        XCTAssertEqual(CloudError.localFileMissing.errorDescription, S.missingFile)
    }
    /// Dosya ön kontrolden sonra, okuma sırasında kaybolursa (sağlayıcı `.localFileMissing` fırlatır) ön kontroldeki yol izlenir:
    /// görev atılır, tek bildirim; deneme sayılıp geri çekilmeyle tekrar denenmez.
    func testThrownLocalFileMissingDropsTaskLikePrecheck() async {
        let p = FakeProvider(); p.results = [.failure(.localFileMissing)]
        let q = queue(p); q.enqueue(task())
        var failed: [CloudError] = []; q.onFailed = { failed.append($1) }
        guard case .failed(let ft, let e) = await q.processNext() else { return XCTFail() }
        XCTAssertEqual(e, .localFileMissing); XCTAssertEqual(ft.attempts, 0); XCTAssertTrue(q.tasks.isEmpty, "görev kuyrukta kalmaz")
        XCTAssertEqual(failed, [.localFileMissing])
        let idle = await q.processNext(); XCTAssertEqual(idle, .idle)
    }
    /// Okunamayan ama diskte duran dosya: görev kuyrukta kalır, normal yeniden deneme yolu işler.
    func testUnreadableLocalFileKeepsTaskForRetry() async {
        let p = FakeProvider(); p.results = [.failure(.localFileUnreadable)]
        let q = queue(p); q.enqueue(task())
        guard case .failed(let ft, let e) = await q.processNext() else { return XCTFail() }
        XCTAssertEqual(e, .localFileUnreadable); XCTAssertEqual(ft.attempts, 1); XCTAssertEqual(q.tasks.count, 1)
        XCTAssertEqual(CloudError.localFileUnreadable.errorDescription, S.cloudErrFileUnreadable)
    }
    /// `CloudHTTP.body`: yok → `.localFileMissing`, var ama okunamıyor → `.localFileUnreadable`.
    func testBodyDistinguishesMissingFromUnreadable() throws {
        XCTAssertEqual(try CloudHTTP.body(of: file, stripMetadata: false).count, 100)
        XCTAssertThrowsError(try CloudHTTP.body(of: dir.appendingPathComponent("yok.png"), stripMetadata: false)) { XCTAssertEqual($0 as? CloudError, .localFileMissing) }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) }
        XCTAssertThrowsError(try CloudHTTP.body(of: file, stripMetadata: false)) { XCTAssertEqual($0 as? CloudError, .localFileUnreadable) }
    }
    /// COR-01: kuyruk durumu ana iş parçacığında değişir (geri bildirimler de orada).
    func testProcessNextMutatesOnMainThread() async {
        let p = FakeProvider(); let q = queue(p); q.enqueue(task())
        var changesOnMain: [Bool] = []; q.onChange = { changesOnMain.append(Thread.isMainThread) }
        var uploadedOnMain: Bool?; q.onUploaded = { _, _ in uploadedOnMain = Thread.isMainThread }
        let r = await Task.detached { await q.processNext() }.value
        guard case .uploaded = r else { return XCTFail("yüklenmeliydi") }
        XCTAssertFalse(changesOnMain.isEmpty); XCTAssertTrue(changesOnMain.allSatisfy { $0 }); XCTAssertEqual(uploadedOnMain, true)
    }
    /// COR-22: başarılı yükleme aynı öğe + sağlayıcının tükenmiş eski görevlerini de temizler.
    func testSuccessDropsExhaustedSiblings() async {
        let p = FakeProvider(); let q = queue(p); let item = UUID()
        var old = UploadTask(itemID: item, filePath: file.path, provider: .s3, remotePath: "o", access: .publicObject, purpose: .share, now: clock); old.attempts = UploadQueue.maxAttempts
        q.enqueue(old); q.enqueue(UploadTask(itemID: item, filePath: file.path, provider: .s3, remotePath: "n", access: .publicObject, purpose: .share, now: clock))
        guard case .uploaded = await q.processNext() else { return XCTFail("yüklenmeliydi") }
        XCTAssertTrue(q.tasks.isEmpty, "tükenmiş eski görev de gider")
        q.enqueue(old); q.dropExhausted(itemID: item, provider: .googleDrive); XCTAssertEqual(q.tasks.count, 1, "başka sağlayıcı etkilenmez")
        q.dropExhausted(itemID: item, provider: .s3); XCTAssertTrue(q.tasks.isEmpty)
    }
    /// SEC-05: paylaşım yüklemesi üst veriyi atar, yedek orijinali gönderir.
    func testShareStripsMetadataBackupDoesNot() async {
        let p = FakeProvider(); let q = queue(p); q.enqueue(task(.share)); q.enqueue(task(.backup))
        _ = await q.processNext(); _ = await q.processNext()
        XCTAssertEqual(p.strips, [true, false])
    }
    /// PERF-17: toplu ekleme kuyruğu bir kez yazar ve bir kez bildirir.
    func testBatchEnqueueNotifiesOnce() {
        let p = FakeProvider(); let q = queue(p); var changes = 0; q.onChange = { changes += 1 }
        q.enqueue(contentsOf: [task(), task(), task()]); XCTAssertEqual(changes, 1); XCTAssertEqual(q.tasks.count, 3)
        q.enqueue(contentsOf: []); XCTAssertEqual(changes, 1, "boş toplu ekleme bildirmez")
        XCTAssertEqual(queue(p).tasks.count, 3, "diske yazıldı")
    }
    /// PERF-20: zamanlayıcı yalnız bekleyen görev varken ve en erken deneme anına kurulur.
    func testNextWakeOnlyForPendingTasks() {
        XCTAssertNil(UploadQueue.nextWake(tasks: [], now: clock))
        var exhausted = task(); exhausted.attempts = UploadQueue.maxAttempts
        XCTAssertNil(UploadQueue.nextWake(tasks: [exhausted], now: clock), "yalnız tükenmiş görev → uyanma yok")
        var later = task(); later.nextAttemptAt = clock.addingTimeInterval(300)
        var sooner = task(); sooner.nextAttemptAt = clock.addingTimeInterval(30)
        XCTAssertEqual(UploadQueue.nextWake(tasks: [later, sooner, exhausted], now: clock), 30)
        XCTAssertEqual(UploadQueue.nextWake(tasks: [task()], now: clock), 1, "vadesi gelmiş görev: en az 1 sn")
        XCTAssertEqual(UploadQueue.nextWake(tasks: [task()], now: clock, offline: true), 60)
    }
    private func runLoopOnce(_ q: UploadQueue) async throws {
        q.start()
        for _ in 0..<200 where q.isProcessing { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertFalse(q.isProcessing)
    }
    func testStartWithOnlyExhaustedTasksSchedulesNothing() async throws {
        let p = FakeProvider(); let q = queue(p, persist: false)
        var t = task(); t.attempts = UploadQueue.maxAttempts; q.enqueue(t)
        try await runLoopOnce(q)
        XCTAssertFalse(q.isWakeScheduled, "bekleyen görev yok → zamanlayıcı yok"); XCTAssertFalse(q.isWatchingNetwork)
    }
    func testFailedTaskSchedulesOneShotWake() async throws {
        let p = FakeProvider(); p.results = [.failure(.server(500, ""))]
        let q = UploadQueue(fileURL: nil, providers: { _ in p }, isOnline: { true })
        q.enqueue(UploadTask(itemID: UUID(), filePath: file.path, provider: .s3, remotePath: "k", access: .publicObject, purpose: .share))
        try await runLoopOnce(q)
        XCTAssertTrue(q.isWakeScheduled, "geri çekilme sonrası tek seferlik uyanma"); XCTAssertTrue(q.isWatchingNetwork)
    }
    func testHistoryKeepsNewestFirstAndCaps() {
        let h = UploadHistoryStore(fileURL: dir.appendingPathComponent("uploads.json"))
        for i in 0..<(UploadHistoryStore.maxRecords + 5) { h.add(UploadRecord(id: UUID(), itemID: nil, fileName: "f\(i)", object: CloudObject(provider: .s3, remoteID: "k\(i)", remotePath: "k\(i)", link: nil, access: .publicObject, uploadedAt: Date(), size: 1, checksum: nil), purpose: .share, date: Date())) }
        XCTAssertEqual(h.records.count, UploadHistoryStore.maxRecords); XCTAssertEqual(h.records.first?.fileName, "f\(UploadHistoryStore.maxRecords + 4)")
        let h2 = UploadHistoryStore(fileURL: dir.appendingPathComponent("uploads.json")); XCTAssertEqual(h2.records.count, UploadHistoryStore.maxRecords)
        XCTAssertNotNil(h2.record(provider: .s3, remoteID: "k10")); h2.remove(id: h2.records[0].id); XCTAssertEqual(h2.records.count, UploadHistoryStore.maxRecords - 1)
    }

    /// Konteyner göçü: kuyruktaki görevlerin yerel yolları da yeni köke bağlanır.
    func testRebaseRewritesQueuedFilePaths() {
        let p = FakeProvider(); let q = queue(p, persist: false); online = false
        q.enqueue(UploadTask(itemID: UUID(), filePath: "/old/Shotmori/Türevler/a.png", provider: .s3, remotePath: "k", access: .publicObject, purpose: .backup, now: clock))
        q.enqueue(UploadTask(itemID: UUID(), filePath: "/u/Desktop/b.png", provider: .s3, remotePath: "k2", access: .publicObject, purpose: .backup, now: clock))
        XCTAssertEqual(q.rebasePaths(from: "/old/Shotmori", to: "/new/Shotmori"), 1)
        XCTAssertEqual(Set(q.tasks.map(\.filePath)), ["/new/Shotmori/Türevler/a.png", "/u/Desktop/b.png"])
    }
}
#endif
