import XCTest
@testable import Shotmori

@MainActor
final class StripBehaviorTests: XCTestCase {
    private func state(_ reason: StripController.RevealReason, mode: NewCaptureStripMode = .peek, pinned: Bool = false,
                       inside: Bool = false, notice: Bool = false, since: Double, away: Double) -> StripRetractState {
        StripRetractState(reason: reason, mode: mode, pinned: pinned, pointerInside: inside, dragging: false, menuOpen: false,
                          pressing: false, quickLookOpen: false, editorOpen: false, persistentNotice: notice, busy: false,
                          secondsSinceReveal: since, secondsPointerAway: away)
    }

    /// Spec §7.1/§7.4a: kısayol ve iğne hiç kendiliğinden çekilmez; kısa gösterim 2,5 sn + 0,5 sn uzak; menü çubuğu 0,5 sn uzak.
    func testRetractDecision() {
        XCTAssertFalse(StripRetract.shouldRetract(state(.shortcut, since: 100, away: 100)), "kısayol yalnız Esc/kısayol/dışarı tık/bırakma ile")
        XCTAssertFalse(StripRetract.shouldRetract(state(.newCapture, since: 2.4, away: 2.4)), "2,5 sn dolmadan çekilmez")
        XCTAssertTrue(StripRetract.shouldRetract(state(.newCapture, since: 2.5, away: 0.5)))
        XCTAssertFalse(StripRetract.shouldRetract(state(.newCapture, since: 2.5, away: 0.49)), "imleç 0,5 sn uzak kalmadan çekilmez")
        XCTAssertFalse(StripRetract.shouldRetract(state(.newCapture, inside: true, since: 10, away: 10)), "imleç şeritte")
        XCTAssertFalse(StripRetract.shouldRetract(state(.newCapture, notice: true, since: 10, away: 10)), "kalıcı bildirim durdurur")
        XCTAssertTrue(StripRetract.shouldRetract(state(.external, since: 2.5, away: 0.5)), "dış yollar yeni kare ayarına uyar")
        XCTAssertFalse(StripRetract.shouldRetract(state(.newCapture, mode: .stay, since: 100, away: 100)), "kapatana kadar açık")
        XCTAssertFalse(StripRetract.shouldRetract(state(.external, mode: .stay, since: 100, away: 100)))
        XCTAssertFalse(StripRetract.shouldRetract(state(.menuBar, since: 0.1, away: 0.49)))
        XCTAssertTrue(StripRetract.shouldRetract(state(.menuBar, since: 0.1, away: 0.5)), "menü çubuğu: 2,5 sn kuralı yok")
        for r in [StripController.RevealReason.shortcut, .newCapture, .menuBar, .external] {
            for m in [NewCaptureStripMode.peek, .stay] {
                XCTAssertFalse(StripRetract.shouldRetract(state(r, mode: m, pinned: true, since: 100, away: 100)), "iğne: \(r) \(m)")
            }
        }
        // Her durdurucu tek başına çekilmeyi engeller.
        let base = state(.menuBar, since: 10, away: 10)
        XCTAssertTrue(StripRetract.shouldRetract(base))
        let blockers: [WritableKeyPath<StripRetractState, Bool>] = [\.pointerInside, \.dragging, \.menuOpen, \.pressing, \.quickLookOpen,
                                                                    \.editorOpen, \.persistentNotice, \.busy]
        for k in blockers {
            var s = base; s[keyPath: k] = true
            XCTAssertFalse(StripRetract.shouldRetract(s), "\(k)")
        }
    }

    private func makeController() -> (StripController, UserDefaults, String) {
        let suite = "dev.shotmori.tests.stripbehavior.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!; d.removePersistentDomain(forName: suite)
        let prefs = Preferences(defaults: d)
        let c = StripController(store: ShelfStore(fileURL: nil, maxItems: 5), registry: ActionRegistry(prefs: prefs), prefs: prefs,
                                detachedShelves: { [] }, onDetachedTabClicked: { _ in }, watchedFolder: { nil })
        return (c, d, suite)
    }

    func testStripControllerConforms() {
        let (c, d, suite) = makeController()
        defer { c.hide(reason: "test"); d.removePersistentDomain(forName: suite) }
        let p: ShelfPresenting = c
        XCTAssertFalse(p.isVisible)
        XCTAssertTrue(p.showsTabs)
        p.show(takeKey: false)
        XCTAssertTrue(p.isVisible)
        XCTAssertTrue(c.panel.isVisible, "pencere ekranda")
        XCTAssertFalse(NSApp.keyWindow === c.panel, "odak almadan iner")
        XCTAssertFalse(c.panel.keyboardFocusAllowed)
        XCTAssertEqual(c.model.emptyState, .noFolder, "klasör yokken klasör seç kapsülü")
        XCTAssertTrue(c.panel.allowsToolTipsWhenApplicationIsInactive, "A11Y-13: menü çubuğu uygulaması etkin değilken de araç ipuçları")
        p.hide(reason: "test")
        XCTAssertFalse(p.isVisible)
    }

    /// Model eylem bilgisini kayıttan alır (boşken sağ kapsül soru işareti gösterirdi); sekmeler ve kapsül dolar.
    func testModelIsFilledFromStoreAndRegistry() {
        let (c, d, suite) = makeController()
        defer { d.removePersistentDomain(forName: suite) }
        XCTAssertEqual(c.model.actionInfo("copy-image")?.symbol, "doc.on.doc")
        XCTAssertNil(c.model.actionInfo("yok"))
        XCTAssertEqual(c.model.tabs.count, 1)
        XCTAssertTrue(c.model.tabs[0].active)
        XCTAssertEqual(c.model.capsule, [.actionsMenu, .pin(on: false)], "seçim yok")
        let item = ShelfItem(path: "/nonexistent/shotmori-strip-behavior/a.png", fileID: nil, capturedAt: Date())
        c.store.add(item)
        c.selectNewest()
        XCTAssertEqual(c.model.items.map(\.id), [item.id])
        XCTAssertEqual(c.model.selection, [item.id])
        XCTAssertEqual(c.model.capsule.first, .selectionCount(1))
    }

    /// Şeritte kart üstü "Kopyalandı" kapsülü varken rutin toast yutulur (spec §7.4a); başka metin bildirim olur.
    func testCopiedToastSwallowedWhileBadgeShown() {
        let (c, d, suite) = makeController()
        defer { c.hide(reason: "test"); d.removePersistentDomain(forName: suite) }
        let item = ShelfItem(path: "/nonexistent/shotmori-strip-behavior/b.png", fileID: nil, capturedAt: Date())
        c.store.add(item); c.show(takeKey: false)
        // `run("copy-image")` eylemi çalıştırırken kopyalanan kimlikleri tutar (gerçek panoya yazmamak için burada elle).
        c.copyingIDs = [item.id]
        c.showToast(S.copiedToast)
        c.copyingIDs = []
        XCTAssertEqual(c.model.copiedID, item.id)
        XCTAssertNil(c.model.notice, "Kopyalandı toast'ı gösterilmez")
        c.showToast("başka")
        XCTAssertEqual(c.model.notice?.text, "başka")
    }

