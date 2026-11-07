import Foundation
import AppKit

/// macOS'un ekran görüntüsü kısayollarını okur (Sistem Ayarları › Klavye › Klavye Kısayolları › Ekran Görüntüleri).
/// Kaynak: `com.apple.symbolichotkeys` › `AppleSymbolicHotKeys`; girdi yoksa macOS varsayılanı geçerlidir.
enum ScreenshotHotKeys {
    enum Action: Int, CaseIterable {
        case fullScreenToClipboard = 28, areaToClipboard = 29, fullScreenToFile = 30, areaToFile = 31, optionsPanel = 184
        var defaultKey: (code: UInt32, mods: NSEvent.ModifierFlags) {
            switch self {
            case .fullScreenToClipboard: return (20, [.control, .shift, .command]) // ⌃⇧⌘3
            case .areaToClipboard: return (21, [.control, .shift, .command])       // ⌃⇧⌘4
            case .fullScreenToFile: return (20, [.shift, .command])                // ⇧⌘3
            case .areaToFile: return (21, [.shift, .command])                      // ⇧⌘4
            case .optionsPanel: return (23, [.shift, .command])                    // ⇧⌘5
            }
        }
    }
    struct Binding: Equatable { var keyCode: UInt32; var modifiers: NSEvent.ModifierFlags; var character: String?; var enabled: Bool }

    /// Yalnız Debug'da sistem tablosu okunur; Release'te (sandbox zaten okuyamaz, gizlilik bildirimi CA92.1 yalnız kendi tercihlerimiz) boş tablo → macOS varsayılanları.
    static func readTable() -> [String: Any] {
        #if DEBUG
        return UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys") ?? [:]
        #else
        return [:]
        #endif
    }
    /// `parameters = (karakter, tuşKodu, değiştiriciler)`; değiştirici bitleri NSEvent.ModifierFlags ile aynıdır.
    static func binding(_ a: Action, table: [String: Any] = readTable()) -> Binding {
        let d = a.defaultKey
        guard let e = table[String(a.rawValue)] as? [String: Any] else { return Binding(keyCode: d.code, modifiers: d.mods, character: nil, enabled: true) }
        let enabled = (e["enabled"] as? NSNumber)?.boolValue ?? true
        guard let v = e["value"] as? [String: Any], let p = v["parameters"] as? [NSNumber], p.count >= 3 else { return Binding(keyCode: d.code, modifiers: d.mods, character: nil, enabled: enabled) }
        let ch = p[0].intValue; let mods = NSEvent.ModifierFlags(rawValue: UInt(p[2].uintValue)).intersection([.control, .option, .shift, .command])
        let char = (ch > 32 && ch != 65535) ? UnicodeScalar(ch).map { String(Character($0)).uppercased() } : nil
        return Binding(keyCode: UInt32(p[1].intValue), modifiers: mods, character: char, enabled: enabled)
    }
    /// Gösterim: "⇧⌘4". Kısayol kapalıysa macOS varsayılanı değil, ⇧⌘5 seçenek paneli gösterilir (o da kapalıysa yine de ⇧⌘5).
    static func display(_ a: Action, table: [String: Any] = readTable()) -> String {
        var b = binding(a, table: table)
        if !b.enabled, a != .optionsPanel { b = binding(.optionsPanel, table: table) }
        var s = ""
        if b.modifiers.contains(.control) { s += "⌃" }; if b.modifiers.contains(.option) { s += "⌥" }
        if b.modifiers.contains(.shift) { s += "⇧" }; if b.modifiers.contains(.command) { s += "⌘" }
        // macOS'un sakladığı karakter, yoksa ABD düzeni adı (Apple bu kısayolları AZERTY'de de "⇧⌘4" diye anlatır;
        // rakam sırasının değiştiricisiz karakteri orada sembol). Düzen çevirisi yalnız son çare.
        return s + (b.character ?? HotKeyCenter.usName(b.keyCode) ?? HotKeyCenter.keyName(b.keyCode))
    }
    static var area: String { display(.areaToFile) }
    static var options: String { display(.optionsPanel) }
}
