import AppKit
import Quartz

/// Boşluk ile Quick Look: raf yüzeyleri (yüzen panel, üst şerit) aynı paylaşılan önizleme denetleyicisini kullanır.
/// Yüzey penceresi `acceptsPreviewPanelControl` ile sorumlu zincirine girer ve `begin`/`end` çağrılarını buraya iletir.
/// Uygulama etkinleştirilmez: önizleme paneli de odak çalmayan panel olarak yüzeyin üstünde açılır; Boşluk/Esc kapatır.
final class ShelfQuickLook: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = ShelfQuickLook()
    private(set) var urls: [URL] = []
    private var startIndex = 0
    /// Denetimi alan panel (begin…end arası); nil iken veri kaynağı bağlı değildir.
    private weak var controlled: QLPreviewPanel?
    /// Önizlemeyi açan yüzey penceresi: önizleme key iken klavye olayları ona iletilir.
    private weak var host: NSWindow?

    var isOpen: Bool { QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible }

    /// Açıksa kapatır; kapalıysa `urls` ile `index`ten açar. Boş listede bip.
    /// `host`: önizlemeyi açan yüzey penceresi (çağıran önce key yapar); iki yüzey paylaştığı için açıkça kaydedilir.
    func toggle(urls: [URL], index: Int, host: NSWindow) {
        if isOpen { QLPreviewPanel.shared().orderOut(nil); return }
        guard !urls.isEmpty else { NSSound.beep(); return }
        self.urls = urls; startIndex = Self.clampedIndex(index, count: urls.count)
        guard let p = QLPreviewPanel.shared() else { return }
        p.updateController() // anahtar pencerenin sorumlu zinciri: ShelfPanel → begin(_:)
        if controlled !== p { attach(p) } else { p.reloadData(); p.currentPreviewItemIndex = startIndex }
        // Önizleme paneli gösterilince key olmak ister; olağan (etkinleştiren) panel olarak bunu yapınca uygulama ön planda değilken
        // key kaybolur ve tuşlar ön uygulamaya gider (elle denendi, 30.10.2026). Raf paneli gibi odak çalmayan panel yapılır:
        // ön uygulama değişmez, önizleme key olur; Boşluk/Esc'i kendisi kapatır, diğer tuşlar `previewPanel(_:handle:)` ile yüzeye gider.
        p.styleMask.insert(.nonactivatingPanel)
        p.hidesOnDeactivate = false
        self.host = host
        p.orderFront(nil)
        Log.info("Quick Look açıldı: \(urls.count) öğe")
    }
    /// Önizlemeyi bu pencere mi açtı (başka yüzeyin seçimi açık önizlemeyi değiştirmez).
    func isHosted(by w: NSWindow) -> Bool { host === w }
    func close() { if isOpen { QLPreviewPanel.shared().orderOut(nil) } }
    /// Yalnız bu pencerenin açtığı önizlemeyi kapatır (başka yüzeyin önizlemesine dokunmaz).
    func close(ifHostedBy w: NSWindow) { if isOpen, isHosted(by: w) { close() } }
    /// Önizleme açıkken seçim değişti: aynı panelde yeni listeye geçer; liste boşalırsa kapanır.
    func update(urls: [URL], index: Int) {
        guard isOpen else { return }
        guard !urls.isEmpty else { close(); return }
        self.urls = urls; startIndex = Self.clampedIndex(index, count: urls.count)
        if let p = controlled { p.reloadData(); p.currentPreviewItemIndex = startIndex }
    }
    static func clampedIndex(_ i: Int, count: Int) -> Int { count == 0 ? 0 : min(max(i, 0), count - 1) }

    // MARK: Yüzey penceresinden iletilir
    func begin(_ panel: QLPreviewPanel) { attach(panel) }
    func end(_ panel: QLPreviewPanel) {
        if panel.dataSource === self { panel.dataSource = nil }
        if panel.delegate === self { panel.delegate = nil }
        if controlled === panel { controlled = nil }
    }
    private func attach(_ p: QLPreviewPanel) {
        p.dataSource = self; p.delegate = self; controlled = p
        p.reloadData(); p.currentPreviewItemIndex = startIndex
    }

    // MARK: QLPreviewPanelDelegate
    /// Önizleme key iken tuşlar yüzeyin kısayollarına gider (⌘ ile olanlar `performKeyEquivalent`, diğerleri `keyDown`).
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard let e = event, e.type == .keyDown, let h = host, h.isVisible else { return false }
        if e.modifierFlags.contains(.command) { return h.performKeyEquivalent(with: e) }
        h.keyDown(with: e); return true
    }

    // MARK: QLPreviewPanelDataSource
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        urls.indices.contains(index) ? urls[index] as NSURL : nil
    }
}
