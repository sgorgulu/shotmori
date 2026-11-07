#if SHOTMORI_CLOUD // Bulut kodu SHOTMORI_CLOUD bayrağıyla derlenir (Debug ve Release 1.0'da açık, bkz. Features.swift); bayrak kaldırılırsa derlenmez.
import SwiftUI
import AppKit

/// Ayarlar › Bulut modeli: hesaplar, link gizliliği, yol şablonları, otomatik yedek. Gizli alanlar Anahtar Zinciri'ne gider.
final class CloudSettingsModel: ObservableObject {
    let cloud: CloudCenter
    private var p: Preferences { cloud.prefs }
    @Published var driveClientID: String
    @Published var driveClientSecret: String = ""
    /// Kendi istemcinin gizli anahtarı Anahtar Zinciri'nde kayıtlı mı (alan boş görünür; boş bırakıp kaydetmek onu silmez).
    @Published var driveHasSecret: Bool
    /// Gelişmiş (kendi istemci) bölümü: gömülü istemci yoksa veya kullanıcı kendi kimliğini girdiyse açık başlar.
    @Published var showAdvancedClient: Bool
    var canSignIn: Bool { CloudDefaults.effectiveDriveClient(customID: driveClientID, customSecret: nil) != nil }
    /// S3 hesabı kayıtlı mı (Hesaplar satırı durumu).
    var s3Configured: Bool { cloud.prefs.s3Config != nil }
    @Published var driveConnected: Bool
    @Published var driveAccessAnyone: Bool
    @Published var driveTemplate: String
    @Published var s3: S3Config
    @Published var s3Secret: String = ""
    @Published var s3HasSecret: Bool
    @Published var s3Public: Bool
    @Published var s3PresignSeconds: Int
    @Published var s3Template: String
    @Published var linkFormat: LinkFormat
    @Published var backupProvider: CloudProviderID?
    @Published var backupDerivatives: Bool
    @Published var trashAfterBackup: Bool
    @Published var busy: String? = nil
    @Published var notice: String? = nil
    @Published var noticeIsError = false
    var pendingCount: Int { cloud.queue.pendingCount }

