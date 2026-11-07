import AppKit

/// Rafı kullanıcıya gösteren yüzey: yüzen panel ya da (sonra) üst şerit. Uygulama tek arayüzle konuşur.
protocol ShelfPresenting: AnyObject {
    var isVisible: Bool { get }
    var isBusy: Bool { get }
    var displayedShelfID: UUID { get }
    var showsTabs: Bool { get }
    func show(takeKey: Bool)
    func hide(reason: String)
    func toggle()
    func reload()
    /// Görünürse hemen yeniden kurar, gizliyse işi bir sonraki gösterime bırakır (gizli yüzey için bulut/tercih olaylarında boşuna kurulum yok).
    func setNeedsReload()
    func selectNewest()
    func activateShelf(_ id: UUID)
    func run(_ id: String, items: [ShelfItem], anchor: NSView?)
    func showToast(_ text: String)
    func showNotice(_ text: String)
    /// Kalıcı bildirim + tek eylem bağlantısı (yükleme hatasında "Yeniden dene").
    func showNotice(_ text: String, action: NoticeAction)
    func setBusy(_ text: String?)
    func syncPinFromPrefs()
}

/// Kalıcı bildirimdeki eylem bağlantısı: başlık eylemden gelir. `runsOnReturn`: bildirim varken ↩ eylemi çalıştırır
/// (yeniden deneme); false ise ↩ olağan kopyalamadır.
struct NoticeAction {
    let title: String
    var runsOnReturn = false
    let run: () -> Void
    init(title: String, runsOnReturn: Bool = false, run: @escaping () -> Void) { self.title = title; self.runsOnReturn = runsOnReturn; self.run = run }
}

#if SHOTMORI_CLOUD
extension ShelfPresenting {
    /// Yükleme hatası: "Yeniden dene" (↩ da çalıştırır).
    func showNotice(_ text: String, retry: @escaping () -> Void) { showNotice(text, action: NoticeAction(title: S.cloudRetry, runsOnReturn: true, run: retry)) }
}
#endif

extension ShelfPresenting {
    /// Varsayılan: yalnız görünürken yeniden kur. Gizli yüzey gösterilirken zaten yeniden kurulur
    /// (`ShelfPanelController.show` her zaman, `StripController.reveal` gizliyken inişte).
    func setNeedsReload() { if isVisible { reload() } }
}
