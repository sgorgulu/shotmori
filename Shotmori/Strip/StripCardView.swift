import AppKit
import SwiftUI

// Uyarlama: Tendedero/ClipBoardLine PeggedView.swift, MIT, © 2026 Alejandro Buján
// Fark: çerçeve cam değil (Shotmori kuralı: kart asla cam değildir) — opak `ShotmoriStyle.elevated` + ayırıcı kenar.

/// Mandalla ipe asılı tek kare: ilk görünüşte yukarıdan düşer, salınır, esintiyle sallanır.
/// Uçuş ve düşme tüm ekranı kaplayan katmanda çizilir; o sırada kart yerinde görünmez.
struct StripCardView: View {
    let item: ShelfItem
    @ObservedObject var model: StripModel
    let actions: StripViewActions
    /// Mandalın tepesinden şeridin altına kadar asılı alanın yüksekliği (dönüş noktası için).
    let hangHeight: CGFloat

    @State private var swing: Double
    @State private var arrived: Bool
    @State private var hovering = false
    @State private var thumb: NSImage?
    /// En son istenen küçük resmin yolu: geç gelen eski çözüm (kart başka dosyaya geçtiyse) yazılmaz.
    @State private var requestedThumbURL: URL?
    /// Karşıtlığı artır canlı izlenir (sistem ayarı değişince kart yeniden çizilir).
    @Environment(\.colorSchemeContrast) private var contrast

    init(item: ShelfItem, model: StripModel, actions: StripViewActions, hangHeight: CGFloat) {
        self.item = item
        self.model = model
        self.actions = actions
        self.hangHeight = hangHeight
        let drops = model.needsArrival(item.id)
        _arrived = State(initialValue: !drops)
        _swing = State(initialValue: drops ? StripMotion.arrivalSwing : 0)
    }

    private var id: UUID { item.id }
    private var selected: Bool { model.selection.contains(id) }
    private var copied: Bool { model.copiedID == id }
    private var dragging: Bool { model.draggingID == id }
    private var pressed: Bool { model.pressedID == id }
    private var flying: Bool { model.flyingIDs.contains(id) }
    private var falling: Bool { model.fallingIDs.contains(id) }
    private var isNew: Bool { model.newIDs.contains(id) }
    private var reduceMotion: Bool { model.reduceMotion() }
    private var quickNumber: Int? { model.keyboardFocused ? model.quickNumbers[id] : nil }
    private var tilt: Double { StripLayout.tilt(for: id) }

    /// Görüntü oranı korunur; aşırı oranlarda en az 8 pt.
    private var photoSize: CGSize {
        let p = StripLayout.photoSize(for: thumb?.size ?? CGSize(width: StripLayout.cardWidth - 14, height: StripLayout.photoMaxHeight))
        return CGSize(width: max(8, p.width), height: max(8, p.height))
    }
    private var photoRadius: CGFloat { StripLayout.frameRadius - StripLayout.frameInset }
    private var statusText: String {
        ThumbnailItemView.footerText(capturedAt: item.capturedAt, isDerivative: item.source == .derivative,
                                     isMissing: false, editedCaption: S.editedCaption)
    }

    var body: some View {
        VStack(spacing: -StripLayout.clipOverlap) {
            StripClip().zIndex(1)
            card
        }
        .frame(width: StripLayout.cardWidth, height: hangHeight, alignment: .top)
        // Dönüş mandal noktasından (ipin geçtiği yer).
        .rotationEffect(.degrees(swing + tilt), anchor: UnitPoint(x: 0.5, y: StripLayout.pinAbove / hangHeight))
        .offset(y: arrived ? 0 : -StripMotion.arrivalDrop)
        .opacity(falling || flying ? 0 : (arrived ? 1 : 0))
        // Uçuş/düşme katmanı devralırken ve bırakırken opaklık anlık (animasyonsuz): uçan katman kartın üstünde söner (spec §5.3).
        .transaction { t in if falling { t.animation = nil } }
        .onAppear(perform: appear)
        .onChange(of: flying) { was, now in if was && !now { landed() } }
        .onChange(of: model.gust) { _, _ in breeze() }
        .onChange(of: copied) { _, now in if now { nudge(StripMotion.copyNudge) } }
        .onChange(of: item.path) { _, _ in loadThumbnail() }
    }

    /// Kart ölçeği: basılı 0,95, üzerinde 1,035; hareket azaltmada her zaman 1 (yalnız gölge değişir).
    static func scale(pressed: Bool, hovering: Bool, reduceMotion: Bool) -> CGFloat {
        if reduceMotion { return 1 }
        return pressed ? StripMotion.pressScale : (hovering ? StripMotion.hoverScale : 1)
    }

