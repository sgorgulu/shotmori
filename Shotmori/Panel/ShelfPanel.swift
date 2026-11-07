import AppKit
import Quartz

/// Odak çalmayan yüzen panel. `.nonactivatingPanel`: sahibi uygulamayı etkinleştirmez;
/// `canBecomeKey` ile klavye (Esc, oklar) alabilir ama önceki uygulama ön uygulama kalır.
final class ShelfPanel: NSPanel {
    weak var controller: ShelfPanelController?
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 760, height: 196),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { controller?.hide(reason: "Esc") }
    /// Pencere ▸ Kapat (⌘W): panelin kapatma düğmesi yok (`.closable` değil), NSWindow varsayılanı menüyü pasif yapar ya da bip sesi çıkarır.
    /// Panel gizlenir; ayrılmış raf paneli `hide` yoluyla sekmeye döner. Test için değiştirilebilir.
    lazy var onClose: () -> Void = { [weak self] in self?.controller?.hide(reason: "⌘W") }
    override func performClose(_ sender: Any?) { onClose() }
    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { menuItem.action == #selector(performClose(_:)) ? true : super.validateMenuItem(menuItem) }
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool { item.action == #selector(performClose(_:)) ? true : super.validateUserInterfaceItem(item) }
    /// Panelin kendi ⌘ kısayolları (`ShelfKeyboard`: ⌘C/⌘A/⌘R/⌘O/⌘K/⌘W/⌘1…⌘8 …) ana menüden önce çalışır (menüdeki ⌘C alana değil kareye gitmeli).
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Raf adı düzenlenirken (alan düzenleyicisi first responder) ⌘A/⌘C/⌘V ve tüm tuşlar metne gider.
        if firstResponder is NSText { return super.performKeyEquivalent(with: event) }
        if event.modifierFlags.contains(.command), keyHandler(event) { return true }
        return super.performKeyEquivalent(with: event)
    }
    /// Test için değiştirilebilir; varsayılan denetleyicinin handleKey'i.
    lazy var keyHandler: (NSEvent) -> Bool = { [weak self] ev in self?.controller?.handleKey(ev) == true }
    override func keyDown(with event: NSEvent) {
        if !keyHandler(event) { super.keyDown(with: event) }
    }
    // MARK: Quick Look: panel key iken sorumlu zincirinde önizleme denetleyicisi olur (uygulama etkinleştirilmez).
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) { ShelfQuickLook.shared.begin(panel) }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { ShelfQuickLook.shared.end(panel) }
}
