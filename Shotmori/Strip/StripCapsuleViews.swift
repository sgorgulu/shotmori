import AppKit
import SwiftUI

/// Siyah %72 opak kapsül zemini (Saydamlığı azalt açıkken tam opak): cam değil, beyaz metin, gölge 0/4/14 %25.
/// Saydamlığı azalt SwiftUI ortamından canlı izlenir (sistem ayarı değişince kapsül hemen yeniden çizilir).
struct StripCapsuleBackground: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    nonisolated static func fillOpacity(reduceTransparency: Bool) -> Double { reduceTransparency ? 1 : 0.72 }

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(Color.black.opacity(Self.fillOpacity(reduceTransparency: reduceTransparency))))
            .shadow(color: .black.opacity(0.25), radius: 14, x: 0, y: 4)
            .foregroundStyle(Color.white)
            .font(.system(size: 10, weight: .medium))
    }
}

extension View {
    func stripCapsuleStyle() -> some View { modifier(StripCapsuleBackground()) }
}

/// Saydam AppKit tık yüzeyi: sol tık `onClick(görünüm)`, sağ tık `onRightClick(olay, görünüm)`; menüler bu görünüme demirlenir.
/// `onDrop` verilirse uygulama içi kart sürüklemesini (`ShelfPanelController.internalItemsType`) kabul eder.
struct StripAnchorView: NSViewRepresentable {
    var onClick: (NSView) -> Void = { _ in }
    var onRightClick: ((NSEvent, NSView) -> Void)?
    var onDrop: ((NSDraggingInfo) -> Bool)?

    func makeNSView(context: Context) -> StripAnchorNSView {
        let v = StripAnchorNSView()
        updateNSView(v, context: context)
        return v
    }

    func updateNSView(_ v: StripAnchorNSView, context: Context) {
        v.onClick = onClick
        v.onRightClick = onRightClick
        v.onDrop = onDrop
    }
}

final class StripAnchorNSView: NSView {
    var onClick: (NSView) -> Void = { _ in }
    var onRightClick: ((NSEvent, NSView) -> Void)?
    var onDrop: ((NSDraggingInfo) -> Bool)? {
        didSet {
            guard (onDrop == nil) != (oldValue == nil) else { return }
            if onDrop != nil { registerForDraggedTypes([ShelfPanelController.internalItemsType]) } else { unregisterDraggedTypes() }
        }
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { onDrop == nil ? [] : .move }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { onDrop == nil ? [] : .move }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { onDrop?(sender) ?? false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick(self) }
    }
    override func rightMouseDown(with event: NSEvent) {
        if let onRightClick { onRightClick(event, self) } else { super.rightMouseDown(with: event) }
    }
}

enum StripTabChip {
    /// Etkin raf "ad · N", diğerleri yalnız ad.
    static func label(for tab: StripTab) -> String { tab.active ? "\(tab.title) · \(tab.count)" : tab.title }
    /// VoiceOver etiketi: ayrı pencerede duran raf (görselde %50 opak) etikette de söylenir.
    static func accessibilityLabel(for tab: StripTab) -> String {
        let base = S.shelfTabAX(tab.title, tab.count)
        return tab.detached ? "\(base), \(S.shelfInWindowBadge)" : base
    }
}

/// Sol kapsül: raf sekmeleri ve "+".
struct StripLeftCapsule: View {
    @ObservedObject var model: StripModel
    let actions: StripViewActions
    static let maxShelves = ShelfStore.maxShelves

    /// Denetleyici tek rafta yalnız etkin rafı verir; "+" 8 rafta gizlidir.
    static func showsAdd(tabCount: Int) -> Bool { tabCount >= 1 && tabCount < maxShelves }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(model.tabs) { tab in
                Text(StripTabChip.label(for: tab))
                    .lineLimit(1)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(tab.active ? Color(nsColor: ShotmoriStyle.accent) : Color.clear))
                    .foregroundStyle(tab.active ? Color(nsColor: ShotmoriStyle.onAccent) : Color.white)
                    .opacity(tab.detached ? 0.5 : 1)
                    .overlay(StripAnchorView(onClick: { _ in actions.tab(tab.id) },
                                             onRightClick: { e, v in actions.tabMenu(tab.id, e, v) },
                                             onDrop: tab.active ? nil : { info in
                                                 actions.dropOnTab(tab.id, ShelfDragWriter.itemIDs(from: info.draggingPasteboard), info.draggingSource)
                                             }))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(StripTabChip.accessibilityLabel(for: tab))
                    .accessibilityAddTraits(tab.active ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction { actions.tab(tab.id) }
                    .accessibilityActions {
                        // Sağ tık menüsünün eşleri: Yeniden adlandır, (birden çok rafta) Rafı kapat, (ayrılabilirse) Ayrı pencerede aç.
                        Button(S.shelfRename) { actions.renameTab(tab.id) }
                        if model.tabs.count > 1 { Button(S.shelfClose) { actions.closeTab(tab.id) } }
                        if tab.canDetach { Button(S.shelfDetach) { actions.detachTab(tab.id) } }
                    }
            }
            if Self.showsAdd(tabCount: model.tabs.count) {
                Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                    .frame(width: 22, height: 18)
                    .overlay(StripAnchorView(onClick: { _ in actions.addShelf() }))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(S.shelfTabNew)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { actions.addShelf() }
            }
        }
        .stripCapsuleStyle()
        .stripHitRect("left")
    }
}