    /// "Kopyalandı" rozeti yalnız şeridin kopyaladığı ve şeritte görünen karta; başka kopyalamalarda bildirim gösterilir.
    func testCopiedBadgeOnlyForCopiedDisplayedItem() {
        let a = UUID(), b = UUID(), other = UUID()
        XCTAssertEqual(StripController.copiedBadgeTarget(copying: [b], displayed: [a, b], shown: true), b, "kopyalanan kart, seçim çapası değil")
        XCTAssertNil(StripController.copiedBadgeTarget(copying: [other], displayed: [a, b], shown: true), "şeritte olmayan öğe")
        XCTAssertNil(StripController.copiedBadgeTarget(copying: [], displayed: [a, b], shown: true), "run dışı kopyalama (Kestirmeler, bulut bağlantısı)")
        XCTAssertNil(StripController.copiedBadgeTarget(copying: [a], displayed: [a, b], shown: false), "şerit gizli")

        let (c, d, suite) = makeController()
        defer { c.hide(reason: "test"); d.removePersistentDomain(forName: suite) }
        let i1 = ShelfItem(path: "/nonexistent/shotmori-strip-behavior/c1.png", fileID: nil, capturedAt: Date())
        let i2 = ShelfItem(path: "/nonexistent/shotmori-strip-behavior/c2.png", fileID: nil, capturedAt: Date())
        c.store.add([i1, i2]); c.show(takeKey: false); c.selectNewest()
        c.showToast(S.copiedToast) // ör. son kareyi kopyala / Kestirmeler: şeridin run'ı değil
        XCTAssertNil(c.model.copiedID, "seçili karta rozet konmaz")
        XCTAssertEqual(c.model.notice?.text, S.copiedToast, "olağan bildirim gösterilir")
    }

    /// İğne her tıktan önce gelir (menü çubuğu dahil); iğnesizken menü çubuğu her inişte, dışarı tık yalnız kısayol/"kapatana kadar".
    func testClickHidingRules() {
        for r in [StripController.RevealReason.shortcut, .newCapture, .menuBar, .external] {
            XCTAssertTrue(StripController.hidesOnClick(inMenuBar: true, reason: r, mode: .peek, pinned: false), "menü çubuğu: \(r)")
            XCTAssertFalse(StripController.hidesOnClick(inMenuBar: true, reason: r, mode: .stay, pinned: true), "iğne menü çubuğundan önce: \(r)")
            XCTAssertFalse(StripController.hidesOnClick(inMenuBar: false, reason: r, mode: .stay, pinned: true), "iğne: \(r)")
        }
        XCTAssertTrue(StripController.hidesOnClick(inMenuBar: false, reason: .shortcut, mode: .peek, pinned: false))
        XCTAssertTrue(StripController.hidesOnClick(inMenuBar: false, reason: .newCapture, mode: .stay, pinned: false))
        XCTAssertTrue(StripController.hidesOnClick(inMenuBar: false, reason: .external, mode: .stay, pinned: false))
        XCTAssertFalse(StripController.hidesOnClick(inMenuBar: false, reason: .newCapture, mode: .peek, pinned: false), "kısa gösterim kendisi çekilir")
        XCTAssertFalse(StripController.hidesOnClick(inMenuBar: false, reason: .menuBar, mode: .stay, pinned: false))

        let screens: [(frame: NSRect, visible: NSRect)] = [(NSRect(x: 0, y: 0, width: 1800, height: 1169), NSRect(x: 0, y: 59, width: 1800, height: 1071)),
                                                           (NSRect(x: 1800, y: 0, width: 1000, height: 800), NSRect(x: 1800, y: 0, width: 1000, height: 800))]
        XCTAssertTrue(StripController.inMenuBarBand(NSPoint(x: 900, y: 1150), screens: screens))
        XCTAssertTrue(StripController.inMenuBarBand(NSPoint(x: 900, y: 1130), screens: screens), "görünür alanın tepesi banda dahil")
        XCTAssertFalse(StripController.inMenuBarBand(NSPoint(x: 900, y: 1129), screens: screens))
        XCTAssertFalse(StripController.inMenuBarBand(NSPoint(x: 900, y: 30), screens: screens), "Dock bandı menü çubuğu değil")
        XCTAssertTrue(StripController.inMenuBarBand(NSPoint(x: 2300, y: 799), screens: screens, thickness: 24), "menü çubuğu gizli ekran: durum çubuğu kalınlığında bant")
        XCTAssertFalse(StripController.inMenuBarBand(NSPoint(x: 2300, y: 775), screens: screens, thickness: 24))
        XCTAssertFalse(StripController.inMenuBarBand(NSPoint(x: 5000, y: 100), screens: screens), "ekran dışı")
        XCTAssertEqual(StripController.menuBarScreenIndex(NSPoint(x: 2300, y: 790), screens: screens, thickness: 24), 1, "bant hangi ekranın")
        XCTAssertNil(StripController.menuBarScreenIndex(NSPoint(x: 900, y: 600), screens: screens, thickness: 24))
    }

    /// Spec §7.1: menü çubuğu bandında 0,25 sn kesintisiz durunca bir kez iner; tık, imleç banttan çıkana dek yeniden inişi bastırır.
    func testMenuBarDwell() {
        let t = { (s: Double) in Date(timeIntervalSinceReferenceDate: s) }
        var d = MenuBarDwell()
        XCTAssertFalse(d.tick(inMenuBar: true, now: t(0)))
        XCTAssertFalse(d.tick(inMenuBar: true, now: t(0.24)))
        XCTAssertTrue(d.tick(inMenuBar: true, now: t(0.25)), "0,25 sn kesintisiz")
        XCTAssertFalse(d.tick(inMenuBar: true, now: t(0.30)), "bir kez")
        XCTAssertFalse(d.tick(inMenuBar: true, now: t(0.80)), "bantta kaldıkça yeniden tetiklenmez")
        XCTAssertFalse(d.tick(inMenuBar: false, now: t(0.9)))
        XCTAssertNil(d.since); XCTAssertFalse(d.suppressed)
        XCTAssertFalse(d.tick(inMenuBar: true, now: t(1.0)))
        XCTAssertTrue(d.tick(inMenuBar: true, now: t(1.25)), "bant dışından sonra yeniden")

        var c = MenuBarDwell()
        XCTAssertFalse(c.tick(inMenuBar: true, now: t(10)))
        c.menuBarClicked()
        XCTAssertTrue(c.suppressed); XCTAssertNil(c.since)
        for i in 0...30 { XCTAssertFalse(c.tick(inMenuBar: true, now: t(10 + Double(i) / 30)), "tıktan sonra bantta 1 sn: \(i)") }
        XCTAssertFalse(c.tick(inMenuBar: false, now: t(11.1)), "bant dışı bir tik")
        XCTAssertFalse(c.suppressed)
        XCTAssertFalse(c.tick(inMenuBar: true, now: t(12)))
        XCTAssertTrue(c.tick(inMenuBar: true, now: t(12.25)))

        var k = MenuBarDwell()
        XCTAssertFalse(k.tick(inMenuBar: true, now: t(20)))
        XCTAssertFalse(k.tick(inMenuBar: false, now: t(20.2)))
        XCTAssertFalse(k.tick(inMenuBar: true, now: t(20.25)))
        XCTAssertFalse(k.tick(inMenuBar: true, now: t(20.45)), "kesintili: süre baştan")
        XCTAssertTrue(k.tick(inMenuBar: true, now: t(20.5)))
    }

