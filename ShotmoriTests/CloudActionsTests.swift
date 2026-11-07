import XCTest
@testable import Shotmori

#if SHOTMORI_CLOUD // Yükleme eylemleri, kuyruk ve son yüklemeler yalnız bulutlu (Debug) derlemede.
final class CloudActionsTests: XCTestCase {
    var suite = ""; var prefs: Preferences!; var store: ShelfStore!; var dir: URL!; var cloud: CloudCenter!; var fake: FakeProvider!
    override func setUpWithError() throws {
        suite = "dev.shotmori.tests.cloudactions.\(UUID().uuidString)"; let d = UserDefaults(suiteName: suite)!; d.removePersistentDomain(forName: suite); prefs = Preferences(defaults: d)
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ca-\(UUID())", isDirectory: true); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store = ShelfStore(fileURL: nil, maxItems: 10); fake = FakeProvider(id: .s3)
        cloud = CloudCenter(prefs: prefs, keychain: KeychainStore(service: "dev.shotmori.tests.ca.\(UUID())"), store: store, dataDir: dir)
        cloud.providerOverride = { id in id == .s3 ? self.fake : nil }
    }
    override func tearDownWithError() throws { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: dir) }
    private func items(_ n: Int) throws -> [ShelfItem] { try (1...n).map { i in let u = dir.appendingPathComponent("s\(i).png"); try Data([1]).write(to: u); let it = ShelfItem(path: u.path, fileID: nil, capturedAt: Date()); _ = store.add(it); return it } }

    func testRegistryIncludesUploadActionsOnlyWithCloudAndMenuGroupsCoverThem() {
        let plain = ActionRegistry(prefs: prefs); XCTAssertNil(plain.action("upload-drive"))
        let reg = ActionRegistry(prefs: prefs, cloud: cloud)
        XCTAssertNotNil(reg.action("upload-drive")); XCTAssertNotNil(reg.action("upload-s3"))
        XCTAssertEqual(Set(ActionRegistry.menuGroups.flatMap { $0 }), Set(reg.all.map(\.id)))
        XCTAssertTrue(reg.favoriteCandidates.contains { $0.id == "upload-s3" })
    }
    func testAvailabilityRequiresConnectionAndExistingFiles() throws {
        let reg = ActionRegistry(prefs: prefs, cloud: cloud); let its = try items(1)
        XCTAssertFalse(reg.action("upload-drive")!.availability(for: its).isAvailable, "Drive bağlı değil")
        XCTAssertTrue(reg.action("upload-s3")!.availability(for: its).isAvailable)
        fake.isConnected = false; XCTAssertEqual(reg.action("upload-s3")!.availability(for: its).reason, S.cloudNotConnected("S3"))
    }
    func testPerformEnqueuesOneTaskPerItemWithoutDuplicates() throws {
        let reg = ActionRegistry(prefs: prefs, cloud: cloud); let its = try items(2)
        let a = reg.action("upload-s3")!
        a.perform(ActionContext(items: its, anchorView: nil, store: store, panel: nil))
        XCTAssertEqual(cloud.queue.tasks.count, 2); XCTAssertTrue(cloud.queue.tasks.allSatisfy { $0.purpose == .share && $0.provider == .s3 })
        a.perform(ActionContext(items: its, anchorView: nil, store: store, panel: nil)); XCTAssertEqual(cloud.queue.tasks.count, 2, "bekleyen görev yinelenmez")
    }
    func testUploadedTaskUpdatesShelfHistoryAndBadge() async throws {
        let its = try items(1); cloud.share(items: its, to: .s3)
        guard case .uploaded = await cloud.queue.processNext() else { return XCTFail("yüklenmeliydi") }
        await MainActor.run {} // kuyruk geri bildirimleri ana iş parçacığına atlanır; raf/geçmiş orada güncellenir
        let item = store.items.first { $0.id == its[0].id }!
        XCTAssertEqual(item.cloud.count, 1); XCTAssertEqual(item.cloud.first?.provider, .s3)
        XCTAssertEqual(cloud.history.records.count, 1); XCTAssertEqual(cloud.badge(for: item), .uploaded(.s3))
        let menu = CloudMenuBuilder.submenu(for: item, cloud: cloud); XCTAssertEqual(menu?.items.map(\.title), [S.cloudCopyLink, S.cloudOpenLink, S.cloudAccessMenu, S.cloudDelete])
    }
    /// Kestirmeler › Buluta yükle: sessiz paylaşım bitince panoya yazmaz, tost göstermez (panoyu intent yönetir); raf/geçmiş yine güncellenir.
    func testSilentShareDoesNotAnnounceOrCopyLink() async throws {
        let its = try items(1); cloud.share(items: its, to: .s3, copyLinkOnFinish: false)
        XCTAssertEqual(cloud.queue.tasks.count, 1)
        let task = try XCTUnwrap(cloud.queue.tasks.first)
        XCTAssertEqual(task.silent, true); XCTAssertEqual(task.purpose, .share)
        XCTAssertFalse(CloudCenter.announcesOnFinish(task))
        guard case .uploaded = await cloud.queue.processNext() else { return XCTFail("yüklenmeliydi") }
        await MainActor.run {}
        XCTAssertEqual(store.items.first { $0.id == its[0].id }?.cloud.count, 1)
        XCTAssertEqual(cloud.history.records.count, 1)
    }
    func testShareTaskAnnouncesByDefaultAndDecodesLegacyQueue() throws {
        let its = try items(1); cloud.share(items: its, to: .s3)
        let task = try XCTUnwrap(cloud.queue.tasks.first)
        XCTAssertNil(task.silent); XCTAssertTrue(CloudCenter.announcesOnFinish(task))
        let backup = UploadTask(itemID: its[0].id, filePath: its[0].path, provider: .s3, remotePath: "x", access: .publicObject, purpose: .backup)
        XCTAssertFalse(CloudCenter.announcesOnFinish(backup))
        // Eski kuyruk dosyası (`silent` alanı yok) okunur, sessiz sayılmaz.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(task)) as? [String: Any])
        json.removeValue(forKey: "silent")
        let back = try JSONDecoder().decode(UploadTask.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(back.silent); XCTAssertTrue(CloudCenter.announcesOnFinish(back))
        let silent = try JSONDecoder().decode(UploadTask.self, from: JSONEncoder().encode(CloudCenter.shareTask(for: its[0], provider: .s3, template: "{name}", access: .publicObject, silent: true)))
        XCTAssertEqual(silent.silent, true)
    }
    /// Bekleme sınırı `perform()` girişinden: hazırlık süresi 30 sn'lik intent sınırına sayılır.
    func testUploadIntentDeadlineCountsFromPerformStart() {
        let begun = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(UploadIntent.deadline(begun: begun), begun.addingTimeInterval(25))
        XCTAssertLessThan(UploadIntent.waitLimit, 30)
    }
    /// COR-22: tükenmiş görevin yerine yeni paylaşım geçer; rozet etkin/bekleyen görevi gösterir.
    func testReshareReplacesExhaustedTaskAndBadgePrefersPending() throws {
        let its = try items(1)
        var old = CloudCenter.shareTask(for: its[0], provider: .s3, template: "{name}", access: .publicObject, silent: false); old.attempts = UploadQueue.maxAttempts
        cloud.queue.enqueue(old)
        XCTAssertEqual(cloud.badge(for: its[0]), .failed(.s3))
        cloud.share(items: its, to: .s3)
        XCTAssertEqual(cloud.queue.tasks.count, 1); XCTAssertNotEqual(cloud.queue.tasks.first?.id, old.id, "tükenmiş görev atıldı")
        XCTAssertEqual(cloud.badge(for: its[0]), .pending(.s3))
    }
    /// SEC-02: yerel kopyası Çöp'e taşınmış öğede silme onayı tek kopya uyarısı verir.
    func testDeleteConfirmationWarnsWhenLocalCopyTrashed() {
        XCTAssertEqual(CloudMenuBuilder.deleteBody(provider: .s3, localTrashed: false), S.cloudDeleteBody("S3"))
        XCTAssertEqual(CloudMenuBuilder.deleteBody(provider: .googleDrive, localTrashed: true), S.cloudDeleteBodyLocalTrashed("Google Drive"))
        XCTAssertNotEqual(S.cloudDeleteBodyLocalTrashed("S3"), S.cloudDeleteBody("S3"))
    }
    /// COR-10: girişten önce yeniden kayıt (gizli anahtar alanı boş) kendi istemcinin kayıtlı gizli anahtarını silmez.
    func testSavingDriveClientWithoutSecretKeepsStoredSecret() {
        cloud.saveDrive(clientID: "cid", clientSecret: "S1"); XCTAssertEqual(cloud.keychain.get(CloudAccount.driveClientSecret), "S1")
        cloud.saveDrive(clientID: "cid", clientSecret: nil); XCTAssertEqual(cloud.keychain.get(CloudAccount.driveClientSecret), "S1", "nil → dokunulmaz")
        XCTAssertTrue(cloud.hasDriveClientSecret)
        cloud.saveDrive(clientID: "", clientSecret: nil); XCTAssertNil(cloud.keychain.get(CloudAccount.driveClientSecret), "gömülü istemciye dönüş → kaldırılır")
        let model = CloudSettingsModel(cloud: cloud)
        cloud.saveDrive(clientID: "cid", clientSecret: "S2"); model.driveClientID = "cid"; model.driveClientSecret = ""
        model.saveDriveClient(); XCTAssertEqual(cloud.keychain.get(CloudAccount.driveClientSecret), "S2"); XCTAssertTrue(model.driveHasSecret)
        cloud.keychain.delete(CloudAccount.driveClientSecret)
    }
    /// PERF-19: bulutla ilgisiz tercih değişimi sağlayıcıları yeniden kurmaz, rafı yenilemez.
    func testUnrelatedPreferenceChangeDoesNotRebuildProviders() async {
        cloud.providerOverride = nil
        prefs.s3Config = S3Config(preset: .amazon, endpoint: "", region: "eu-central-1", bucket: "b", pathStyle: false, accessKey: "AK"); cloud.rebuildProviders()
        let s3 = cloud.s3; XCTAssertNotNil(s3)
        await MainActor.run {} // kurulumun birleştirilmiş bildirimi boşalsın
        var changes = 0; cloud.onChange = { changes += 1 }
        NotificationCenter.default.post(name: Preferences.didChange, object: nil)
        await MainActor.run {}; await MainActor.run {}
        XCTAssertTrue(cloud.s3 === s3, "aynı sağlayıcı"); XCTAssertEqual(changes, 0)
        prefs.s3Config = S3Config(preset: .amazon, endpoint: "", region: "eu-west-1", bucket: "b", pathStyle: false, accessKey: "AK")
        NotificationCenter.default.post(name: Preferences.didChange, object: nil)
        await MainActor.run {}; await MainActor.run {}
        XCTAssertFalse(cloud.s3 === s3, "S3 yapılandırması değişti → yeniden kuruldu"); XCTAssertEqual(changes, 1)
    }
    /// L10N-02: ön ayar örnek uç noktayı alana yazmaz, istem olarak gösterir; yol stili ön ayardan.
    func testPresetDoesNotWritePlaceholderEndpoint() {
        let model = CloudSettingsModel(cloud: cloud)
        model.s3.preset = .cloudflareR2; model.applyPreset()
        XCTAssertEqual(model.s3.endpoint, ""); XCTAssertEqual(model.endpointPrompt, S.s3EndpointPromptR2); XCTAssertTrue(model.s3.pathStyle); XCTAssertEqual(model.s3.region, "auto")
        model.s3.preset = .backblazeB2; model.applyPreset(); XCTAssertEqual(model.s3.endpoint, ""); XCTAssertEqual(model.endpointPrompt, S.s3EndpointPromptB2)
        model.s3.preset = .amazon; model.applyPreset(); XCTAssertFalse(model.s3.pathStyle)
    }
    func testSecretsNeverLandInPreferences() {
        cloud.saveS3(config: S3Config(preset: .amazon, endpoint: "", region: "eu-central-1", bucket: "b", pathStyle: false, accessKey: "AKIA"), secret: "SUPERSECRET")
        cloud.saveDrive(clientID: "cid", clientSecret: "DRIVESECRET")
        let dump = UserDefaults(suiteName: suite)!.persistentDomain(forName: suite) ?? [:]
        let blob = dump.map { k, v in "\(k)=" + ((v as? Data).map { String(decoding: $0, as: UTF8.self) } ?? String(describing: v)) }.joined(separator: "\n")
        XCTAssertFalse(blob.contains("SUPERSECRET")); XCTAssertFalse(blob.contains("DRIVESECRET")); XCTAssertTrue(blob.contains("AKIA"), blob); XCTAssertEqual(prefs.driveClientID, "cid"); XCTAssertEqual(prefs.s3Config?.accessKey, "AKIA")
        XCTAssertEqual(cloud.keychain.get(CloudAccount.s3Secret), "SUPERSECRET"); cloud.clearS3(); XCTAssertNil(cloud.keychain.get(CloudAccount.s3Secret)); cloud.keychain.delete(CloudAccount.driveClientSecret)
    }
}

