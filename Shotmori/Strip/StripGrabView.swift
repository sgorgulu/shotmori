import AppKit
import SwiftUI

// Uyarlama: Tendedero/ClipBoardLine GrabArea.swift, MIT, © 2026 Alejandro Buján

/// Kartın üstündeki saydam AppKit fare yüzeyi. `NSDraggingSource` değildir: 4 pt üstü sürüklemede
/// `beginDrag` çağrılır, oturumu denetleyici başlatır (dışarıya her zaman kopya).
struct StripGrabView: NSViewRepresentable {
    let id: UUID
    let model: StripModel
    let actions: StripViewActions

    func makeNSView(context: Context) -> StripGrabNSView {
        let view = StripGrabNSView()
        configure(view)
        return view
    }

    func updateNSView(_ view: StripGrabNSView, context: Context) { configure(view) }

    private func configure(_ view: StripGrabNSView) {
        let id = id, model = model, actions = actions
        view.onClick = { flags in actions.select(id, flags) }
        view.onDoubleClick = { actions.doubleClick(id) }
        view.onLongPress = { actions.longPress(id) }
        view.onForceClick = { actions.forceClick(id) }
        view.onRemove = { actions.remove(id) }
        view.onContextMenu = { event, v in actions.contextMenu(id, event, v) }
        view.onBeginDrag = { event, v in actions.beginDrag(id, event, v) }
        view.onPressChange = { pressed in
            if pressed { model.pressedID = id } else if model.pressedID == id { model.pressedID = nil }
        }
    }
}

/// Tık (⌘/⇧ dahil) seçer, çift tık kopyalar, 0,45 sn basılı tutma düzenler, force click Quick Look,
/// 4 pt üstü sürükleme sürüklemeyi başlatır, sağ tık menü, sol üst köşe ✕ raftan kaldırır.
final class StripGrabNSView: NSView {
    /// Basılı tutma süresi: yavaş tıkta tetiklenmeyecek, bilinçli hissettirecek kadar.
    static let holdDuration: TimeInterval = 0.45
    static let dragThreshold: CGFloat = 4
    /// Sol üst ✕ tıklama alanı (görünür daire 20 pt + 3 pt pay).
    static let crossHitSize: CGFloat = 26

    var onClick: (NSEvent.ModifierFlags) -> Void = { _ in }
    var onDoubleClick: () -> Void = {}
    var onLongPress: () -> Void = {}
    var onForceClick: () -> Void = {}
    var onRemove: () -> Void = {}
    var onContextMenu: (NSEvent, NSView) -> Void = { _, _ in }
    var onBeginDrag: (NSEvent, NSView) -> Void = { _, _ in }
    var onPressChange: (Bool) -> Void = { _ in }

    private var downPoint: NSPoint?
    private var downModifiers: NSEvent.ModifierFlags = []
    private var startedDrag = false
    private var didLongPress = false
    private var handledClick = false
    private var holdTimer: Timer?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { false }
    /// Saydam görünüm varsayılanı pencereyi taşımaktır; kart sürüklemesi pencereyi taşımamalı.
    override var mouseDownCanMoveWindow: Bool { false }

    deinit { holdTimer?.invalidate() }

    private var crossRect: NSRect {
        let s = Self.crossHitSize
        return NSRect(x: 0, y: isFlipped ? 0 : bounds.height - s, width: s, height: s)
    }
    private func isInCross(_ event: NSEvent) -> Bool { crossRect.contains(convert(event.locationInWindow, from: nil)) }

    /// ✕ araç ipucu köşe alanında (çizim SwiftUI'de isabet almadığından `.help` orada tetiklenmez).
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        removeAllToolTips()
        addToolTip(crossRect, owner: self, userData: nil)
    }

    override func mouseDown(with event: NSEvent) {
        if isInCross(event) { reset(); onRemove(); return }
        if event.clickCount >= 2 { reset(); onDoubleClick(); return }
        downModifiers = event.modifierFlags
        handledClick = !event.modifierFlags.intersection([.command, .shift]).isEmpty
        if handledClick { onClick(event.modifierFlags) }
        downPoint = event.locationInWindow
        startedDrag = false
        didLongPress = false
        onPressChange(true)
        holdTimer?.invalidate()
        holdTimer = nil
        if handledClick { return }
        holdTimer = Timer.scheduledTimer(withTimeInterval: Self.holdDuration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.downPoint != nil, !self.startedDrag, !self.didLongPress else { return }
                self.didLongPress = true
                self.endPress()
                self.onLongPress()
            }
        }
    }

    /// İzleme yüzeyinde force click Quick Look açar (Finder'daki gibi); tık ve uzun basma yerine sayılır.
    override func pressureChange(with event: NSEvent) {
        guard event.stage == 2, downPoint != nil, !startedDrag, !didLongPress else { return }
        didLongPress = true
        endPress()
        onForceClick()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = downPoint, !startedDrag, !didLongPress else { return }
        let p = event.locationInWindow
        guard hypot(p.x - start.x, p.y - start.y) > Self.dragThreshold else { return }
        startedDrag = true
        endPress()
        onBeginDrag(event, self)
    }

    override func mouseUp(with event: NSEvent) {
        endPress()
        if downPoint != nil, !startedDrag, !didLongPress, !handledClick { onClick(downModifiers) }
        reset()
    }

    override func rightMouseDown(with event: NSEvent) {
        if downPoint != nil { endPress() }
        reset()
        onContextMenu(event, self)
    }

    private func endPress() {
        holdTimer?.invalidate()
        holdTimer = nil
        onPressChange(false)
    }

    private func reset() {
        holdTimer?.invalidate()
        holdTimer = nil
        downPoint = nil
        startedDrag = false
        didLongPress = false
        handledClick = false
    }
}

extension StripGrabNSView: NSViewToolTipOwner {
    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        S.removeHint
    }
}
