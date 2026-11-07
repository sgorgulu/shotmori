import XCTest
import AppKit
@testable import Shotmori

/// B: altı sayfa, son sayfada yalnız bitirme, hayalet sayfa yok; kapsam metaverisi availability ile tutarlı.
final class OnboardingFlowTests: XCTestCase {
    func testSixPagesNoGhostSeventh() {
        var f = OnboardingFlow(); XCTAssertEqual(OnboardingFlow.pageCount, 6); XCTAssertTrue(f.isFirst); XCTAssertEqual(f.filledSegments, 1)
        for _ in 0..<5 { f.next() }
        XCTAssertEqual(f.step, 5); XCTAssertTrue(f.isLast); XCTAssertEqual(f.filledSegments, 6)
        f.next(); XCTAssertEqual(f.step, 5, "son sayfadan sonra yedinci sayfa yok")
        f.back(); XCTAssertEqual(f.step, 4); for _ in 0..<10 { f.back() }; XCTAssertTrue(f.isFirst)
    }
    func testSkipOnlyOnTryPageWithoutDetection() {
        var f = OnboardingFlow(); XCTAssertFalse(f.canSkip(detected: false))
        for _ in 0..<4 { f.next() }; XCTAssertEqual(f.step, OnboardingFlow.tryPage)
        XCTAssertTrue(f.canSkip(detected: false)); XCTAssertFalse(f.canSkip(detected: true))
        f.next(); XCTAssertFalse(f.canSkip(detected: false))
    }
    func testScopeMetadataMatchesAvailability() throws {
        let reg = ActionRegistry(prefs: Preferences(defaults: UserDefaults(suiteName: "dev.shotmori.tests.scope")!))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("scope-\(UUID())", isDirectory: true); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let png: Data = { let img = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { r in NSColor.red.setFill(); r.fill(); return true }; return NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])! }()
        let items: [ShelfItem] = try (1...2).map { i in let u = dir.appendingPathComponent("s\(i).png"); try png.write(to: u); return ShelfItem(path: u.path, fileID: nil, capturedAt: Date()) }
        for id in ["edit", "copy-text", "resize"] {
            let a = try XCTUnwrap(reg.action(id)); XCTAssertEqual(a.scope, .single, id)
            XCTAssertFalse(a.availability(for: items).isAvailable, "\(id) iki görüntüde pasif olmalı"); XCTAssertTrue(a.availability(for: [items[0]]).isAvailable)
        }
        for id in ["copy-image", "share", "save-as", "reveal-in-finder", "open"] { let a = try XCTUnwrap(reg.action(id)); XCTAssertEqual(a.scope, .selection, id); XCTAssertTrue(a.availability(for: items).isAvailable, id) }
        XCTAssertEqual(reg.action("clear-shelf")?.scope, .wholeShelf)
        try? FileManager.default.removeItem(at: dir)
    }

    func testFolderPageNeedsChoiceToAdvance() {
        var f = OnboardingFlow()
        XCTAssertTrue(f.canAdvance(folderChosen: false), "karşılama sayfası klasör istemez")
        f.next(); XCTAssertEqual(f.step, OnboardingFlow.folderPage)
        XCTAssertFalse(f.canAdvance(folderChosen: false))
        XCTAssertTrue(f.canAdvance(folderChosen: true))
        f.next(); XCTAssertTrue(f.canAdvance(folderChosen: false))
    }

    /// Erişim kaybolunca (göç, silinen klasör) kurulum baştan değil, yalnız klasör sayfasıyla açılır.
    func testFolderOnlyFlowStartsAtFolderPageAndEndsThere() {
        var f = OnboardingFlow(folderOnly: true)
        XCTAssertEqual(f.step, OnboardingFlow.folderPage)
        XCTAssertTrue(f.isFirst); XCTAssertTrue(f.isLast)
        XCTAssertFalse(f.canAdvance(folderChosen: false)); XCTAssertTrue(f.canAdvance(folderChosen: true))
        f.next(); XCTAssertEqual(f.step, OnboardingFlow.folderPage, "tek sayfa: ileri gitmez")
        f.back(); XCTAssertEqual(f.step, OnboardingFlow.folderPage, "tek sayfa: geri gitmez")
    }
}