final class RecentUploadsMenuTests: XCTestCase {
    func testMenuListsNewestFirstAndEmptyState() throws {
        let suite = "dev.shotmori.tests.recent.\(UUID().uuidString)"; let d = UserDefaults(suiteName: suite)!; defer { d.removePersistentDomain(forName: suite) }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ru-\(UUID())", isDirectory: true); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: dir) }
        let cloud = CloudCenter(prefs: Preferences(defaults: d), keychain: KeychainStore(service: "dev.shotmori.tests.ru.\(UUID())"), store: ShelfStore(fileURL: nil, maxItems: 5), dataDir: dir)
        XCTAssertEqual(RecentUploadsMenu.titles(cloud: cloud), [S.cloudRecentEmpty])
        for i in 1...3 { cloud.history.add(UploadRecord(id: UUID(), itemID: nil, fileName: "f\(i).png", object: CloudObject(provider: .s3, remoteID: "k\(i)", remotePath: "k\(i)", link: URL(string: "https://x/k\(i)"), access: .publicObject, uploadedAt: Date(), size: 1, checksum: nil), purpose: .share, date: Date())) }
        XCTAssertEqual(RecentUploadsMenu.titles(cloud: cloud), ["f3.png", "f2.png", "f1.png"])
        XCTAssertEqual(RecentUploadsMenu.titles(cloud: cloud, limit: 2).count, 2)
    }
}
#endif

