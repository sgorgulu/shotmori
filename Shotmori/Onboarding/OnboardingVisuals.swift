import SwiftUI

/// Kurulum görselleri: metinsiz, dil-nötr SwiftUI şekilleri (site görselleri İngilizce metin taşıdığı için kullanılmaz).

/// 1. sayfa: üç adım — görüntü al › rafa bul › sürükle; hiyerarşik vurgu sembolleri.
struct StepIconRow: View {
    let labels: (capture: String, shelf: String, drag: String)
    var body: some View {
        HStack(spacing: 0) {
            step("photo.on.rectangle.angled", labels.capture); chevron
            step("tray.full", labels.shelf); chevron
            step("cursorarrow.motionlines", labels.drag)
        }.frame(maxWidth: .infinity)
    }
    private var chevron: some View { Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(.tertiary).frame(maxWidth: .infinity).accessibilityHidden(true) }
    private func step(_ symbol: String, _ label: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 40, weight: .regular)).symbolRenderingMode(.hierarchical).foregroundStyle(Color.smAccent)
            Text(label).font(.callout)
        }.frame(width: 130)
    }
}

/// 3. sayfa: kart v2 görünümlü dört örnek kart; ilki seçili + "Yeni" noktası. İçerikler şekil (grafik, belge satırları, pencere, kod satırları).
struct SampleShelfPreview: View {
    enum SampleKind: CaseIterable, Hashable { case chart, document, interface, code }
    static let kinds = SampleKind.allCases
    /// VoiceOver için tüm görselin açıklaması (dört kart, ikisi yeni).
    let accessibilityText: String
    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(Self.kinds.enumerated()), id: \.offset) { i, kind in
                card(kind, selected: i == 0, isNew: i < 2)
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel(accessibilityText)
    }
    private func card(_ kind: SampleKind, selected: Bool, isNew: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? Color.smSelection : Color.smElevated)
            content(kind).padding(10)
            RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(selected ? Color.smAccent : Color.smSeparator, lineWidth: selected ? 2 : 1)
            if selected {
                Circle().fill(Color.smAccent).frame(width: 20, height: 20).overlay(Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.smOnAccent)).padding(6)
            } else if isNew {
                Circle().fill(Color.smAccent).frame(width: 8, height: 8).overlay(Circle().stroke(Color.smElevated, lineWidth: 1.5)).padding(8)
            }
        }
        .frame(width: 112, height: 82)
    }
    @ViewBuilder private func content(_ kind: SampleKind) -> some View {
        switch kind {
        case .chart:
            HStack(alignment: .bottom, spacing: 5) {
                ForEach([0.35, 0.6, 0.45, 0.9, 0.55, 0.7], id: \.self) { h in RoundedRectangle(cornerRadius: 2).fill(Color.smAccent.opacity(h > 0.8 ? 1 : 0.45)).frame(height: 54 * h) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        case .document:
            VStack(alignment: .leading, spacing: 6) {
                ForEach([0.5, 0.9, 0.8, 0.6], id: \.self) { w in Capsule().fill(Color.smSeparator).frame(width: 88 * w, height: 6) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .interface:
            VStack(spacing: 4) {
                HStack(spacing: 3) { ForEach(0..<3, id: \.self) { _ in Circle().fill(Color.smSeparator).frame(width: 5, height: 5) }; Spacer() }
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.smSeparator.opacity(0.6)).frame(width: 24)
                    VStack(spacing: 4) { RoundedRectangle(cornerRadius: 3).fill(Color.smSeparator.opacity(0.5)); RoundedRectangle(cornerRadius: 3).fill(Color.smAccent.opacity(0.35)) }
                }
            }
        case .code:
            VStack(alignment: .leading, spacing: 5) {
                ForEach([(0.4, true), (0.7, false), (0.55, false), (0.3, true)], id: \.0) { w, accent in Capsule().fill(accent ? Color.smAccent.opacity(0.6) : Color.smSeparator).frame(width: 88 * w, height: 6).padding(.leading, accent ? 0 : 10) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// 6. sayfa: kart › ok › hedef pencere çerçevesi (sürükleyip bırakma).
struct DragIllustration: View {
    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.smElevated)
                RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.smAccent, lineWidth: 2)
                Image(systemName: "photo").font(.system(size: 22)).foregroundStyle(Color.smAccent)
            }.frame(width: 84, height: 62)
            Image(systemName: "arrow.right").font(.system(size: 22, weight: .semibold)).foregroundStyle(Color.smAccent)
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.smElevated)
                RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.smSeparator, lineWidth: 1)
                HStack(spacing: 4) { ForEach(0..<3, id: \.self) { _ in Circle().fill(Color.smSeparator).frame(width: 6, height: 6) }; Spacer() }.padding(8)
                RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.smAccent, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])).frame(width: 88, height: 46).padding(.top, 24)
            }.frame(width: 150, height: 84)
        }.frame(maxWidth: .infinity).accessibilityHidden(true)
    }
}