    private var card: some View {
        photo
            .padding(StripLayout.frameInset)
            .background {
                RoundedRectangle(cornerRadius: StripLayout.frameRadius, style: .continuous)
                    .fill(Color.smElevated)
                    .shadow(color: .black.opacity(hovering ? 0.26 : 0.18), radius: hovering ? 14 : 10, y: hovering ? 8 : 5)
            }
            .overlay {
                RoundedRectangle(cornerRadius: StripLayout.frameRadius, style: .continuous)
                    .strokeBorder(Color.smSeparator, lineWidth: contrast == .increased ? 1.5 : 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: StripLayout.frameRadius, style: .continuous)
                    .strokeBorder(selected ? Color.smAccent : .clear, lineWidth: 3)
            }
            .overlay(alignment: .topLeading) { newDot }
            .overlay(alignment: .topLeading) { removeCross }
            .overlay(alignment: .bottomLeading) { numberBadge }
            // Uzun basma "dolar": basılıyken yavaşça içeri, bırakınca yaylanır.
            .scaleEffect(Self.scale(pressed: pressed, hovering: hovering, reduceMotion: reduceMotion), anchor: .top)
            .animation(reduceMotion ? nil : (pressed ? .easeInOut(duration: StripMotion.pressDuration) : .spring(response: 0.3, dampingFraction: 0.6)), value: pressed)
            .opacity(dragging ? StripMotion.dragOpacity : 1)
            .overlay(StripGrabView(id: id, model: model, actions: actions))
            .overlay(alignment: .bottom) { if copied { copyBadge } }
            .animation(.easeOut(duration: StripMotion.hoverDuration), value: hovering)
            .animation(.easeOut(duration: 0.2), value: copied)
            .onHover { hovering = $0 }
            .stripHitRect(falling || flying ? nil : id.uuidString)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.fileName)
            .accessibilityValue(isNew ? "\(S.newBadge) · \(statusText)" : statusText)
            .accessibilityAddTraits(selected ? [.isImage, .isSelected] : .isImage)
            .accessibilityAction { actions.select(id, []) }
            .accessibilityAction(named: Text(S.removeHint)) { actions.remove(id) }
    }

    @ViewBuilder private var photo: some View {
        if let thumb {
            Image(nsImage: thumb)
                .resizable()
                .interpolation(.high)
                .frame(width: photoSize.width, height: photoSize.height)
                .clipShape(RoundedRectangle(cornerRadius: photoRadius, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: photoRadius, style: .continuous)
                .fill(Color.smSeparator.opacity(0.35))
                .overlay { Image(systemName: "photo").font(.system(size: 22)).foregroundStyle(Color.smSecondary) }
                .frame(width: photoSize.width, height: photoSize.height)
        }
    }

    /// "Yeni": sol üstte vurgu noktası + açık halka (VoiceOver değeri "Yeni" der); ✕ görününce çekilir.
    @ViewBuilder private var newDot: some View {
        if isNew {
            Circle().fill(Color.smAccent).frame(width: 8, height: 8)
                .padding(1.5).background(Circle().fill(Color.smElevated))
                .padding(8)
                .opacity(hovering && !dragging ? 0 : 1)
                .allowsHitTesting(false)
        }
    }

    /// Sol üst ✕: çizim burada, tıklama ve araç ipucu `StripGrabNSView` köşe alanında (bu görünüm isabet almaz, `.help` tetiklenmezdi).
    private var removeCross: some View {
        Image(systemName: "xmark")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(Circle().fill(Color(nsColor: ShotmoriStyle.badge)))
            .padding(3)
            .opacity(hovering && !dragging ? 1 : 0)
            .scaleEffect(hovering || reduceMotion ? 1 : 0.6)
            .allowsHitTesting(false)
    }

    @ViewBuilder private var numberBadge: some View {
        if let n = quickNumber {
            Text("\(n)")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color(nsColor: ShotmoriStyle.badge)))
                .padding(6)
                .allowsHitTesting(false)
        }
    }

    private var copyBadge: some View {
        Label(S.copiedToast, systemImage: "checkmark")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .fixedSize()
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(Color(nsColor: ShotmoriStyle.badge)))
            .offset(y: 10)
            .allowsHitTesting(false)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -4)))
    }

    // MARK: Hareket

    private func appear() {
        loadThumbnail()
        // Uçan kartın varışı inişte karara bağlanır (`landed`): uçuş iptal olursa yine yukarıdan düşer.
        if !flying, model.consumeArrival(id) {
            swing = StripMotion.arrivalSwing
            dropIn()
        } else {
            arrived = true
            swing = 0
        }
    }

    /// Uçuş bitti ya da iptal edildi. Bitti: kart anında yerinde, küçük salınım. İptal: kart varışla düşer.
    private func landed() {
        guard model.consumeArrival(id) else { nudge(StripMotion.landNudge); return }
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { arrived = false; swing = StripMotion.arrivalSwing }
        DispatchQueue.main.async { dropIn() }
    }

    /// Varış: kart yukarıdan yayla iner, salınım az sönümlü yayla durulur (değerler `StripMotion`).
    private func dropIn() {
        withAnimation(.spring(response: StripMotion.arrivalDropResponse, dampingFraction: StripMotion.arrivalDropDamping)) { arrived = true }
        withAnimation(.interpolatingSpring(stiffness: StripMotion.arrivalSwingStiffness, damping: StripMotion.arrivalSwingDamping)) { swing = 0 }
    }

    private func loadThumbnail() {
        let url = item.url
        requestedThumbURL = url
        if let c = ThumbnailCache.shared.cached(url) { thumb = c; return }
        ThumbnailCache.shared.thumbnail(for: url) { img in
            // `item` bu kapanışta yakalanan kopyadır (hep eşit); güncel istek @State'ten okunur.
            if Self.acceptsThumbnail(for: url, requested: requestedThumbURL) { thumb = img }
        }
    }
    /// Gelen küçük resim kartın şu an istediği dosyanın mı.
    nonisolated static func acceptsThumbnail(for url: URL, requested: URL?) -> Bool { requested == url }

    private func breeze() {
        guard !reduceMotion else { return }
        let delay = Double.random(in: StripMotion.gustJitter)
        let degrees = Double.random(in: StripMotion.gustNudge)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { nudge(degrees) }
    }

    /// 0,3 sn ease-out ile `degrees`'e, ardından yaylı salınımla 0'a.
    private func nudge(_ degrees: Double) {
        guard !reduceMotion else { return }
        withAnimation(.easeOut(duration: StripMotion.nudgeOut)) { swing = degrees }
        DispatchQueue.main.asyncAfter(deadline: .now() + StripMotion.nudgeOut) {
            withAnimation(.interpolatingSpring(stiffness: StripMotion.nudgeStiffness, damping: StripMotion.nudgeDamping)) { swing = 0 }
        }
    }
}

