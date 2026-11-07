import XCTest
import SwiftUI
@testable import Shotmori

final class StripCapsuleTests: XCTestCase {
    private func favs(_ list: [(String, Bool)]) -> [(id: String, available: Bool)] { list.map { (id: $0.0, available: $0.1) } }

    func testNoSelectionShowsMenuAndPin() {
        let r = StripCapsule.entries(selectionCount: 0, favorites: favs([("copy-image", true)]), pinned: false)
        XCTAssertEqual(r.entries, [.actionsMenu, .pin(on: false)])
        XCTAssertEqual(r.overflow, [])
    }

    func testSelectionShowsAvailableFavoritesInOrderWithPrimaryCopy() {
        let r = StripCapsule.entries(selectionCount: 2,
                                     favorites: favs([("copy-image", true), ("share", true), ("edit", false), ("reveal-in-finder", true)]),
                                     pinned: false)
        XCTAssertEqual(r.entries, [.selectionCount(2), .action(id: "copy-image", primary: true), .action(id: "share", primary: false),
                                   .action(id: "reveal-in-finder", primary: false), .separator, .actionsMenu, .pin(on: false)])
        XCTAssertEqual(r.overflow, [])
    }

    func testNoPrimaryWhenFirstFavoriteIsNotCopy() {
        let r = StripCapsule.entries(selectionCount: 1, favorites: favs([("share", true), ("copy-image", true)]), pinned: false)
        XCTAssertEqual(r.entries.compactMap { e -> Bool? in if case .action(_, let p) = e { return p } else { return nil } }, [false, false])
    }

    func testUnavailableFirstCopyIsNotPrimaryOfOthers() {
        let r = StripCapsule.entries(selectionCount: 1, favorites: favs([("copy-image", false), ("share", true)]), pinned: false)
        XCTAssertEqual(r.entries[1], .action(id: "share", primary: false))
    }

    func testOverflowBeyondMaxActions() {
        let ids = (1...8).map { "a\($0)" }
        let r = StripCapsule.entries(selectionCount: 3, favorites: favs(ids.map { ($0, true) }), pinned: false, maxActions: 6)
        XCTAssertEqual(r.entries.filter { if case .action = $0 { return true } else { return false } }.count, 6)
        XCTAssertEqual(r.overflow, ["a7", "a8"])
    }

    func testPinnedState() {
        let r = StripCapsule.entries(selectionCount: 0, favorites: [], pinned: true)
        XCTAssertEqual(r.entries.last, .pin(on: true))
    }
}

