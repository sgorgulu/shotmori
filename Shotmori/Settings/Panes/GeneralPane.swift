import SwiftUI

/// Genel: Başlangıç (girişte başlat, dil), Klavye (kısayol), Otomasyon (URL şeması, Kestirmeler, Servisler, Denetim Merkezi), sıfırlama.
struct GeneralPane: View {
    @ObservedObject var m: SettingsModel
    var body: some View {
        Pane.form {
            Section(S.settingsStartupSection) {
                Pane.row(S.launchAtLogin) {
                    Toggle("", isOn: Binding(get: { m.launchAtLogin }, set: { m.toggleLaunchAtLogin($0) })).labelsHidden().toggleStyle(.switch).accessibilityLabel(S.launchAtLogin)
                }
                Pane.row(S.languageLabel) {
                    Picker("", selection: Binding(get: { m.uiLanguage }, set: { m.setLanguage($0) })) {
                        Text(S.languageSystem).tag(""); Text(S.languageTurkish).tag("tr"); Text(S.languageEnglish).tag("en")
                    }.labelsHidden().pickerStyle(.menu).frame(width: 160).accessibilityLabel(S.languageLabel)
                }
                if m.languageChanged {
                    Pane.row(S.languageRelaunchNote) { Button(S.relaunchNow) { m.relaunch() }.controlSize(.small) }
                }
            }
            Section {
                Pane.row(S.hotKeyLabel, help: S.generalHotKeyHelp) { KeyRecorder(keyCode: $m.hotKeyCode, modifiers: $m.hotKeyModifiers).frame(width: 150, height: 26) }
                    .onChange(of: m.hotKeyCode) { _, _ in m.save() }.onChange(of: m.hotKeyModifiers) { _, _ in m.save() }
            } header: { Text(S.settingsKeyboardSection) }
            Section {
                Pane.row(S.urlSchemeToggle, help: S.urlSchemeHelp) {
                    Toggle("", isOn: Binding(get: { m.urlSchemeEnabled }, set: { m.setURLSchemeEnabled($0) })).labelsHidden().toggleStyle(.switch).accessibilityLabel(S.urlSchemeToggle)
                }
                Pane.row(S.openShortcuts, help: S.openShortcutsHelp) {
                    Button { if let u = URL(string: "shortcuts://") { NSWorkspace.shared.open(u) } } label: {
                        Image(systemName: "arrow.up.forward.app").foregroundStyle(Color.smAccent)
                    }.buttonStyle(.plain).accessibilityLabel(S.openShortcuts)
                }
                Pane.row(S.servicesInfo, help: S.servicesInfoHelp) { EmptyView() }
                if #available(macOS 26, *) {
                    Pane.row(S.controlCenterInfo, help: S.controlCenterInfoHelp) { EmptyView() }
                }
            } header: { Text(S.settingsAutomationSection) } footer: { Pane.resetRow { m.resetGeneral() } }
        }
    }
}
