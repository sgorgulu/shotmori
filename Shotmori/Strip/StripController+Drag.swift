import AppKit

/// Şerit: kartları dışarı sürükleme (gerçek dosya URL'si, dışarıya her zaman kopya) ve sekmeye bırakma.
extension StripController: NSDraggingSource {
    func beginDrag(_ id: UUID, event: NSEvent, view: NSView) {
        if !sel.contains(id) { sel.selectOnly(id); applySelection() }
        let pairs = selectedItems().compactMap { it in ShelfPanelController.dragWriter(for: it).map { (it, $0) } }
        guard !pairs.isEmpty else { showToast(S.reasonMissing); return }
        internalDropHandled = false
        let allIDs = pairs.map(\.0.id)
        let base = view.bounds.insetBy(dx: 6, dy: 6)
        let dragItems: [NSDraggingItem] = pairs.enumerated().map { i, pair in
            let it = pair.0
            let d = NSDraggingItem(pasteboardWriter: ShelfDragWriter(base: pair.1, itemIDs: allIDs))
            let img = (ThumbnailCache.shared.cached(it.url) ?? NSWorkspace.shared.icon(forFile: it.path)).withCountBadge(i == 0 ? pairs.count : 1)
            let off = CGFloat(i) * 5
            d.setDraggingFrame(NSRect(x: base.minX + off, y: base.minY - off, width: base.width, height: base.height), contents: img)
            return d
        }
        model.draggingID = id
        Log.info("Şeritten sürükleme başladı: \(pairs.count) dosya")
        let session = view.beginDraggingSession(with: dragItems, event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true // kabul edilmezse kart başlangıca geri uçar
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        ShelfPanelController.dragOperationMask(outside: context == .outsideApplication, allowsInternalMove: true) // içeride yalnız sekmeye taşıma
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        model.draggingID = nil
        Log.info("Şeritten sürükleme bitti: \(operation.isEmpty ? "reddedildi/iptal" : "kabul (\(operation.rawValue))"), dahili=\(internalDropHandled)")
        let handoff = ShelfPanelController.shouldCountAsHandoff(operation: operation, internalDropHandled: internalDropHandled)
        internalDropHandled = false
        guard handoff else { return }
        store.markHandoff(shelfID: displayedShelfID)
        if ShelfPanelController.shouldHideAfterDrop(hideAfterDrop: prefs.hideAfterDrop, optionHeld: NSEvent.modifierFlags.contains(.option), pinned: pinnedOpen) {
            pendingDropHide?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.pendingDropHide = nil; self?.hide(reason: "bırakma kabul edildi") }
            pendingDropHide = work
            DispatchQueue.main.asyncAfter(deadline: .now() + StripMotion.hideAfterDropDelay, execute: work)
        }
    }

    /// Sekmeye bırakma: öğeler o rafa taşınır; kaynak (şerit ya da yüzen panel) bunu aktarım saymaz.
    /// Öğelerin hepsi zaten hedef raftaysa (ör. ayrı pencerede duran raftan kendi sekmesine) bırakma reddedilir, "taşındı" denmez.
    func dropItems(_ ids: Set<UUID>, onShelf shelfID: UUID, source: Any?) -> Bool {
        guard !ids.isEmpty, shelfID != store.activeShelfID, let t = store.shelves.first(where: { $0.id == shelfID }) else { return false }
        let movable = Self.movableItems(ids, to: shelfID) { store.shelf(containing: $0)?.id }
        guard !movable.isEmpty else { return false }
        if let p = source as? ShelfPanelController { p.noteInternalDrop(from: p) } else { ((source as? StripController) ?? self).internalDropHandled = true }
        let n = store.move(ids: movable, to: t.id)
        showToast(n > 0 ? S.moveTrimmedToast(n) : S.movedToShelfToast(movable.count, t.name))
        return true
    }
    /// Hedef rafta olmayan (taşınabilecek) öğeler; hiçbir rafta olmayan kimlik de taşınamaz.
    static func movableItems(_ ids: Set<UUID>, to shelfID: UUID, shelfOf: (UUID) -> UUID?) -> Set<UUID> {
        ids.filter { id in shelfOf(id).map { $0 != shelfID } ?? false }
    }
}
