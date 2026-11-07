import AppKit

/// Onay diyaloglarının güvenli varsayılanları (B): ilk düğme güvenli seçenek (Return ve Esc), ikinci düğme asıl/yıkıcı işlem.
/// Return kazara yıkıcı işleme gitmez; "devam" yalnızca ikinci düğmenin yanıt koduyla kabul edilir.
enum ConfirmDialog {
    /// Yalnızca bu yanıt "devam et" demektir.
    static let proceedResponse: NSApplication.ModalResponse = .alertSecondButtonReturn
    static func shouldProceed(_ r: NSApplication.ModalResponse) -> Bool { r == proceedResponse }
    /// Asıl düğmenin tuşu: ⌘⌫ (Backspace + Komut).
    static let proceedKeyEquivalent = "\u{8}"

    /// `safe` ilk ve varsayılan düğme (Return), `proceed` ikinci düğme; Esc `run` içinde güvenli düğmeye yönlendirilir.
    /// NSAlert, Esc tuş eşdeğeri verilen düğmeyi varsayılan olmaktan çıkardığı için ikisi aynı düğmede yalnızca `run` ile birleşir.
    @discardableResult
    static func configure(_ a: NSAlert, safe: String, proceed: String, destructive: Bool, symbol: String? = nil) -> NSAlert {
        let s = a.addButton(withTitle: safe); let p = a.addButton(withTitle: proceed)
        s.keyEquivalent = "\r"          // Return → güvenli (varsayılan düğme)
        // Asıl işlem: tıklama, odak + Boşluk ya da bilinçli ⌘⌫ (Tam Klavye Erişimi kapalıyken de klavyeden ulaşılır; Return/Esc güvenli kalır).
        p.keyEquivalent = proceedKeyEquivalent; p.keyEquivalentModifierMask = [.command]
        p.hasDestructiveAction = destructive
        if let name = symbol, let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 30, weight: .regular)) { a.icon = img }
        return a
    }
    static func isEscape(_ e: NSEvent) -> Bool { e.type == .keyDown && e.keyCode == 53 && e.modifierFlags.intersection([.command, .control, .option]).isEmpty }
    /// Modal çalıştırır; Esc güvenli (ilk) düğmeye basar. Yanıt `shouldProceed` ile okunur.
    static func run(_ a: NSAlert) -> NSApplication.ModalResponse {
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            guard isEscape(e), e.window === a.window, let safe = a.buttons.first else { return e }
            safe.performClick(nil); return nil
        }
        defer { if let m = monitor { NSEvent.removeMonitor(m) } }
        return a.runModal()
    }

    /// Dosya listesi: tam adlar, seçilebilir ve klavyeyle incelenebilir (salt okunur metin); uzun listede kaydırılır.
    static func fileListAccessory(_ names: [String], width: CGFloat = 360) -> NSView {
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 10))
        tv.isEditable = false; tv.isSelectable = true; tv.drawsBackground = false
        tv.font = ShotmoriStyle.Fonts.control; tv.textColor = ShotmoriStyle.text
        tv.string = names.joined(separator: "\n"); tv.isVerticallyResizable = true; tv.textContainerInset = NSSize(width: 6, height: 6)
        tv.setAccessibilityLabel(names.count == 1 ? names[0] : S.imageCount(names.count)) // çıplak sayı değil: "3 görüntü"
        let sv = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: min(CGFloat(names.count) * 18 + 14, 112)))
        sv.documentView = tv; sv.hasVerticalScroller = names.count > 5; sv.drawsBackground = true; sv.backgroundColor = ShotmoriStyle.surface
        sv.borderType = .noBorder; sv.wantsLayer = true; sv.layer?.cornerRadius = 8
        return sv
    }
}
