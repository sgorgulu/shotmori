import SwiftUI

/// Kenar çubuğu: sayfa listesi (renkli ikon karesi + ad), altta sürüm.
struct SettingsSidebar: View {
    @Binding var selection: SettingsPage
    let version: String
    var body: some View {
        List(selection: Binding(get: { Optional(selection) }, set: { if let p = $0 { selection = p } })) {
            ForEach(SettingsPage.available) { page in
                Label { Text(page.title) } icon: { PageIcon(page: page) }.tag(page)
            }
            Text(version).font(.footnote).foregroundStyle(.tertiary).monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6).padding(.vertical, 8)
                .listRowSeparator(.hidden).selectionDisabled()
                .accessibilityLabel("\(S.aboutVersion) \(version)")
        }
        .listStyle(.sidebar)
        .softScrollEdge()
    }
}

/// 22 pt yuvarlatılmış renkli kare içinde beyaz sembol.
struct PageIcon: View {
    let page: SettingsPage
    var body: some View {
        Image(systemName: page.symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(nsColor: page.tint)))
            .accessibilityHidden(true)
    }
}

extension View {
    /// macOS 26+: kaydırma kenarında yumuşak bulanıklık; altında etkisiz.
    @ViewBuilder func softScrollEdge() -> some View {
        if #available(macOS 26, *) { scrollEdgeEffectStyle(.soft, for: .all) } else { self }
    }
}
