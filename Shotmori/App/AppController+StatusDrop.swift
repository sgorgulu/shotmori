import AppKit

/// Menü çubuğu simgesine bırakma: dosyalar ya da görsel verisi tek giriş kapısından (`Gelen/`) etkin rafa.
extension AppController {
    func installStatusDrop() {
        guard let button = status.item.button, !button.subviews.contains(where: { $0 is StatusDropView }) else { return }
        let drop = StatusDropView(frame: button.bounds)
        drop.button = button
        drop.onDrop = { [weak self] urls, data in
            guard let self else { return }
            if !urls.isEmpty { self.importExternal(urls, source: .statusDrop) }
            else if let (d, ext) = data { self.importExternalData(d, ext: ext, source: .statusDrop) }
        }
        button.addSubview(drop)
    }
}
