import Foundation

/// `shotmori://` komutları: saf ayrıştırıcı + izin kapısı kararı (yürütme `AppController+URLScheme`).
/// Beyaz liste dışı her şey sessizce reddedilir (nil). Hiçbir komut dosya yolu almaz; yıkıcı komut ve yükleme yok.
/// Panoya veri yazan komut yok: son görüntüyü kopyalama yalnız kimlikli yoldan (`CopyLatestIntent`, menü), URL izniyle açılmaz (SEC-04).
enum URLCommand: Equatable {
    case show(shelf: Int?), hide, toggle(shelf: Int?), addClipboard, newShelf(name: String?), selectShelf(index: Int), settings(page: SettingsPage?)

    static let scheme = "shotmori"
    /// Raf numarası URL'de 1 tabanlı; üst sınır raf sayısı sınırı.
    static let shelfRange = 1...ShelfStore.maxShelves
    /// Hangi komutta görünürse görünsün URL'yi geçersiz kılan anahtarlar (dosya/konum taşıyabilecek her şey).
    static let forbiddenKeys: Set<String> = ["path", "file", "url"]
    /// Komut → izin verilen sorgu anahtarları.
    private static let allowedKeys: [String: Set<String>] = [
        "show": ["shelf"], "hide": [], "toggle": ["shelf"], "add-clipboard": [],
        "new-shelf": ["name"], "shelf": ["index"], "settings": ["page"],
    ]

    static func parse(_ url: URL) -> URLCommand? {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              c.scheme?.lowercased() == scheme,
              c.user == nil, c.password == nil, c.port == nil, c.fragment == nil,
              c.path.isEmpty || c.path == "/",
              let command = c.host?.lowercased(), let allowed = allowedKeys[command] else { return nil }
        var q: [String: String] = [:]
        for item in c.queryItems ?? [] {
            let key = item.name.lowercased()
            guard !forbiddenKeys.contains(key), allowed.contains(key), q[key] == nil else { return nil }
            q[key] = item.value ?? ""
        }
        func shelfNumber(_ key: String) -> Int?? {
            guard let raw = q[key] else { return .some(nil) }       // parametre yok → geçerli, nil
            guard let n = Int(raw), shelfRange.contains(n) else { return nil } // var ama geçersiz → ret
            return .some(n)
        }
        switch command {
        case "show": guard let s = shelfNumber("shelf") else { return nil }; return .show(shelf: s)
        case "toggle": guard let s = shelfNumber("shelf") else { return nil }; return .toggle(shelf: s)
        case "hide": return .hide
        case "add-clipboard": return .addClipboard
        case "new-shelf":
            let name = (q["name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { return .newShelf(name: nil) }
            guard name.count <= ShelfStore.maxNameLength, name.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return nil }
            return .newShelf(name: name)
        case "shelf": guard let s = shelfNumber("index"), let n = s else { return nil }; return .selectShelf(index: n)
        case "settings": return .settings(page: q["page"].flatMap(SettingsPage.init(rawValue:)))
        default: return nil
        }
    }

    enum GateDecision: Equatable { case run, ask, drop }
    /// Anahtar açık → yürüt; hiç sorulmadıysa → sor; sorulup reddedildiyse → sessizce düşür.
    static func gate(enabled: Bool, asked: Bool) -> GateDecision { enabled ? .run : (asked ? .drop : .ask) }

    /// Kapıyı tercihlere uygular. `.ask` ise `ask()` bir kez çağrılır; yanıt ne olursa olsun `urlSchemeAsked` kaydedilir,
    /// yalnız izin verilirse anahtar açılır. Döndürür: komut yürütülsün mü.
    static func authorize(prefs: Preferences, ask: () -> Bool) -> Bool {
        switch gate(enabled: prefs.urlSchemeEnabled, asked: prefs.urlSchemeAsked) {
        case .run: return true
        case .drop: return false
        case .ask:
            let allowed = ask()
            prefs.urlSchemeAsked = true
            if allowed { prefs.urlSchemeEnabled = true }
            prefs.notifyChanged()
            return allowed
        }
    }

    /// Günlük için komut adı (parametre değeri yok).
    var logName: String {
        switch self {
        case .show: return "show"
        case .hide: return "hide"
        case .toggle: return "toggle"
        case .addClipboard: return "add-clipboard"
        case .newShelf: return "new-shelf"
        case .selectShelf: return "shelf"
        case .settings: return "settings"
        }
    }
}