/// Sürükleme yazıcısı her derlemede: Debug'da yazılmış `cloud`/`localTrashed` alanları Release'te de okunur (bulutsuz derlemede de derlenir).
final class DragWriterTests: XCTestCase {
    var dir: URL!
    override func setUpWithError() throws { dir = FileManager.default.temporaryDirectory.appendingPathComponent("dw-\(UUID())", isDirectory: true); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }
    func testDragWriterUsesFileThenCloudLinkThenNothing() throws {
        let u = dir.appendingPathComponent("s1.png"); try Data([1]).write(to: u); let it = ShelfItem(path: u.path, fileID: nil, capturedAt: Date())
        XCTAssertEqual((ShelfPanelController.dragWriter(for: it) as? NSURL)?.isFileURL, true)
        var gone = it; try FileManager.default.removeItem(at: it.url)
        XCTAssertNil(ShelfPanelController.dragWriter(for: gone), "dosya yok, bulut yok → sürüklenmez")
        gone.localTrashed = true; gone.cloud = [CloudObject(provider: .s3, remoteID: "k", remotePath: "k", link: URL(string: "https://b.s3.amazonaws.com/k.png"), access: .publicObject, uploadedAt: Date(), size: 1, checksum: nil)]
        XCTAssertEqual((ShelfPanelController.dragWriter(for: gone) as? NSURL)?.absoluteString, "https://b.s3.amazonaws.com/k.png")
    }

    /// TR biçimleyici "1 gün"de dar bölünmez boşluk (U+202F) üretir, sistem yazısında bitişik görünür; tam genişlikte NBSP'ye çevrilir.
    func testDurationTextUsesReadableNonBreakingSpace() {
        XCTAssertEqual(CloudMenuBuilder.readableSpaces("1\u{202F}gün"), "1\u{00A0}gün")
        XCTAssertEqual(CloudMenuBuilder.readableSpaces("1 day"), "1 day")
        XCTAssertFalse(CloudMenuBuilder.durationText(86_400).unicodeScalars.contains { $0.value == 0x202F })
    }
}
