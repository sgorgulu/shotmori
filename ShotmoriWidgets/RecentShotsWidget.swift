import AppKit
import SwiftUI
import WidgetKit

/// "Son görüntüler" widget'ı: küçük boy son kare + sayı, orta boy 3 kare + "N yeni". Veri ana uygulamanın grup konteynerine
/// yazdığı anlık görüntüden gelir; uygulama raf değişince zaman çizelgesini yeniler (`policy: .never`).
/// Dokunuş `ShowShelfCommandIntent` (`Button(intent:)`, `openAppWhenRun`): uygulama sürecinde rafı açar; URL şemasına ve onun
/// izin sorusuna bağlı değildir (URL izni reddedilmiş ya da kapalı olsa da çalışır).
struct RecentShotsWidget: Widget {
    static let kind = "RecentShotsWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: RecentShotsProvider()) { entry in
            // Tüm yüzey dokunulabilir: içerik alanı doldurur (varsayılan ortalama korunur), boşluklar da isabet alır.
            Button(intent: ShowShelfCommandIntent()) {
                RecentShotsView(entry: entry).frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .containerBackground(for: .widget) { WidgetStyle.background }
        }
        .configurationDisplayName(WS.widgetRecentTitle)
        .description(WS.widgetRecentDesc)
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct RecentShotsEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    /// Yuva sırasıyla küçük resimler (JSON'daki `thumb` adlarından; yoksa nil).
    let images: [NSImage?]
}

struct RecentShotsProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecentShotsEntry {
        // Galeri yer tutucusu: üç boş kare (sistem kırpar/gizler); gerçek veri yok.
        let items = (0..<WidgetSnapshot.maxItems).map { _ in WidgetSnapshot.Item(id: UUID(), fileName: "", capturedAt: Date(), thumb: nil) }
        return RecentShotsEntry(date: Date(), snapshot: WidgetSnapshot(version: WidgetSnapshot.version, totalCount: 3, newCount: 0, items: items),
                                images: Array(repeating: nil, count: items.count))
    }
    func getSnapshot(in context: Context, completion: @escaping (RecentShotsEntry) -> Void) { completion(load()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<RecentShotsEntry>) -> Void) {
        completion(Timeline(entries: [load()], policy: .never))
    }
    private func load() -> RecentShotsEntry {
        let container = WidgetSnapshot.containerURL(isolated: nil)
        guard let snap = SnapshotReader.read(container: container) else { return RecentShotsEntry(date: Date(), snapshot: nil, images: []) }
        WS.languageOverride = snap.language // widget metinleri uygulamanın dilini izler
        let images = snap.items.map { item in item.thumb.flatMap { SnapshotReader.image($0, container: container) } }
        return RecentShotsEntry(date: Date(), snapshot: snap, images: images)
    }
}

struct RecentShotsView: View {
    let entry: RecentShotsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let snap = entry.snapshot, !snap.items.isEmpty {
                if family == .systemMedium { medium(snap) } else { small(snap) }
            } else {
                empty
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func small(_ snap: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: WidgetStyle.spacing) {
            ThumbTile(image: entry.images.first ?? nil)
            HStack(spacing: 4) {
                Text(WS.widgetTotal(snap.totalCount))
                    .font(.caption)
                    .foregroundStyle(WidgetStyle.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if snap.newCount > 0 { NewChip(count: snap.newCount) }
            }
        }
    }

    private func medium(_ snap: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: WidgetStyle.spacing) {
            HStack(spacing: 6) {
                Text(WS.widgetRecentTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WidgetStyle.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if snap.newCount > 0 {
                    NewChip(count: snap.newCount)
                } else {
                    Text(WS.widgetTotal(snap.totalCount)).font(.caption).foregroundStyle(WidgetStyle.secondaryText).lineLimit(1)
                }
            }
            HStack(spacing: WidgetStyle.spacing) {
                // Sabit 3 yuva: daha az kare varsa boş yuva yer tutar, kare boyu değişmez.
                ForEach(0..<WidgetSnapshot.maxItems, id: \.self) { i in
                    if i < snap.items.count { ThumbTile(image: entry.images.indices.contains(i) ? entry.images[i] : nil) }
                    else { Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity) }
                }
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.title2)
                .foregroundStyle(WidgetStyle.accent)
            Text(WS.widgetEmpty)
                .font(.caption)
                .foregroundStyle(WidgetStyle.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var accessibilityText: String {
        guard let snap = entry.snapshot, !snap.items.isEmpty else { return "\(WS.widgetRecentTitle), \(WS.widgetEmpty)" }
        var parts = [WS.widgetRecentTitle, WS.widgetTotal(snap.totalCount)]
        if snap.newCount > 0 { parts.append(WS.widgetNew(snap.newCount)) }
        return parts.joined(separator: ", ")
    }
}

/// Kare: küçük resim yuvayı doldurur (taşan kırpılır); resim yoksa silik görsel simgesi.
private struct ThumbTile: View {
    let image: NSImage?
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WidgetStyle.tileRadius, style: .continuous)
        shape.fill(WidgetStyle.tileFill)
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().interpolation(.high).scaledToFill()
                } else {
                    Image(systemName: "photo").font(.title3).foregroundStyle(WidgetStyle.secondaryText)
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(WidgetStyle.separator, lineWidth: 0.5))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
    }
}

/// "N yeni" kapsülü: tek vurgu rengi. Tek renk (vibrant) widget stilinde sistem metni ve zemini aynı renge indirir;
/// metin görünmez kalmasın diye orada dolgu yerine ince çerçeve kullanılır.
private struct NewChip: View {
    let count: Int
    @Environment(\.widgetRenderingMode) private var renderingMode
    var body: some View {
        Text(WS.widgetNew(count))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(WidgetStyle.accent)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background {
                if renderingMode == .vibrant { Capsule().strokeBorder(WidgetStyle.accent, lineWidth: 1) }
                else { Capsule().fill(WidgetStyle.accentFill) }
            }
    }
}