    /// Bant: çerçevenin tepesi ile görünür alanın tepesi arası; menü çubuğu gizliyse durum çubuğu kalınlığı.
    func testMenuBarBand() {
        let f = CGRect(x: 0, y: 0, width: 1512, height: 982)
        XCTAssertEqual(MenuBarBand.rect(screenFrame: f, visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949), statusBarThickness: 24),
                       CGRect(x: 0, y: 949, width: 1512, height: 33))
        XCTAssertEqual(MenuBarBand.rect(screenFrame: f, visibleFrame: CGRect(x: 0, y: 70, width: 1512, height: 912), statusBarThickness: 24),
                       CGRect(x: 0, y: 958, width: 1512, height: 24), "görünür alan tepeye değiyor (maxY 982)")
        XCTAssertEqual(MenuBarBand.rect(screenFrame: CGRect(x: 1512, y: -200, width: 1000, height: 800),
                                        visibleFrame: CGRect(x: 1512, y: -200, width: 1000, height: 775), statusBarThickness: 24),
                       CGRect(x: 1512, y: 575, width: 1000, height: 25), "ikinci ekran, eksi köken")
    }

    /// Boşta CPU %0 (spec §9): gizliyken izleyici yalnız Üst şerit seçili ve menü çubuğu tercihi açıkken çalışır; görünürken hep.
    func testPointerTrackerRunsOnlyWhenNeeded() {
        XCTAssertFalse(StripController.shouldTrack(style: .floating, revealFromMenuBar: true, visible: false))
        XCTAssertTrue(StripController.shouldTrack(style: .floating, revealFromMenuBar: true, visible: true), "görünür şerit hep izlenir (stil değişirken geçiş)")
        XCTAssertFalse(StripController.shouldTrack(style: .strip, revealFromMenuBar: false, visible: false))
        XCTAssertTrue(StripController.shouldTrack(style: .strip, revealFromMenuBar: false, visible: true))
        XCTAssertTrue(StripController.shouldTrack(style: .strip, revealFromMenuBar: true, visible: false))

        let (c, d, suite) = makeController()
        defer { c.hide(reason: "test"); c.updateTracking(); d.removePersistentDomain(forName: suite) }
        c.prefs.shelfStyle = .floating
        c.updateTracking()
        XCTAssertFalse(c.pointerTracker.isRunning, "yüzen panel: izleme yok")
        c.prefs.shelfStyle = .strip
        c.updateTracking()
        XCTAssertTrue(c.pointerTracker.isRunning, "şerit + menü çubuğu tercihi: gizliyken de")
        XCTAssertTrue(c.pointerTracker.isWatching, "gizliyken yalnız hareket olayı izlenir")
        if !StripController.inMenuBarBand(NSEvent.mouseLocation) {
            XCTAssertFalse(c.pointerTracker.isPolling, "PERF-14: imleç menü çubuğunda değilken 30 Hz tık yok")
        }
        c.prefs.stripRevealFromMenuBar = false
        c.updateTracking()
        XCTAssertFalse(c.pointerTracker.isRunning, "tercih kapalı ve gizli: izleme yok")
        c.show(takeKey: false)
        XCTAssertTrue(c.pointerTracker.isRunning, "görünürken tercihten bağımsız")
        XCTAssertTrue(c.pointerTracker.isPolling, "görünürken 30 Hz")
        XCTAssertFalse(c.pointerTracker.isWatching)
        c.hide(reason: "test")
        XCTAssertFalse(c.pointerTracker.isRunning)
    }

    /// Gizliyken bantta 0,25 sn → odak almadan o ekranda iner; Ayarlar/kurulum açıkken inmez;
    /// menü çubuğuna tık şeridi çeker ve imleç banttan çıkana dek yeniden indirmez.
    func testHiddenTickRevealsFromMenuBarAndClickSuppresses() throws {
        guard let screen = NSScreen.screens.first else { throw XCTSkip("ekran yok") }
        let (c, d, suite) = makeController()
        defer { c.hide(reason: "test"); c.updateTracking(); d.removePersistentDomain(forName: suite) }
        c.prefs.shelfStyle = .strip
        let band = MenuBarBand.rect(screenFrame: screen.frame, visibleFrame: screen.visibleFrame, statusBarThickness: NSStatusBar.system.thickness)
        let p = NSPoint(x: band.midX, y: band.midY), out = NSPoint(x: screen.frame.midX, y: screen.frame.midY)
        let t0 = Date(timeIntervalSinceReferenceDate: Date().timeIntervalSinceReferenceDate.rounded(.down)) // tam saniye: farklar kesin

        c.suppressMenuBarReveal = { true }
        c.tick(mouse: p, now: t0); c.tick(mouse: p, now: t0 + 1)
        XCTAssertFalse(c.isVisible, "Ayarlar ya da kurulum açıkken inmez")
        c.suppressMenuBarReveal = { false }
        c.tick(mouse: p, now: t0 + 2)
        XCTAssertFalse(c.isVisible, "bastırma kalkınca süre baştan")

        c.prefs.stripRevealFromMenuBar = false
        c.tick(mouse: p, now: t0 + 2.3)
        XCTAssertFalse(c.isVisible, "tercih kapalı")
        c.prefs.stripRevealFromMenuBar = true

        c.tick(mouse: p, now: t0 + 3)
        c.tick(mouse: p, now: t0 + 3.24)
        XCTAssertFalse(c.isVisible)
        c.tick(mouse: p, now: t0 + 3.25)
        XCTAssertTrue(c.isVisible, "0,25 sn bantta: iner")
        XCTAssertEqual(c.reason, .menuBar)
        XCTAssertFalse(NSApp.keyWindow === c.panel, "odak almadan")
        XCTAssertFalse(c.panel.keyboardFocusAllowed)

        c.handleMouseDown(at: p)
        XCTAssertFalse(c.isVisible, "menü çubuğuna tık çeker")
        for i in 0...30 { c.tick(mouse: p, now: t0 + 4 + Double(i) / 30) }
        XCTAssertFalse(c.isVisible, "imleç menü çubuğundan çıkana dek yeniden inmez")
        c.tick(mouse: out, now: t0 + 5.1)
        c.tick(mouse: p, now: t0 + 5.2); c.tick(mouse: p, now: t0 + 5.45)
        XCTAssertTrue(c.isVisible, "banttan çıkıp dönünce yeniden iner")
    }

    /// Adlandırma bitince önceki uygulama yalnız Shotmori hâlâ öndeyse geri gelir (kullanıcı başka uygulamaya geçtiyse o kalır).
    func testRenameRestoresPreviousAppOnlyIfStillActive() {
        XCTAssertTrue(StripController.shouldRestorePreviousApp(appStillActive: true, previousIsOther: true))
        XCTAssertFalse(StripController.shouldRestorePreviousApp(appStillActive: false, previousIsOther: true), "kullanıcı C'ye tıkladı: A öne çekilmez")
        XCTAssertFalse(StripController.shouldRestorePreviousApp(appStillActive: true, previousIsOther: false))
    }

    /// Şerit çekilirken açık adlandırma balonu yazılan adı kaydeder; Esc vazgeçer.
    func testRenameSessionCloseSavesEscCancels() {
        var saved: String?? = .none
        let s = StripRenameSession(name: "Raf 1") { saved = .some($0) }
        s.field.stringValue = "Yeni ad"
        s.close()
        XCTAssertEqual(saved, .some("Yeni ad"), "dışarı tık / çekilme kaydeder")
        var cancelled: String?? = .none
        let e = StripRenameSession(name: "Raf 1") { cancelled = .some($0) }
        _ = e.control(e.field, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        e.popoverDidClose(Notification(name: NSPopover.didCloseNotification))
        XCTAssertEqual(cancelled, .some(nil), "Esc: ad değişmez")
    }

    /// Kaydırma [0, maximumOffset] içinde kalır.
    func testScrollClamped() {
        let (c, d, suite) = makeController()
        defer { d.removePersistentDomain(forName: suite) }
        for i in 0..<5 { c.store.add(ShelfItem(path: "/nonexistent/shotmori-strip-behavior/\(i).png", fileID: nil, capturedAt: Date())) }
        c.reload() // gizliyken depo değişimi bir sonraki gösterimde çizilir
        c.scroll(by: -10_000, width: 400)
        XCTAssertEqual(c.model.scrollOffset, StripLayout.maximumOffset(count: 5, width: 400))
        c.scroll(by: 10_000, width: 400)
        XCTAssertEqual(c.model.scrollOffset, 0)
    }

    // MARK: Görev 11: yeni karede iniş, uçuş, düşme

    private func makeController(reduceMotion: Bool) -> (StripController, UserDefaults, String) {
        let suite = "dev.shotmori.tests.stripbehavior.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!; d.removePersistentDomain(forName: suite)
        let prefs = Preferences(defaults: d)
        let c = StripController(store: ShelfStore(fileURL: nil, maxItems: 5), registry: ActionRegistry(prefs: prefs), prefs: prefs,
                                detachedShelves: { [] }, onDetachedTabClicked: { _ in }, watchedFolder: { nil }, reduceMotion: { reduceMotion })
        return (c, d, suite)
    }

    /// Spec §5.3/§5.9: uçuş yalnız hareket azaltma kapalı, yakalama dikdörtgeni var, şerit görünür, hedef var ve 2'den az uçuşta.
    func testFlightGate() {
        XCTAssertTrue(FlightGate.shouldFly(reduceMotion: false, hasCaptureRect: true, stripVisible: true, flightsInProgress: 0, hasTarget: true))
        XCTAssertTrue(FlightGate.shouldFly(reduceMotion: false, hasCaptureRect: true, stripVisible: true, flightsInProgress: 1, hasTarget: true))
        XCTAssertFalse(FlightGate.shouldFly(reduceMotion: false, hasCaptureRect: true, stripVisible: true, flightsInProgress: 2, hasTarget: true), "en çok 2 uçuş")
        XCTAssertFalse(FlightGate.shouldFly(reduceMotion: true, hasCaptureRect: true, stripVisible: true, flightsInProgress: 0, hasTarget: true), "hareket azaltma")
        XCTAssertFalse(FlightGate.shouldFly(reduceMotion: false, hasCaptureRect: false, stripVisible: true, flightsInProgress: 0, hasTarget: true), "xattr yok")
        XCTAssertFalse(FlightGate.shouldFly(reduceMotion: false, hasCaptureRect: true, stripVisible: false, flightsInProgress: 0, hasTarget: true), "şerit gizli")
        XCTAssertFalse(FlightGate.shouldFly(reduceMotion: false, hasCaptureRect: true, stripVisible: true, flightsInProgress: 0, hasTarget: false), "hedef yok")
        XCTAssertEqual(StripMotion.maxConcurrentFlights, 2)
    }

    /// Spec §7.4: şerit yakalama dikdörtgeninin merkezini içeren ekrana iner; yoksa imleç ekranına düşülür (nil).
    func testScreenForCaptureRect() {
        let screens = [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: 1512, y: 0, width: 1920, height: 1080)]
        XCTAssertEqual(StripPresentation.screen(containing: CGRect(x: 1800, y: 100, width: 200, height: 100), screens: screens), 1)
        XCTAssertEqual(StripPresentation.screen(containing: CGRect(x: 100, y: 100, width: 200, height: 100), screens: screens), 0)
        XCTAssertNil(StripPresentation.screen(containing: nil, screens: screens))
        XCTAssertNil(StripPresentation.screen(containing: CGRect(x: -5000, y: 100, width: 200, height: 100), screens: screens), "ekran dışı")
    }

    /// Yeni karede ne yapılır: tercih kapalı/kurulum açıkken hiçbir şey; gizliyken fare basılı değilse iner; görünürken süre yenilenir.
    func testNewCaptureStep() {
        XCTAssertEqual(StripPresentation.newCaptureStep(enabled: true, onboarding: false, visible: false, mouseDown: false), .reveal)
        XCTAssertEqual(StripPresentation.newCaptureStep(enabled: true, onboarding: false, visible: false, mouseDown: true), .none, "tıklama sürerken araya girilmez")
        XCTAssertEqual(StripPresentation.newCaptureStep(enabled: true, onboarding: false, visible: true, mouseDown: false), .refresh)
        XCTAssertEqual(StripPresentation.newCaptureStep(enabled: true, onboarding: false, visible: true, mouseDown: true), .refresh)
        XCTAssertEqual(StripPresentation.newCaptureStep(enabled: false, onboarding: false, visible: false, mouseDown: false), .none)
        XCTAssertEqual(StripPresentation.newCaptureStep(enabled: false, onboarding: false, visible: true, mouseDown: false), .none)
        XCTAssertEqual(StripPresentation.newCaptureStep(enabled: true, onboarding: true, visible: false, mouseDown: false), .none)
        for e in [true, false] { for o in [true, false] { for m in [true, false] {
            XCTAssertEqual(StripPresentation.newCaptureStep(enabled: e, onboarding: o, visible: false, mouseDown: m) == .reveal,
                           AppController.shouldAutoShowShelf(enabled: e, onboarding: o, panelVisible: false, mouseDown: m), "gizliyken yüzen panelle aynı koşul")
        } } }
    }

    /// Uçuşun hedefi / düşmenin başlangıcı: kartın dinlenme çerçevesi (ekran koordinatı, eğimsiz); görünür alan dışındaysa nil.
    func testCardFrameOnScreen() throws {
        let panel = CGRect(x: 0, y: 780, width: 1512, height: 202)
        let f = try XCTUnwrap(StripController.cardFrame(index: 0, scrollOffset: 0, panelFrame: panel, imageSize: CGSize(width: 1000, height: 500)))
        let x = StripLayout.x(index: 0, scrollOffset: 0)
        let cardTop = StripLayout.ropeY(x: x, width: panel.width) - StripLayout.pinAbove + StripLayout.clipSize.height - StripLayout.clipOverlap
        XCTAssertEqual(f.size, StripLayout.cardSize(for: CGSize(width: 1000, height: 500)))
        XCTAssertEqual(f.midX, panel.minX + x, accuracy: 0.001)
        XCTAssertEqual(f.maxY, panel.maxY - cardTop, accuracy: 0.001)
        let shifted = try XCTUnwrap(StripController.cardFrame(index: 1, scrollOffset: 0, panelFrame: panel.offsetBy(dx: 1512, dy: 0), imageSize: nil))
        XCTAssertEqual(shifted.midX, 1512 + StripLayout.x(index: 1, scrollOffset: 0), accuracy: 0.001, "ikinci ekran")
        XCTAssertNil(StripController.cardFrame(index: 20, scrollOffset: 0, panelFrame: panel, imageSize: nil), "ekran dışı kart")
        XCTAssertNil(StripController.cardFrame(index: 0, scrollOffset: 400, panelFrame: panel, imageSize: nil), "kaydırılıp çıkmış kart")
    }

    /// Görev 9 bulgusu: şerit kısa gösterimdeyken gelen ikinci kare süreyi yeniden başlatır, kullanıcının seçimini değiştirmez.
    func testSecondCaptureRestartsPeekKeepsSelection() {
        let (c, d, suite) = makeController(reduceMotion: true)
        defer { c.hide(reason: "test"); d.removePersistentDomain(forName: suite) }
        let a = ShelfItem(path: "/nonexistent/shotmori-strip-behavior/n1.png", fileID: nil, capturedAt: Date())
        let b = ShelfItem(path: "/nonexistent/shotmori-strip-behavior/n2.png", fileID: nil, capturedAt: Date())
        c.store.add(a); c.store.add(b)
        c.presentNewCapture(b, from: nil, on: nil)
        XCTAssertTrue(c.isVisible)
        XCTAssertEqual(c.reason, .newCapture)
        XCTAssertFalse(NSApp.keyWindow === c.panel, "yeni kare odak almaz")
        XCTAssertEqual(c.model.selection, [b.id], "gizliyken en yeni seçilir")
        c.sel.selectOnly(a.id); c.applySelection()
        let first = c.revealedAt
        Thread.sleep(forTimeInterval: 0.01)
        let n = ShelfItem(path: "/nonexistent/shotmori-strip-behavior/n3.png", fileID: nil, capturedAt: Date())
        c.store.add(n)
        c.presentNewCapture(n, from: nil, on: nil)
        XCTAssertGreaterThan(c.revealedAt, first, "kısa gösterim süresi yeniden başlar")
        XCTAssertEqual(c.model.selection, [a.id], "görünür şeritte seçim değişmez")
        XCTAssertEqual(c.model.items.first?.id, n.id)
    }

    /// Uçuş adayı kart, şerit çizilmeden uçuyor işaretlenir (yerinde düşmesin); uçuş olmazsa (görüntü yok) kart varışla gelir.
    func testFlightMarksCardAndFallsBackToArrival() {
        let (c, d, suite) = makeController(reduceMotion: false)
        defer { c.hide(reason: "test"); d.removePersistentDomain(forName: suite) }
        let a = ShelfItem(path: "/nonexistent/shotmori-strip-behavior/f1.png", fileID: nil, capturedAt: Date())
        c.store.add(a)
        c.presentNewCapture(a, from: CGRect(x: 100, y: 100, width: 300, height: 200), on: nil)
        XCTAssertEqual(c.model.flyingIDs, [a.id], "çizimden önce uçuyor")
        let done = expectation(description: "uçuş kararı")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { done.fulfill() }
        wait(for: [done], timeout: 2)
        XCTAssertTrue(c.model.flyingIDs.isEmpty, "görüntü okunamadı: uçuş yok")
        XCTAssertEqual(CaptureFlight.flightsInProgress, 0)

        let (r, rd, rsuite) = makeController(reduceMotion: true)
        defer { r.hide(reason: "test"); rd.removePersistentDomain(forName: rsuite) }
        let b = ShelfItem(path: "/nonexistent/shotmori-strip-behavior/f2.png", fileID: nil, capturedAt: Date())
        r.store.add(b)
        r.presentNewCapture(b, from: CGRect(x: 100, y: 100, width: 300, height: 200), on: nil)
        XCTAssertTrue(r.model.flyingIDs.isEmpty, "hareket azaltmada uçuş yok")
    }

    /// Uçuş bitince kart yerinde belirir ve artık varış düşüşü oynatmaz (yalnız küçük salınım); iptal edilen uçuşta varışla gelir.
    func testLandingMarksArrived() {
        let (c, d, suite) = makeController(reduceMotion: false)
        defer { d.removePersistentDomain(forName: suite) }
        let id = UUID()
        c.model.newIDs = [id]
        c.markFlying(id, true)
        XCTAssertFalse(c.model.needsArrival(id))
        c.markFlying(id, false)
        XCTAssertTrue(c.model.flyingIDs.isEmpty)
        XCTAssertFalse(c.model.needsArrival(id), "uçarak gelen kart yeniden düşmez")
        let other = UUID()
        c.model.newIDs = [other]
        c.markFlying(other, true)
        c.cancelFlight(other)
        XCTAssertTrue(c.model.flyingIDs.isEmpty)
        XCTAssertTrue(c.model.needsArrival(other), "iptal edilen uçuşun kartı varışla gelir")
    }

    // MARK: Son düzeltme dalgası

    /// B2: adlandırma balonu açıkken hiçbir tuş (Esc, ↩, rakam, ⌘) şeride gitmez; balon kapanınca şerit yine alır.
    func testKeysGoToRenameBalloonNotStrip() {
        XCTAssertFalse(StripController.acceptsKeys(isKey: true, quickLookHosted: false, renaming: true))
        XCTAssertFalse(StripController.acceptsKeys(isKey: false, quickLookHosted: true, renaming: true))
        XCTAssertTrue(StripController.acceptsKeys(isKey: true, quickLookHosted: false, renaming: false))
        XCTAssertTrue(StripController.acceptsKeys(isKey: false, quickLookHosted: true, renaming: false))
        XCTAssertFalse(StripController.acceptsKeys(isKey: false, quickLookHosted: false, renaming: false))

        let (c, d, suite) = makeController()
        defer { c.hide(reason: "test"); d.removePersistentDomain(forName: suite) }
        c.renameSession = StripRenameSession(name: "Raf 1") { _ in }
        for (code, chars) in [(UInt16(53), "\u{1b}"), (36, "\r"), (18, "1")] {
            let ev = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                                      characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
            XCTAssertFalse(c.handleKey(ev), "tuş \(code) balona kalır")
        }
        let cmdK = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0, context: nil,
                                    characters: "k", charactersIgnoringModifiers: "k", isARepeat: false, keyCode: 40)!
        XCTAssertFalse(c.handleKey(cmdK), "⌘ kısayolu da balona kalır")
        XCTAssertTrue(c.isVisible == false, "şerit çekilmedi / açılmadı: tuş yan etkisiz")
    }

    /// B3: paylaşım seçicisi, açılır menü katmanı, dosya paneli ya da sayfa açıkken şerit kendiliğinden çekilmez;
    /// şeridin kendi penceresi ve uçuş katmanı sayılmaz.
    func testOtherWindowsHoldStripOpen() {
        func w(level: NSWindow.Level = .normal, visible: Bool = true, file: Bool = false, sheet: Bool = false,
               attached: Bool = false, excluded: Bool = false) -> StripWindowSnapshot {
            StripWindowSnapshot(level: level.rawValue, visible: visible, isFilePanel: file, isSheet: sheet, hasAttachedSheet: attached, excluded: excluded)
        }
        XCTAssertFalse(StripRetract.otherWindowHoldsOpen([]))
        XCTAssertFalse(StripRetract.otherWindowHoldsOpen([w(), w(level: .floating)]), "Ayarlar/düzenleyici kendi kuralında")
        XCTAssertTrue(StripRetract.otherWindowHoldsOpen([w(level: .popUpMenu)]), "paylaşım seçicisi (katman 101)")
        XCTAssertTrue(StripRetract.otherWindowHoldsOpen([w(level: NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1))]))
        XCTAssertFalse(StripRetract.otherWindowHoldsOpen([w(level: .popUpMenu, visible: false)]), "kapanmış seçici")
        XCTAssertTrue(StripRetract.otherWindowHoldsOpen([w(file: true)]), "Farklı kaydet / Buraya kopyala")
        XCTAssertTrue(StripRetract.otherWindowHoldsOpen([w(sheet: true)]))
        XCTAssertTrue(StripRetract.otherWindowHoldsOpen([w(attached: true)]))
        XCTAssertFalse(StripRetract.otherWindowHoldsOpen([w(level: .popUpMenu, excluded: true)]), "şerit / uçuş katmanı")
        XCTAssertEqual(CaptureFlight.windowLevel.rawValue, NSWindow.Level.floating.rawValue + 1)
    }

    /// B3: seçici kipsizdir; `didChoose` (hizmet seçildi ya da vazgeçildi) gelene dek açık sayılır ve şeridi tutar.
    func testSharePickerHoldsStripUntilDismissed() {
        let (c, d, suite) = makeController()
        defer { c.hide(reason: "test"); d.removePersistentDomain(forName: suite) }
        XCTAssertFalse(SharePickerTracker.isOpen)
        XCTAssertFalse(c.retractState(now: Date()).menuOpen)
        let picker = NSSharingServicePicker(items: [URL(fileURLWithPath: "/nonexistent/shotmori-strip-behavior/s.png")])
        SharePickerTracker.track(picker)
        XCTAssertTrue(SharePickerTracker.isOpen)
        XCTAssertTrue(c.retractState(now: Date()).menuOpen, "seçici açıkken şerit çekilmez")
        picker.delegate?.sharingServicePicker?(picker, didChoose: nil)
        XCTAssertFalse(SharePickerTracker.isOpen, "vazgeçince kayıt düşer")
        XCTAssertFalse(c.retractState(now: Date()).menuOpen)
    }

    /// B1: ilk inişte numaralar (1–9) ve kaydırma sınırı pencerenin yerleşmiş genişliğiyle hesaplanır (800 pt'lik ilk genişlikle değil).
    func testFirstRevealNumbersUsePlacedWidth() throws {
        let suite = "dev.shotmori.tests.stripbehavior.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!; d.removePersistentDomain(forName: suite)
        defer { d.removePersistentDomain(forName: suite) }
        let prefs = Preferences(defaults: d)
        let c = StripController(store: ShelfStore(fileURL: nil, maxItems: 20), registry: ActionRegistry(prefs: prefs), prefs: prefs,
                                detachedShelves: { [] }, onDetachedTabClicked: { _ in }, watchedFolder: { nil }, reduceMotion: { true })
        defer { c.hide(reason: "test") }
        for i in 0..<14 { c.store.add(ShelfItem(path: "/nonexistent/shotmori-strip-behavior/n\(i).png", fileID: nil, capturedAt: Date())) }
        XCTAssertEqual(c.panel.frame.width, 800, "yerleşmeden önceki genişlik")
        c.show(takeKey: false)
        let screen = try XCTUnwrap(c.panel.screen ?? NSScreen.main)
        XCTAssertEqual(c.panel.frame.width, screen.visibleFrame.width, "tam genişlik")
        let width = c.panel.frame.width, half = StripLayout.cardWidth / 2
        let visible = StripLayout.visibleRange(count: 14, width: width, offset: 0).filter {
            let x = StripLayout.x(index: $0, scrollOffset: 0); return x + half > 0 && x - half < width
        }
        XCTAssertEqual(c.model.quickNumbers.count, min(9, visible.count), "numaralar gerçek genişlikteki görünür kartlara")
        if width >= 1700 { XCTAssertEqual(c.model.quickNumbers.count, 9) }
    }

    /// "Yeniden dene" yalnız yeniden denenebilen bildirimde; kapatınca ya da başka bildirimle düşer.
    func testNoticeRetryFlagFollowsRetryAction() {
        let (c, d, suite) = makeController()
        defer { c.hide(reason: "test"); d.removePersistentDomain(forName: suite) }
        c.showNotice("kalıcı")
        XCTAssertNil(c.model.noticeActionTitle, "yeniden denenemeyen kalıcı bildirim")
        var retried = 0
        c.showNotice("yükleme başarısız", retry: { retried += 1 })
        XCTAssertEqual(c.model.noticeActionTitle, S.cloudRetry, "eski yeniden deneme yolu aynı başlığı korur")
        c.showToast("başka")
        XCTAssertNil(c.model.noticeActionTitle, "yeni bildirim eskisinin düğmesini taşımaz")
        c.showNotice("yükleme başarısız", retry: { retried += 1 })
        c.noticeActionTapped()
        XCTAssertEqual(retried, 1)
        XCTAssertNil(c.model.noticeActionTitle)
        c.showNotice("yükleme başarısız", retry: { retried += 1 })
        c.dismissNotice()
        XCTAssertNil(c.model.noticeActionTitle, "✕ ile kapatınca düşer")
    }

    /// Bildirim eylemi genel; başlık eylemden gelir. `runsOnReturn` false iken ↩ eylemi çalıştırmaz (kopyalama sürer).
    func testNoticeActionTitleComesFromActionAndReturnOnlyForRetry() {
        let (c, d, suite) = makeController()
        defer { c.hide(reason: "test"); d.removePersistentDomain(forName: suite) }
        c.show(takeKey: false)
        var ran = 0
        c.showNotice("bilgi", action: NoticeAction(title: "Eylem") { ran += 1 })
        XCTAssertEqual(c.model.noticeActionTitle, "Eylem")
        c.perform(.copyAndClose)
        XCTAssertEqual(ran, 0, "↩ eylemi çalıştırmaz")
        c.showNotice("bilgi", action: NoticeAction(title: "Eylem") { ran += 1 })
        c.noticeActionTapped()
        XCTAssertEqual(ran, 1)
        XCTAssertNil(c.model.noticeActionTitle)
        XCTAssertNil(c.model.notice)
    }

    /// VoiceOver basışı tık görünümü olmadan aynı işi yapar (iğne; seçim yokken eylem çalışmaz).
    func testCapsuleAccessibilityPress() {
        let (c, d, suite) = makeController()
        defer { c.hide(reason: "test"); d.removePersistentDomain(forName: suite) }
        XCTAssertFalse(c.pinnedOpen)
        c.invokeCapsule(.pin(on: false), anchor: nil)
        XCTAssertTrue(c.pinnedOpen)
        XCTAssertEqual(c.model.capsule.last, .pin(on: true))
        c.invokeCapsule(.pin(on: true), anchor: nil)
        XCTAssertFalse(c.pinnedOpen)
        c.invokeCapsule(.selectionCount(1), anchor: nil) // yan etkisiz
    }

    // MARK: Faz 2 denetim düzeltmeleri (G5)

    /// COR-19: bozuk yakalama dikdörtgeni (sonsuz, NaN, sıfır, aşırı büyük) `Int` dönüşümünde çökertmez; boyut 400…1500 px.
    func testFlightPixelSizeRejectsBadRects() {
        XCTAssertNil(StripController.flightPixelSize(rect: CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 10), scale: 2))
        XCTAssertNil(StripController.flightPixelSize(rect: CGRect(x: CGFloat.nan, y: 0, width: 100, height: 10), scale: 2))
        XCTAssertNil(StripController.flightPixelSize(rect: CGRect(x: 0, y: 0, width: 0, height: 10), scale: 2))
        XCTAssertNil(StripController.flightPixelSize(rect: CGRect(x: 0, y: 0, width: 100, height: 100), scale: .infinity))
        XCTAssertEqual(StripController.flightPixelSize(rect: CGRect(x: 0, y: 0, width: 1e300, height: 1e300), scale: 2), 1500, "aşırı büyük: üst sınır")
        XCTAssertEqual(StripController.flightPixelSize(rect: CGRect(x: 0, y: 0, width: 100, height: 50), scale: 2), 400, "küçük: alt sınır")
        XCTAssertEqual(StripController.flightPixelSize(rect: CGRect(x: 0, y: 0, width: 300, height: 600), scale: 2), 1200)
    }

    /// COR-19: sonsuz dikdörtgenle gelen yeni kare çökmeden varışla gelir.
    func testInfiniteCaptureRectCancelsFlight() {
        let (c, d, suite) = makeController(reduceMotion: false)
        defer { c.hide(reason: "test"); d.removePersistentDomain(forName: suite) }
        let a = ShelfItem(path: "/nonexistent/shotmori-strip-behavior/inf.png", fileID: nil, capturedAt: Date())
        c.store.add(a)
        c.presentNewCapture(a, from: CGRect(x: 0, y: 0, width: CGFloat.infinity, height: CGFloat.infinity), on: nil)
        let done = expectation(description: "uçuş kararı")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { done.fulfill() }
        wait(for: [done], timeout: 2)
        XCTAssertTrue(c.model.flyingIDs.isEmpty)
    }

    /// COR-20: öğeler zaten hedef raftaysa sekmeye bırakma reddedilir ve "taşındı" bildirimi çıkmaz; karışık seçimde yalnız taşınanlar sayılır.
    func testDropOnTabIgnoresItemsAlreadyOnTarget() throws {
        let (c, d, suite) = makeController()
        defer { c.hide(reason: "test"); d.removePersistentDomain(forName: suite) }
        let first = c.store.activeShelfID
        let target = try XCTUnwrap(c.store.addShelf(name: "Hedef"))
        c.store.setActiveShelf(id: first)
        let a = ShelfItem(path: "/nonexistent/shotmori-strip-behavior/m1.png", fileID: nil, capturedAt: Date())
        let b = ShelfItem(path: "/nonexistent/shotmori-strip-behavior/m2.png", fileID: nil, capturedAt: Date())
        c.store.add(a, to: target.id); c.store.add(b, to: first)
        XCTAssertEqual(StripController.movableItems([a.id, b.id, UUID()], to: target.id) { c.store.shelf(containing: $0)?.id }, [b.id])

        XCTAssertFalse(c.dropItems([a.id], onShelf: target.id, source: nil), "zaten hedefte")
        XCTAssertNil(c.model.notice, "yanıltıcı \"taşındı\" yok")
        XCTAssertFalse(c.internalDropHandled, "reddedilen bırakma aktarım işaretlemez")

        XCTAssertTrue(c.dropItems([a.id, b.id], onShelf: target.id, source: nil))
        XCTAssertEqual(c.model.notice?.text, S.movedToShelfToast(1, "Hedef"), "yalnız taşınan öğe sayılır")
        XCTAssertEqual(c.store.shelf(containing: b.id)?.id, target.id)
        XCTAssertTrue(c.internalDropHandled, "kaynak (şerit) bırakmayı aktarım saymaz")
    }

    /// PERF-14/X-02: gizli kipte 30 Hz tık yalnız imleç sıcak bölgedeyken; bölgeden çıkınca son konum bir kez bildirilir ve tık durur.
    func testPointerTrackerPollsOnlyInHotZone() {
        var mouse = NSPoint(x: 10, y: 10)
        var ticks: [NSPoint] = []
        let t = StripPointerTracker(location: { mouse }) { ticks.append($0) }
        defer { t.stop() }
        let hot: (NSPoint) -> Bool = { $0.y > 100 }
        t.watch(hot: hot)
        XCTAssertTrue(t.isWatching)
        XCTAssertFalse(t.isPolling, "bölge dışında zamanlayıcı yok")
        mouse = NSPoint(x: 10, y: 150); t.pointerMoved()
        XCTAssertTrue(t.isPolling, "bölgeye girince 30 Hz")
        mouse = NSPoint(x: 10, y: 20); t.pointerMoved()
        XCTAssertFalse(t.isPolling, "bölgeden çıkınca durur")
        XCTAssertEqual(ticks, [NSPoint(x: 10, y: 20)], "çıkış konumu bir kez bildirilir (bekleme sıfırlanır)")
        mouse = NSPoint(x: 10, y: 150)
        t.watch(hot: hot) // yinelenen çağrı izleyicileri çoğaltmaz
        t.start()
        XCTAssertTrue(t.isPolling)
        XCTAssertFalse(t.isWatching, "sürekli kip izleme kipini kapatır")
        t.stop()
        XCTAssertFalse(t.isRunning)
        // Zaten bölgedeyken izlemeye geçilirse tık hemen başlar.
        t.watch(hot: hot)
        XCTAssertTrue(t.isPolling)
        XCTAssertLessThanOrEqual(StripPointerTracker.tolerance, StripPointerTracker.interval * 0.5)
    }

    /// PERF-15: esinti imleç `gustIdleLimit` sn şeride uğramayınca durur; örtülü pencerede, sürüklemede, boş şeritte oynamaz.
    func testGustStopsWhenIdleOrHidden() {
        XCTAssertTrue(StripController.keepsGusting(idleSeconds: 0))
        XCTAssertTrue(StripController.keepsGusting(idleSeconds: StripMotion.gustIdleLimit - 0.1))
        XCTAssertFalse(StripController.keepsGusting(idleSeconds: StripMotion.gustIdleLimit), "iğneli / açık şerit boşta")
        XCTAssertTrue(StripController.shouldGust(hasItems: true, dragging: false, reduceMotion: false, windowVisible: true))
        XCTAssertFalse(StripController.shouldGust(hasItems: false, dragging: false, reduceMotion: false, windowVisible: true))
        XCTAssertFalse(StripController.shouldGust(hasItems: true, dragging: true, reduceMotion: false, windowVisible: true))
        XCTAssertFalse(StripController.shouldGust(hasItems: true, dragging: false, reduceMotion: true, windowVisible: true))
        XCTAssertFalse(StripController.shouldGust(hasItems: true, dragging: false, reduceMotion: false, windowVisible: false), "örtülü pencere")

        let (c, d, suite) = makeController()
        defer { c.hide(reason: "test"); d.removePersistentDomain(forName: suite) }
        XCTAssertFalse(c.isGustScheduled)
        c.show(takeKey: false)
        XCTAssertTrue(c.isGustScheduled, "inişte esinti kurulur")
        c.hide(reason: "test")
        XCTAssertFalse(c.isGustScheduled, "gizliyken esinti yok")
    }

    /// PERF-16: aynı ekrandaki düşmeler tek katman penceresini paylaşır; son hareket bitince pencere kapanır.
    func testFallsShareOneOverlayWindow() throws {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { throw XCTSkip("ekran yok") }
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(ctx.makeImage())
        XCTAssertEqual(CaptureFlight.overlayWindowCount, 0)
        let card = CGRect(x: screen.frame.midX, y: screen.frame.maxY - 200, width: 100, height: 80)
        for i in 0..<5 { CaptureFlight.fall(image: image, card: card.offsetBy(dx: CGFloat(i) * 110, dy: 0), tilt: 2, on: screen) }
        XCTAssertEqual(CaptureFlight.overlayWindowCount, 1, "beş düşme tek pencerede")
        XCTAssertEqual(CaptureFlight.flightsInProgress, 0, "düşme uçuş sayılmaz")
        let done = expectation(description: "düşmeler bitti")
        DispatchQueue.main.asyncAfter(deadline: .now() + StripMotion.fallDuration + 0.4) { done.fulfill() }
        wait(for: [done], timeout: 3)
        XCTAssertEqual(CaptureFlight.overlayWindowCount, 0, "boşta katman penceresi tutulmaz")
    }

    // MARK: EFF-23: klavye komutları, sekmeye bırakma kaynağı, scrollToVisible

    private func makeLongController(count: Int) -> (StripController, UserDefaults, String) {
        let suite = "dev.shotmori.tests.stripbehavior.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!; d.removePersistentDomain(forName: suite)
        let prefs = Preferences(defaults: d)
        let c = StripController(store: ShelfStore(fileURL: nil, maxItems: 30), registry: ActionRegistry(prefs: prefs), prefs: prefs,
                                detachedShelves: { [] }, onDetachedTabClicked: { _ in }, watchedFolder: { nil }, reduceMotion: { true })
        for i in 0..<count { c.store.add(ShelfItem(path: "/nonexistent/shotmori-strip-behavior/k\(i).png", fileID: nil, capturedAt: Date())) }
        c.reload()
        return (c, d, suite)
    }

    /// ⌘→/⌘← uç karta gider ve kartı görünür alana kaydırır; ok tuşu tek adım, ⇧ ile seçimi genişletir.
    func testKeyboardMoveFirstLastScrollsToVisible() {
        let (c, d, suite) = makeLongController(count: 14)
        defer { d.removePersistentDomain(forName: suite) }
        let ids = c.model.items.map(\.id)
        let width = c.panel.frame.width, half = StripLayout.cardWidth / 2
        c.selectNewest()
        XCTAssertEqual(c.model.selection, [ids[0]])

        c.perform(.last)
        XCTAssertEqual(c.model.selection, [ids[13]])
        XCTAssertGreaterThan(c.model.scrollOffset, 0, "son karta kaydırıldı")
        let xl = StripLayout.x(index: 13, scrollOffset: c.model.scrollOffset)
        XCTAssertTrue(xl - half >= -0.5 && xl + half <= width + 0.5, "son kart tam görünür")
        XCTAssertLessThanOrEqual(c.model.scrollOffset, StripLayout.maximumOffset(count: 14, width: width))

        c.perform(.first)
        XCTAssertEqual(c.model.selection, [ids[0]])
        XCTAssertEqual(c.model.scrollOffset, 0, "ilk karta dönünce baştan")

        c.perform(.move(1, extend: false))
        XCTAssertEqual(c.model.selection, [ids[1]])
        c.perform(.move(1, extend: true))
        XCTAssertEqual(c.model.selection, [ids[1], ids[2]], "⇧ seçimi genişletir")
        c.perform(.move(-1, extend: false))
        XCTAssertEqual(c.model.selection.count, 1)
    }

    /// 1–9: numarası verilen görünür kart seçilir; numara kaydırmayla yeniden dağıtılır.
    func testKeyboardSelectNumber() throws {
        let (c, d, suite) = makeLongController(count: 6)
        defer { d.removePersistentDomain(forName: suite) }
        let ids = c.model.items.map(\.id)
        XCTAssertEqual(c.model.quickNumbers[ids[0]], 1)
        let second = try XCTUnwrap(c.model.quickNumbers.first { $0.value == 2 }?.key)
        c.perform(.selectNumber(2))
        XCTAssertEqual(c.model.selection, [second])
        XCTAssertEqual(second, ids[1], "gösterim sırası")
    }

    /// Tab/⇧Tab raflar arasında döner; ayrı pencerede duran raf atlanır.
    func testKeyboardNextShelfCycles() throws {
        var detached: Set<UUID> = []
        let suite = "dev.shotmori.tests.stripbehavior.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!; d.removePersistentDomain(forName: suite)
        defer { d.removePersistentDomain(forName: suite) }
        let prefs = Preferences(defaults: d)
        let c = StripController(store: ShelfStore(fileURL: nil, maxItems: 5), registry: ActionRegistry(prefs: prefs), prefs: prefs,
                                detachedShelves: { detached }, onDetachedTabClicked: { _ in }, watchedFolder: { nil }, reduceMotion: { true })
        let a = c.store.activeShelfID
        let b = try XCTUnwrap(c.store.addShelf(name: "B")).id
        let e = try XCTUnwrap(c.store.addShelf(name: "C")).id
        c.store.setActiveShelf(id: a)
        c.perform(.nextShelf)
        XCTAssertEqual(c.store.activeShelfID, b)
        c.perform(.previousShelf)
        XCTAssertEqual(c.store.activeShelfID, a)
        detached = [b]
        c.perform(.nextShelf)
        XCTAssertEqual(c.store.activeShelfID, e, "ayrı pencerede duran raf atlanır")
        c.perform(.nextShelf)
        XCTAssertEqual(c.store.activeShelfID, a, "döngü")
    }

    /// Sekmeye bırakma, kaynağı (başka şerit denetleyicisi) iç bırakma olarak işaretler; hedef değil.
    func testDropOnTabMarksSourceStrip() throws {
        let (c, d, suite) = makeController()
        defer { d.removePersistentDomain(forName: suite) }
        let (source, sd, ssuite) = makeController()
        defer { sd.removePersistentDomain(forName: ssuite) }
        let first = c.store.activeShelfID
        let target = try XCTUnwrap(c.store.addShelf(name: "Hedef"))
        c.store.setActiveShelf(id: first)
        let a = ShelfItem(path: "/nonexistent/shotmori-strip-behavior/src.png", fileID: nil, capturedAt: Date())
        c.store.add(a)
        XCTAssertTrue(c.dropItems([a.id], onShelf: target.id, source: source))
        XCTAssertTrue(source.internalDropHandled, "kaynak şerit aktarım saymaz")
        XCTAssertFalse(c.internalDropHandled)
        XCTAssertFalse(c.dropItems([a.id], onShelf: first, source: nil), "etkin rafa bırakma yok")
    }

    // MARK: A11Y-14 / A11Y-15

    /// Sekme VoiceOver eylemleri: ayrı pencerede duran raf etikette söylenir; ayırma yalnız bağlantı varken ve son takılı raf değilken.
    func testTabAccessibilityActions() throws {
        let tab = StripTab(id: UUID(), title: "Raf 2", count: 3, active: false, detached: true)
        XCTAssertEqual(StripTabChip.accessibilityLabel(for: tab), "\(S.shelfTabAX("Raf 2", 3)), \(S.shelfInWindowBadge)")
        var plain = tab; plain.detached = false
        XCTAssertEqual(StripTabChip.accessibilityLabel(for: plain), S.shelfTabAX("Raf 2", 3))

        let (c, d, suite) = makeController()
        defer { d.removePersistentDomain(forName: suite) }
        let b = try XCTUnwrap(c.store.addShelf(name: "B"))
        c.reload()
        XCTAssertEqual(c.model.tabs.map(\.canDetach), [false, false], "bağlantı yokken ayırma yok")
        var requested: [UUID] = []
        c.onDetachRequest = { requested.append($0) }
        c.reload()
        XCTAssertEqual(c.model.tabs.map(\.canDetach), [true, true])
        c.detachTab(b.id)
        XCTAssertEqual(requested, [b.id], "VoiceOver eylemi sağ tık menüsüyle aynı iş")
    }

    /// Kalıcı bildirim varken Esc önce bildirimi kapatır (şerit açık kalır), ↩ "Yeniden dene"yi çalıştırır.
    func testEscDismissesNoticeReturnRetries() {
        XCTAssertEqual(StripController.noticeKeyAction(.close, persistentNotice: true, hasRetry: false), .dismiss)
        XCTAssertNil(StripController.noticeKeyAction(.close, persistentNotice: true, hasRetry: false, quickLookOpen: true), "önce Quick Look kapanır")
        XCTAssertNil(StripController.noticeKeyAction(.close, persistentNotice: false, hasRetry: false))
        XCTAssertEqual(StripController.noticeKeyAction(.copyAndClose, persistentNotice: true, hasRetry: true), .retry)
        XCTAssertNil(StripController.noticeKeyAction(.copyAndClose, persistentNotice: true, hasRetry: false), "denenemeyen bildirimde ↩ kopyalar")
        XCTAssertNil(StripController.noticeKeyAction(.copy, persistentNotice: true, hasRetry: true))

        let (c, d, suite) = makeController()
        defer { c.hide(reason: "test"); d.removePersistentDomain(forName: suite) }
        c.show(takeKey: false)
        var retried = 0
        c.showNotice("yükleme başarısız", retry: { retried += 1 })
        c.perform(.copyAndClose)
        XCTAssertEqual(retried, 1)
        XCTAssertNil(c.model.notice)
        XCTAssertTrue(c.isVisible)
        c.showNotice("kalıcı")
        c.perform(.close)
        XCTAssertNil(c.model.notice, "Esc bildirimi kapatır")
        XCTAssertTrue(c.isVisible, "şerit açık kalır")
        c.perform(.close)
        XCTAssertFalse(c.isVisible, "bildirim yokken Esc şeridi çeker")
    }
}
