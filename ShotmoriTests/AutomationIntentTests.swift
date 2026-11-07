import XCTest
import AppIntents
import UniformTypeIdentifiers
@testable import Shotmori

/// Otomasyon yüzeyleri (G6): widget ve Denetim Merkezi komutları, Kestirmeler teslim/hazırlık/yükleme yardımcıları.
/// Bellek içi raf (`ShelfStore(fileURL: nil)`); gerçek rafa, tercihlere ve kullanıcının dosyalarına dokunulmaz.
@MainActor
final class AutomationIntentTests: XCTestCase {
    private var root: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent() }
    private func source(_ relative: String) throws -> String { try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8) }

    // MARK: Widget ve Denetim Merkezi (COR-03, STORE-02)

    /// Widget dokunuşu URL izin kapısından geçmez (reddedilmiş izinde ölü kalmasın); Denetim Merkezi "Rafı göster" seçili yüzeyi açar.
    func testWidgetTapAndControlUseShowShelfIntentOnActiveSurface() throws {
        let widget = try source("ShotmoriWidgets/RecentShotsWidget.swift")
        XCTAssertTrue(widget.contains("Button(intent: ShowShelfCommandIntent())"), "widget dokunuşu intent'le")
        XCTAssertFalse(widget.contains(".widgetURL("), "widget URL şemasına (izin sorusuna) bağlı olmamalı")
        let commands = try source("Shared/CommandIntents.swift")
        XCTAssertTrue(commands.contains("c.shelf.show(takeKey: true)"), "seçili raf stili (şerit/panel)")
        XCTAssertFalse(commands.contains("c.panel."), "yüzen panel doğrudan açılmamalı: şerit kipinde yanlış yüzey")
        XCTAssertTrue(ShowShelfCommandIntent.openAppWhenRun, "perform uygulama sürecinde çalışır")
    }

    // MARK: Raftan al: teslim işareti (COR-28, COR-30) ve bayt bütçesi (PERF-23)

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func makeStore(fileURL: URL? = nil) -> ShelfStore { ShelfStore(fileURL: fileURL, maxItems: 50) }
    private func item(_ name: String, at date: Date) -> ShelfItem {
        ShelfItem(path: "/tmp/g6-\(UUID().uuidString)-\(name)", fileID: nil, capturedAt: date, addedAt: date)
    }
    private func names(_ items: [ShelfItem]) -> [String] { items.map { String($0.fileName.split(separator: "-").last ?? "") } }
    private func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("shotmori-g6-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); return d
    }

    /// Hiçbir dosya okunamadıysa (ör. harici disk çıkarılmış) teslim işareti ilerlemez; kareler sonraki çağrıda yine gelir.
    func testHandoffUnchangedWhenNothingDelivered() throws {
        let s = makeStore()
        for i in 0..<3 { s.add(item("\(i).png", at: t0.addingTimeInterval(Double(i)))) }
        let p = try XCTUnwrap(ShelfIntentCore.pick(store: s, shelfID: nil, onlyNew: true, limit: 10))
        XCTAssertEqual(p.items.count, 3); XCTAssertTrue(p.complete)
        ShelfIntentCore.markDelivered([], of: p, store: s)
        XCTAssertNil(s.activeShelf.lastHandoffAt)
        XCTAssertEqual(s.itemsSinceLastHandoff().count, 3, "okunamayan kareler teslim edilmiş sayılmaz")
    }
    /// İşaret verilen en yeni kareye konur; parti tamam ve en yeni de verildiyse seçim anına (okuma sırasında gelen kare yeni kalır).
    func testHandoffFollowsNewestDeliveredAndPickTime() throws {
        let s = makeStore()
        let its = (0..<4).map { item("\($0).png", at: t0.addingTimeInterval(Double($0))) }
        its.forEach { s.add($0) }
        let p = try XCTUnwrap(ShelfIntentCore.pick(store: s, shelfID: nil, onlyNew: true, limit: 10, now: t0.addingTimeInterval(10)))
        XCTAssertEqual(names(p.readOrder), ["0.png", "1.png", "2.png", "3.png"], "yeni modda eskiden yeniye okunur")
        ShelfIntentCore.markDelivered([its[0], its[1]], of: p, store: s)
        XCTAssertEqual(s.activeShelf.lastHandoffAt, its[1].addedAt)
        XCTAssertEqual(names(s.itemsSinceLastHandoff().sorted { $0.addedAt < $1.addedAt }), ["2.png", "3.png"])
        let p2 = try XCTUnwrap(ShelfIntentCore.pick(store: s, shelfID: nil, onlyNew: true, limit: 10, now: t0.addingTimeInterval(20)))
        s.add(item("sonra.png", at: t0.addingTimeInterval(30))) // okuma sürerken gelen kare
        ShelfIntentCore.markDelivered(p2.items, of: p2, store: s)
        XCTAssertEqual(s.activeShelf.lastHandoffAt, t0.addingTimeInterval(20), "\"şimdi\" değil, seçim anı")
        XCTAssertEqual(names(s.itemsSinceLastHandoff()), ["sonra.png"])
        // Tam parti ama en yeni kare okunamadı: işaret verilen en yeni karenin anında, okunamayan yeni kalır.
        let p3 = try XCTUnwrap(ShelfIntentCore.pick(store: s, shelfID: nil, onlyNew: true, limit: 10))
        ShelfIntentCore.markDelivered([], of: p3, store: s)
        XCTAssertEqual(s.itemsSinceLastHandoff().count, 1)
    }
    /// "Tüm görüntüler" kipinde işaret hiç değişmez.
    func testMarkDeliveredIgnoresAllImagesMode() throws {
        let s = makeStore(); s.add(item("a.png", at: t0))
        let p = try XCTUnwrap(ShelfIntentCore.pick(store: s, shelfID: nil, onlyNew: false, limit: 10))
        ShelfIntentCore.markDelivered(p.items, of: p, store: s)
        XCTAssertNil(s.activeShelf.lastHandoffAt)
    }
    /// Parti aynı anı taşıyan öğelerin ortasından bölünmez; sınırın tamamı tek an ise grup bütün verilir.
    func testBatchDoesNotSplitSameInstant() throws {
        let s = makeStore()
        s.add(item("a.png", at: t0))
        for n in ["b", "c", "d"] { s.add(item("\(n).png", at: t0.addingTimeInterval(1))) }
        let first = ShelfIntentCore.items(store: s, shelfID: nil, onlyNew: true, limit: 2, markHandoff: true)
        XCTAssertEqual(names(first), ["a.png"], "b eş zamanlı c/d'den ayrılmaz")
        let second = ShelfIntentCore.items(store: s, shelfID: nil, onlyNew: true, limit: 2, markHandoff: true)
        XCTAssertEqual(Set(names(second)), ["b.png", "c.png", "d.png"], "tek anlık grup bölünemez: hepsi verilir")
        XCTAssertTrue(s.itemsSinceLastHandoff().isEmpty)
    }
    /// Kalıcı biçim milisaniye: milisaniye altı farklı iki kare yeniden açılıştan sonra eşit okunur; kısmi teslim ikisini ayırmaz,
    /// kalan yeniler yeniden açılıştan sonra da "yeni" (önceden katı `>` süzgecine takılıp düşüyordu).
    func testPartialHandoffSurvivesReloadWithSubMillisecondTies() throws {
        let dir = try tempDir(); let url = dir.appendingPathComponent("shelf.json")
        let s = makeStore(fileURL: url)
        s.add(item("a.png", at: t0))
        s.add(item("b.png", at: t0.addingTimeInterval(1.0001)))
        s.add(item("c.png", at: t0.addingTimeInterval(1.0004)))
        XCTAssertEqual(names(ShelfIntentCore.items(store: s, shelfID: nil, onlyNew: true, limit: 2, markHandoff: true)), ["a.png"])
        let reloaded = makeStore(fileURL: url)
        XCTAssertEqual(Set(names(reloaded.itemsSinceLastHandoff())), ["b.png", "c.png"], "yeniden açılışta yeni kalır")
        XCTAssertTrue(ShelfIntentCore.sameInstant(t0, t0.addingTimeInterval(0.0009)))
        XCTAssertFalse(ShelfIntentCore.sameInstant(t0, t0.addingTimeInterval(0.001)))
    }
    /// Okuma: okunamayan atlanır, bütçe aşılınca durur (ilk dosya her zaman verilir); kalanlar yeni modda yeni kalır.
    func testLoadSkipsUnreadableAndStopsAtByteBudget() throws {
        let its = (0..<5).map { item("\($0).png", at: t0.addingTimeInterval(Double($0))) }
        let sizes: [String: Int] = [its[0].path: 40, its[2].path: 40, its[3].path: 40, its[4].path: 40] // its[1] okunamaz
        let read: (URL) -> Data? = { u in sizes[u.path].map { Data(count: $0) } }
        let got = ShelfIntentCore.load(its, budget: 100, read: read)
        XCTAssertEqual(got.map(\.item.id), [its[0].id, its[2].id], "1 okunamadı, 3 bütçeyi aşardı")
        XCTAssertEqual(ShelfIntentCore.load([its[0]], budget: 10, read: read).count, 1, "tek dosya bütçeden büyük olsa da verilir")
        XCTAssertGreaterThanOrEqual(ShelfIntentCore.handoffByteBudget, 50 * 1_048_576, "en az bir 50 MB dosya sığar")
        let s = makeStore(); its.forEach { s.add($0) }
        let p = try XCTUnwrap(ShelfIntentCore.pick(store: s, shelfID: nil, onlyNew: true, limit: 100))
        ShelfIntentCore.markDelivered(ShelfIntentCore.load(p.readOrder, budget: 100, read: read).map(\.item), of: p, store: s)
        XCTAssertEqual(names(s.itemsSinceLastHandoff().sorted { $0.addedAt < $1.addedAt }), ["3.png", "4.png"], "bütçe dışı kalanlar yeni")
    }
    /// Bütçe kesimi toplu eklenmiş (milisaniye altı aralıklı) grubun ortasına düşmez; kalan grup yeniden açılıştan sonra da yeni.
    /// Grup ilk kareden başlıyorsa kesim yerinde kalır (aynı kareler her çağrıda yeniden verilmesin).
    func testBudgetCutKeepsSubMillisecondGroupAcrossReload() throws {
        let dir = try tempDir(); let url = dir.appendingPathComponent("shelf.json")
        let s = makeStore(fileURL: url)
        let a = item("a.png", at: t0)
        let group = (0..<4).map { item("g\($0).png", at: t0.addingTimeInterval(1 + Double($0) * 0.0001)) }
        s.add(a); group.forEach { s.add($0) }
        let read: (URL) -> Data? = { _ in Data(count: 40) }
        let p = try XCTUnwrap(ShelfIntentCore.pick(store: s, shelfID: nil, onlyNew: true, limit: 100))
        let loaded = ShelfIntentCore.load(p.readOrder, budget: 100, read: read)
        XCTAssertEqual(names(loaded.map(\.item)), ["a.png"], "g0 tek başına verilmez: g1 ile aynı an")
        ShelfIntentCore.markDelivered(loaded.map(\.item), of: p, store: s)
        let reloaded = makeStore(fileURL: url)
        XCTAssertEqual(Set(names(reloaded.itemsSinceLastHandoff())), ["g0.png", "g1.png", "g2.png", "g3.png"], "yeniden açılışta yeni kalır")
        XCTAssertEqual(ShelfIntentCore.load(group, budget: 100, read: read).count, 2, "baştan tek grup: kesim yerinde, ilerleme var")
    }
    /// Zincirleme yakın anlar (x.0000, x.0004, x.0012): sınıra zincirle bağlı kareler birlikte sonraki partiye kalır; parti baştan tek
    /// zincirse zincirin hepsi verilir.
    func testBatchDoesNotSplitChainedNearInstants() throws {
        let dir = try tempDir(); let url = dir.appendingPathComponent("shelf.json")
        let s = makeStore(fileURL: url)
        s.add(item("a.png", at: t0))
        for (n, d) in [("c0", 1.0), ("c1", 1.0004), ("c2", 1.0012)] { s.add(item("\(n).png", at: t0.addingTimeInterval(d))) }
        XCTAssertEqual(names(ShelfIntentCore.items(store: s, shelfID: nil, onlyNew: true, limit: 3, markHandoff: true)), ["a.png"])
        let reloaded = makeStore(fileURL: url)
        XCTAssertEqual(Set(names(reloaded.itemsSinceLastHandoff())), ["c0.png", "c1.png", "c2.png"], "yeniden açılışta zincir yeni")
        let second = ShelfIntentCore.items(store: reloaded, shelfID: nil, onlyNew: true, limit: 2, markHandoff: true)
        XCTAssertEqual(Set(names(second)), ["c0.png", "c1.png", "c2.png"], "baştan tek zincir: sınırı aşsa da bütün verilir")
        XCTAssertTrue(reloaded.itemsSinceLastHandoff().isEmpty)
    }
    /// Eşzamanlı iki çağrıdan geç biten, işareti geriye çekip verilmiş kareleri yeniden "yeni" yapmaz.
    func testMarkDeliveredNeverMovesHandoffBack() throws {
        let s = makeStore()
        let its = (0..<3).map { item("\($0).png", at: t0.addingTimeInterval(Double($0))) }
        its.forEach { s.add($0) }
        let early = try XCTUnwrap(ShelfIntentCore.pick(store: s, shelfID: nil, onlyNew: true, limit: 10, now: t0.addingTimeInterval(10)))
        let late = try XCTUnwrap(ShelfIntentCore.pick(store: s, shelfID: nil, onlyNew: true, limit: 10, now: t0.addingTimeInterval(11)))
        ShelfIntentCore.markDelivered(late.items, of: late, store: s)
        XCTAssertEqual(s.activeShelf.lastHandoffAt, t0.addingTimeInterval(11))
        ShelfIntentCore.markDelivered([its[0]], of: early, store: s)
        XCTAssertEqual(s.activeShelf.lastHandoffAt, t0.addingTimeInterval(11), "işaret geri gitmez")
        XCTAssertTrue(s.itemsSinceLastHandoff().isEmpty)
    }

    // MARK: Kestirme verisinin hazırlanması (SEC-08, SEC-09, EFF-35)

    func testStagedNameCleansPathAndAddsExtension() {
        XCTAssertEqual(IntentFileStaging.stagedName(filename: "ekran.png", typeExtension: "png"), "ekran.png")
        XCTAssertEqual(IntentFileStaging.stagedName(filename: "../../etc/kare", typeExtension: "png"), "kare.png", "yalnız son bileşen")
        XCTAssertEqual(IntentFileStaging.stagedName(filename: "", typeExtension: "jpeg"), "Kestirme.jpeg")
        XCTAssertEqual(IntentFileStaging.stagedName(filename: ".gizli.png", typeExtension: nil), "Kestirme.png", "gizli ad")
        XCTAssertEqual(IntentFileStaging.stagedName(filename: "~kilit", typeExtension: nil), "Kestirme")
        XCTAssertEqual(IntentFileStaging.stagedName(filename: "a.heic", typeExtension: "png"), "a.heic", "uzantılı ad korunur")
    }
    /// Veri öğesi geçici klasöre yazılır; sınır üstü veri hiç yazılmaz, hepsi sınır üstüyse `tooLarge`; dosya URL'si olduğu gibi geçer.
    func testStagingWritesDataSkipsOversizedAndPassesFileURLs() throws {
        let root = try tempDir(), src = try tempDir()
        let file = src.appendingPathComponent("var.png"); try Data([1, 2, 3]).write(to: file)
        let staged = try IntentFileStaging.urls(for: [IntentFile(data: Data(count: 8), filename: "kucuk", type: .png),
                                                      IntentFile(data: Data(count: 32), filename: "buyuk.png", type: .png),
                                                      IntentFile(fileURL: file, filename: "var.png", type: .png)],
                                                maxBytes: 16, stageRoot: root)
        defer { staged.stopAccess() }
        XCTAssertEqual(staged.urls.count, 2, "büyük veri atlandı")
        XCTAssertEqual(staged.urls.first?.lastPathComponent, "kucuk.png")
        XCTAssertTrue(staged.urls.first?.path.hasPrefix(root.path) == true)
        XCTAssertEqual(staged.urls.last, file, "dosya URL'si kopyalanmadan geçer")
        let written = try FileManager.default.subpathsOfDirectory(atPath: root.path).filter { $0.hasSuffix(".png") }
        XCTAssertEqual(written.map { ($0 as NSString).lastPathComponent }, ["kucuk.png"], "sınır üstü veri diske yazılmadı")
        XCTAssertThrowsError(try IntentFileStaging.urls(for: [IntentFile(data: Data(count: 32), filename: "b.png", type: .png)], maxBytes: 16, stageRoot: root)) {
            XCTAssertEqual($0 as? IntentError, .tooLarge)
        }
    }
    /// Hazırlık yarıda hata verirse hata yukarı iletilir (açılmış kapsamlar kapatılır; kalıcı silme yok).
    func testStagingFailurePropagates() throws {
        let src = try tempDir()
        let notADir = src.appendingPathComponent("dosya"); try Data([0]).write(to: notADir)
        let file = src.appendingPathComponent("var.png"); try Data([1]).write(to: file)
        XCTAssertThrowsError(try IntentFileStaging.urls(for: [IntentFile(fileURL: file, filename: "var.png", type: .png),
                                                              IntentFile(data: Data(count: 4), filename: "x.png", type: .png)],
                                                        stageRoot: notADir))
    }

    // MARK: Varlıklar (PERF-22, L10N-10) ve pano öğesi (EFF-36)

    /// Varlık meta verisi küçük resimsiz kurulur; küçük resim ayrı adımda eklenir, meta veri değişmez.
    func testShotEntityThumbnailIsSeparateStep() throws {
        let dir = try tempDir(), f = dir.appendingPathComponent("kare.png")
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                 isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: f)
        let s = makeStore(); let it = ShelfItem(path: f.path, fileID: nil, capturedAt: t0, addedAt: t0); s.add(it)
        let e = ShotEntity(it, store: s)
        XCTAssertNil(e.thumbnail, "meta veri kurulurken dosya çözülmez")
        let withThumb = ShotEntity.withThumbnails([(e, f)])[0]
        XCTAssertNotNil(withThumb.thumbnail)
        XCTAssertEqual(withThumb.id, e.id); XCTAssertEqual(withThumb.fileName, e.fileName); XCTAssertEqual(withThumb.isNew, e.isNew)
        XCTAssertNil(ShotEntity.withThumbnails([(e, dir.appendingPathComponent("yok.png"))])[0].thumbnail)
    }
    /// Raf varlığının alt başlığı birimli ve çoğullu.
    func testShelfEntitySubtitleHasUnit() throws {
        let one = ShelfEntity(id: UUID(), name: "Raf 1", itemCount: 1).displayRepresentation
        let many = ShelfEntity(id: UUID(), name: "Raf 1", itemCount: 3).displayRepresentation
        let s1 = String(localized: try XCTUnwrap(one.subtitle)), s3 = String(localized: try XCTUnwrap(many.subtitle))
        XCTAssertEqual(s1, S.imageCount(1)); XCTAssertEqual(s3, S.imageCount(3))
        XCTAssertNotEqual(s3, "3"); XCTAssertTrue(s3.contains("3"))
    }
    /// Pano öğesi tek yerde kurulur (menü, Kestirmeler, Denetim Merkezi): kaynak pano, çekim anı verilen an.
    func testClipboardShelfItemAndExistingMatch() {
        let u = URL(fileURLWithPath: "/tmp/g6-\(UUID().uuidString)-Pano.png")
        let it = ClipboardImport.shelfItem(for: u, now: t0)
        XCTAssertEqual(it.source, .clipboard); XCTAssertEqual(it.capturedAt, t0); XCTAssertEqual(it.path, u.path)
        let s = makeStore(); s.add(it)
        let again = ClipboardImport.shelfItem(for: u)
        XCTAssertEqual(s.existingItem(matching: again)?.id, it.id, "aynı kopya ikinci kez eklenmez, raftaki öğe döner")
    }
    /// "Yeni görüntüleri al" kendi açıklamasını kullanır ("Yalnız yeni olanlar" anahtarını anmaz).
    func testGetNewImagesHasOwnDescription() throws {
        let src = try source("Shotmori/Intents/ShelfIntents.swift")
        let block = try XCTUnwrap(src.range(of: "struct GetNewShelfItemsIntent").map { String(src[$0.lowerBound...].prefix(400)) })
        XCTAssertTrue(block.contains("IntentDescription(\"intentGetNewDesc\")"))
        XCTAssertNotEqual(S.intentGetNewDesc, S.intentGetDesc)
    }

    // MARK: Buluta yükle (COR-29, EFF-35)

    #if SHOTMORI_CLOUD
    private func cloudObject(at date: Date, link: String? = "https://x/a") -> CloudObject {
        CloudObject(provider: .s3, remoteID: UUID().uuidString, remotePath: "a", link: link.flatMap(URL.init(string:)), access: .publicObject, uploadedAt: date, size: 1, checksum: nil)
    }
    /// Linkler: hepsi yüklendiyse öğe sırasıyla; biri eksikse nil; raftan düşen beklenmez; `since` öncesi yükleme sayılmaz; linksiz atlanır.
    func testUploadLinksCases() {
        let s = makeStore()
        let a = item("a.png", at: t0), b = item("b.png", at: t0.addingTimeInterval(1)), c = item("c.png", at: t0.addingTimeInterval(2))
        [a, b, c].forEach { s.add($0) }
        let since = t0.addingTimeInterval(100)
        XCTAssertNil(UploadIntent.links(for: [a.id, b.id], provider: .s3, since: since, store: s), "hiçbiri yüklenmedi")
        s.setCloud(itemID: a.id, cloudObject(at: since.addingTimeInterval(1), link: "https://x/a"), provider: .s3)
        XCTAssertNil(UploadIntent.links(for: [a.id, b.id], provider: .s3, since: since, store: s), "biri eksik")
        s.setCloud(itemID: b.id, cloudObject(at: since.addingTimeInterval(2), link: "https://x/b"), provider: .s3)
        XCTAssertEqual(UploadIntent.links(for: [b.id, a.id], provider: .s3, since: since, store: s)?.map(\.absoluteString), ["https://x/b", "https://x/a"])
        XCTAssertEqual(UploadIntent.links(for: [a.id, UUID()], provider: .s3, since: since, store: s)?.count, 1, "raftan düşen öğe beklenmez")
        s.setCloud(itemID: c.id, cloudObject(at: since.addingTimeInterval(-60)), provider: .s3)
        XCTAssertNil(UploadIntent.links(for: [c.id], provider: .s3, since: since, store: s), "eski yükleme bu isteğin sonucu değil")
        s.setCloud(itemID: c.id, cloudObject(at: since.addingTimeInterval(3), link: nil), provider: .s3)
        XCTAssertEqual(UploadIntent.links(for: [a.id, c.id], provider: .s3, since: since, store: s)?.count, 1, "linksiz yükleme atlanır")
        XCTAssertNil(UploadIntent.links(for: [a.id], provider: .googleDrive, since: since, store: s), "başka sağlayıcı sayılmaz")
    }
    /// Başarısız deneme beklenmeden fark edilir; etkin deneme ve eski görevin önceki denemeleri hata sayılmaz; kaybolan görev linksizse hata.
    func testUploadFailureDetection() {
        let s = makeStore(); let a = item("a.png", at: t0); s.add(a)
        let since = t0.addingTimeInterval(100)
        var t = UploadTask(itemID: a.id, filePath: a.path, provider: .s3, remotePath: "a", access: .publicObject, purpose: .share, now: since)
        let watched = [t]
        XCTAssertFalse(UploadIntent.failed(watched, provider: .s3, since: since, queue: [t], activeTaskID: nil, store: s), "henüz denenmedi")
        t.attempts = 1
        XCTAssertTrue(UploadIntent.failed(watched, provider: .s3, since: since, queue: [t], activeTaskID: nil, store: s), "deneme başarısız")
        XCTAssertFalse(UploadIntent.failed(watched, provider: .s3, since: since, queue: [t], activeTaskID: t.id, store: s), "yeniden deneniyor")
        XCTAssertFalse(UploadIntent.failed([t], provider: .s3, since: since, queue: [t], activeTaskID: nil, store: s), "eski görevin önceki denemesi")
        XCTAssertTrue(UploadIntent.failed(watched, provider: .s3, since: since, queue: [], activeTaskID: nil, store: s), "görev link yazılmadan çıktı")
        s.setCloud(itemID: a.id, cloudObject(at: since.addingTimeInterval(1)), provider: .s3)
        XCTAssertFalse(UploadIntent.failed(watched, provider: .s3, since: since, queue: [], activeTaskID: nil, store: s), "başarıyla çıktı")
        XCTAssertFalse(UploadIntent.failed(watched, provider: .s3, since: since, queue: [], activeTaskID: nil, store: makeStore()), "raftan düşen öğe")
        XCTAssertEqual(UploadIntentError.failed.errorDescription, S.cloudBadgeFailed)
    }
    #endif
}
