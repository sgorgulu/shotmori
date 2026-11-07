import AppKit

/// Şeridin imleç izleyicisi (spec §9 boşta CPU %0). İki kip; hangisinin ne zaman çalışacağına `StripController.updateTracking` karar verir:
/// - `start()`: şerit görünürken 30 Hz zamanlayıcı (`.common` modu: menü açıkken ve sürüklerken de çalışır; geçirgenlik ve çekilme).
/// - `watch(hot:)`: şerit gizliyken zamanlayıcı yok; fare hareketi izleyicileri (global + yerel) yalnız imleç sıcak bölgeye
///   (menü çubuğu bandı) girince 30 Hz tıkı başlatır, çıkınca bir son tık verip durdurur. İmleç kıpırdamazken uyanma yok.
@MainActor
final class StripPointerTracker {
    static let interval: TimeInterval = 1.0 / 30
    /// Zamanlayıcı toleransı: sistem uyanmaları birleştirebilsin (geçirgenlik ve bekleme 30 Hz'in altına düşmez).
    static let tolerance: TimeInterval = interval * 0.2
    /// Gizliyken izlenen hareket olayları (sürükleme de: Finder'dan dosya sürüklerken menü çubuğunda bekleme şeridi indirir).
    static let watchedEvents: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]

    private let onTick: (NSPoint) -> Void
    private let location: () -> NSPoint
    private var timer: Timer?
    private var monitors: [Any] = []
    private var hot: ((NSPoint) -> Bool)?

    init(location: @escaping () -> NSPoint = { NSEvent.mouseLocation }, onTick: @escaping (NSPoint) -> Void) {
        self.location = location
        self.onTick = onTick
    }
    deinit {
        MainActor.assumeIsolated {
            timer?.invalidate()
            monitors.forEach { NSEvent.removeMonitor($0) }
        }
    }

    /// Herhangi bir kipte çalışıyor mu (sürekli ya da izleme).
    var isRunning: Bool { timer != nil || hot != nil }
    /// 30 Hz zamanlayıcı şu an tıklıyor mu.
    var isPolling: Bool { timer != nil }
    /// Gizli kipte, olay izleyicileriyle bekliyor mu.
    var isWatching: Bool { hot != nil }

    /// Sürekli kip: 30 Hz tık (izleme kipini kapatır).
    func start() {
        stopWatching()
        startTimer()
    }

    /// İzleme kipi: zamanlayıcı yalnız imleç `hot` bölgedeyken. İmleç zaten bölgedeyse tık hemen başlar
    /// (bantta kalırken çekilen şeridin bekleme sayacı sürer).
    func watch(hot: @escaping (NSPoint) -> Bool) {
        guard self.hot == nil else { self.hot = hot; return }
        stopTimer()
        self.hot = hot
        let handler: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: Self.watchedEvents, handler: handler) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: Self.watchedEvents, handler: { ev in handler(ev); return ev }) { monitors.append(l) }
        pointerMoved()
    }

    func stop() {
        stopWatching()
        stopTimer()
    }

    /// İzleme kipinde imleç hareket etti: sıcak bölgede tık başlar; çıkınca son konum bir kez bildirilir (bekleme sıfırlanır) ve tık durur.
    func pointerMoved() {
        guard let hot else { return }
        let p = location()
        if hot(p) {
            startTimer()
        } else if timer != nil {
            stopTimer()
            onTick(p)
        }
    }

    private func startTimer() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.timerFired() }
        }
        t.tolerance = Self.tolerance
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func timerFired() {
        let p = location()
        // İzleme kipinde imleç olay gelmeden bölgeden çıktıysa (ör. ekran değişti) tık burada da durur.
        if let hot, !hot(p) { stopTimer() }
        onTick(p)
    }

    private func stopTimer() { timer?.invalidate(); timer = nil }

    private func stopWatching() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        hot = nil
    }
}
