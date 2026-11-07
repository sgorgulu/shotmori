import SwiftUI
import AppKit

final class OnboardingModel: ObservableObject {
    let app: AppController
    @Published var flow: OnboardingFlow
    /// Seçilen klasör; nil → henüz seçilmedi (sandbox'ta macOS ayarı okunamaz, seçim zorunlu).
    @Published var folderPath: String?
    /// NSOpenPanel'in açılacağı öneri dizini (eski seçim ya da Masaüstü).
    let suggestedPath: String
    @Published var hotKeyCode: UInt32
    @Published var hotKeyModifiers: NSEvent.ModifierFlags
    @Published var detectedName: String?
    var step: Int { flow.step }
    init(app: AppController, folderOnly: Bool = false) {
        self.app = app
        flow = OnboardingFlow(folderOnly: folderOnly)
        switch FolderAccess(prefs: app.prefs).resolve() {
        case .ready(let u): folderPath = u.path; suggestedPath = u.path
        case .needsSelection(let s): folderPath = nil; suggestedPath = s.path
        }
        hotKeyCode = app.prefs.hotKeyCode; hotKeyModifiers = app.prefs.hotKeyModifiers
        app.onScreenshotDetected = { [weak self] url in DispatchQueue.main.async { self?.detectedName = url.lastPathComponent } }
    }
    func chooseFolder() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.prompt = S.choosePrompt; p.directoryURL = URL(fileURLWithPath: folderPath ?? suggestedPath)
        guard p.runModal() == .OK, let u = p.url else { return }
        do { try app.chooseFolder(u); folderPath = u.path } catch { Log.error("Klasör kaydedilemedi: \((error as NSError).code)"); FolderPrompt.showError(S.folderSaveFailed) }
    }
    var canAdvance: Bool { flow.canAdvance(folderChosen: folderPath != nil) }
    /// Klasör adımından çıkarken izleyici kurulum sırasında çalışır (deneme adımı kareyi algılasın).
    func commitFolderAndStartWatching() { app.startWatching() }
    func commitHotKey() { app.prefs.hotKeyCode = hotKeyCode; app.prefs.hotKeyModifiers = hotKeyModifiers; app.prefs.notifyChanged() }
    func advance() {
        guard canAdvance else { return }
        if flow.step == OnboardingFlow.folderPage { commitFolderAndStartWatching() }
        if flow.step == OnboardingFlow.hotKeyPage { commitHotKey() }
        flow.next()
    }
    func back() { flow.back() }
    func skip() { flow.next() }
}

