import XCTest
@testable import Shotmori

final class RemovalActionTests: XCTestCase {
    func tempFile(_ name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("shotmori-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let u = dir.appendingPathComponent(name); try Data([0x89, 0x50, 0x4E, 0x47]).write(to: u); return u
    }
    func store() -> ShelfStore { ShelfStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("shelf-\(UUID()).json"), maxItems: 20) }

    func testRemoveFromShelfLeavesFileOnDisk() throws {
        let u = try tempFile("a.png"); let st = store()
        let it = ShelfItem(path: u.path, fileID: nil, capturedAt: Date()); st.add(it)
        RemoveFromShelfAction().perform(ActionContext(items: [it], anchorView: nil, store: st, panel: nil))
        XCTAssertTrue(st.items.isEmpty); XCTAssertTrue(FileManager.default.fileExists(atPath: u.path))
    }
    func testBulkRemoveAffectsOnlyGivenItems() throws {
        let st = store()
        let items = try (1...4).map { ShelfItem(path: try tempFile("f\($0).png").path, fileID: nil, capturedAt: Date()) }
        items.forEach { st.add($0) }
        let selected = [items[1], items[3]]
        XCTAssertEqual(RemoveFromShelfAction().menuTitle(for: selected), S.actionRemoveSelected(2))
        RemoveFromShelfAction().perform(ActionContext(items: selected, anchorView: nil, store: st, panel: nil))
        XCTAssertEqual(Set(st.items.map(\.id)), [items[0].id, items[2].id])
        items.forEach { XCTAssertTrue(FileManager.default.fileExists(atPath: $0.path)) }
    }
    func testCancellingTrashKeepsFileAndShelfEntry() throws {
        let u = try tempFile("keep.png"); let st = store()
        let it = ShelfItem(path: u.path, fileID: nil, capturedAt: Date()); st.add(it)
        let action = MoveToTrashAction(); var asked: [String] = []
        action.confirm = { asked = $0.map(\.fileName); return false }
        action.trash = { _ in XCTFail("iptalde çöpe taşıma çağrılmamalı") }
        action.perform(ActionContext(items: [it], anchorView: nil, store: st, panel: nil))
        XCTAssertEqual(asked, ["keep.png"]); XCTAssertEqual(st.items.count, 1); XCTAssertTrue(FileManager.default.fileExists(atPath: u.path))
    }
    func testConfirmedTrashMovesFileAndRemovesEntry() throws {
        let u = try tempFile("gone.png"); let st = store()
        let it = ShelfItem(path: u.path, fileID: nil, capturedAt: Date()); st.add(it)
        let bin = FileManager.default.temporaryDirectory.appendingPathComponent("fake-trash-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let action = MoveToTrashAction()
        action.confirm = { _ in true }
        action.trash = { src in try FileManager.default.moveItem(at: src, to: bin.appendingPathComponent(src.lastPathComponent)) }
        XCTAssertEqual(action.menuTitle(for: [it]), S.actionMoveToTrash)
        let done = expectation(description: "trash"); action.onFinished = { done.fulfill() }
        action.perform(ActionContext(items: [it], anchorView: nil, store: st, panel: nil))
        wait(for: [done], timeout: 10)
        XCTAssertTrue(st.items.isEmpty); XCTAssertFalse(FileManager.default.fileExists(atPath: u.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bin.appendingPathComponent("gone.png").path))
    }
    func testRemovedItemsDoNotReturnAfterReload() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-\(UUID()).json")
        let s1 = ShelfStore(fileURL: url, maxItems: 20)
        let a = ShelfItem(path: try tempFile("a.png").path, fileID: "1:1", capturedAt: Date()), b = ShelfItem(path: try tempFile("b.png").path, fileID: "1:2", capturedAt: Date())
        s1.add(a); s1.add(b); s1.remove(ids: [a.id])
        let s2 = ShelfStore(fileURL: url, maxItems: 20)
        XCTAssertEqual(s2.items.map(\.id), [b.id])
    }
}

/// Menü sırası: her kayıtlı eylem tam bir kez, Çöp ayrı son grupta, kopyala/paylaş/kaydet önce.
final class ActionMenuOrderTests: XCTestCase {
    func testMenuGroupsCoverEveryActionOnceWithTrashIsolated() {
        let reg = ActionRegistry(prefs: Preferences(defaults: UserDefaults(suiteName: "dev.shotmori.tests.menu")!))
        let flat = ActionRegistry.menuGroups.flatMap { $0 }
        XCTAssertEqual(flat.count, Set(flat).count, "yinelenen eylem")
        XCTAssertEqual(Set(flat).subtracting(["upload-drive", "upload-s3"]), Set(reg.all.map(\.id)), "kayıtlı eylemlerle menü grupları farklı (bulut eylemleri CloudCenter ile gelir)")
        XCTAssertEqual(ActionRegistry.menuGroups.first, ["copy-image", "share", "save-as"])
        XCTAssertEqual(ActionRegistry.menuGroups.last, ["move-to-trash"])
    }
}
