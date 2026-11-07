import AppIntents

/// App Shortcuts: Kestirmeler ve Spotlight'ta kurulumsuz görünen eylemler. İfadeler `AppShortcuts.strings` (tablo A) üzerinden TR/EN;
/// hepsi uygulama adını içerir, başka ürün adı yok. En çok 10 kestirme.
struct ShotmoriShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddToShelfIntent(), phrases: [
            "Add images to \(.applicationName)",
            "Add to \(.applicationName) shelf",
        ], shortTitle: "intentAddTitle", systemImageName: "tray.and.arrow.down")
        AppShortcut(intent: GetShelfItemsIntent(), phrases: [
            "Get images from \(.applicationName)",
        ], shortTitle: "intentGetTitle", systemImageName: "tray.and.arrow.up")
        AppShortcut(intent: GetNewShelfItemsIntent(), phrases: [
            "Get new images from \(.applicationName)",
        ], shortTitle: "intentGetNewTitle", systemImageName: "sparkles")
        AppShortcut(intent: AddClipboardIntent(), phrases: [
            "Add clipboard to \(.applicationName)",
        ], shortTitle: "intentClipboardTitle", systemImageName: "photo.on.rectangle")
        AppShortcut(intent: CopyLatestIntent(), phrases: [
            "Copy latest image from \(.applicationName)",
        ], shortTitle: "intentCopyLatestTitle", systemImageName: "doc.on.doc")
        AppShortcut(intent: ShowShelfIntent(), phrases: [
            "Show \(.applicationName) shelf",
        ], shortTitle: "intentShowTitle", systemImageName: "rectangle.stack")
        AppShortcut(intent: HideShelfIntent(), phrases: [
            "Hide \(.applicationName) shelf",
        ], shortTitle: "intentHideTitle", systemImageName: "eye.slash")
        AppShortcut(intent: ClearShelfIntent(), phrases: [
            "Clear \(.applicationName) shelf",
        ], shortTitle: "intentClearTitle", systemImageName: "xmark.bin")
        #if SHOTMORI_CLOUD
        AppShortcut(intent: UploadIntent(), phrases: [
            "Upload with \(.applicationName)",
        ], shortTitle: "intentUploadTitle", systemImageName: "icloud.and.arrow.up")
        #endif
    }
}
