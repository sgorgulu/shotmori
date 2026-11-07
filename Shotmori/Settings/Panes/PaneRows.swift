import SwiftUI

/// Ayarlar sayfalarının ortak satır deseni: gruplu form, başlık solda / kontrol sağda, açıklama araç ipucunda, küçük sıfırlama düğmesi.
enum Pane {
    /// Gruplu form; zemin saydam (cam krom görünsün), üstte 8 pt nefes.
    static func form<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        Form { content() }.formStyle(.grouped).scrollContentBackground(.hidden).contentMargins(.top, 8, for: .scrollContent)
    }
    /// Başlık + sağda kontrol. `help` varsa satırın araç ipucu ve VoiceOver yardımı olur (görünür açıklama cümlesi yok).
    static func row<C: View>(_ title: String, help: String? = nil, @ViewBuilder control: () -> C) -> some View {
        LabeledContent { control() } label: { Text(title) }
            .help(help ?? "")
            .accessibilityHint(help ?? "")
    }
    /// Sağa dayalı küçük "Varsayılanlara dön": son bölümün altbilgisi olarak kullanılır (ayrı kart değil).
    static func resetRow(_ action: @escaping () -> Void) -> some View {
        HStack { Spacer(); Button(S.resetDefaults, action: action).controlSize(.small).buttonStyle(.bordered) }.padding(.top, 4)
    }
    /// Bağlantı görünümlü düğme: `.link` stili tint'i/foregroundStyle'ı almaz (sistem mavisi); tek vurgu rengi için düz stil + vurgu metni.
    static func linkButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).foregroundStyle(Color.smAccent) }.buttonStyle(.plain)
    }
    /// Bölüm altbilgisi: tek cümle, ikincil.
    static func footer(_ text: String) -> some View { Text(text).font(.caption).foregroundStyle(.secondary) }
}
