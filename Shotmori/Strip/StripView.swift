import AppKit
import SwiftUI

// Uyarlama: Tendedero/ClipBoardLine LineView.swift, MIT, © 2026 Alejandro Buján

/// Şerit görünümünün denetleyiciye (Görev 9) giden olayları.
struct StripViewActions {
    var select: (UUID, NSEvent.ModifierFlags) -> Void = { _, _ in }
    var doubleClick: (UUID) -> Void = { _ in }
    var longPress: (UUID) -> Void = { _ in }
    var forceClick: (UUID) -> Void = { _ in }
    var remove: (UUID) -> Void = { _ in }
    var contextMenu: (UUID, NSEvent, NSView) -> Void = { _, _, _ in }
    var beginDrag: (UUID, NSEvent, NSView) -> Void = { _, _, _ in }
    var capsule: (StripCapsuleEntry, NSView) -> Void = { _, _ in }
    /// VoiceOver ile basma (tık görünümü yok): menüler ve demirli eylemler isabet dikdörtgenine / şeride demirlenir.
    var capsuleAccessibility: (StripCapsuleEntry) -> Void = { _ in }
    var tab: (UUID) -> Void = { _ in }
    var tabMenu: (UUID, NSEvent, NSView) -> Void = { _, _, _ in }
    /// Sekme menüsünün VoiceOver eşleri (sağ tık menüsüyle aynı iş).
    var renameTab: (UUID) -> Void = { _ in }
    var closeTab: (UUID) -> Void = { _ in }
    var detachTab: (UUID) -> Void = { _ in }
    /// Kart(lar) sekmeye bırakıldı: (hedef raf, öğe kimlikleri, sürükleme kaynağı) → kabul edildi mi.
    var dropOnTab: (UUID, Set<UUID>, Any?) -> Bool = { _, _, _ in false }
    var addShelf: () -> Void = {}
    var chooseFolder: () -> Void = {}
    var dismissNotice: () -> Void = {}
    var retry: () -> Void = {}
}

/// İp, mandallı kartlar, sol/sağ kapsül, boş raf ve bildirim.
/// Yalnız görünür aralıktaki kartlar kurulur; her kart çerçevesini `StripHitRectsKey` ile raporlar.
struct StripView: View {
    @ObservedObject var model: StripModel
    let actions: StripViewActions
    /// Kapsüller üst kenardan 8 pt aşağıda, yan kenarlardan 14 pt içeride.
    static let capsuleTopInset: CGFloat = 8
    static let capsuleSideInset: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = StripLayout.stripHeight
            let items = model.items
            let range = StripLayout.visibleRange(count: items.count, width: width, offset: model.scrollOffset)
            ZStack(alignment: .topLeading) {
                StripRope(width: width)
                ForEach(range.map { (index: $0, item: items[$0]) }, id: \.item.id) { index, item in
                    let x = StripLayout.x(index: index, scrollOffset: model.scrollOffset)
                    let ropeY = StripLayout.ropeY(x: x, width: width)
                    let hang = max(1, height - ropeY + StripLayout.pinAbove)
                    StripCardView(item: item, model: model, actions: actions, hangHeight: hang)
                        .position(x: x, y: ropeY - StripLayout.pinAbove + hang / 2)
                }
                StripEmptyCapsule(state: model.emptyState, actions: actions)
                    .position(x: width / 2, y: StripLayout.ropeY(x: width / 2, width: width))
                StripLeftCapsule(model: model, actions: actions)
                    .padding(.leading, StripView.capsuleSideInset).padding(.top, StripView.capsuleTopInset)
                VStack(alignment: .trailing, spacing: 6) {
                    StripRightCapsule(model: model, actions: actions)
                    if let notice = model.notice {
                        StripNoticeView(notice: notice, actionTitle: model.noticeActionTitle, actions: actions)
                    }
                }
                .animation(model.reduceMotion() ? nil : .easeOut(duration: 0.15), value: model.notice)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, StripView.capsuleSideInset).padding(.top, StripView.capsuleTopInset)
            }
            .frame(width: width, height: height, alignment: .topLeading)
        }
        .onPreferenceChange(StripHitRectsKey.self) { rects in
            MainActor.assumeIsolated { model.hitRects = rects }
        }
    }
}

/// Kartların ve kapsüllerin tıklama alanları (`.global`, pencere sol üst).
struct StripHitRectsKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Görünümün küresel çerçevesini `key` altında isabet alanı olarak raporlar.
    func stripHitRect(_ key: String?) -> some View {
        background(GeometryReader { g in
            Color.clear.preference(key: StripHitRectsKey.self, value: key.map { [$0: g.frame(in: .global)] } ?? [:])
        })
    }
}

/// İp: ikinci derece eğri; uçları `ropeTop`, ortası `ropeTop + sag` (`StripLayout.ropeY` ile birebir).
struct StripRope: View {
    let width: CGFloat
    @Environment(\.colorScheme) private var scheme

    private var path: Path {
        Path { p in
            p.move(to: CGPoint(x: 0, y: StripLayout.ropeTop))
            p.addQuadCurve(to: CGPoint(x: width, y: StripLayout.ropeTop),
                           control: CGPoint(x: width / 2, y: StripLayout.ropeTop + 2 * StripLayout.sag(width: width)))
        }
    }

    var body: some View {
        ZStack {
            path.stroke(Color.black.opacity(0.22), lineWidth: 2.4).offset(y: 1.2).blur(radius: 1.2)
            path.stroke(scheme == .dark ? Color(white: 0.85) : Color(white: 0.55), lineWidth: 2.2)
            path.stroke(Color.white.opacity(0.4), lineWidth: 0.6).offset(y: -0.5)
        }
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.04),
                                     .init(color: .black, location: 0.96), .init(color: .clear, location: 1)],
                             startPoint: .leading, endPoint: .trailing))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