    init(cloud: CloudCenter) {
        self.cloud = cloud; let p = cloud.prefs
        driveClientID = p.driveClientID; driveHasSecret = cloud.hasDriveClientSecret; showAdvancedClient = !CloudDefaults.hasEmbeddedGoogleClient || !p.driveClientID.isEmpty; driveConnected = cloud.isConnected(.googleDrive); driveAccessAnyone = p.driveLinkAccess == .anyoneWithLink; driveTemplate = p.driveFolderTemplate
        s3 = p.s3Config ?? S3Config(); s3HasSecret = cloud.keychain.get(CloudAccount.s3Secret) != nil; s3Public = p.s3LinkAccess == .publicObject; s3PresignSeconds = p.s3PresignSeconds; s3Template = p.s3PathTemplate
        linkFormat = p.linkFormat; backupProvider = p.backupProvider; backupDerivatives = p.backupIncludesDerivatives; trashAfterBackup = p.trashLocalAfterBackup
    }
    // MARK: Drive
    /// Boş gizli anahtar alanı "değiştirme" demektir (kayıtlı anahtar korunur); istemci kimliği boşaltılınca kayıtlı anahtar kaldırılır.
    func saveDriveClient() {
        cloud.saveDrive(clientID: driveClientID, clientSecret: driveClientSecret.isEmpty ? nil : driveClientSecret)
        driveClientSecret = ""; driveHasSecret = cloud.hasDriveClientSecret; driveConnected = cloud.isConnected(.googleDrive)
    }
    func signIn() {
        // Yazılıp kaydedilmemiş istemci kimliği varsa önce kaydedilir; gizli anahtar alanı boşsa kayıtlı anahtara dokunulmaz.
        if driveClientID.trimmingCharacters(in: .whitespacesAndNewlines) != p.driveClientID || !driveClientSecret.isEmpty { saveDriveClient() }
        busy = S.cloudSigningIn; notice = nil
        Task { @MainActor in
            do { try await cloud.connectDrive(); driveConnected = true; show(S.cloudConnected, error: false) }
            catch { driveConnected = cloud.isConnected(.googleDrive); show(error.localizedDescription, error: true) }
            busy = nil
        }
    }
    func signOut() { Task { @MainActor in await cloud.disconnectDrive(); driveConnected = false; show(S.cloudDisconnected, error: false) } }
    func saveDriveOptions() { p.driveLinkAccess = driveAccessAnyone ? .anyoneWithLink : .ownerOnly; p.driveFolderTemplate = driveTemplate.isEmpty ? PathTemplate.default : driveTemplate; p.notifyChanged() }
    // MARK: S3
    /// Ön ayar: yol stili ve (R2) bölge. Uç nokta örneği alana yazılmaz, yalnız istem olarak görünür (`endpointPrompt`).
    func applyPreset() {
        s3.pathStyle = s3.preset.defaultsToPathStyle
        switch s3.preset {
        case .amazon: s3.endpoint = ""
        case .cloudflareR2: s3.region = "auto"
        case .backblazeB2, .minio, .other: break
        }
    }
    var endpointPrompt: String {
        switch s3.preset { case .cloudflareR2: return S.s3EndpointPromptR2; case .backblazeB2: return S.s3EndpointPromptB2; default: return "https://…" }
    }
    func saveS3() { cloud.saveS3(config: s3, secret: s3Secret.isEmpty ? nil : s3Secret); s3Secret = ""; s3HasSecret = cloud.keychain.get(CloudAccount.s3Secret) != nil; saveS3Options(); show(S.s3Save, error: false) }
    func clearS3() { cloud.clearS3(); s3 = S3Config(); s3HasSecret = false; s3Secret = "" }
    func saveS3Options() { p.s3LinkAccess = s3Public ? .publicObject : .presigned(seconds: s3PresignSeconds); p.s3PresignSeconds = s3PresignSeconds; p.s3PathTemplate = s3Template.isEmpty ? PathTemplate.default : s3Template; p.notifyChanged() }
    // MARK: Ortak
    func saveCommon() { p.linkFormat = linkFormat; p.backupProvider = backupProvider; p.backupIncludesDerivatives = backupDerivatives; p.trashLocalAfterBackup = trashAfterBackup; p.notifyChanged() }
    func test(_ id: CloudProviderID) {
        if id == .s3 { saveS3() }
        busy = S.cloudTesting; notice = nil
        Task { @MainActor in
            do { try await cloud.test(id); show(S.cloudTestOK, error: false) }
            catch { driveConnected = cloud.isConnected(.googleDrive); show(error.localizedDescription, error: true) } // iptal edilmiş oturum "Bağlı değil"e döner
            busy = nil
        }
    }
    func reset() { p.resetCloudSection(); driveAccessAnyone = false; driveTemplate = PathTemplate.default; s3Public = false; s3PresignSeconds = 86_400; s3Template = PathTemplate.default; linkFormat = .url; backupProvider = nil; backupDerivatives = false; trashAfterBackup = false; p.notifyChanged() }
    private func show(_ m: String, error: Bool) { notice = m; noticeIsError = error }
}

struct CloudSettingsView: View {
    @ObservedObject var m: CloudSettingsModel
    @State private var showS3Sheet = false
    @State private var showDriveAdvanced = false
    private static let presignChoices: [Int] = [3600, 6 * 3600, 86_400, 3 * 86_400, 7 * 86_400]

