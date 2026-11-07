import XCTest
@testable import Shotmori

final class ShelfStoreTests: XCTestCase {
    func makeStore(max: Int = 5, persist: Bool = false) -> ShelfStore {
        let url = persist ? FileManager.default.temporaryDirectory.appendingPathComponent("shelf-\(UUID().uuidString).json") : nil
        return ShelfStore(fileURL: url, maxItems: max)
    }
    func item(_ name: String, fid: String? = nil, at: Date = Date()) -> ShelfItem {
        ShelfItem(path: "/tmp/\(name)", fileID: fid, capturedAt: at, addedAt: at)
    }
    func testAddPutsNewestFirstAndDedupesByPathAndFileID() {
        let s = makeStore()
        XCTAssertTrue(s.add(item("a.png", fid: "1:1")))
        XCTAssertTrue(s.add(item("b.png", fid: "1:2")))
        XCTAssertFalse(s.add(item("a.png", fid: "1:9")), "aynı yol eklenmemeli")
        XCTAssertFalse(s.add(item("c.png", fid: "1:2")), "aynı dosya kimliği eklenmemeli")
        XCTAssertEqual(s.items.map(\.fileName), ["b.png", "a.png"])
    }
    /// Kaldırma izi izleyici yolunda kareyi geri getirmez; açık içe aktarma (`overrideDismissed`) izi siler ve ekler.
    func testOverrideDismissedReaddsRemovedItem() {
        let s = makeStore()
        let it = item("gelen.png", fid: "7:7", at: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertTrue(s.add(it))
        s.remove(ids: [it.id])
        let again = ShelfItem(path: it.path, fileID: it.fileID, capturedAt: it.capturedAt)
        XCTAssertFalse(s.add(again), "izleyici yolu: kaldırılan kare geri gelmez")
        XCTAssertTrue(s.add(again, overrideDismissed: true), "açık içe aktarma izi aşar")
        XCTAssertEqual(s.items.map(\.path), [it.path])
        XCTAssertFalse(s.state.dismissed.contains { $0.matches(again) }, "eşleşen iz silinir")
        // Temizlemeden sonra da aynı.
        s.clear()
        XCTAssertTrue(s.add([ShelfItem(path: it.path, fileID: it.fileID, capturedAt: it.capturedAt)], overrideDismissed: true).count == 1)
    }
    func testTrimsToMaxItems() {
        let s = makeStore(max: 3)
        for i in 0..<5 { s.add(item("\(i).png")) }
        XCTAssertEqual(s.items.count, 3)
        XCTAssertEqual(s.items.first?.fileName, "4.png")
    }
    /// Sınır düşürülünce her raf ayrı kırpılır; düşen kareler izlenir ve izleyici yolunda geri gelmez, açık içe aktarma getirir.
    func testSetMaxItemsTrimsEveryShelfAndDismisses() throws {
        let s = makeStore(max: 10); let b = try XCTUnwrap(s.addShelf()).id
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        for i in 0..<4 { s.add(item("a\(i).png", at: t0 + Double(i))) }
        for i in 0..<3 { s.add(item("b\(i).png", at: t0 + Double(i)), to: b) }
        var notified = 0; s.addObserver { notified += 1 }
        s.setMaxItems(2)
        XCTAssertEqual(s.maxItems, 2); XCTAssertEqual(notified, 1)
        XCTAssertEqual(s.shelves[0].items.map(\.fileName), ["a3.png", "a2.png"], "en yeniler kalır")
        XCTAssertEqual(s.shelves[1].items.map(\.fileName), ["b2.png", "b1.png"])
        XCTAssertEqual(Set(s.state.dismissed.map(\.path)), ["/tmp/a0.png", "/tmp/a1.png", "/tmp/b0.png"])
        s.setMaxItems(10)
        XCTAssertFalse(s.add(item("a0.png", at: t0)), "düşen kare izleyici yolunda geri gelmez")
        XCTAssertTrue(s.add(item("a0.png", at: t0), overrideDismissed: true))
    }
    /// Eş öğe: aynı yol ya da aynı dosya kimliği, raf fark etmeksizin.
    func testExistingItemMatchesPathOrFileIDAcrossShelves() throws {
        let s = makeStore(); let b = try XCTUnwrap(s.addShelf()).id
        let a = item("a.png", fid: "1:1"); s.add(a, to: b)
        XCTAssertEqual(s.existingItem(matching: item("a.png"))?.id, a.id)
        XCTAssertEqual(s.existingItem(matching: item("yeni-ad.png", fid: "1:1"))?.id, a.id, "yeniden adlandırılmış dosya")
        XCTAssertNil(s.existingItem(matching: item("b.png", fid: "1:2")))
        XCTAssertNil(s.existingItem(matching: item("c.png")), "kimliksiz öğe yalnız yolla eşleşir")
    }
    func testDroppedCountIfLowered() throws {
        let s = makeStore(max: 10); let b = try XCTUnwrap(s.addShelf()).id
        for i in 0..<7 { s.add(item("a\(i).png")) }
        for i in 0..<3 { s.add(item("b\(i).png"), to: b) }
        XCTAssertEqual(s.droppedCount(ifMaxItems: 5), 2, "7'lik raftan 2 düşer, 3'lük raf etkilenmez")
        XCTAssertEqual(s.droppedCount(ifMaxItems: 10), 0)
        XCTAssertEqual(s.allItems.count, 10, "yalnız hesaplar, listeyi değiştirmez")
    }
    func testHandoffHighlightsOnlyNewerItems() {
        let s = makeStore()
        let t0 = Date(timeIntervalSinceNow: -100)
        s.add(item("old.png", at: t0))
        s.markHandoff(at: Date(timeIntervalSinceNow: -50))
        s.add(item("new.png"))
        XCTAssertEqual(s.itemsSinceLastHandoff().map(\.fileName), ["new.png"])
    }
    func testRemoveAndClearDoNotTouchFiles() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("keep-\(UUID()).png")
        try Data([0x89, 0x50]).write(to: tmp)
        let s = makeStore()
        let it = ShelfItem(path: tmp.path, fileID: nil, capturedAt: Date())
        s.add(it); s.remove(ids: [it.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.path))
        s.add(it); s.clear()
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.path))
        XCTAssertTrue(s.items.isEmpty)
    }
    func testPersistenceRoundTrip() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-\(UUID().uuidString).json")
        let s1 = ShelfStore(fileURL: url, maxItems: 10)
        s1.add(item("x.png", fid: "2:2")); s1.markHandoff(); s1.startGroup(at: s1.items[0].id)
        let s2 = ShelfStore(fileURL: url, maxItems: 10)
        XCTAssertEqual(s2.items.count, 1)
        XCTAssertEqual(s2.items[0].fileID, "2:2")
        XCTAssertTrue(s2.items[0].startsGroup)
        XCTAssertNotNil(s2.activeShelf.lastHandoffAt)
    }
    func testPruneMissingDropsOnlyMissing() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("exists-\(UUID()).png")
        try Data([1]).write(to: tmp)
        let s = makeStore()
        s.add(ShelfItem(path: tmp.path, fileID: nil, capturedAt: Date()))
        s.add(item("ghost.png"))
        XCTAssertEqual(s.pruneMissing { _ in true }, 1)
        XCTAssertEqual(s.items.map(\.path), [tmp.path])
    }

    // MARK: Çoklu raf — model v2 ve göç
    private func tmpDir() throws -> URL { let d = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-v2-\(UUID())", isDirectory: true); try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); tempDirs.append(d); return d }
    func testMigratesV1FileToSingleShelf() throws {
        let dir = try tmpDir(); let url = dir.appendingPathComponent("shelf.json")
        try #"{"items":[{"id":"7B6D5D7E-6E3C-4B1A-9C1E-1F2A3B4C5D6E","path":"/tmp/x.png","capturedAt":"2026-10-18T08:48:00Z","addedAt":"2026-10-18T08:48:00Z","source":"screenshot"}],"lastHandoffAt":"2026-10-18T08:00:00Z"}"#.write(to: url, atomically: true, encoding: .utf8)
        let s = ShelfStore(fileURL: url, maxItems: 10)
        XCTAssertEqual(s.shelves.count, 1); XCTAssertEqual(s.shelves[0].name, S.shelfDefaultName(1)); XCTAssertEqual(s.items.count, 1)
        XCTAssertEqual(s.activeShelfID, s.shelves[0].id); XCTAssertNotNil(s.activeShelf.lastHandoffAt)
    }
    func testV1BackupWrittenOnceAndNeverOverwritten() throws {
        let dir = try tmpDir(); let url = dir.appendingPathComponent("shelf.json"); let bak = dir.appendingPathComponent("shelf-v1.bak.json")
        try #"{"items":[],"lastHandoffAt":null}"#.write(to: url, atomically: true, encoding: .utf8)
        let s = ShelfStore(fileURL: url, maxItems: 10); s.markHandoff()
        let first = try Data(contentsOf: bak); XCTAssertFalse(first.isEmpty)
        try "bozuk".write(to: bak, atomically: true, encoding: .utf8)
        let s2 = ShelfStore(fileURL: url, maxItems: 10); s2.markHandoff()
        XCTAssertEqual(try String(contentsOf: bak, encoding: .utf8), "bozuk", "yedek bir kez yazılır, üstüne yazılmaz")
    }
    func testV2RoundTripKeepsShelvesAndActive() throws {
        let dir = try tmpDir(); let url = dir.appendingPathComponent("shelf.json"); let s = ShelfStore(fileURL: url, maxItems: 10)
        let b = try XCTUnwrap(s.addShelf(name: "İş")); s.setActiveShelf(id: b.id)
        let s2 = ShelfStore(fileURL: url, maxItems: 10)
        XCTAssertEqual(s2.shelves.map(\.name), [S.shelfDefaultName(1), "İş"]); XCTAssertEqual(s2.activeShelfID, b.id); XCTAssertEqual(s2.state.version, 2)
    }
    /// Varsayılan raf adı kalıcı yazılmaz: numara saklanır, ad o anki dilde üretilir; eski dosyadaki "Raf N"/"Shelf N" varsayılan sayılır.
    func testDefaultShelfNameIsNotFrozenInFile() throws {
        let dir = try tmpDir(); let url = dir.appendingPathComponent("shelf.json"); let s = ShelfStore(fileURL: url, maxItems: 10)
        let b = try XCTUnwrap(s.addShelf()); _ = s.addShelf(name: "İş")
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let shelves = try XCTUnwrap(raw?["shelves"] as? [[String: Any]])
        XCTAssertEqual(shelves.map { $0["defaultNumber"] as? Int }, [1, 2, nil], "varsayılan raflar numarasıyla, özel ad numarasız")
        XCTAssertEqual(shelves[2]["name"] as? String, "İş")
        XCTAssertNil(s.shelves[1].customName); XCTAssertEqual(b.name, S.shelfDefaultName(2))
        let dec = JSONDecoder(); dec.dateDecodingStrategy = ShelfStore.dateDecoder
        func legacy(_ name: String) throws -> Shelf {
            try dec.decode(Shelf.self, from: Data(#"{"id":"7B6D5D7E-6E3C-4B1A-9C1E-1F2A3B4C5D6E","name":"\#(name)","createdAt":"2026-10-18T08:48:00Z","items":[]}"#.utf8))
        }
        XCTAssertEqual(try legacy("Shelf 3").name, S.shelfDefaultName(3), "eski İngilizce varsayılan ad o anki dilde")
        XCTAssertEqual(try legacy("Raf 2").name, S.shelfDefaultName(2))
        for custom in ["İş", "Raf", "Raf 02", "Shelf 1a", "Rafx 2"] { XCTAssertEqual(try legacy(custom).customName, custom) }
        XCTAssertEqual(Shelf.defaultNumber(inLegacyName: S.shelfDefaultName(7)), 7, "yerelleştirilmiş şablon göç kalıbıyla uyumlu")
        s.renameShelf(id: b.id, to: "Ev"); XCTAssertEqual(ShelfStore(fileURL: url, maxItems: 10).shelves[1].name, "Ev")
    }
    func testCorruptFileStartsWithOneEmptyShelf() throws {
        let dir = try tmpDir(); let url = dir.appendingPathComponent("shelf.json"); try "{".write(to: url, atomically: true, encoding: .utf8)
        let s = ShelfStore(fileURL: url, maxItems: 10); XCTAssertEqual(s.shelves.count, 1); XCTAssertTrue(s.items.isEmpty)
    }

    // MARK: Çoklu raf — işlemler
    func testAddGoesToActiveShelfAndDedupAcrossShelves() throws {
        let s = makeStore(); let b = try XCTUnwrap(s.addShelf()); s.setActiveShelf(id: b.id)
        XCTAssertTrue(s.add(item("a.png"))); XCTAssertEqual(s.activeShelf.items.count, 1); XCTAssertTrue(s.shelves[0].items.isEmpty)
        s.setActiveShelf(id: s.shelves[0].id); XCTAssertFalse(s.add(item("a.png")), "aynı yol başka rafta olsa da eklenmez")
    }
    func testMoveKeepsRelativeOrderAndPrependsToTarget() throws {
        let s = makeStore(); let b = try XCTUnwrap(s.addShelf()).id
        s.add(item("3.png")); s.add(item("2.png")); s.add(item("1.png")) // etkin: ilk raf; sıra 1,2,3
        s.add(item("old.png"), to: b)
        s.move(ids: Set(s.items.filter { $0.path.hasSuffix("1.png") || $0.path.hasSuffix("3.png") }.map(\.id)), to: b)
        XCTAssertEqual(s.shelves[1].items.map(\.fileName), ["1.png", "3.png", "old.png"]); XCTAssertEqual(s.shelves[0].items.map(\.fileName), ["2.png"])
        s.move(ids: Set(s.shelves[1].items.map(\.id)), to: b); XCTAssertEqual(s.shelves[1].items.map(\.fileName), ["1.png", "3.png", "old.png"], "aynı rafa taşıma no-op")
    }
    func testRemoveShelfLastIsNoopMoveOrDrop() throws {
        let s = makeStore(); s.removeShelf(id: s.shelves[0].id, movingItemsTo: nil); XCTAssertEqual(s.shelves.count, 1)
        let b = try XCTUnwrap(s.addShelf()).id; s.add(item("a.png"), to: b)
        s.removeShelf(id: b, movingItemsTo: s.shelves[0].id); XCTAssertEqual(s.shelves.count, 1); XCTAssertEqual(s.items.count, 1)
        let c = try XCTUnwrap(s.addShelf()).id; s.add(item("b.png"), to: c); s.removeShelf(id: c, movingItemsTo: nil); XCTAssertEqual(s.allItems.count, 1)
    }
    func testRemoveActiveShelfHandsActiveToNeighborBeforeAdd() throws {
        let s = makeStore(); let b = try XCTUnwrap(s.addShelf()).id; s.setActiveShelf(id: b)
        s.removeShelf(id: b, movingItemsTo: nil); XCTAssertEqual(s.activeShelfID, s.shelves[0].id)
        XCTAssertTrue(s.add(item("n.png"))); XCTAssertEqual(s.items.count, 1)
    }
    func testCloudUpdateFindsItemInAnyShelf() throws {
        let s = makeStore(); let b = try XCTUnwrap(s.addShelf()).id; s.add(item("a.png"), to: b); let id = s.shelves[1].items[0].id
        s.setCloud(itemID: id, CloudObject(provider: .s3, remoteID: "k", remotePath: "k", link: nil, access: .publicObject, uploadedAt: Date(), size: 1, checksum: nil), provider: .s3)
        XCTAssertEqual(s.shelf(containing: id)?.items.first?.cloud.count, 1)
        s.markLocalTrashed(itemID: id); XCTAssertTrue(s.shelves[1].items[0].localTrashed)
        s.remove(path: "/tmp/a.png"); XCTAssertTrue(s.shelves[1].items.isEmpty)
    }
    func testLimitsAndNewCount() {
        let s = makeStore(max: 2); for _ in 0..<7 { XCTAssertNotNil(s.addShelf()) }; XCTAssertNil(s.addShelf(), "8'de sınır")
        s.renameShelf(id: s.shelves[0].id, to: String(repeating: "a", count: 40)); XCTAssertEqual(s.shelves[0].name.count, 24)
        s.renameShelf(id: s.shelves[0].id, to: "  "); XCTAssertEqual(s.shelves[0].name.count, 24, "boş ad eskiyi korur")
        s.add(item("1.png")); s.add(item("2.png")); s.add(item("3.png")); XCTAssertEqual(s.items.count, 2, "raf başına maxItems")
        s.add(item("4.png"), to: s.shelves[1].id); XCTAssertEqual(s.newCountAll, 3)
        s.markHandoff(); XCTAssertEqual(s.newCountAll, 1, "handoff raf başına")
    }

    func testMigrationPersistsV2ImmediatelyWithBackup() throws {
        let dir = try tmpDir(); let url = dir.appendingPathComponent("shelf.json")
        try #"{"items":[],"lastHandoffAt":null}"#.write(to: url, atomically: true, encoding: .utf8)
        _ = ShelfStore(fileURL: url, maxItems: 10)
        let d = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        XCTAssertEqual(d?["version"] as? Int, 2, "açılışta v2 yazılır"); XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("shelf-v1.bak.json").path))
    }

    // MARK: Son inceleme düzeltmeleri
    func testRemoveShelfDroppingOnlySnapshotMovesLateArrivalsToNeighbor() throws {
        let s = makeStore(); let b = try XCTUnwrap(s.addShelf()).id; s.setActiveShelf(id: b)
        s.add(item("old.png")); let snapshot = Set(s.items.map(\.id))   // dialog açıldığı andaki öğeler
        s.add(item("late.png"))                                            // dialog açıkken gelen kare
        s.removeShelf(id: b, movingItemsTo: nil, droppingOnly: snapshot)
        XCTAssertEqual(s.shelves.count, 1); XCTAssertEqual(s.allItems.map(\.fileName), ["late.png"], "sonradan gelen komşuya taşınır, anlık görüntüdekiler düşer")
    }
    func testV1FileIsNotOverwrittenWhenBackupCannotBeWritten() throws {
        let dir = try tmpDir(); let url = dir.appendingPathComponent("shelf.json")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("shelf-v1.bak.json"), withIntermediateDirectories: true) // yedek yolu yazılamaz (dizin)
        try #"{"items":[],"lastHandoffAt":null}"#.write(to: url, atomically: true, encoding: .utf8)
        let s = ShelfStore(fileURL: url, maxItems: 10); s.markHandoff()
        let d = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        XCTAssertNil(d?["version"], "yedek yazılamadıysa v1 dosyası ezilmez")
    }

    // MARK: İnceleme sonrası küçük düzeltmeler
    func testRemoveShelfReportsTrimmedCountWhenTargetOverflows() throws {
        let s = makeStore(max: 2); let b = try XCTUnwrap(s.addShelf()).id
        s.add(item("a1.png")); s.add(item("a2.png")); s.add(item("b1.png"), to: b); s.add(item("b2.png"), to: b)
        XCTAssertEqual(s.removeShelf(id: b, movingItemsTo: s.shelves[0].id), 2, "hedef 2+2 → 2, kırpılan 2 bildirilir")
        XCTAssertEqual(s.items.map(\.fileName), ["b2.png", "b1.png"])
        let c = try XCTUnwrap(s.addShelf()).id
        XCTAssertEqual(s.removeShelf(id: c, movingItemsTo: s.shelves[0].id), 0, "boş raf: kırpma yok")
    }
    func testMoveReportsTrimmedCountWhenTargetOverflows() throws {
        let s = makeStore(max: 2); let b = try XCTUnwrap(s.addShelf()).id
        s.add(item("a1.png")); s.add(item("a2.png")); s.add(item("b1.png"), to: b); s.add(item("b2.png"), to: b)
        XCTAssertEqual(s.move(ids: Set(s.items.map(\.id)), to: b), 2)
        XCTAssertEqual(s.shelves[1].items.map(\.fileName), ["a2.png", "a1.png"])
        XCTAssertEqual(s.move(ids: [], to: b), 0, "taşınacak yoksa 0")
    }
    func testAddShelfPicksSmallestUnusedDefaultNumber() throws {
        let s = makeStore()
        let b = try XCTUnwrap(s.addShelf()); XCTAssertEqual(b.name, S.shelfDefaultName(2))
        let c = try XCTUnwrap(s.addShelf()); XCTAssertEqual(c.name, S.shelfDefaultName(3))
        s.removeShelf(id: b.id, movingItemsTo: nil)
        XCTAssertEqual(try XCTUnwrap(s.addShelf()).name, S.shelfDefaultName(2), "kapatılan 2 yeniden kullanılır, ikinci Raf 3 olmaz")
        XCTAssertEqual(s.shelves.map(\.name), [S.shelfDefaultName(1), S.shelfDefaultName(3), S.shelfDefaultName(2)])
        XCTAssertEqual(try XCTUnwrap(s.addShelf()).name, S.shelfDefaultName(4))
    }

    // MARK: Konteyner göçü (sandbox): Shotmori'nin kendi klasöründeki yollar konteynere bağlanır
    func testRebaseRewritesOnlyOldRootPaths() {
        let s = makeStore()
        s.add(ShelfItem(path: "/U/Library/Application Support/Shotmori/Türevler/a.png", fileID: nil, capturedAt: Date(), source: .derivative))
        s.add(ShelfItem(path: "/U/Desktop/b.png", fileID: nil, capturedAt: Date()))
        XCTAssertEqual(s.rebasePaths(from: "/U/Library/Application Support/Shotmori", to: "/C/Data/Library/Application Support/Shotmori"), 1)
        XCTAssertEqual(Set(s.allItems.map(\.path)), ["/C/Data/Library/Application Support/Shotmori/Türevler/a.png", "/U/Desktop/b.png"])
    }
    func testRebaseIgnoresSiblingPrefix() {
        let s = makeStore()
        s.add(ShelfItem(path: "/U/Library/Application Support/Shotmori2/x.png", fileID: nil, capturedAt: Date()))
        XCTAssertEqual(s.rebasePaths(from: "/U/Library/Application Support/Shotmori", to: "/C"), 0)
        XCTAssertEqual(s.allItems.first?.path, "/U/Library/Application Support/Shotmori2/x.png")
    }
    func testRebaseSameRootIsNoOp() {
        let s = makeStore(); s.add(item("a.png"))
        XCTAssertEqual(s.rebasePaths(from: "/tmp", to: "/tmp"), 0)
    }
    func testRebasePersists() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let s = ShelfStore(fileURL: url, maxItems: 5)
        s.add(ShelfItem(path: "/old/Shotmori/Pano/p.png", fileID: nil, capturedAt: Date(), source: .clipboard))
        _ = s.rebasePaths(from: "/old/Shotmori", to: "/new/Shotmori")
        XCTAssertEqual(ShelfStore(fileURL: url, maxItems: 5).allItems.first?.path, "/new/Shotmori/Pano/p.png")
    }

    // MARK: Dayanıklılık (Görev 2)
    private var tempDirs: [URL] = []
    override func tearDown() {
        for d in tempDirs { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: d.path); try? FileManager.default.removeItem(at: d) }
        tempDirs = []; super.tearDown()
    }
    private func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("shelfdir-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); return d
    }
    func testCorruptFileIsBackedUpNotOverwritten() throws {
        let d = try tempDir(); let u = d.appendingPathComponent("shelf.json")
        try Data("{bozuk".utf8).write(to: u)
        let s = ShelfStore(fileURL: u, maxItems: 5)
        s.add(item("a.png"))
        let names = try FileManager.default.contentsOfDirectory(atPath: d.path)
        let bak = try XCTUnwrap(names.first { $0.hasPrefix(ShelfStore.corruptBackupPrefix) })
        XCTAssertEqual(try String(contentsOf: d.appendingPathComponent(bak), encoding: .utf8), "{bozuk")
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(contentsOf: u)))
    }
    func testOneUndecodableItemDoesNotDropTheShelf() throws {
        let d = try tempDir(); let u = d.appendingPathComponent("shelf.json")
        let shid = UUID()
        func it(_ n: String, _ src: String) -> String { "{\"id\":\"\(UUID().uuidString)\",\"path\":\"/tmp/\(n)\",\"capturedAt\":\"2026-10-21T10:00:00Z\",\"addedAt\":\"2026-10-21T10:00:00Z\",\"source\":\"\(src)\"}" }
        let json = "{\"version\":2,\"activeShelfID\":\"\(shid)\",\"shelves\":[{\"id\":\"\(shid)\",\"name\":\"Çalışma\",\"createdAt\":\"2026-10-21T10:00:00Z\",\"items\":[\(it("a.png", "screenshot")),\(it("b.png", "gelecek"))]}]}"
        try Data(json.utf8).write(to: u)
        let s = ShelfStore(fileURL: u, maxItems: 5)
        XCTAssertEqual(s.items.count, 1); XCTAssertEqual(s.activeShelf.name, "Çalışma")
    }
    func testSubSecondAddedAtSurvivesReload() throws {
        let d = try tempDir(); let u = d.appendingPathComponent("shelf.json")
        let s = ShelfStore(fileURL: u, maxItems: 5)
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        s.markHandoff(at: t); s.add(item("n.png", at: t.addingTimeInterval(0.3)))
        let r = ShelfStore(fileURL: u, maxItems: 5)
        XCTAssertEqual(r.itemsSinceLastHandoff().count, 1)
    }
    func testWholeSecondLegacyDatesStillLoad() throws {
        let d = try tempDir(); let u = d.appendingPathComponent("shelf.json")
        let v1 = "{\"items\":[{\"id\":\"\(UUID().uuidString)\",\"path\":\"/tmp/x.png\",\"capturedAt\":\"2026-10-21T10:00:00Z\",\"addedAt\":\"2026-10-21T10:00:00Z\",\"source\":\"screenshot\"}],\"lastHandoffAt\":\"2026-10-21T09:00:00Z\"}"
        try Data(v1.utf8).write(to: u)
        XCTAssertEqual(ShelfStore(fileURL: u, maxItems: 5).items.count, 1)
    }
    func testBatchAddPersistsAndNotifiesOnce() throws {
        let u = try tempDir().appendingPathComponent("shelf.json")
        let s = ShelfStore(fileURL: u, maxItems: 5); var n = 0
        s.addObserver { n += 1 }
        XCTAssertEqual(s.add([item("a.png"), item("b.png"), item("c.png")]).count, 3)
        XCTAssertEqual(n, 1)
        let reopened = ShelfStore(fileURL: u, maxItems: 5)
        XCTAssertEqual(Set(reopened.items.map(\.fileName)), ["a.png", "b.png", "c.png"])
        XCTAssertEqual(s.add([item("a.png"), item("d.png")]).map(\.fileName), ["d.png"])
    }
    func testClearOnlyRemovesSnapshotIDs() {
        let s = makeStore()
        s.add(item("a.png")); s.add(item("b.png"))
        let snap = Set(s.items.map(\.id))
        s.add(item("c.png"))
        s.clear(shelfID: nil, onlyIDs: snap)
        XCTAssertEqual(s.items.map(\.fileName), ["c.png"])
    }
    func testPruneSkipsItemsOutsideCoveredScopes() {
        let s = makeStore()
        s.add(ShelfItem(path: "/kapsam/yok1.png", fileID: nil, capturedAt: Date()))
        s.add(ShelfItem(path: "/baska/yok2.png", fileID: nil, capturedAt: Date()))
        XCTAssertEqual(s.pruneMissing { $0.path.hasPrefix("/kapsam/") }, 1)
        XCTAssertEqual(s.items.map(\.path), ["/baska/yok2.png"])
    }
    private func backups(_ d: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: d.path).filter { $0.hasPrefix(ShelfStore.corruptBackupPrefix) }
    }
    func testReopenAfterCorruptBackupDoesNotCreateSecondBackup() throws {
        let d = try tempDir(); let u = d.appendingPathComponent("shelf.json")
        try Data("{bozuk".utf8).write(to: u)
        let s = ShelfStore(fileURL: u, maxItems: 5); s.add(item("a.png"))
        _ = ShelfStore(fileURL: u, maxItems: 5)
        XCTAssertEqual(try backups(d).count, 1)
    }
    func testUnknownCloudProviderKeepsItemAndBacksUpOriginal() throws {
        let d = try tempDir(); let u = d.appendingPathComponent("shelf.json"); let shid = UUID()
        let json = "{\"version\":2,\"activeShelfID\":\"\(shid)\",\"shelves\":[{\"id\":\"\(shid)\",\"name\":\"R\",\"createdAt\":\"2026-10-21T10:00:00Z\",\"items\":[{\"id\":\"\(UUID().uuidString)\",\"path\":\"/tmp/a.png\",\"capturedAt\":\"2026-10-21T10:00:00Z\",\"addedAt\":\"2026-10-21T10:00:00Z\",\"source\":\"screenshot\",\"cloud\":[{\"provider\":\"gelecek-saglayici\"}]}]}]}"
        try Data(json.utf8).write(to: u)
        let s = ShelfStore(fileURL: u, maxItems: 5)
        XCTAssertEqual(s.items.count, 1); XCTAssertTrue(s.items[0].cloud.isEmpty)
        let b = try backups(d); XCTAssertEqual(b.count, 1)
        XCTAssertEqual(try String(contentsOf: d.appendingPathComponent(b[0]), encoding: .utf8), json)
        s.add(item("b.png")); _ = ShelfStore(fileURL: u, maxItems: 5)
        XCTAssertEqual(try backups(d).count, 1, "yeniden açılışta ikinci yedek yok")
    }
    func testFailedBackupBlocksSavingAndKeepsCorruptFile() throws {
        let d = try tempDir(); let u = d.appendingPathComponent("shelf.json")
        try Data("{bozuk".utf8).write(to: u)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: d.path) // yeniden adlandırma başarısız
        let s = ShelfStore(fileURL: u, maxItems: 5)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: d.path) // yazma artık mümkün; yalnız persistBlocked engelleyebilir
        s.add(item("a.png"))
        XCTAssertEqual(try String(contentsOf: u, encoding: .utf8), "{bozuk", "tek kopya ezilmemeli")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: d.path), ["shelf.json"], "yedek/başka dosya yazılmamalı")
    }
    // MARK: Konteyner temizliği ve eksik yükleme (Görev 9 düzeltme)
    func testCorruptLoadDisablesJanitorThisLaunchAndBackupPathsProtectedNext() throws {
        let d = try tempDir(); let u = d.appendingPathComponent("shelf.json")
        try Data("{\"version\":2,\"shelves\":[{\"items\":[{\"path\":\"/kap/T\\u00fcrevler/a.png\",\"x\":1},{\"path\":\"/kap/Pano/b.png\"},{\"path\":\"/kap/Pano/kes".utf8).write(to: u) // kesik JSON
        let s = ShelfStore(fileURL: u, maxItems: 5)
        XCTAssertTrue(s.loadWasDegraded); XCTAssertNil(s.janitorReferences(), "bozuk yüklemede temizlik yapılmamalı")
        s.add(ShelfItem(path: "/kap/Pano/yeni.png", fileID: nil, capturedAt: Date()))
        let next = ShelfStore(fileURL: u, maxItems: 5)
        XCTAssertFalse(next.loadWasDegraded)
        XCTAssertEqual(next.janitorReferences(), ["/kap/Pano/yeni.png", "/kap/Türevler/a.png", "/kap/Pano/b.png"], "yedekteki yollar korunur")
    }
    func testPartiallyDecodedLoadDisablesJanitor() throws {
        let d = try tempDir(); let u = d.appendingPathComponent("shelf.json"); let shid = UUID()
        func it(_ n: String, _ src: String) -> String { "{\"id\":\"\(UUID().uuidString)\",\"path\":\"/kap/Pano/\(n)\",\"capturedAt\":\"2026-10-21T10:00:00Z\",\"addedAt\":\"2026-10-21T10:00:00Z\",\"source\":\"\(src)\"}" }
        try Data("{\"version\":2,\"activeShelfID\":\"\(shid)\",\"shelves\":[{\"id\":\"\(shid)\",\"name\":\"R\",\"createdAt\":\"2026-10-21T10:00:00Z\",\"items\":[\(it("a.png", "screenshot")),\(it("b.png", "gelecek"))]}]}".utf8).write(to: u)
        let s = ShelfStore(fileURL: u, maxItems: 5)
        XCTAssertEqual(s.items.count, 1); XCTAssertTrue(s.loadWasDegraded); XCTAssertNil(s.janitorReferences())
        XCTAssertNil(ShelfStore(fileURL: u, maxItems: 5).janitorReferences(), "dosya yeniden yazılana dek her açılış eksik yükler")
        s.add(ShelfItem(path: "/kap/Pano/c.png", fileID: nil, capturedAt: Date())) // dosya yeniden yazılır; atlanan öğe yalnız yedekte
        XCTAssertEqual(ShelfStore(fileURL: u, maxItems: 5).janitorReferences(), ["/kap/Pano/a.png", "/kap/Pano/b.png", "/kap/Pano/c.png"], "atlanan öğenin yolu yedekten korunur")
    }
    func testBlockedSaveAndUnreadableBackupDisableJanitor() throws {
        let d = try tempDir(); let u = d.appendingPathComponent("shelf.json")
        try Data("{bozuk".utf8).write(to: u)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: d.path)
        let s = ShelfStore(fileURL: u, maxItems: 5)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: d.path)
        XCTAssertTrue(s.loadWasDegraded); XCTAssertNil(s.janitorReferences())
        let e = try tempDir(); let v = e.appendingPathComponent("shelf.json")
        try Data([0xFF, 0xFE, 0x00]).write(to: e.appendingPathComponent("\(ShelfStore.corruptBackupPrefix)x.json"))
        let t = ShelfStore(fileURL: v, maxItems: 5)
        XCTAssertFalse(t.loadWasDegraded); XCTAssertNil(t.janitorReferences(), "okunamayan yedek varken temizlik yapılmamalı")
    }
    func testHealthyLoadGivesShelfPathsToJanitor() throws {
        let u = try tempDir().appendingPathComponent("shelf.json")
        ShelfStore(fileURL: u, maxItems: 5).add(ShelfItem(path: "/kap/Pano/a.png", fileID: nil, capturedAt: Date()))
        let s = ShelfStore(fileURL: u, maxItems: 5)
        XCTAssertFalse(s.loadWasDegraded); XCTAssertEqual(s.janitorReferences(), ["/kap/Pano/a.png"])
    }
    func testBatchAddDoesNotReturnTrimmedItems() {
        let s = makeStore(max: 2)
        let r = s.add([item("a.png"), item("b.png"), item("c.png")])
        XCTAssertEqual(r.count, 2); XCTAssertEqual(Set(r.map(\.id)), Set(s.items.map(\.id)))
    }
    func testClearWithNoMatchDoesNotNotify() {
        let s = makeStore(); s.add(item("a.png")); var n = 0; s.addObserver { n += 1 }
        s.clear(shelfID: nil, onlyIDs: [UUID()])
        XCTAssertEqual(n, 0)
    }

    // MARK: Kaldırılanlar geri gelmez (Görev 3)
    func testRemovedItemIsNotReAdded() {
        let s = makeStore(); let t = Date()
        let a = item("a.png", fid: "1:1", at: t)
        XCTAssertTrue(s.add(a)); s.remove(ids: [a.id])
        XCTAssertFalse(s.add(item("a.png", fid: "1:1", at: t)), "kaldırılan kare aynı yol+tarihle geri gelmemeli")
        XCTAssertTrue(s.add(item("a.png", fid: "1:7", at: t.addingTimeInterval(30))), "aynı yolda yeni kare (farklı tarih) eklenmeli")
    }
    func testExternalRemovalDoesNotBlockReturn() {
        let s = makeStore(); let t = Date()
        let a = item("a.png", fid: "1:1", at: t)
        XCTAssertTrue(s.add(a)); s.remove(path: a.path)
        XCTAssertTrue(s.items.isEmpty)
        XCTAssertTrue(s.add(item("a.png", fid: "1:1", at: t)), "dışarıda silinip geri konan (Çöp › Geri koy) kare yeniden eklenmeli")
    }
    func testOneUndecodableDismissedKeyKeepsTheRest() throws {
        let d = try tempDir(); let u = d.appendingPathComponent("shelf.json"); let shid = UUID()
        func key(_ n: String, _ at: String) -> String { "{\"path\":\"/tmp/\(n)\",\"fileID\":\"1:\(n)\",\"capturedAt\":\"\(at)\"}" }
        let json = "{\"version\":2,\"activeShelfID\":\"\(shid)\",\"shelves\":[{\"id\":\"\(shid)\",\"name\":\"R\",\"createdAt\":\"2026-10-21T10:00:00Z\",\"items\":[]}],\"dismissed\":[\(key("a.png", "2026-10-21T10:00:00Z")),\(key("b.png", "bozuk-tarih")),\(key("c.png", "2026-10-21T10:05:00Z"))]}"
        try Data(json.utf8).write(to: u)
        let s = ShelfStore(fileURL: u, maxItems: 5)
        XCTAssertEqual(s.state.dismissed.count, 2, "okunamayan tek anahtar atlanır, kalanlar korunur")
        let f = ISO8601DateFormatter()
        XCTAssertFalse(s.add(ShelfItem(path: "/tmp/a.png", fileID: "1:a.png", capturedAt: f.date(from: "2026-10-21T10:00:00Z")!)))
        XCTAssertFalse(s.add(ShelfItem(path: "/tmp/c.png", fileID: "1:c.png", capturedAt: f.date(from: "2026-10-21T10:05:00Z")!)))
        XCTAssertEqual(try backups(d).count, 1, "kayıp sayılır, özgün dosya yedeklenir")
    }
    func testPartialDecodeBackupIsNotDuplicatedAcrossLaunches() throws {
        let d = try tempDir(); let u = d.appendingPathComponent("shelf.json"); let shid = UUID()
        func it(_ n: String, _ src: String) -> String { "{\"id\":\"\(UUID().uuidString)\",\"path\":\"/tmp/\(n)\",\"capturedAt\":\"2026-10-21T10:00:00Z\",\"addedAt\":\"2026-10-21T10:00:00Z\",\"source\":\"\(src)\"}" }
        try Data("{\"version\":2,\"activeShelfID\":\"\(shid)\",\"shelves\":[{\"id\":\"\(shid)\",\"name\":\"R\",\"createdAt\":\"2026-10-21T10:00:00Z\",\"items\":[\(it("a.png", "screenshot")),\(it("b.png", "gelecek"))]}]}".utf8).write(to: u)
        for _ in 0..<3 { XCTAssertTrue(ShelfStore(fileURL: u, maxItems: 5).loadWasDegraded, "eksik yükleme her açılışta bildirilir") }
        XCTAssertEqual(try backups(d).count, 1, "aynı özgün için tek yedek")
    }
    func testDismissedSurvivesReloadAndCapsAt500() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-\(UUID().uuidString).json")
        let s = ShelfStore(fileURL: url, maxItems: 1000); let t = Date()
        var all: [ShelfItem] = []
        for i in 0..<510 { all.append(item("d\(i).png", at: t.addingTimeInterval(Double(i) * 10))) }
        s.add(all); s.clear()
        XCTAssertEqual(s.state.dismissed.count, 500)
        let s2 = ShelfStore(fileURL: url, maxItems: 1000)
        XCTAssertEqual(s2.state.dismissed.count, 500)
        XCTAssertFalse(s2.add(all[509]), "yeniden açılışta da geri gelmemeli")
        XCTAssertTrue(s2.add(all[0]), "en eski 10 anahtar düşer")
    }
    func testOldJSONWithoutDismissedLoadsEmpty() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-\(UUID().uuidString).json")
        let s = ShelfStore(fileURL: url, maxItems: 5); s.add(item("a.png"))
        var obj = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        obj["dismissed"] = nil
        try JSONSerialization.data(withJSONObject: obj).write(to: url)
        XCTAssertEqual(ShelfStore(fileURL: url, maxItems: 5).state.dismissed, [])
    }
    func testTrimmedItemsAreDismissed() {
        let s = makeStore(max: 2); let t = Date()
        let a = item("a.png", at: t), b = item("b.png", at: t.addingTimeInterval(10)), c = item("c.png", at: t.addingTimeInterval(20))
        s.add(a); s.add(b); s.add(c)
        XCTAssertEqual(s.items.count, 2)
        XCTAssertFalse(s.add(a), "kırpmayla düşen kare geri gelmemeli")
    }
    func testUpdatePathKeepsShelfAndGroup() {
        let s = makeStore(); let sh2 = s.addShelf()!; let t = Date()
        let x = item("x.png", fid: "1:1", at: t), y = item("y.png", fid: "1:2", at: t.addingTimeInterval(5))
        s.add(x, to: sh2.id); s.add(y, to: sh2.id); s.startGroup(at: x.id)
        s.updatePath(itemID: x.id, to: "/tmp/renamed.png")
        let sh = s.shelves.first { $0.id == sh2.id }!
        XCTAssertEqual(sh.items.map(\.fileName), ["y.png", "renamed.png"])
        XCTAssertTrue(sh.items[1].startsGroup)
        XCTAssertEqual(sh.items[1].id, x.id)
        XCTAssertEqual(s.allItems.count, 2)
    }
}
