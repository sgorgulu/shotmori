import SwiftUI

/// Raf: izlenen klasör, raf davranışı (sınır, bırakınca gizle, önde tut), küçük resim uyarısı, sıfırlama.
struct ShelfPane: View {
    @ObservedObject var m: SettingsModel
    var body: some View {
        Pane.form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "folder.fill").font(.title2).foregroundStyle(Color.smAccent).frame(width: 32).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        if let f = m.folderURL {
                            Text(f.lastPathComponent).fontWeight(.medium)
                            Text((f.path as NSString).abbreviatingWithTildeInPath).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        } else {
                            Text(S.folderNotChosen).fontWeight(.medium)
                        }
                    }
                    Spacer()
                    Button(m.folderURL == nil ? S.chooseFolder : S.folderChange) { m.chooseFolder() }
                }
                .help(m.folderURL?.path ?? S.folderNotChosen)
                .accessibilityElement(children: .combine).accessibilityValue(m.folderURL?.path ?? S.folderNotChosen)
                if m.folderURL != nil { Pane.linkButton(S.folderReveal) { m.revealFolder() } }
            } header: { Text(S.folderLabel) } footer: { Pane.footer(S.folderFooter).help(S.folderHelp) }
            Section(S.shelfBehaviorSection) {
                Pane.row(S.shelfStyle, help: S.shelfStyleHelp) {
                    Picker("", selection: $m.shelfStyle) { Text(S.shelfStyleFloating).tag(ShelfStyle.floating); Text(S.shelfStyleStrip).tag(ShelfStyle.strip) }
                        .labelsHidden().pickerStyle(.segmented).frame(width: 220).onChange(of: m.shelfStyle) { _, _ in m.save() }.accessibilityLabel(S.shelfStyle)
                }
                Pane.row(S.stripNewCapture, help: S.stripNewCaptureHelp) {
                    Picker("", selection: $m.newCaptureStripMode) { Text(S.stripNewCapturePeek).tag(NewCaptureStripMode.peek); Text(S.stripNewCaptureStay).tag(NewCaptureStripMode.stay) }
                        .labelsHidden().pickerStyle(.menu).frame(width: 180).onChange(of: m.newCaptureStripMode) { _, _ in m.save() }.accessibilityLabel(S.stripNewCapture)
                }.disabled(m.shelfStyle != .strip)
                Pane.row(S.stripMenuBarReveal, help: S.stripMenuBarRevealHelp) {
                    Toggle("", isOn: $m.stripRevealFromMenuBar).labelsHidden().toggleStyle(.switch).onChange(of: m.stripRevealFromMenuBar) { _, _ in m.save() }.accessibilityLabel(S.stripMenuBarReveal)
                }.disabled(m.shelfStyle != .strip)
                Pane.row(S.maxItemsLabel, help: S.maxItemsHelp) {
                    Stepper(value: Binding(get: { m.maxItems }, set: { m.stepMaxItems($0) }), in: 5...100, step: 5) { Text("\(m.maxItems)").monospacedDigit().frame(width: 36, alignment: .trailing) }
                        .accessibilityLabel(S.maxItemsLabel).accessibilityValue("\(m.maxItems)")
                }
                Pane.row(S.showOnNewShot, help: S.showOnNewShotHelp) {
                    Toggle("", isOn: $m.showShelfOnNewScreenshot).labelsHidden().toggleStyle(.switch).onChange(of: m.showShelfOnNewScreenshot) { _, _ in m.save() }.accessibilityLabel(S.showOnNewShot)
                }
                Pane.row(S.hideAfterDrop, help: S.hideAfterDropHelp) {
                    Toggle("", isOn: $m.hideAfterDrop).labelsHidden().toggleStyle(.switch).onChange(of: m.hideAfterDrop) { _, _ in m.save() }.accessibilityLabel(S.hideAfterDrop)
                }
                Pane.row(S.shelfPin, help: S.shelfPinHelp) {
                    Toggle("", isOn: $m.keepShelfOpen).labelsHidden().toggleStyle(.switch).onChange(of: m.keepShelfOpen) { _, _ in m.save() }.accessibilityLabel(S.shelfPin)
                }
            }
            Section {
                Label(S.thumbnailWarningTitle, systemImage: "info.circle").foregroundStyle(.secondary)
                    .help(S.thumbnailWarningBody).accessibilityHint(S.thumbnailWarningBody)
            } footer: { Pane.resetRow { m.resetShelf() } }
        }
    }
}
