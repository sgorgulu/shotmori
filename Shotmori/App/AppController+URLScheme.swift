import AppKit

/// `shotmori://` URL şeması: beyaz liste (`URLCommand.parse`) + izin kapısı (ilk istekte tek seferlik soru, Ayarlar › Genel › Otomasyon'da anahtar).
/// Olay `application(_:open:)` → `handleOpen` üzerinden gelir; `kAEGetURL` kurulmaz (çift işleme olmasın).
/// Günlüğe yalnız komut adı ve sayaç yazılır; URL, parametre değeri, raf adı yazılmaz.
private enum URLSchemeState {
    /// Reddedilen URL sayacı (yalnız günlük için).
    static var rejected = 0
    /// İzin sorusu açıkken gelen istekler düşürülür: üst üste diyalog açılmaz.
    static var asking = false
}

extension AppController {
    func handleURLCommand(_ url: URL) {
        guard let cmd = URLCommand.parse(url) else {
            URLSchemeState.rejected += 1; Log.info("url: reddedildi (\(URLSchemeState.rejected))"); return
        }
        guard !URLSchemeState.asking else { Log.info("url: izin sorusu açıkken geldi, işlenmedi"); return }
        guard URLCommand.authorize(prefs: prefs, ask: { askURLSchemePermission() }) else { Log.info("url: izin yok, \(cmd.logName) yürütülmedi"); return }
        runURLCommand(cmd)
    }

    /// Güvenli düğme "İzin verme" (Return/Esc); "İzin ver" yalnız tıklama ya da odak + Boşluk. Menü çubuğu uygulamasında diyalog öne gelir.
    private func askURLSchemePermission() -> Bool {
        URLSchemeState.asking = true; defer { URLSchemeState.asking = false }
        var allowed = false
        ForegroundHelper.withActivation { done in
            let a = NSAlert(); a.alertStyle = .informational
            a.messageText = S.urlSchemeAskTitle; a.informativeText = S.urlSchemeAskBody
            ConfirmDialog.configure(a, safe: S.urlSchemeDeny, proceed: S.urlSchemeAllow, destructive: false, symbol: "link")
            allowed = ConfirmDialog.shouldProceed(ConfirmDialog.run(a)); done()
        }
        Log.info(allowed ? "url: izin verildi" : "url: izin verilmedi")
        return allowed
    }

    func runURLCommand(_ cmd: URLCommand) {
        Log.info("url: \(cmd.logName)")
        switch cmd {
        case .show(let n):
            guard let n else { shelf.show(takeKey: true); return }
            guard let id = shelfID(number: n) else { Log.info("url: raf yok"); return }
            focusShelf(id)
        case .hide:
            shelf.hide(reason: "url")
        case .toggle(let n):
            guard let n else { shelf.toggle(); return }
            guard let id = shelfID(number: n) else { Log.info("url: raf yok"); return }
            if shelf.isVisible && store.activeShelfID == id && !panel.detachedShelves.contains(id) { shelf.hide(reason: "url") } else { focusShelf(id) }
        case .addClipboard:
            addFromClipboard()
        case .newShelf(let name):
            guard let sh = store.addShelf(name: name) else { Log.info("url: raf sınırı dolu"); return }
            shelf.activateShelf(sh.id); shelf.reload()
        case .selectShelf(let n):
            guard let id = shelfID(number: n) else { Log.info("url: raf yok"); return }
            if panel.detachedShelves.contains(id) { panel.onDetachedTabClicked?(id) } else { shelf.activateShelf(id) }
        case .settings(let page):
            openSettingsPage(page.flatMap { SettingsPage.available.contains($0) ? $0 : nil })
        }
    }

    /// URL'deki 1 tabanlı raf numarası → kimlik; o kadar raf yoksa nil.
    private func shelfID(number n: Int) -> UUID? {
        let shelves = store.shelves
        return shelves.indices.contains(n - 1) ? shelves[n - 1].id : nil
    }
    /// Ayrılmış raf kendi penceresinde öne gelir; değilse panelde etkinleşir ve panel gösterilir.
    private func focusShelf(_ id: UUID) {
        if panel.detachedShelves.contains(id) { panel.onDetachedTabClicked?(id); return }
        shelf.activateShelf(id); shelf.show(takeKey: true)
    }
}