    /// Hesaplar (İnternet Hesapları deseni) · Paylaşım · Otomatik yedek. Hesap kurulumları ayrı sayfada (sheet); uzun form ana sayfada durmaz.
    var body: some View {
        Pane.form {
            Section {
                accountRow(symbol: "icloud.fill", tint: .systemBlue, title: S.cloudDriveSection, connected: m.driveConnected, subtitle: m.driveConnected ? S.cloudConnected : S.cloudDisconnected) {
                    if m.driveConnected {
                        Button(S.cloudTest) { m.test(.googleDrive) }.controlSize(.small).disabled(m.busy != nil)
                        Button(S.cloudSignOut) { m.signOut() }.controlSize(.small)
                    } else {
                        Button(S.cloudAdvancedButton) { showDriveAdvanced = true }.controlSize(.small)
                        Button(S.cloudSignIn) { m.signIn() }.glassButton(prominent: true).controlSize(.small).disabled(!m.canSignIn || m.busy != nil)
                    }
                }
                accountRow(symbol: "externaldrive.fill", tint: .systemOrange, title: S.cloudS3Section, connected: m.s3Configured, subtitle: m.s3Configured ? "\(S.cloudConnected) · \(m.s3.preset.title)" : S.cloudS3Subtitle) {
                    if m.s3Configured {
                        Button(S.cloudTest) { m.test(.s3) }.controlSize(.small).disabled(m.busy != nil)
                        Button(S.cloudEdit) { showS3Sheet = true }.controlSize(.small)
                    } else {
                        Button(S.cloudSetUp) { showS3Sheet = true }.glassButton(prominent: true).controlSize(.small)
                    }
                }
            } header: { Text(S.cloudAccountsSection) } footer: { Pane.footer(S.cloudAccountsFooter) }
            Section(S.cloudSharingSection) {
                Pane.row(S.cloudDriveLinkAccess) {
                    Picker("", selection: $m.driveAccessAnyone) { Text(S.cloudAccessOwner).tag(false); Text(S.cloudAccessAnyone).tag(true) }.labelsHidden().accessibilityLabel(S.cloudDriveLinkAccess).pickerStyle(.menu).frame(width: 220).onChange(of: m.driveAccessAnyone) { _, _ in m.saveDriveOptions() }
                }
                Pane.row(S.cloudS3LinkAccess) {
                    Picker("", selection: $m.s3Public) { Text(S.cloudAccessPresigned(CloudMenuBuilder.durationText(m.s3PresignSeconds))).tag(false); Text(S.cloudAccessPublic).tag(true) }.labelsHidden().accessibilityLabel(S.cloudS3LinkAccess).pickerStyle(.menu).frame(width: 220).onChange(of: m.s3Public) { _, _ in m.saveS3Options() }
                }
                if !m.s3Public {
                    Pane.row(S.s3PresignDuration) {
                        Picker("", selection: $m.s3PresignSeconds) { ForEach(Self.presignChoices, id: \.self) { Text(CloudMenuBuilder.durationText($0)).tag($0) } }.labelsHidden().accessibilityLabel(S.s3PresignDuration).pickerStyle(.menu).frame(width: 160).onChange(of: m.s3PresignSeconds) { _, _ in m.saveS3Options() }
                    }
                }
                Pane.row(S.cloudLinkFormat) {
                    Picker("", selection: $m.linkFormat) { Text(S.cloudLinkFormatURL).tag(LinkFormat.url); Text(S.cloudLinkFormatMarkdown).tag(LinkFormat.markdown); Text(S.cloudLinkFormatHTML).tag(LinkFormat.html) }.labelsHidden().accessibilityLabel(S.cloudLinkFormat).pickerStyle(.menu).frame(width: 200).onChange(of: m.linkFormat) { _, _ in m.saveCommon() }
                }
                templateRow(S.cloudDriveTemplate, $m.driveTemplate) { m.saveDriveOptions() }
                templateRow(S.cloudS3Template, $m.s3Template) { m.saveS3Options() }
            }
            Section {
                Pane.row(S.cloudBackupTarget) {
                    Picker("", selection: $m.backupProvider) { Text(S.cloudBackupOff).tag(CloudProviderID?.none); ForEach(CloudProviderID.allCases, id: \.self) { Text($0.title).tag(CloudProviderID?.some($0)) } }.labelsHidden().accessibilityLabel(S.cloudBackupTarget).pickerStyle(.menu).frame(width: 200).onChange(of: m.backupProvider) { _, _ in m.saveCommon() }
                }
                Pane.row(S.cloudBackupDerivatives) { Toggle("", isOn: $m.backupDerivatives).labelsHidden().toggleStyle(.switch).onChange(of: m.backupDerivatives) { _, _ in m.saveCommon() }.accessibilityLabel(S.cloudBackupDerivatives) }
                Pane.row(S.cloudTrashAfterBackup, help: S.cloudTrashAfterBackupHelp) { Toggle("", isOn: $m.trashAfterBackup).labelsHidden().toggleStyle(.switch).onChange(of: m.trashAfterBackup) { _, _ in m.saveCommon() }.accessibilityLabel(S.cloudTrashAfterBackup) }
                    .foregroundStyle(m.trashAfterBackup ? Color.smDestructive : Color.primary)
                if m.trashAfterBackup { Pane.footer(S.cloudTrashAfterBackupHelp) } // yıkıcı seçenek açıkken güvence görünür kalır
                if m.pendingCount > 0 { Text(S.cloudQueueStatus(m.pendingCount)).font(.callout).foregroundStyle(.secondary) }
            } header: { Text(S.cloudBackupSection) } footer: {
                VStack(alignment: .trailing, spacing: 6) {
                    if let b = m.busy { HStack { ProgressView().controlSize(.small); Text(b).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading) }
                    if let n = m.notice { Label(n, systemImage: m.noticeIsError ? "exclamationmark.triangle" : "checkmark.circle").font(.caption).foregroundStyle(m.noticeIsError ? Color.smDestructive : Color.primary).frame(maxWidth: .infinity, alignment: .leading) }
                    Pane.resetRow { m.reset() }
                }
            }
        }
        .sheet(isPresented: $showS3Sheet) { S3AccountSheet(m: m) }
        .sheet(isPresented: $showDriveAdvanced) { DriveAdvancedSheet(m: m) }
    }