@MainActor
final class StripCapsuleViewTests: XCTestCase {
    private func render(_ m: StripModel, width: CGFloat = 1000) -> (NSWindow, NSHostingView<StripView>) {
        let host = NSHostingView(rootView: StripView(model: m, actions: StripViewActions()))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: StripLayout.stripHeight),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        host.frame = NSRect(x: 0, y: 0, width: width, height: StripLayout.stripHeight)
        window.contentView = host
        let deadline = Date().addingTimeInterval(1)
        repeat {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            host.layoutSubtreeIfNeeded()
        } while m.hitRects.isEmpty && Date() < deadline
        return (window, host)
    }

    func testCapsulesAndNoticeReportHitRects() {
        let m = StripModel(reduceMotion: { true })
        m.tabs = [StripTab(id: UUID(), title: "Raf 1", count: 3, active: true, detached: false),
                  StripTab(id: UUID(), title: "Raf 2", count: 0, active: false, detached: true)]
        m.capsule = [.selectionCount(2), .action(id: "copy-image", primary: true), .separator, .actionsMenu, .pin(on: false)]
        m.selection = [UUID(), UUID()]
        m.notice = StatusMessage(text: "Hata", kind: .persistent)
        let (w, _) = render(m)
        guard let l = m.hitRects["left"], let r = m.hitRects["right"], let n = m.hitRects["notice"] else {
            return XCTFail("kapsül çerçeveleri raporlanmadı: \(m.hitRects.keys)")
        }
        XCTAssertEqual(l.minX, StripView.capsuleSideInset, accuracy: 1)
        XCTAssertEqual(r.maxX, 1000 - StripView.capsuleSideInset, accuracy: 1)
        XCTAssertEqual(l.minY, StripView.capsuleTopInset, accuracy: 1)
        XCTAssertEqual(n.minY, r.maxY + 6, accuracy: 1)
        XCTAssertEqual(n.maxX, r.maxX, accuracy: 1)
        XCTAssertNil(m.hitRects["empty"])
        // ⌘K çapası: İşlemler düğmesi kendi dikdörtgenini ilk çizimde raporlar, sağ kapsülün içinde ve sağ ucunda.
        guard let a = m.hitRects[StripCapsuleEntry.actionsHitKey] else { return XCTFail("İşlemler düğmesi raporlanmadı") }
        XCTAssertTrue(r.insetBy(dx: -0.5, dy: -0.5).contains(a))
        XCTAssertGreaterThan(a.minX, r.minX + 40, "kapsülün sol kenarı değil")
        w.close()
    }

    func testEmptyStateReportsHitRect() {
        let m = StripModel(reduceMotion: { true })
        m.emptyState = .empty(hotKey: "⌥⌘S")
        let (w, _) = render(m)
        guard let e = m.hitRects["empty"] else { return XCTFail("boş raf kapsülü raporlanmadı") }
        XCTAssertEqual(e.midX, 500, accuracy: 2)
        w.close()
    }

    func testTabChipLabelOnlyActiveShowsCount() {
        let a = StripTab(id: UUID(), title: "Raf 1", count: 3, active: true, detached: false)
        let b = StripTab(id: UUID(), title: "Raf 2", count: 5, active: false, detached: false)
        XCTAssertEqual(StripTabChip.label(for: a), "Raf 1 · 3")
        XCTAssertEqual(StripTabChip.label(for: b), "Raf 2")
    }

    func testAddButtonHiddenAtEightShelves() {
        XCTAssertTrue(StripLeftCapsule.showsAdd(tabCount: 1))
        XCTAssertTrue(StripLeftCapsule.showsAdd(tabCount: 7))
        XCTAssertFalse(StripLeftCapsule.showsAdd(tabCount: 8))
        XCTAssertFalse(StripLeftCapsule.showsAdd(tabCount: 0))
    }

    // MARK: Son düzeltme dalgası

    /// B5: kapsül girdilerinin kimliği seçim değişince sabit (görünüm ve demirli menü/seçici yeniden kurulmaz) ve kapsülde tekil.
    func testStableIDsAreUniqueAndSurviveSelectionChange() {
        let f: [(id: String, available: Bool)] = [(id: "copy-image", available: true), (id: "share", available: true)]
        let a = StripCapsule.entries(selectionCount: 1, favorites: f, pinned: false).entries
        let b = StripCapsule.entries(selectionCount: 3, favorites: f, pinned: true).entries
        XCTAssertEqual(Set(a.map { $0.stableID }).count, a.count, "tekil")
        XCTAssertEqual(a.map { $0.stableID }, b.map { $0.stableID }, "sayı ve iğne değişince kimlik aynı")
        XCTAssertEqual(StripCapsuleEntry.actionsMenu.stableID, StripCapsuleEntry.actionsHitKey)
    }

    /// B5: ⌘K menüsü İşlemler düğmesinin dikdörtgenine demirlenir (düğmeye önceden tıklanmış olması gerekmez).
    func testActionsMenuAnchorRect() {
        let right = CGRect(x: 1490, y: 8, width: 300, height: 22), actions = CGRect(x: 1690, y: 10, width: 54, height: 18)
        XCTAssertEqual(StripCapsule.actionsMenuAnchorRect(hitRects: ["right": right, "actions": actions, "left": .zero]), actions)
        XCTAssertEqual(StripCapsule.actionsMenuAnchorRect(hitRects: ["right": right]), right, "yedek: bütün kapsül")
        XCTAssertNil(StripCapsule.actionsMenuAnchorRect(hitRects: [:]))
    }

    /// Saydamlığı azalt açıkken kapsül zemini tam opak; kapalıyken %72.
    func testCapsuleOpaqueWithReduceTransparency() {
        XCTAssertEqual(StripCapsuleBackground.fillOpacity(reduceTransparency: false), 0.72)
        XCTAssertEqual(StripCapsuleBackground.fillOpacity(reduceTransparency: true), 1)
    }

    /// "Yeniden dene" yalnız yeniden denenebilen kalıcı bildirimde (yüzen panelle aynı).
    func testRetryOnlyForRetryableNotice() {
        XCTAssertTrue(StripNoticeView.showsAction(kind: .persistent, hasAction: true))
        XCTAssertFalse(StripNoticeView.showsAction(kind: .persistent, hasAction: false))
        XCTAssertFalse(StripNoticeView.showsAction(kind: .success, hasAction: true))
        XCTAssertFalse(StripNoticeView.showsAction(kind: .busy, hasAction: true))
    }

    /// Geç gelen küçük resim yalnız kart hâlâ o dosyayı istiyorsa yazılır.
    func testThumbnailGuardComparesCurrentRequest() {
        let a = URL(fileURLWithPath: "/nonexistent/a.png"), b = URL(fileURLWithPath: "/nonexistent/b.png")
        XCTAssertTrue(StripCardView.acceptsThumbnail(for: a, requested: a))
        XCTAssertFalse(StripCardView.acceptsThumbnail(for: a, requested: b), "kart başka dosyaya geçti")
        XCTAssertFalse(StripCardView.acceptsThumbnail(for: a, requested: nil))
    }
}

