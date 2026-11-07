import AppKit

extension NSWindow {
    /// macOS 26+ cam pencere kromu: `.fullSizeContentView` + (boş ya da gerçek) araç çubuğu + birleşik araç çubuğu stili.
    /// 14–15'te aynı çağrı normal başlık çubuğu verir. İçerik, başlık çubuğunun altına girmesin diye `contentLayoutGuide`'a bağlanır.
    func applyGlassChrome(toolbarIdentifier: String, subtitle: String? = nil, delegate: NSToolbarDelegate? = nil) {
        styleMask.insert(.fullSizeContentView)
        let tb = NSToolbar(identifier: NSToolbar.Identifier(toolbarIdentifier))
        tb.delegate = delegate; tb.displayMode = .iconOnly; tb.allowsUserCustomization = false
        toolbar = tb
        toolbarStyle = .unified
        titlebarAppearsTransparent = false
        if let s = subtitle { self.subtitle = s }
    }
}