    /// Hesap satırı: renkli simge karesi · ad + durum (nokta) · sağda eylemler.
    private func accountRow<A: View>(symbol: String, tint: NSColor, title: String, connected: Bool, subtitle: String, @ViewBuilder actions: () -> A) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color(nsColor: tint))).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                HStack(spacing: 5) {
                    Circle().fill(connected ? Color.green : Color.smSeparator).frame(width: 7, height: 7).accessibilityHidden(true)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            actions()
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .contain).accessibilityLabel("\(title), \(subtitle)")
    }
    /// Şablon satırı: başlık üstte, alan satırın tamamı kadar geniş (varsayılan şablon kesilmeden görünür).
    private func templateRow(_ title: String, _ text: Binding<String>, commit: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
            TextField("", text: text).textFieldStyle(.roundedBorder).frame(maxWidth: .infinity).labelsHidden().monospaced().onSubmit(commit).accessibilityLabel(title)
        }
        .help(S.cloudTemplateHelp).accessibilityHint(S.cloudTemplateHelp)
    }
}

/// S3 / S3 uyumlu hesap kurulumu: sağlayıcı, uç nokta, bölge, bucket, anahtarlar, yol stili; Bağlantıyı sına · Kaydet.
private struct S3AccountSheet: View {
    @ObservedObject var m: CloudSettingsModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            Pane.form {
                Section(S.s3SheetTitle) {
                    Pane.row(S.s3Preset) { Picker("", selection: $m.s3.preset) { ForEach(S3Config.Preset.allCases, id: \.self) { Text($0.title).tag($0) } }.labelsHidden().accessibilityLabel(S.s3Preset).pickerStyle(.menu).frame(width: 200).onChange(of: m.s3.preset) { _, _ in m.applyPreset() } }
                    if m.s3.preset != .amazon { Pane.row(S.s3Endpoint) { TextField("", text: $m.s3.endpoint, prompt: Text(m.endpointPrompt)).textFieldStyle(.roundedBorder).frame(width: 240).labelsHidden().accessibilityLabel(S.s3Endpoint) } }
                    Pane.row(S.s3Region) { TextField("", text: $m.s3.region).textFieldStyle(.roundedBorder).frame(width: 160).labelsHidden().accessibilityLabel(S.s3Region) }
                    Pane.row(S.s3Bucket) { TextField("", text: $m.s3.bucket).textFieldStyle(.roundedBorder).frame(width: 240).labelsHidden().accessibilityLabel(S.s3Bucket) }
                    Pane.row(S.s3AccessKey) { TextField("", text: $m.s3.accessKey).textFieldStyle(.roundedBorder).frame(width: 240).labelsHidden().accessibilityLabel(S.s3AccessKey) }
                    Pane.row(S.s3SecretKey) { SecureField(m.s3HasSecret ? "••••••••" : "", text: $m.s3Secret).textFieldStyle(.roundedBorder).frame(width: 240).labelsHidden().accessibilityLabel(S.s3SecretKey) }
                    if m.s3HasSecret { Pane.footer(S.s3SecretStored) } // durum bilgisi görünür (yeniden girmeye gerek yok)
                    Pane.row(S.s3PathStyle) { Toggle("", isOn: $m.s3.pathStyle).labelsHidden().toggleStyle(.switch).accessibilityLabel(S.s3PathStyle) }
                }
            }
            Divider()
            HStack(spacing: 10) {
                if m.s3Configured { Button(S.s3Clear, role: .destructive) { m.clearS3(); dismiss() } }
                if let b = m.busy { ProgressView().controlSize(.small); Text(b).font(.caption).foregroundStyle(.secondary) }
                else if let n = m.notice { Label(n, systemImage: m.noticeIsError ? "exclamationmark.triangle" : "checkmark.circle").font(.caption).foregroundStyle(m.noticeIsError ? Color.smDestructive : Color.primary).lineLimit(1) }
                Spacer()
                Button(S.cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(S.cloudTest) { m.test(.s3) }.disabled(!m.s3.isComplete || m.busy != nil)
                Button(S.s3Save) { m.saveS3(); dismiss() }.glassButton(prominent: true).keyboardShortcut(.defaultAction).disabled(!m.s3.isComplete)
            }.padding(16)
        }
        .frame(width: 520, height: 440).tint(.smAccent)
    }
}

