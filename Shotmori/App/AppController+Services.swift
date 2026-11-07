import AppKit

/// Finder Servisi ("Shotmori rafına ekle", Info.plist `NSServices` → `addToShelfService`).
/// Pasteboard'daki dosyalar ya da (dosya yoksa) görsel verisi tek giriş kapısından (`Gelen/`) etkin rafa.
/// `NSUpdateDynamicServices()` çağrılmaz: sistem kurulumda tarar; geliştirmede `pbs -update`.
extension AppController {
    func installServices() {
        NSApp.servicesProvider = self
    }

    @objc func addToShelfService(_ pb: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = ServicePasteboard.fileURLs(from: pb)
        if !urls.isEmpty {
            Log.info("Servis: \(urls.count) dosya geldi")
            importExternal(urls, source: .service)
        } else if let (data, ext) = ServicePasteboard.imageData(from: pb) {
            Log.info("Servis: görsel verisi geldi")
            importExternalData(data, ext: ext, source: .service)
        } else {
            Log.info("Servis: görsel yok, reddedildi")
            error.pointee = S.inboundRejected as NSString
        }
    }
}
