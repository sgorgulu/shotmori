import SwiftUI
import WidgetKit

/// Uzantı giriş noktası: Bildirim Merkezi/masaüstü widget'ı (14+) + Denetim Merkezi düğmeleri (26+).
@main
struct ShotmoriWidgetBundle: WidgetBundle {
    /// Uzantı süreci başlarken uygulamanın dilini anlık görüntüden alır (Denetim Merkezi etiketleri de bu dili izler).
    init() { WS.languageOverride = SnapshotReader.read()?.language }

    var body: some Widget {
        RecentShotsWidget()
        controls
    }

    /// Control Widget'lar yalnız macOS 26+; koşullu kısım ayrı oluşturucu özelliğinde.
    @WidgetBundleBuilder
    private var controls: some Widget {
        if #available(macOS 26, *) {
            ShowShelfControl()
            AddClipboardControl()
            CopyLatestControl()
        }
    }
}
