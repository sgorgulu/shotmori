#if DEBUG
import AppKit

/// Yalnız Debug/QA: `SHOTMORI_QA_OPEN=settings|about|editor|resize|onboarding|panel|panel-detached|popover|strip|strip-selected` ayarlıysa
/// açılışta ilgili yüzey hemen gösterilir (ekran görüntüsü otomasyonu: `scripts/qa-shots.sh`, mağaza görüntüleri `scripts/store-shots/`). Release'te derlenmez.
/// Mağaza görüntüleri için isteğe bağlı ayarlar (hepsi yalnız görünümü kurar, dosyaya/tercihe yazmaz):
/// `SHOTMORI_QA_ITEM` (editör/boyutlandır için etkin raftaki öğe sırası), `SHOTMORI_QA_SELECT` / `SHOTMORI_QA_SELECT2` (panelde / ayrı pencerede
/// seçilecek ilk n kart), `SHOTMORI_QA_EDIT` (`crop=x,y,w,h;redact=x,y,w,h|x,y,w,h;tool=redact`, görüntü pikseli),
/// `SHOTMORI_QA_RESIZE` (`50,jpeg`), `SHOTMORI_QA_PLACE` (`panel=x,y;detached=x,y;editor=x,y;resize=x,y;settings=x,y[,g,y];strip=x,y,g,y`, ana ekranın sol-üstünden nokta; dört değerde boyut da).
enum QAOpen {
    private static var env: [String: String] { ProcessInfo.processInfo.environment }
    static func apply(app: AppController) {
        guard let which = env["SHOTMORI_QA_OPEN"], !which.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { open(which, app: app) }
        for t in [1.8, 3.2] { DispatchQueue.main.asyncAfter(deadline: .now() + t) { place(app: app) } } // editör/boyutlandır geç yüklenir
        // `SHOTMORI_QA_KEY=panel|deactivate`: etkin olmayan pencere/uygulama görünümü provası (birincil düğme karşıtlığı).
        if let k = env["SHOTMORI_QA_KEY"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.6) {
                if k == "panel" { app.panel.panel.makeKey() } else if k == "deactivate" { NSApp.deactivate() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    Log.info("QA anahtar: appActive=\(NSApp.isActive) " + NSApp.windows.filter(\.isVisible).map { "\(type(of: $0)) key=\($0.isKeyWindow) main=\($0.isMainWindow)" }.joined(separator: ", "))
                }
            }
        }
    }
    private static func open(_ which: String, app: AppController) {
        switch which {
        case "settings": app.openSettings()
        case "about": app.openSettingsPage(.about)
        case "shelf-settings": app.openSettingsPage(.shelf)
        case "actions-settings": app.openSettingsPage(.actions)
        case "cloud-settings": app.openSettingsPage(.cloud)
        case "panel":
            app.shelf.show(takeKey: true)
            if let n = Int(env["SHOTMORI_QA_SELECT"] ?? ""), n > 0 { app.panel.qaSelectFirst(n) }
        case "panel-detached":
            // Mağaza karesi: ana panel + ikinci raf ayrı pencerede (gerçek `detach` yolu).
            app.panel.show(takeKey: false)
            if app.store.shelves.count > 1 { app.detach(app.store.shelves[1].id) }
            if let n = Int(env["SHOTMORI_QA_SELECT"] ?? ""), n > 0 { app.panel.qaSelectFirst(n) }
            if let n = Int(env["SHOTMORI_QA_SELECT2"] ?? ""), n > 0 { app.detached.values.first?.qaSelectFirst(n) }
        case "strip", "strip-selected":
            // shelfStyle=strip tercihini qa-shots.sh yalıtılmış `dev.shotmori.qa` takımına yazar; burada tercih yazılmaz.
            app.shelf.show(takeKey: true)
            if which == "strip-selected" {
                MainActor.assumeIsolated {
                    let sc = app.stripController
                    sc.reload()
                    sc.sel.set(Set(sc.displayedItems.prefix(2).map(\.id)), anchor: sc.displayedItems.first?.id)
                    sc.applySelection()
                }
            }
        case "popover": app.status.showPopoverForQA()
        case "onboarding": app.showOnboarding(); if let n = Int(env["SHOTMORI_QA_PAGE"] ?? "") { app.onboardingWC?.showPageForQA(n) }
        case "editor", "resize":
            let idx = Int(env["SHOTMORI_QA_ITEM"] ?? "") ?? 0
            guard app.store.items.indices.contains(idx) else { Log.error("QA: raf boş, \(which) açılamadı"); return }
            let item = app.store.items[idx]
            app.shelf.show(takeKey: false)
            app.shelf.run(which == "editor" ? "edit" : "resize", items: [item], anchor: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if which == "editor", let spec = env["SHOTMORI_QA_EDIT"] { EditorWindowController.current?.qaApply(spec) }
                if which == "resize", let spec = env["SHOTMORI_QA_RESIZE"] { ResizeWindowController.current?.qaApply(spec) }
            }
        default: Log.error("QA: bilinmeyen yüzey \(which)")
        }
    }
    /// `SHOTMORI_QA_PLACE`: pencereleri verilen sol-üst noktalara taşır (mağaza karesinin yerleşimi imleç konumuna bağlı kalmasın).
    private static func place(app: AppController) {
        guard let spec = env["SHOTMORI_QA_PLACE"], let top = NSScreen.screens.first?.frame.maxY else { return }
        for part in spec.split(separator: ";") {
            let kv = part.split(separator: "="); guard kv.count == 2 else { continue }
            let xy = kv[1].split(separator: ",").compactMap { Double($0) }; guard xy.count == 2 || xy.count == 4 else { continue }
            let w: NSWindow?
            switch kv[0] {
            case "panel": w = app.panel.panel
            case "detached": w = app.detached.values.first?.panel
            case "editor": w = EditorWindowController.current?.window
            case "resize": w = ResizeWindowController.current?.window
            case "settings": w = NSApp.windows.first { $0.isVisible && $0.styleMask.contains(.titled) && !($0 is NSPanel) }
            case "strip": w = MainActor.assumeIsolated { app.stripController.panel } // dar ekran provası: şerit verilen genişlikte yeniden yerleşir
            default: w = nil
            }
            if xy.count == 4, let w { w.setFrame(NSRect(x: xy[0], y: top - xy[1] - xy[3], width: xy[2], height: xy[3]), display: true) } // x,y,genişlik,yükseklik
            else { w?.setFrameTopLeftPoint(NSPoint(x: xy[0], y: top - xy[1])) }
        }
    }
}
#endif
