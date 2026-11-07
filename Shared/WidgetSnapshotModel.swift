import Foundation

/// Ana uygulamanın grup konteynerine yazdığı, widget uzantısının okuduğu küçük anlık görüntü (iki hedefe de derlenir).
/// Yalnız sayılar, kimlik ve çekim zamanı; dosya adı (`fileName` eski JSON uyumu için var, boş yazılır), OCR/metin ya da tam çözünürlük görsel yok.
/// Küçük resimler sabit adlı en çok 3 dosyadır (`thumb-0.png` … `thumb-2.png`), üzerine yazılır; boşalan yuvanın dosyası 1×1 saydam PNG ile
/// ezilir (silme yok), JSON'da o yuva yoktur ya da `thumb == nil`.
struct WidgetSnapshot: Codable, Equatable {
    static let version = 1
    /// macOS'ta takım önekli App Group (profil gerektirmez). Entitlement: Shotmori, Shotmori-Debug, ShotmoriWidgets.
    static let groupID = "ANW6K6228Y.dev.shotmori"
    static let fileName = "widget-snapshot.json"
    static let maxItems = 3
    static func thumbName(_ i: Int) -> String { "thumb-\(i).png" }

    struct Item: Codable, Equatable {
        var id: UUID
        var fileName: String
        var capturedAt: Date
        var thumb: String?
    }

    var version: Int
    var totalCount: Int
    var newCount: Int
    var items: [Item]
    /// Ana uygulamada seçili arayüz dili ("tr"/"en"); nil = sistem dili. Widget metinleri bu dili izler (uzantı kendi başına uygulama tercihini okuyamaz).
    var language: String?

    /// Anlık görüntü klasörü. `isolated` (test/QA veri kökü) verilirse `<kök>/WidgetGroup` — gerçek widget bunu görmez;
    /// verilmezse sistem grup konteyneri (grup entitlement'ı yoksa nil).
    static func containerURL(isolated: URL?) -> URL? {
        if let isolated { return isolated.appendingPathComponent("WidgetGroup", isDirectory: true) }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
    }
}