/// Kurulum: altı sayfa, segmentli ilerleme, sayfa sayacı; Devam ana eylem, Geri bağlantı, deneme sayfasında "Şimdilik atla".
struct OnboardingView: View {
    @ObservedObject var m: OnboardingModel
    let finish: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 32, height: 32).accessibilityHidden(true)
                Spacer()
            }
            if !m.flow.folderOnly {
                HStack(spacing: 6) {
                    ForEach(0..<OnboardingFlow.pageCount, id: \.self) { i in Capsule().fill(i < m.flow.filledSegments ? Color.smAccent : Color.smSeparator).frame(height: 4) }
                }.padding(.top, 12).accessibilityElement(children: .ignore).accessibilityLabel(S.obProgress(m.flow.filledSegments, OnboardingFlow.pageCount))
            }
            Group {
                switch m.step {
                case 0: page(S.obWelcomeTitle, S.obWelcomeBody) {
                    StepIconRow(labels: (S.obStepCapture, S.obStepShelf, S.obStepDrag)).padding(.top, 18)
                }
                case 1: page(S.obFolderTitle, S.obFolderBody) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Image(systemName: "folder").font(.title2).foregroundStyle(Color.smSecondary).frame(width: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                if let path = m.folderPath {
                                    Text((path as NSString).lastPathComponent).font(.headline).foregroundStyle(Color.smText)
                                    Text((path as NSString).abbreviatingWithTildeInPath).font(.callout).foregroundStyle(Color.smSecondary).lineLimit(1).truncationMode(.middle)
                                    Text(S.folderCustom).font(.caption).foregroundStyle(Color.smSecondary)
                                } else {
                                    Text(S.folderNotChosen).font(.headline).foregroundStyle(Color.smText)
                                    Text((m.suggestedPath as NSString).abbreviatingWithTildeInPath).font(.callout).foregroundStyle(Color.smSecondary).lineLimit(1).truncationMode(.middle)
                                }
                            }
                            Spacer()
                            Button(S.chooseFolder) { m.chooseFolder() }
                        }
                        .padding(14).background(RoundedRectangle(cornerRadius: 8).fill(Color.smSurface)).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.smSeparator))
                        .help(m.folderPath ?? S.folderNotChosen).accessibilityElement(children: .combine).accessibilityValue(m.folderPath ?? S.folderNotChosen)
                        Text(S.obFolderPermission).font(.callout).foregroundStyle(Color.smSecondary)
                        Label(S.thumbnailWarningBody, systemImage: "info.circle").font(.caption).foregroundStyle(Color.smSecondary).padding(.top, 2)
                    }
                }
                case 2: page(S.obAccumulateTitle, S.obAccumulateBody) {
                    SampleShelfPreview(accessibilityText: S.obSampleShelfAX).padding(.top, 14)
                }
                case 3: page(S.obHotKeyTitle, S.obHotKeyBody) {
                    VStack(alignment: .center, spacing: 8) {
                        KeyRecorder(keyCode: $m.hotKeyCode, modifiers: $m.hotKeyModifiers).frame(width: 200, height: 32)
                        Text(S.obHotKeyHelp).font(.callout).foregroundStyle(Color.smSecondary)
                    }.frame(maxWidth: .infinity).padding(.top, 6)
                }
                case 4: page(S.obTryTitle, S.obTryBody) {
                    VStack(spacing: 12) {
                        Text(ScreenshotHotKeys.area).font(.system(size: 22, weight: .medium)).monospacedDigit().foregroundStyle(Color.smText)
                            .padding(.horizontal, 24).padding(.vertical, 10).background(RoundedRectangle(cornerRadius: 8).fill(Color.smElevated)).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.smSeparator))
                        HStack(spacing: 8) {
                            if let n = m.detectedName { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.smAccent); Text("\(S.obTryDetected) \(n)").lineLimit(1).truncationMode(.middle).help(n) }
                            else { ProgressView().controlSize(.small); Text(S.obTryWaiting).foregroundStyle(Color.smSecondary) }
                        }.font(.callout)
                    }.frame(maxWidth: .infinity).padding(.top, 6)
                }
                default: page(S.obDragTitle, S.obDragBody) {
                    VStack(spacing: 14) {
                        DragIllustration()
                        Text("\(S.obShelfOpens): \(HotKeyCenter.display(keyCode: m.hotKeyCode, modifiers: m.hotKeyModifiers))").font(.headline).help(S.generalHotKeyHelp)
                    }.frame(maxWidth: .infinity).padding(.top, 12)
                }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 20)
            Spacer(minLength: 0)
            HStack {
                if !m.flow.isFirst { Pane.linkButton(S.back) { m.back() } }
                Spacer()
                if m.flow.canSkip(detected: m.detectedName != nil) { Pane.linkButton(S.obSkipForNow) { m.skip() }.padding(.trailing, 12) }
                if m.flow.isLast { Button(S.finish) { finish() }.keyboardShortcut(.defaultAction).glassButton(prominent: true).controlSize(.large).disabled(!m.canAdvance) }
                else { Button(S.next) { m.advance() }.keyboardShortcut(.defaultAction).glassButton(prominent: true).controlSize(.large).disabled(!m.canAdvance) }
            }
        }
        .padding(.horizontal, 28).padding(.bottom, 24).padding(.top, 8).frame(width: 640, height: 420)
        .tint(.smAccent)
        .accessibilityElement(children: .contain).accessibilityLabel(m.flow.folderOnly ? S.onboardingTitle : "\(S.onboardingTitle), \(S.obProgress(m.flow.filledSegments, OnboardingFlow.pageCount))")
    }
    @ViewBuilder private func page<C: View>(_ title: String, _ body: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 22, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            Text(body).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            content()
        }
    }
}

final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private let onFinish: () -> Void
    private let model: OnboardingModel
    /// Yalnız klasör sayfası mı (erişim kaybı, "Klasör Seç…"): yeniden açma kararı bu kipe bakar.
    let folderOnly: Bool
    /// Pencere hangi yoldan kapanırsa kapansın (✕, ⌘W, Bitir) bir kez çağrılır; AppController kurulum durumunu temizler.
    var onClose: (() -> Void)?
    #if DEBUG
    /// QA: belirli sayfayı gösterir (ekran görüntüsü); `canAdvance` koşulları atlanır.
    func showPageForQA(_ page: Int) { let target = max(0, min(page - 1, OnboardingFlow.pageCount - 1)); while model.step < target { model.skip() } }
    #endif
    init(app: AppController, folderOnly: Bool = false, onFinish: @escaping () -> Void) {
        self.onFinish = onFinish; self.folderOnly = folderOnly
        let model = OnboardingModel(app: app, folderOnly: folderOnly); self.model = model
        var finishRef: (() -> Void)?
        let host = NSHostingController(rootView: OnboardingView(m: model) { finishRef?() })
        let w = NSWindow(contentViewController: host)
        w.title = S.onboardingTitle; w.styleMask = [.titled, .closable]; w.isReleasedWhenClosed = false
        w.applyGlassChrome(toolbarIdentifier: "onboarding"); w.center()
        w.level = .floating; w.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        super.init(window: w)
        w.delegate = self
        finishRef = { [weak self] in self?.close(); self?.onFinish() }
    }
    required init?(coder: NSCoder) { fatalError() }
    override func showWindow(_ sender: Any?) { super.showWindow(sender); window?.orderFrontRegardless(); window?.makeKey() }
    /// Kapatmak = atla (kurulum bitmiş sayılmaz; izleyici zaten başlatılmış olabilir). Yine de "kurulum açık" durumu kalkar:
    /// yeni karede raf kendiliğinden açılabilsin (COR-02).
    func windowWillClose(_ notification: Notification) { let c = onClose; onClose = nil; c?() }
}