/// Gelişmiş: kendi Google OAuth istemcin (boş = gömülü istemci).
private struct DriveAdvancedSheet: View {
    @ObservedObject var m: CloudSettingsModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            Pane.form {
                Section {
                    Pane.row(S.cloudClientID) { TextField("", text: $m.driveClientID).textFieldStyle(.roundedBorder).frame(width: 280).labelsHidden().accessibilityLabel(S.cloudClientID) }
                    Pane.row(S.cloudClientSecret) { SecureField(m.driveHasSecret ? "••••••••" : "", text: $m.driveClientSecret).textFieldStyle(.roundedBorder).frame(width: 280).labelsHidden().accessibilityLabel(S.cloudClientSecret) }
                    if m.driveHasSecret { Pane.footer(S.s3SecretStored) } // kayıtlı anahtar korunur; istemci kimliği boşaltılınca kaldırılır
                } header: { Text(S.cloudDriveAdvancedTitle) } footer: { Pane.footer(CloudDefaults.hasEmbeddedGoogleClient ? S.cloudAdvancedClientHelp : S.cloudClientHelp) }
            }
            Divider()
            HStack { Spacer(); Button(S.cancel) { dismiss() }.keyboardShortcut(.cancelAction); Button(S.s3Save) { m.saveDriveClient(); dismiss() }.glassButton(prominent: true).keyboardShortcut(.defaultAction) }.padding(16)
        }
        .frame(width: 520, height: 300).tint(.smAccent)
    }
}
#endif
