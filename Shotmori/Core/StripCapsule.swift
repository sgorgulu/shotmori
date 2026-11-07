import Foundation

/// Sağ kapsülün bir girdisi (yalnız kimlikler; simge ve başlık görünümde çözülür).
enum StripCapsuleEntry: Equatable {
    case selectionCount(Int), action(id: String, primary: Bool), separator, actionsMenu, pin(on: Bool)

    /// Kapsül içinde kalıcı kimlik: seçim değişince aynı düğmenin görünümü (ve ona demirli menü/seçici) yeniden kurulmaz.
    var stableID: String {
        switch self {
        case .selectionCount: "count"
        case .action(let id, _): "action.\(id)"
        case .separator: "separator"
        case .actionsMenu: Self.actionsHitKey
        case .pin: "pin"
        }
    }
    /// İşlemler düğmesinin isabet dikdörtgeni anahtarı (`StripModel.hitRects`); ⌘K menüsü buna demirlenir.
    static let actionsHitKey = "actions"
}

/// Şeridin boş durumu: ip ortasında kapsül.
enum StripEmptyState: Equatable { case none, noFolder, empty(hotKey: String) }

enum StripCapsule {
    /// Seçim yok: [.actionsMenu, .pin]. Seçim var: [.selectionCount(n)] + uygun favoriler (sıra korunur; ilki "copy-image" ise primary)
    /// en çok `maxActions`, + [.separator, .actionsMenu, .pin]. Uygun olmayan favori gösterilmez;
    /// `maxActions`'ı aşan uygunlar overflow'a (İşlemler menüsünün başına) düşer.
    static func entries(selectionCount: Int, favorites: [(id: String, available: Bool)], pinned: Bool,
                        maxActions: Int = 6) -> (entries: [StripCapsuleEntry], overflow: [String]) {
        let tail: [StripCapsuleEntry] = [.actionsMenu, .pin(on: pinned)]
        guard selectionCount > 0 else { return (tail, []) }
        let usable = favorites.filter(\.available).map(\.id)
        let shown = Array(usable.prefix(max(0, maxActions)))
        let overflow = Array(usable.dropFirst(shown.count))
        let primaryID = favorites.first?.id == "copy-image" && favorites.first?.available == true ? "copy-image" : nil
        var out: [StripCapsuleEntry] = [.selectionCount(selectionCount)]
        out += shown.map { .action(id: $0, primary: $0 == primaryID) }
        out.append(.separator)
        return (out + tail, overflow)
    }
}

extension StripCapsule {
    /// ⌘K menüsünün çapası: İşlemler düğmesi; çizilmemişse (olmamalı) bütün sağ kapsül.
    static func actionsMenuAnchorRect(hitRects: [String: CGRect]) -> CGRect? {
        hitRects[StripCapsuleEntry.actionsHitKey] ?? hitRects["right"]
    }
}
