import AppIntents
import SwiftUI
import WidgetKit

// Denetim Merkezi düğmeleri (macOS 26+). Eylemler `Shared/CommandIntents.swift` komut intent'leri: `openAppWhenRun = true`
// olduğundan `perform()` uygulama sürecinde çalışır (URL kapısından geçmez). Yalnız başlık: alt başlık görünmüyor (FB20022894).

@available(macOS 26, *)
struct ShowShelfControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "dev.shotmori.control.show") {
            ControlWidgetButton(action: ShowShelfCommandIntent()) { Label(WS.cmdShowTitle, systemImage: "rectangle.stack") }
        }
        .displayName(LocalizedStringResource("cmdShowTitle"))
    }
}

@available(macOS 26, *)
struct AddClipboardControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "dev.shotmori.control.clipboard") {
            ControlWidgetButton(action: AddClipboardCommandIntent()) { Label(WS.cmdClipboardTitle, systemImage: "photo.on.rectangle") }
        }
        .displayName(LocalizedStringResource("cmdClipboardTitle"))
    }
}

@available(macOS 26, *)
struct CopyLatestControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "dev.shotmori.control.copy-latest") {
            ControlWidgetButton(action: CopyLatestCommandIntent()) { Label(WS.cmdCopyLatestTitle, systemImage: "doc.on.doc") }
        }
        .displayName(LocalizedStringResource("cmdCopyLatestTitle"))
    }
}
