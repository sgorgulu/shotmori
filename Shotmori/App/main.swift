import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Tembel: test ana bilgisayarında (XCTest) hiç oluşturulmaz; gerçek raf dosyası, durum öğesi ve panel test sürecine dokunmaz.
    lazy var controller = AppController()
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let a = AppPaths.forcedAppearance { NSApp.appearance = a; Log.info("QA görünümü: istenen=\(a.name.rawValue) etkin=\(NSApp.effectiveAppearance.name.rawValue)") } // yalnız QA ortamı
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return } // test ana bilgisayarı
        if let pid = RelaunchGate.waitPID() { RelaunchGate.wait(for: pid) } // yeniden başlatma: eski örnek kapansın
        controller.start()
    }
    /// "Birlikte Aç" ile gelen dosyalar ve `shotmori://` bağlantıları. Test ana bilgisayarında denetleyici oluşturulmaz.
    func application(_ application: NSApplication, open urls: [URL]) {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        controller.handleOpen(urls)
    }
    @objc func openSettings() { controller.openSettings() } // ana menü: nil hedef, yanıt zincirinde temsilci
    @objc func showAbout() { controller.showAbout() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.mainMenu = MainMenu.build()
app.run()
