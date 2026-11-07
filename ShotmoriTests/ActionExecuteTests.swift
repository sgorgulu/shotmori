import XCTest
@testable import Shotmori

/// X-03: eylemlerin tek yürütme noktası `ActionRegistry.execute` (uygunluk → perform).
final class ActionExecuteTests: XCTestCase {
    /// `perform` çağrılarını sayan casus eylem; uygunluk dışarıdan verilir.
    final class SpyAction: ShelfAction {
        let id: String; let title = "Casus"; let symbolName = "star"; let permission = ActionPermissionClass.localFile
        var available: ActionAvailability = .available
        var performed = 0
        init(id: String = "spy") { self.id = id }
        func availability(for items: [ShelfItem]) -> ActionAvailability { available }
        func perform(_ ctx: ActionContext) { performed += 1 }
    }

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private var suite = ""
    private var prefs: Preferences!
    override func setUp() {
        suite = "dev.shotmori.tests.execute.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!; d.removePersistentDomain(forName: suite); prefs = Preferences(defaults: d)
    }
    override func tearDown() { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

    private func ctx(_ store: ShelfStore) -> ActionContext {
        ActionContext(items: [ShelfItem(path: "/tmp/x.png", fileID: nil, capturedAt: t0)], anchorView: nil, store: store, panel: nil)
    }

    func testRunsAvailableAction() {
        let spy = SpyAction()
        let reg = ActionRegistry(prefs: prefs, actions: [spy])
        XCTAssertEqual(reg.execute(spy, ctx: ctx(ShelfStore(fileURL: nil, maxItems: 5))), .ran)
        XCTAssertEqual(spy.performed, 1)
        XCTAssertEqual(reg.execute("spy", ctx: ctx(ShelfStore(fileURL: nil, maxItems: 5))), .ran)
        XCTAssertEqual(spy.performed, 2)
    }

    func testUnavailableActionDoesNotRun() {
        let spy = SpyAction(); spy.available = .unavailable(reason: "neden")
        let reg = ActionRegistry(prefs: prefs, actions: [spy])
        XCTAssertEqual(reg.execute("spy", ctx: ctx(ShelfStore(fileURL: nil, maxItems: 5))), .unavailable("neden"))
        XCTAssertEqual(spy.performed, 0)
        let (a, r) = reg.authorize("spy", items: [])
        XCTAssertTrue(a === spy); XCTAssertEqual(r, .unavailable("neden"))
    }

    func testUnknownID() {
        let reg = ActionRegistry(prefs: prefs, actions: [SpyAction()])
        XCTAssertEqual(reg.execute("yok", ctx: ctx(ShelfStore(fileURL: nil, maxItems: 5))), .unknown)
        XCTAssertNil(reg.authorize("yok", items: []).0)
    }

    /// Bağlam/"…" menüsü hedefi uygunluğu atlamaz (X-03).
    func testMenuTargetHonorsAvailability() {
        let spy = SpyAction()
        let reg = ActionRegistry(prefs: prefs, actions: [spy])
        let store = ShelfStore(fileURL: nil, maxItems: 5)
        func runMenu() {
            let mi = NSMenuItem(); mi.representedObject = ActionInvocation(action: spy, ctx: ctx(store), registry: reg)
            ActionMenuTarget.shared.run(mi)
        }
        spy.available = .unavailable(reason: "eksik")
        runMenu(); XCTAssertEqual(spy.performed, 0, "uygunsuz eylem")
        spy.available = .available
        runMenu(); XCTAssertEqual(spy.performed, 1)
    }

    /// Değişmez denetimi: uygulama kaynaklarında eyleme bağlam veren tek `perform` çağrısı `ActionRegistry.execute` gövdesindedir.
    /// Yeni bir doğrudan yürütme yolu (`.perform(ActionContext(`, `.perform(inv.ctx)`, `.perform(ctx)`) eklenirse test kırılır.
    func testSinglePerformCallSite() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Shotmori", isDirectory: true)
        let pattern = try NSRegularExpression(pattern: #"\.perform\(\s*(ActionContext\(|(inv\.)?ctx\s*\))"#)
        guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return XCTFail("kaynak kök yok") }
        var hits: [String] = [], files = 0
        for case let u as URL in en where u.pathExtension == "swift" {
            files += 1
            let text = try String(contentsOf: u, encoding: .utf8)
            for (i, line) in text.components(separatedBy: "\n").enumerated()
            where pattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                hits.append("\(u.lastPathComponent):\(i + 1)")
            }
        }
        XCTAssertGreaterThan(files, 50)
        XCTAssertEqual(hits.count, 1, "doğrudan yürütme yolları: \(hits)")
        XCTAssertTrue(hits.first?.hasPrefix("ShelfAction.swift:") == true, "\(hits)")
        let src = try String(contentsOf: root.appendingPathComponent("Actions/ShelfAction.swift"), encoding: .utf8)
        let body = try XCTUnwrap(src.range(of: "func execute(_ a: ShelfAction, ctx: ActionContext) -> ExecuteResult {").map { String(src[$0.upperBound...].prefix(200)) })
        XCTAssertTrue(body.contains("a.perform(ctx)"), "tek çağrı execute gövdesinde")
    }
}
