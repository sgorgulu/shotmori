import Foundation

/// Dışa bağlantılar (Ayarlar › Hakkında). Site dile göre: Türkçe arayüz `/tr/`, diğerleri İngilizce kök.
enum Links {
    static let site = URL(string: "https://shotmori.com/")!
    static func help(language: String) -> URL { page("help", language: language) }
    static func privacy(language: String) -> URL { page("privacy", language: language) }
    private static func page(_ slug: String, language: String) -> URL {
        language.lowercased().hasPrefix("tr") ? site.appending(path: "tr/\(slug)/") : site.appending(path: "\(slug)/")
    }
    /// Uygulamanın o an kullandığı dil ("tr"/"en"): paketin tercih edilen yerelleştirmesi.
    static var currentLanguage: String { Bundle.main.preferredLocalizations.first ?? "en" }
}