/// Sağ kapsül: seçime göre değişen eylemler.
struct StripRightCapsule: View {
    @ObservedObject var model: StripModel
    let actions: StripViewActions

    var body: some View {
        HStack(spacing: 2) {
            ForEach(model.capsule, id: \.stableID) { entry in
                button(entry)
            }
        }
        .stripCapsuleStyle()
        .stripHitRect("right")
    }

    private func tap(_ entry: StripCapsuleEntry) -> some View {
        StripAnchorView(onClick: { v in actions.capsule(entry, v) })
    }

    @ViewBuilder private func button(_ entry: StripCapsuleEntry) -> some View {
        switch entry {
        case .selectionCount(let n):
            Text(S.stripSelectedCount(n)).padding(.horizontal, 6)
        case .separator:
            Rectangle().fill(Color.white.opacity(0.2)).frame(width: 1, height: 14).padding(.horizontal, 3)
        case .action(let id, let primary):
            let info = model.actionInfo(id)
            if primary {
                Text(S.copyShortCount(model.selection.count))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color(nsColor: ShotmoriStyle.accent)))
                    .foregroundStyle(Color(nsColor: ShotmoriStyle.onAccent))
                    .overlay(tap(entry))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(info?.title ?? S.copyShortCount(model.selection.count))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { actions.capsuleAccessibility(entry) }
            } else {
                Image(systemName: info?.symbol ?? "questionmark.square")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 24, height: 18)
                    .overlay(tap(entry))
                    .help(info?.title ?? "")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(info?.title ?? "")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { actions.capsuleAccessibility(entry) }
            }
        case .actionsMenu:
            HStack(spacing: 3) {
                Text("⌘")
                Text(S.moreActions)
            }
            .padding(.horizontal, 6).padding(.vertical, 3)
            .overlay(tap(entry))
            .stripHitRect(StripCapsuleEntry.actionsHitKey)
            .help(S.actionsMenuShortcutHelp)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(S.moreActions)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { actions.capsuleAccessibility(entry) }
        case .pin(let on):
            Image(systemName: on ? "pin.fill" : "pin")
                .font(.system(size: 11, weight: .medium))
                .frame(width: 24, height: 18)
                .overlay(tap(entry))
                .help(S.shelfPin)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(S.shelfPin)
                .accessibilityValue(on ? S.shelfPinOn : S.shelfPinOff)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { actions.capsuleAccessibility(entry) }
        }
    }
}

/// İp ortasındaki boş raf kapsülü.
struct StripEmptyCapsule: View {
    let state: StripEmptyState
    let actions: StripViewActions

    var body: some View {
        Group {
            switch state {
            case .none:
                EmptyView()
            case .empty(let hotKey):
                HStack(spacing: 6) {
                    Text(S.emptyShelfTitle)
                    if !hotKey.isEmpty {
                        Text(hotKey)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.18)))
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .stripCapsuleStyle()
                .stripHitRect("empty")
            case .noFolder:
                Text(S.chooseFolder)
                    .underline()
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .overlay(StripAnchorView(onClick: { _ in actions.chooseFolder() }))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(S.chooseFolder)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { actions.chooseFolder() }
                    .stripCapsuleStyle()
                    .stripHitRect("empty")
            }
        }
    }
}

/// Sağ kapsülün altındaki bildirim: başarı metni, kalıcı (✕; eylemli bildirimde "Yeniden dene") ya da meşgul (döner gösterge).
struct StripNoticeView: View {
    let notice: StatusMessage
    /// Eylem bağlantısının başlığı; yalnız kalıcı bildirimde (yüzen panelle aynı: `noticeAction != nil`).
    let actionTitle: String?
    let actions: StripViewActions

    nonisolated static func showsAction(kind: StatusMessage.Kind, hasAction: Bool) -> Bool { kind == .persistent && hasAction }

    var body: some View {
        HStack(spacing: 6) {
            if notice.kind == .busy { ProgressView().controlSize(.mini).colorScheme(.dark) }
            Text(notice.text).lineLimit(2)
            if let title = actionTitle, Self.showsAction(kind: notice.kind, hasAction: true) {
                Text(title).underline()
                    .overlay(StripAnchorView(onClick: { _ in actions.retry() }))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(title)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { actions.retry() }
            }
            if notice.kind == .persistent {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    .frame(width: 16, height: 16)
                    .overlay(StripAnchorView(onClick: { _ in actions.dismissNotice() }))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(S.noticeDismiss)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { actions.dismissNotice() }
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .stripCapsuleStyle()
        .transition(.opacity)
        .stripHitRect("notice")
        .accessibilityElement(children: .contain)
    }
}
