import AppKit
import SwiftUI

/// Tıkla ve tuş bileşimine bas; en az bir ⌘/⌃/⌥ zorunlu.
final class KeyRecorderNSView: NSView {
    var onRecord: ((UInt32, NSEvent.ModifierFlags) -> Void)?
    /// Geçerli kısayol; kayıt sürmüyorsa VoiceOver değeri de güncellenir (ilk değer ve kayıt sonrası yeni kısayol okunur).
    var display: String = "" { didSet { needsDisplay = true; if !recording { setAccessibilityValue(display) } } }
    private(set) var recording = false { didSet { needsDisplay = true; setAccessibilityValue(recording ? S.hotKeyRecordHint : display) } }
    private var focused: Bool { window?.firstResponder === self }
    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 26) }
    override init(frame: NSRect) { super.init(frame: frame); setAccessibilityElement(true); setAccessibilityRole(.button); setAccessibilityLabel(S.hotKeyLabel); setAccessibilityHelp(S.hotKeyRecordStart); toolTip = S.hotKeyRecordStart }
    required init?(coder: NSCoder) { fatalError() }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self); startRecording() }
    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool { recording = false; needsDisplay = true; return true }
    func startRecording() { recording = true }
    func cancelRecording() { recording = false }
    override func accessibilityPerformPress() -> Bool { window?.makeFirstResponder(self); startRecording(); return true }
    /// Odaktayken Boşluk/Return kaydı başlatır; kayıt sırasında Esc iptal eder, ⌘/⌃/⌥ içeren bileşim kaydedilir.
    override func keyDown(with event: NSEvent) {
        if !recording {
            if event.keyCode == 49 || event.keyCode == 36 { startRecording(); return } // Boşluk / Return
            super.keyDown(with: event); return
        }
        if event.keyCode == 53 { cancelRecording(); return } // Esc iptal; odak kalır
        let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard !mods.intersection([.command, .control, .option]).isEmpty else { NSSound.beep(); return }
        onRecord?(UInt32(event.keyCode), mods); recording = false
    }
    override func draw(_ dirtyRect: NSRect) {
        // Sakin görünüm: sistem alanı gibi (yükseltilmiş dolgu + ince ayırıcı); kayıt sırasında vurgu çerçevesi.
        // Klavye odağı yalnız Tam Klavye Erişimi açıkken dış halka çizer (fareyle odaklanınca kalın mor çerçeve yok).
        let p = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        (recording ? ShotmoriStyle.selectionFill : ShotmoriStyle.elevated).setFill(); p.fill()
        (recording ? ShotmoriStyle.accent : ShotmoriStyle.separator).setStroke(); p.lineWidth = recording ? 1.5 : 1; p.stroke()
        if focused && !recording && NSApp.isFullKeyboardAccessEnabled {
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: -2, dy: -2), xRadius: 8, yRadius: 8); ShotmoriStyle.focus.setStroke(); ring.lineWidth = 2; ring.stroke()
        }
        let text = recording ? S.hotKeyRecordHint : display
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: recording ? 10 : 12, weight: .regular), .foregroundColor: recording ? ShotmoriStyle.secondaryText : ShotmoriStyle.text]
        let s = NSAttributedString(string: text, attributes: attrs); let sz = s.size()
        s.draw(at: NSPoint(x: max(6, bounds.midX - sz.width / 2), y: bounds.midY - sz.height / 2))
    }
}
struct KeyRecorder: NSViewRepresentable {
    @Binding var keyCode: UInt32
    @Binding var modifiers: NSEvent.ModifierFlags
    func makeNSView(context: Context) -> KeyRecorderNSView {
        let v = KeyRecorderNSView(); v.onRecord = { k, m in keyCode = k; modifiers = m }; return v
    }
    func updateNSView(_ v: KeyRecorderNSView, context: Context) { v.display = HotKeyCenter.display(keyCode: keyCode, modifiers: modifiers) }
}
