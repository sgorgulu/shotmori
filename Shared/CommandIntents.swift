import AppIntents

// Control Widget düğmelerinin komut intent'leri (iki hedefe de derlenir). `openAppWhenRun = true` olduğundan sistem
// `perform()`'u uygulama sürecinde çalıştırır; uzantı tarafı (SHOTMORI_WIDGET) yalnız `.result()` döndürür.
// Kestirmeler listesinde ve Spotlight'ta görünmezler (`isDiscoverable = false`). Uygulama tarafı `AppController.ready()` sonrası ana
// iş parçacığında menü eylemlerini çağırır (URL kapısından geçmez: uygulama içinde çalışan intent). "Son görüntüler" widget'ına
// dokunuş da `ShowShelfCommandIntent`'i çalıştırır (`Button(intent:)`).

struct ShowShelfCommandIntent: AppIntent {
    static let title: LocalizedStringResource = "cmdShowTitle"
    static let openAppWhenRun = true
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        #if SHOTMORI_WIDGET
        return .result()
        #else
        let c = try await AppController.ready()
        // Seçili raf stilindeki yüzey (Üst şerit ya da yüzen panel); diğer "rafı göster" yollarıyla aynı (`AppController.shelf`).
        await MainActor.run { c.shelf.show(takeKey: true) }
        return .result()
        #endif
    }
}

struct AddClipboardCommandIntent: AppIntent {
    static let title: LocalizedStringResource = "cmdClipboardTitle"
    static let openAppWhenRun = true
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        #if SHOTMORI_WIDGET
        return .result()
        #else
        let c = try await AppController.ready()
        await MainActor.run { c.addFromClipboard() }
        return .result()
        #endif
    }
}

struct CopyLatestCommandIntent: AppIntent {
    static let title: LocalizedStringResource = "cmdCopyLatestTitle"
    static let openAppWhenRun = true
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        #if SHOTMORI_WIDGET
        return .result()
        #else
        let c = try await AppController.ready()
        await MainActor.run { c.copyLastScreenshot() }
        return .result()
        #endif
    }
}
