import AppKit

/// `application(_:open:)`: "Birlikte Aç" dosyaları tek giriş kapısından rafa, `shotmori:` bağlantıları URL komutuna.
extension AppController {
    func handleOpen(_ urls: [URL]) {
        guard Self.shared === self else {
            // Açılışta olay `start()`tan önce gelebilir: hazır olunca işlenir; süre dolarsa düşer.
            Task { @MainActor [weak self] in
                guard let self, (try? await Self.ready()) === self else { Log.info("Açılış: \(urls.count) öğe hazır olmadan geldi, işlenmedi"); return }
                self.dispatchOpen(urls)
            }
            return
        }
        dispatchOpen(urls)
    }

    private func dispatchOpen(_ urls: [URL]) {
        let files = urls.filter(\.isFileURL)
        if !files.isEmpty { importExternal(files, source: .openWith) }
        for u in urls where u.scheme?.lowercased() == "shotmori" { handleURLCommand(u) }
    }
}
