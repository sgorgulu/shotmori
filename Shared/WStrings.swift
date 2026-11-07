import Foundation

/// Widget uzantısı metinleri. Kaynak: ShotmoriWidgets/{tr,en}.lproj/Localizable.strings.
/// Üreteç: scripts/gen_strings.py (tablo W) — elle düzenlenmez. `Bundle.main` uzantı sürecinde uzantı paketidir.
/// Dil: `languageOverride` (anlık görüntüdeki uygulama dili, "tr"/"en") verilirse o `.lproj` okunur; yoksa sistem dili.
enum WS {
    /// Ana uygulamanın seçtiği arayüz dili; uzantı bunu `widget-snapshot.json`dan alır. nil = sistem dili.
    static var languageOverride: String?
    static var widgetRecentTitle: String { WL("widgetRecentTitle") }
    static var widgetRecentDesc: String { WL("widgetRecentDesc") }
    static var widgetEmpty: String { WL("widgetEmpty") }
    static func widgetNew(_ n: Int) -> String { n == 1 ? WL("widgetNew.one") : WF("widgetNew.other", n) }
    static func widgetTotal(_ n: Int) -> String { n == 1 ? WL("widgetTotal.one") : WF("widgetTotal.other", n) }
    static var cmdShowTitle: String { WL("cmdShowTitle") }
    static var cmdClipboardTitle: String { WL("cmdClipboardTitle") }
    static var cmdCopyLatestTitle: String { WL("cmdCopyLatestTitle") }

    /// `languageOverride` paketi varsa o, yoksa `Bundle.main` (sistem dili seçimi).
    static var bundle: Bundle {
        guard let code = languageOverride, let url = Bundle.main.url(forResource: code, withExtension: "lproj"), let b = Bundle(url: url) else { return .main }
        return b
    }
}

@inline(__always) private func WL(_ key: String) -> String { WS.bundle.localizedString(forKey: key, value: nil, table: nil) }
private func WF(_ key: String, _ args: CVarArg...) -> String {
    String(format: WS.bundle.localizedString(forKey: key, value: nil, table: nil), arguments: args)
}
