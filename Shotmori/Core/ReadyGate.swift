import Foundation

/// Hazırlık kapısı: değer `open(_:)` ile verilene dek bekleyenler 100 ms aralıkla yoklar; süre dolarsa `IntentError.notReady`.
/// Değer zayıf tutulur (sahibi giderse kapı yeniden kapanır). Kilitle korunur (`@unchecked Sendable`); `wait` herhangi bir görevden çağrılabilir.
final class ReadyGate<T: AnyObject>: @unchecked Sendable {
    private let lock = NSLock()
    private weak var value: T?
    static var pollInterval: TimeInterval { 0.1 }

    init() {}
    var current: T? { lock.lock(); defer { lock.unlock() }; return value }
    func open(_ v: T) { lock.lock(); value = v; lock.unlock() }

    func wait(timeout: TimeInterval) async throws -> T {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let v = current { return v }
            let left = deadline.timeIntervalSinceNow
            guard left > 0 else { throw IntentError.notReady }
            try await Task.sleep(nanoseconds: UInt64(min(Self.pollInterval, left) * 1_000_000_000))
        }
    }
}
