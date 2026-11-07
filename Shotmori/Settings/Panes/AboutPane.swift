import SwiftUI
import AppKit

/// Hakkında: büyük ikon, ad, sürüm; Yardım / Gizlilik (dile göre site) / Tanılama günlüğü bağlantıları.
struct AboutPane: View {
    let version: String
    @State private var showLicenses = false
    var body: some View {
        Pane.form {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(S.appName).font(.title2.weight(.semibold))
                        Text("\(S.aboutVersion) \(version)").font(.callout).foregroundStyle(.secondary).monospacedDigit()
                    }
                    Spacer()
                }.padding(.vertical, 6)
            }
            Section {
                Pane.linkButton(S.aboutHelpLink) { NSWorkspace.shared.open(Links.help(language: Links.currentLanguage)) }
                Pane.linkButton(S.aboutPrivacyLink) { NSWorkspace.shared.open(Links.privacy(language: Links.currentLanguage)) }
                Pane.linkButton(S.aboutLog) { NSWorkspace.shared.activateFileViewerSelecting([Log.fileURL]) }
                Pane.linkButton(S.openSourceLicenses) { showLicenses = true }
            }
        }
        .sheet(isPresented: $showLicenses) { LicensesSheet() }
    }
}

/// Açık kaynak lisansları: paketlenmiş `ThirdPartyNotices.txt`, kaydırılabilir ve seçilebilir; Esc ya da Kapat kapatır.
struct LicensesSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let notice: String = {
        guard let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }()
    var body: some View {
        VStack(spacing: 0) {
            Text(S.openSourceLicensesTitle).font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(16)
            Divider()
            ScrollView {
                Text(notice).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(16)
            }
            Divider()
            HStack { Spacer(); Button(S.menuClose) { dismiss() }.keyboardShortcut(.cancelAction) }.padding(16)
        }
        .frame(width: 520, height: 420).tint(.smAccent)
    }
}