// Uyarlama: Tendedero/ClipBoardLine PeggedView.swift `Clothespin`, MIT, © 2026 Alejandro Buján
/// Mandalın görünüm sabitleri: kart (`StripClip`) ve uçuş katmanı (`CaptureFlight`) aynı değerleri çizer. Boyut `StripLayout.clipSize`.
enum StripClipStyle {
    static let cornerRadius: CGFloat = 3.5
    /// Fırçalanmış metal, soldan sağa: beyaz düzeyi ve konum.
    static let metal: [(white: CGFloat, location: CGFloat)] = [(0.70, 0), (0.93, 0.35), (0.82, 0.65), (0.62, 1)]
    /// İnce kenar: üstte açık, altta koyu degrade.
    static let edgeTop: (white: CGFloat, alpha: CGFloat) = (1, 0.9)
    static let edgeBottom: (white: CGFloat, alpha: CGFloat) = (0, 0.18)
    static let edgeWidth: CGFloat = 0.6
    /// İpin geçtiği yarık: üstten 8,5 pt aşağıda 5×1,4 pt koyu kapsül.
    static let slitSize = CGSize(width: 5, height: 1.4)
    static let slitTop: CGFloat = 8.5, slitOpacity: CGFloat = 0.32
    static let shadowOpacity: CGFloat = 0.30, shadowRadius: CGFloat = 2, shadowOffsetY: CGFloat = 1.5
}

/// Fırçalanmış metal mandal: 9×26 pt kapsül, ipin geçtiği yarık, yumuşak gölge.
struct StripClip: View {
    private let metal = LinearGradient(
        stops: StripClipStyle.metal.map { Gradient.Stop(color: Color(white: $0.white), location: $0.location) },
        startPoint: .leading, endPoint: .trailing)

    var body: some View {
        RoundedRectangle(cornerRadius: StripClipStyle.cornerRadius, style: .continuous)
            .fill(metal)
            .frame(width: StripLayout.clipSize.width, height: StripLayout.clipSize.height)
            .overlay(
                RoundedRectangle(cornerRadius: StripClipStyle.cornerRadius, style: .continuous)
                    .stroke(LinearGradient(colors: [Color(white: StripClipStyle.edgeTop.white).opacity(StripClipStyle.edgeTop.alpha),
                                                    Color(white: StripClipStyle.edgeBottom.white).opacity(StripClipStyle.edgeBottom.alpha)],
                                           startPoint: .top, endPoint: .bottom), lineWidth: StripClipStyle.edgeWidth)
            )
            .overlay(alignment: .top) {
                Capsule().fill(Color.black.opacity(StripClipStyle.slitOpacity))
                    .frame(width: StripClipStyle.slitSize.width, height: StripClipStyle.slitSize.height)
                    .padding(.top, StripClipStyle.slitTop)
            }
            .shadow(color: .black.opacity(StripClipStyle.shadowOpacity), radius: StripClipStyle.shadowRadius, y: StripClipStyle.shadowOffsetY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
