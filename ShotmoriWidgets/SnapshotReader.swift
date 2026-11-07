import AppKit

/// Uzantı tarafı: ana uygulamanın grup konteynerine yazdığı anlık görüntüyü okur. JSON belirleyicidir: yalnız JSON'un
/// andığı `thumb-N.png` adları okunur (diskte kalmış eski thumb gösterilmez); başka ad/yol kabul edilmez.
enum SnapshotReader {
    static func read(container: URL? = WidgetSnapshot.containerURL(isolated: nil)) -> WidgetSnapshot? {
        guard let container,
              let data = try? Data(contentsOf: container.appendingPathComponent(WidgetSnapshot.fileName)),
              let snap = try? JSONDecoder().decode(WidgetSnapshot.self, from: data),
              snap.version == WidgetSnapshot.version else { return nil }
        return snap
    }

    static func image(_ name: String, container: URL? = WidgetSnapshot.containerURL(isolated: nil)) -> NSImage? {
        guard let container, (0..<WidgetSnapshot.maxItems).map(WidgetSnapshot.thumbName).contains(name) else { return nil }
        return NSImage(contentsOf: container.appendingPathComponent(name))
    }
}
