import Foundation

/// Panel seçim mantığı (UI'dan bağımsız, test edilebilir).
/// Kurallar: tık = yalnız o öğe; ⌘ = aç/kapat; ⇧ = çapadan aralık; seçili öğeye basmak çoklu seçimi
/// hemen bozmaz (sürükleme başlayabilir), daraltma bırakışta olur. ✕ her zaman tek hedef.
struct ShelfSelection: Equatable {
    private(set) var ids: Set<UUID> = []
    private(set) var anchor: UUID?

    var isEmpty: Bool { ids.isEmpty }
    var count: Int { ids.count }
    func contains(_ id: UUID) -> Bool { ids.contains(id) }

    mutating func set(_ new: Set<UUID>, anchor: UUID?) { ids = new; self.anchor = anchor }
    mutating func selectOnly(_ id: UUID) { ids = [id]; anchor = id }
    mutating func selectAll(order: [UUID]) { ids = Set(order) }
    mutating func clear() { ids = []; anchor = nil }

    /// Fare basışı. `order`: görünüm sırası (en yeni önce).
    mutating func mouseDown(on id: UUID, order: [UUID], command: Bool, shift: Bool) {
        if command { if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }; anchor = id; return }
        if shift, let a = anchor, let i = order.firstIndex(of: a), let j = order.firstIndex(of: id) {
            ids = Set(order[min(i, j)...max(i, j)]); return
        }
        if !ids.contains(id) { ids = [id] }
        anchor = id
    }
    /// Sürükleme olmadan bırakış: çoklu seçim tek öğeye daralır.
    mutating func mouseUpWithoutDrag(on id: UUID, command: Bool, shift: Bool) {
        guard !command, !shift else { return }
        if ids.count > 1 { ids = [id]; anchor = id }
    }
    /// Raf değişti (yeni kare geldi / öğe gitti): mevcut seçim korunur, yalnızca kaybolanlar düşer.
    mutating func reconcile(existing: [UUID]) {
        let ex = Set(existing); ids = ids.intersection(ex)
        if let a = anchor, !ex.contains(a) { anchor = ids.first }
    }
    /// ✕ düğmesi: seçimden bağımsız, yalnızca basılan öğe.
    func closeTargets(for id: UUID) -> [UUID] { [id] }
    /// Ok tuşları: yeni çapayı döndürür.
    mutating func move(by delta: Int, order: [UUID], extend: Bool) -> UUID? {
        guard !order.isEmpty else { return nil }
        let cur = anchor.flatMap { order.firstIndex(of: $0) } ?? -1
        let next = min(max(cur + delta, 0), order.count - 1)
        let id = order[next]
        if extend { ids.insert(id) } else { ids = [id] }
        anchor = id
        return id
    }
}
