import AppKit
import ImageIO

// Uyarlama: Tendedero/ClipBoardLine AppDelegate.swift `presentCapture`, `fly`, `fall`, `cardFrame(for:)`, MIT, © 2026 Alejandro Buján

/// Şerit: yeni karede iniş, yakalanan yerden uçuş ve raftan kaldırılan kartın düşmesi (spec §5.3, §5.7, §7.1).
extension StripController {
    /// Yeni ekran görüntüsü (`AppController.flushIngest`): şerit odak almadan `screen` üstüne iner ya da (zaten görünürse)
    /// kısa gösterim süresi yeniden başlar. Gizliyken en yeni kart seçilir; görünürken kullanıcının seçimi korunur.
    /// Yakalama dikdörtgeni varsa kart çizilmeden "uçuyor" işaretlenir (yerinde düşmesin), 0,03 sn sonra (şerit yerleşince)
    /// `FlightGate` geçerse uçar; geçmezse kart varışla gelir.
    func presentNewCapture(_ item: ShelfItem, from rect: CGRect?, on screen: NSScreen?) {
        let wasShown = isVisible
        let candidate = rect != nil && !model.reduceMotion() && CaptureFlight.flightsInProgress < StripMotion.maxConcurrentFlights
        if candidate { markFlying(item.id, true) }
        reveal(on: screen, reason: .newCapture)
        if !wasShown {
            selectNewest()
            scrollToVisible(item.id)
        }
        guard candidate, let rect else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in self?.fly(item, from: rect) }
    }

    private func fly(_ item: ShelfItem, from rect: CGRect) {
        guard model.flyingIDs.contains(item.id) else { return }
        let screen = panel.screen
        // Bozuk ya da kötü niyetli xattr (sonsuz, NaN, aşırı büyük dikdörtgen) `Int` dönüşümünde çökertmez: uçuş olmaz.
        guard let maxPixels = Self.flightPixelSize(rect: rect, scale: screen?.backingScaleFactor ?? 2) else {
            cancelFlight(item.id)
            return
        }
        // Çözme (PNG'de tam çözüm) ana iş parçacığını tutmasın: arka planda, sonuç ana kuyrukta.
        let url = item.url
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let image = Self.flightImage(url, maxPixels: maxPixels)
            DispatchQueue.main.async { self?.launchFlight(item, from: rect, image: image) }
        }
    }

    /// Görüntü hazır: kart hâlâ uçmayı bekliyorsa (şerit çekilmediyse, uçuş iptal olmadıysa) ve kapı geçerse uçar.
    private func launchFlight(_ item: ShelfItem, from rect: CGRect, image: CGImage?) {
        guard model.flyingIDs.contains(item.id) else { return }
        let screen = panel.screen
        let target = image.flatMap { cardFrameOnScreen(item.id, imageSize: CGSize(width: $0.width, height: $0.height)) }
        guard FlightGate.shouldFly(reduceMotion: model.reduceMotion(), hasCaptureRect: true, stripVisible: isVisible,
                                   flightsInProgress: CaptureFlight.flightsInProgress, hasTarget: target != nil && screen != nil),
              let image, let target, let screen else {
            cancelFlight(item.id)
            return
        }
        CaptureFlight.fly(image: image, from: rect, to: target, tilt: StripLayout.tilt(for: item.id), on: screen) { [weak self] in
            self?.markFlying(item.id, false)
        }
    }

    /// Uçuş katmanı kartı çizerken kart yerinde görünmez. `false`: uçuş bitti, kart altında anında belirir (varış düşüşü yok,
    /// yalnız küçük salınım).
    func markFlying(_ id: UUID, _ on: Bool) {
        if on {
            model.flyingIDs.insert(id)
        } else {
            model.markArrived(id)
            model.flyingIDs.remove(id)
        }
    }

    /// Uçuş olmadı (görüntü/hedef yok, şerit çekildi, sınır doldu): kart varışla (yukarıdan düşerek) gelir.
    func cancelFlight(_ id: UUID) { model.flyingIDs.remove(id) }

    /// Kartın ipteki dinlenme çerçevesi (ekran koordinatı, eğimsiz); kart şeridin görünür alanında değilse nil.
    /// `imageSize` yoksa önbellekteki küçük resmin oranı kullanılır (kart da onu çizer).
    func cardFrameOnScreen(_ id: UUID, imageSize: CGSize? = nil) -> CGRect? {
        guard let index = model.items.firstIndex(where: { $0.id == id }) else { return nil }
        let size = imageSize ?? ThumbnailCache.shared.cached(model.items[index].url)?.size
        return Self.cardFrame(index: index, scrollOffset: model.scrollOffset, panelFrame: panel.frame, imageSize: size)
    }

    /// `StripView` + `StripCardView` yerleşimiyle aynı hesap: görünüm üstü `ropeY − pinAbove`, kart mandalın 26 − 12 pt altında.
    static func cardFrame(index: Int, scrollOffset: CGFloat, panelFrame: CGRect, imageSize: CGSize?) -> CGRect? {
        let width = panelFrame.width
        let x = StripLayout.x(index: index, scrollOffset: scrollOffset)
        let size = StripLayout.cardSize(for: imageSize ?? CGSize(width: StripLayout.cardWidth - 14, height: StripLayout.photoMaxHeight))
        guard x + size.width / 2 > 0, x - size.width / 2 < width else { return nil }
        let cardTop = StripLayout.ropeY(x: x, width: width) - StripLayout.pinAbove + StripLayout.clipSize.height - StripLayout.clipOverlap
        return CGRect(x: panelFrame.minX + x - size.width / 2, y: panelFrame.maxY - cardTop - size.height,
                      width: size.width, height: size.height)
    }

    /// Kaldırılan kartlar ipten düşer (şerit görünür, hareket azaltma kapalı); uçmakta olan ya da ekran dışındaki kart düşmez.
    func fall(_ items: [ShelfItem]) {
        guard isVisible, !model.reduceMotion(), let screen = panel.screen else { return }
        for item in items where !model.flyingIDs.contains(item.id) {
            guard let thumb = ThumbnailCache.shared.cached(item.url),
                  let image = thumb.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let card = cardFrameOnScreen(item.id, imageSize: thumb.size) else { continue }
            CaptureFlight.fall(image: image, card: card, tilt: StripLayout.tilt(for: item.id), on: screen)
        }
    }

    /// Uçuş görüntüsünün uzun kenarı (px): ekran çözünürlüğünde ama 400…1500 aralığında; tam Retina ekran görüntüsü
    /// tam boyda çözülmez. Dikdörtgen sonlu ve pozitif değilse nil (uçuş yok).
    static func flightPixelSize(rect: CGRect, scale: CGFloat) -> Int? {
        let values = [rect.minX, rect.minY, rect.width, rect.height, scale]
        guard values.allSatisfy(\.isFinite), rect.width > 0, rect.height > 0, scale > 0 else { return nil }
        let side = min(max(rect.width, rect.height) * scale, 1500) // `Int` dönüşümünden önce sınırlanır
        return max(400, Int(side))
    }

    /// Uçuş görüntüsü: diskten küçük resim (dönüş uygulanmış); okunamazsa nil.
    nonisolated static func flightImage(_ url: URL, maxPixels: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceShouldCacheImmediately: true]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }
}
