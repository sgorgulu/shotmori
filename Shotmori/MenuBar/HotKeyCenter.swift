import AppKit
import Carbon

/// Carbon RegisterEventHotKey: sandbox/izin gerektirmez (D3 deneyi, status=0).
final class HotKeyCenter {
    private var ref: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    var onPress: (() -> Void)?
    private static let signature: OSType = 0x53484D52 // 'SHMR'

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData = userData else { return noErr }
            let me = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { me.onPress?() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }
    deinit { unregister(); if let h = handlerRef { RemoveEventHandler(h) } }

    func register(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        unregister()
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let st = RegisterEventHotKey(keyCode, Self.carbonModifiers(modifiers), id, GetApplicationEventTarget(), 0, &ref)
        Log.info("Kısayol kaydı \(HotKeyCenter.display(keyCode: keyCode, modifiers: modifiers)) status=\(st)")
    }
    func unregister() { if let r = ref { UnregisterEventHotKey(r); ref = nil } }

    static func carbonModifiers(_ f: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if f.contains(.command) { m |= UInt32(cmdKey) }
        if f.contains(.option) { m |= UInt32(optionKey) }
        if f.contains(.control) { m |= UInt32(controlKey) }
        if f.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }
    static func display(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) -> String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + keyName(keyCode)
    }
    /// Tuş adı (L10N-03): harf, rakam ve noktalama etkin klavye düzeninden (Türkçe F'de fiziksel tuşun kendi harfi);
    /// Boşluk yerelleştirilmiş, işlev/ok/denetim tuşları sembol; bilinmeyen tuş "Tuş %d".
    static func keyName(_ code: UInt32) -> String { knownKeyName(code) ?? S.keyCodeName(Int(code)) }
    /// Bilinen tuşun adı; adı çıkarılamayan tuşta nil (çağıran başka bir ad kullanabilir, ör. macOS'un sakladığı karakter).
    static func knownKeyName(_ code: UInt32) -> String? {
        if code == 49 { return S.keySpace }
        if let fixed = fixedNames[code] { return fixed }
        if let ch = keyCharacter(code) { return ch.localizedUppercase }
        return usFallback[code]
    }
    /// Menü kısayol alanı için tek karakter (küçük harf, etkin düzenden); düzen okunamazsa ABD tablosu. İşlev/denetim tuşunda nil.
    static func keyEquivalent(_ code: UInt32) -> String? {
        guard fixedNames[code] == nil, code != 49 else { return nil }
        let ch = keyCharacter(code) ?? usFallback[code]?.lowercased()
        return ch.flatMap { $0.count == 1 ? $0 : nil }
    }
    /// ABD düzenindeki ad (harf/rakam/noktalama); tabloda yoksa nil. macOS ekran görüntüsü kısayolları düzenden bağımsız
    /// bu adla anlatılır (AZERTY'de de "⇧⌘4"), `ScreenshotHotKeys` bunu kullanır.
    static func usName(_ code: UInt32) -> String? { usFallback[code] }
    /// Düzenden bağımsız tuşlar: Return, Tab, Sil, Esc, F1–F12, oklar.
    private static let fixedNames: [UInt32: String] = [36: "↩", 48: "⇥", 51: "⌫", 53: "⎋",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11", 109: "F10", 111: "F12", 118: "F4", 120: "F2", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑"]
    /// Klavye düzeni okunamazsa (ör. test ortamı): ABD düzeni.
    private static let usFallback: [UInt32: String] = [0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 50: "`"]
    /// Etkin ASCII uyumlu klavye düzeninde tuşun değiştiricisiz karakteri (`UCKeyTranslate`); yazdırılamıyorsa nil.
    static func keyCharacter(_ code: UInt32) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        var dead: UInt32 = 0, length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { buf -> OSStatus in
            guard let layout = buf.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return OSStatus(paramErr) }
            return UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysMask), &dead, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        let s = String(utf16CodeUnits: chars, count: length)
        guard !s.isEmpty, s.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && !CharacterSet.whitespacesAndNewlines.contains($0) }) else { return nil }
        return s
    }
}
