import XCTest
import AppKit
@testable import Shotmori

/// G4 denetim düzeltmeleri: panel, editör, Boyutlandır ve eylemler.
final class PanelAuditFixesTests: XCTestCase {
    private func tempDir(_ tag: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("\(tag)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private func samplePNG(in dir: URL, name: String = "Örnek.png") throws -> URL {
        let u = dir.appendingPathComponent(name)
        let img = NSImage(size: NSSize(width: 40, height: 30), flipped: false) { r in NSColor.systemTeal.setFill(); r.fill(); return true }
        try NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: u)
        return u
    }
    private func panel(_ suite: String) throws -> (ShelfStore, ShelfPanelController, URL) {
        let d = UserDefaults(suiteName: suite)!; d.removePersistentDomain(forName: suite)
        let prefs = Preferences(defaults: d); prefs.keepShelfOpen = false
        let store = ShelfStore(fileURL: nil, maxItems: 10)
        let dir = try tempDir("g4panel")
        return (store, ShelfPanelController(store: store, registry: ActionRegistry(prefs: prefs), prefs: prefs), dir)
    }

    // MARK: STORE-01 + A11Y-11 — kartta sağ tık, çift tık ve VoiceOver eylemleri
    func testPanelCardsWireContextMenuDoubleClickAndAccessibilityActions() throws {
        let (store, c, dir) = try panel("dev.shotmori.tests.g4.card")
        let a = try samplePNG(in: dir, name: "a.png"), b = try samplePNG(in: dir, name: "b.png")
        store.add(ShelfItem(path: a.path, fileID: nil, capturedAt: Date())); store.add(ShelfItem(path: b.path, fileID: nil, capturedAt: Date()))
        c.show(takeKey: false); defer { c.hide(reason: "test") }
        let views = c.itemViewsForTesting; XCTAssertEqual(views.count, 2)
        for v in views {
            XCTAssertNotNil(v.onContextMenu, "yüzen panelde sağ tık menüsü bağlı")
            XCTAssertNotNil(v.onDoubleClick, "yüzen panelde çift tık kopyalar")
            XCTAssertEqual(v.accessibilityCustomActions()?.map(\.name), [S.copyShort, S.actionRemoveFromShelf, S.moreActions])
        }
        let last = try XCTUnwrap(views.last)
        XCTAssertTrue(last.accessibilityPerformPress())
        XCTAssertEqual(c.selection, [last.item.id], "VoiceOver basma eylemi kartı tek seçer")
    }
    func testCardWithoutHandlersHasNoAccessibilityActions() throws {
        let v = ThumbnailItemView(item: ShelfItem(path: "/nonexistent/x.png", fileID: nil, capturedAt: Date()))
        XCTAssertFalse(v.accessibilityPerformPress())
        XCTAssertNil(v.accessibilityCustomActions())
    }

