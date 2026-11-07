import SwiftUI

/// Hızlı işlemler: favoriler (sıralı, sürüklenebilir) ve diğer işlemler; taşma notu araç ipucunda.
struct ActionsPane: View {
    @ObservedObject var m: SettingsModel
    var body: some View {
        Pane.form {
            Section {
                ForEach(Array(m.favorites.enumerated()), id: \.element) { i, id in
                    if let a = m.app.registry.action(id) { row(a, on: true, index: i, count: m.favorites.count) }
                }
                .onMove { m.moveFavorites(from: $0, to: $1) }
            } header: { Text(S.favoritesLabel).help(S.favoritesOverflowNote) } footer: { Pane.footer(S.quickActionsFooter) }
            Section {
                ForEach(m.app.registry.favoriteCandidates.filter { !m.favorites.contains($0.id) }, id: \.id) { a in row(a, on: false) }
            } header: { Text(S.otherActionsSection) } footer: { Pane.resetRow { m.resetActions() } }
        }
    }
    private func row(_ a: ShelfAction, on: Bool, index: Int = 0, count: Int = 0) -> some View {
        HStack(spacing: 10) {
            Toggle(isOn: Binding(get: { on }, set: { m.toggleFavorite(a.id, on: $0) })) { EmptyView() }.toggleStyle(.checkbox).labelsHidden()
                .accessibilityLabel("\(a.title), \(on ? S.favoriteOn : S.favoriteOff)")
            Image(systemName: a.symbolName).frame(width: 18).foregroundStyle(Color.smAccent).accessibilityHidden(true)
            Text(a.title)
            Spacer()
            Text(a.scope.label).font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(Color.smElevated)).overlay(Capsule().stroke(Color.smSeparator, lineWidth: 1))
            if on {
                // Sürüklemeye klavye alternatifi: mevcut moveFavorites yolu; ilk/son sınırda pasif.
                Button { m.moveFavorite(at: index, by: -1) } label: { Image(systemName: "chevron.up") }.buttonStyle(.borderless).disabled(index == 0).accessibilityLabel("\(a.title): \(S.moveUp)")
                Button { m.moveFavorite(at: index, by: +1) } label: { Image(systemName: "chevron.down") }.buttonStyle(.borderless).disabled(index >= count - 1).accessibilityLabel("\(a.title): \(S.moveDown)")
                Image(systemName: "line.3.horizontal").foregroundStyle(.secondary).accessibilityLabel(S.dragToReorder)
            }
        }
    }
}