    // MARK: COR-04 — kayıp kartta da halka çizilir
    private func render(_ v: NSView) -> Data {
        let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds)!; v.cacheDisplay(in: v.bounds, to: rep)
        return rep.tiffRepresentation ?? Data()
    }
    func testMissingCardStillDrawsFocusRing() {
        let v = ThumbnailItemView(item: ShelfItem(path: "/nonexistent/kayip.png", fileID: nil, capturedAt: Date()))
        v.isMissing = true
        let plain = render(v)
        v.isKeyboardFocused = true
        XCTAssertNotEqual(render(v), plain, "kayıp kartta klavye odak halkası görünür (⌫ hangi kartı kaldıracağını gösterir)")
    }

    // MARK: PERF-07 + COR-14 — gizli panel yeniden kurulmaz; gösterimde güncel
    func testHiddenPanelDefersRebuildUntilShow() throws {
        let (store, c, dir) = try panel("dev.shotmori.tests.g4.hidden")
        XCTAssertFalse(c.isVisible); XCTAssertEqual(c.itemViewsForTesting.count, 0)
        store.add(ShelfItem(path: try samplePNG(in: dir).path, fileID: nil, capturedAt: Date()))
        c.reload(); c.setNeedsReload()
        XCTAssertEqual(c.itemViewsForTesting.count, 0, "gizliyken kartlar kurulmaz")
        c.show(takeKey: false); defer { c.hide(reason: "test") }
        XCTAssertEqual(c.itemViewsForTesting.count, 1, "gösterim bekleyen değişikliği çizer")
        store.add(ShelfItem(path: try samplePNG(in: dir, name: "iki.png").path, fileID: nil, capturedAt: Date()))
        XCTAssertEqual(c.itemViewsForTesting.count, 2, "görünürken depo gözlemcisi yeniden kurar")
    }

    // MARK: PERF-10 — favori düğmeleri seçim değişiminde yeniden kurulmaz
    func testFavoriteButtonsSurviveSelectionChanges() throws {
        let (store, c, dir) = try panel("dev.shotmori.tests.g4.favs")
        store.add(ShelfItem(path: try samplePNG(in: dir, name: "a.png").path, fileID: nil, capturedAt: Date()))
        store.add(ShelfItem(path: try samplePNG(in: dir, name: "b.png").path, fileID: nil, capturedAt: Date()))
        c.show(takeKey: false); defer { c.hide(reason: "test") }
        let before = c.favoriteButtonsForTesting.map(ObjectIdentifier.init)
        XCTAssertFalse(before.isEmpty)
        c.selectAll()
        XCTAssertEqual(c.favoriteButtonsForTesting.map(ObjectIdentifier.init), before, "seçimde düğmeler aynı nesne")
        let copy = try XCTUnwrap(c.favoriteButtonsForTesting.first { $0.identifier?.rawValue == "copy-image" })
        XCTAssertEqual(copy.title, S.copyShortCount(2), "Kopyala başlığı seçim sayısını izler")
    }

    // MARK: COR-13 — genişleyen panel sağ kenardan taşmaz
    func testClampedOriginKeepsPanelOnScreen() {
        let vis = NSRect(x: 0, y: 0, width: 1440, height: 900)
        XCTAssertEqual(ShelfPanelController.clampedOriginX(820, width: 660, visible: vis), 1440 - 660 - 8, "sağ kenara dayalı panel 612 → 660 olunca içeri çekilir")
        XCTAssertEqual(ShelfPanelController.clampedOriginX(100, width: 660, visible: vis), 100, "sığıyorsa yer değişmez")
        XCTAssertEqual(ShelfPanelController.clampedOriginX(-50, width: 660, visible: vis), 8, "sol kenar da taşmaz")
    }

    // MARK: EFF-22 — iç sürükleme yükü gidiş-dönüş
    func testDragWriterRoundTripKeepsIDsAndFileURL() throws {
        let pb = NSPasteboard(name: NSPasteboard.Name("dev.shotmori.test.drag.\(UUID())")); defer { pb.releaseGlobally() }
        let dir = try tempDir("g4drag"); let u = try samplePNG(in: dir)
        let ids = [UUID(), UUID()]
        pb.clearContents(); XCTAssertTrue(pb.writeObjects([ShelfDragWriter(base: u as NSURL, itemIDs: ids)]))
        XCTAssertEqual(ShelfDragWriter.itemIDs(from: pb), Set(ids))
        let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        XCTAssertEqual(urls?.map(\.standardizedFileURL), [u.standardizedFileURL], "dış sürükleme yükü (dosya URL'si) aynen korunur")
        let other = NSPasteboard(name: NSPasteboard.Name("dev.shotmori.test.drag.empty.\(UUID())")); defer { other.releaseGlobally() }
        other.clearContents(); other.setString("x", forType: .string)
        XCTAssertEqual(ShelfDragWriter.itemIDs(from: other), [], "iç tür yoksa boş küme")
    }

    // MARK: COR-18 — aynı metinli iki bildirim ayrı
    func testRepeatedStatusMessagesAreDistinct() {
        let a = StatusMessage(text: "Kopyalandı", kind: .success), b = StatusMessage(text: "Kopyalandı", kind: .success)
        XCTAssertNotEqual(a, b, "ilk mesajın zamanlayıcısı ikincisini kapatmaz")
        var s = StatusCenter(); s.show(a); s.show(b)
        XCTAssertNotEqual(s.current, a); XCTAssertEqual(s.current, b)
    }

    // MARK: PERF-09 — Düzenle/Boyutlandır uygunluğu dosyayı açmaz
    func testEditAvailabilityUsesTypeNotFileContents() throws {
        let dir = try tempDir("g4avail")
        let fakePNG = dir.appendingPathComponent("bozuk.png"); try Data([1, 2, 3]).write(to: fakePNG)
        let text = dir.appendingPathComponent("not.txt"); try Data("x".utf8).write(to: text)
        let edit = EditAction(), resize = ResizeAction()
        let png = ShelfItem(path: fakePNG.path, fileID: nil, capturedAt: Date()), txt = ShelfItem(path: text.path, fileID: nil, capturedAt: Date())
        XCTAssertTrue(edit.availability(for: [png]).isAvailable, "görüntü uzantısı yeter; çözülemezse hazırlanırken söylenir")
        XCTAssertTrue(resize.availability(for: [png]).isAvailable)
        XCTAssertEqual(edit.availability(for: [txt]).reason, S.reasonImagesOnly)
        XCTAssertEqual(resize.availability(for: [txt]).reason, S.reasonImagesOnly)
        XCTAssertEqual(edit.availability(for: [png, png]).isAvailable, false, "tek görüntü")
    }

    // MARK: COR-15 — ok tuşu kaydırması kenarda boyutu korur
    func testNudgeStopsAtEdgeKeepingSize() {
        let size = CGSize(width: 1000, height: 500)
        let r = CGRect(x: 995, y: 0, width: 5, height: 100)
        XCTAssertEqual(EditorCanvasView.nudged(r, by: CGPoint(x: 10, y: 0), in: size), r, "kenarda: yer ve boyut değişmez")
        XCTAssertEqual(EditorCanvasView.nudged(CGRect(x: 2, y: 2, width: 50, height: 50), by: CGPoint(x: -10, y: -10), in: size), CGRect(x: 0, y: 0, width: 50, height: 50))
        XCTAssertEqual(EditorCanvasView.nudged(CGRect(x: 10, y: 10, width: 50, height: 50), by: CGPoint(x: 1, y: 0), in: size), CGRect(x: 11, y: 10, width: 50, height: 50))
    }

    // MARK: COR-16 — oran değişimi seçilen oranı korur
    func testAspectFitKeepsRatioInsideImage() {
        let size = CGSize(width: 1000, height: 500)
        let sq = EditorCanvasView.fitAspect(CGRect(x: 0, y: 0, width: 1000, height: 200), ratio: 1, in: size)
        XCTAssertEqual(sq.width / sq.height, 1, accuracy: 0.001); XCTAssertLessThanOrEqual(sq.maxY, 500); XCTAssertEqual(sq, CGRect(x: 0, y: 0, width: 500, height: 500))
        let low = EditorCanvasView.fitAspect(CGRect(x: 100, y: 450, width: 160, height: 50), ratio: 16.0 / 9.0, in: size)
        XCTAssertEqual(low.height, 90, accuracy: 0.001); XCTAssertEqual(low.maxY, 500, accuracy: 0.001, "alttan taşan kırpma yukarı kayar")
        XCTAssertEqual(low.width, 160)
    }

    // MARK: COR-17 — seçim/araç değişimi çıktıyı eskitmez
    func testEditOutputSnapshotIgnoresSelection() {
        var s = EditState(); s.crop = CGRect(x: 0, y: 0, width: 10, height: 10); s.redactions = [CGRect(x: 1, y: 1, width: 2, height: 2)]
        var o = OutputSession<EditOutputSnapshot>(); o.begin(EditOutputSnapshot(s))
        var selected = s; selected.selectedRedaction = 0
        XCTAssertTrue(o.canDeliver(current: EditOutputSnapshot(selected)), "yalnız seçim değişti: teslim edilir")
        var moved = s; moved.redactions = [CGRect(x: 3, y: 3, width: 2, height: 2)]
        XCTAssertFalse(o.canDeliver(current: EditOutputSnapshot(moved)), "gizleme alanı değişti: eskidi")
    }

    // MARK: PERF-11 — tuvalde yalnız değişen alan yeniden çizilir
    func testCanvasInvalidationIsLocal() {
        var a = EditState(); a.redactions = [CGRect(x: 0, y: 0, width: 10, height: 10), CGRect(x: 100, y: 100, width: 10, height: 10)]
        var b = a; b.redactions[1] = CGRect(x: 110, y: 100, width: 10, height: 10)
        XCTAssertEqual(EditorCanvasView.invalidation(old: a, new: b), .rect(CGRect(x: 100, y: 100, width: 20, height: 10)))
        XCTAssertEqual(EditorCanvasView.invalidation(old: a, new: a), .none)
        var c = a; c.crop = CGRect(x: 0, y: 0, width: 50, height: 50)
        XCTAssertEqual(EditorCanvasView.invalidation(old: a, new: c), .full, "kırpma görünüp kaybolunca dış karartma her yeri etkiler")
        var d = c; d.crop = CGRect(x: 0, y: 0, width: 60, height: 50)
        XCTAssertEqual(EditorCanvasView.invalidation(old: c, new: d), .rect(CGRect(x: 0, y: 0, width: 60, height: 50)))
        var e = a; e.selectedRedaction = 0
        XCTAssertEqual(EditorCanvasView.invalidation(old: a, new: e), .rect(CGRect(x: 0, y: 0, width: 10, height: 10)), "seçim çerçevesi")
    }

    // MARK: COR-05 + COR-12 — Boyutlandır her kapanışta iptal ve `current` temizliği
    func testResizeWindowCloseClearsCurrent() throws {
        let dir = try tempDir("g4resize"); let u = try samplePNG(in: dir)
        let exp = expectation(description: "resize"); var wc: ResizeWindowController?
        ResizeWindowController.load(item: ShelfItem(path: u.path, fileID: nil, capturedAt: Date()), store: ShelfStore(fileURL: nil, maxItems: 5), panel: nil) { wc = $0; exp.fulfill() }
        wait(for: [exp], timeout: 5)
        let c = try XCTUnwrap(wc); ResizeWindowController.current = c
        c.window?.performClose(nil) // ✕ ile aynı yol
        XCTAssertNil(ResizeWindowController.current, "✕ sonrası üst şerit geri çekilebilir")
    }
    func testCancelledResizeModelDoesNotDeliver() throws {
        let dir = try tempDir("g4cancel"); let u = try samplePNG(in: dir)
        let m = ResizeModel(source: u, info: try XCTUnwrap(ImageResizer.sourceInfo(u)))
        let never = expectation(description: "teslim yok"); never.isInverted = true
        m.render { _ in never.fulfill() }
        m.cancel()
        wait(for: [never], timeout: 1)
        XCTAssertFalse(m.working, "iş bitince meşgul durumu kalkar")
    }
}
