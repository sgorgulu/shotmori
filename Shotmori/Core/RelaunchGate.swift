import Foundation

/// Dil değişikliğinden sonra yeniden başlatma: yeni örnek, eski örnek kapanana kadar bekler.
/// Böylece iki örnek aynı anda `shelf.json` yazmaz, iki menü çubuğu öğesi ve iki izleyici çalışmaz.
enum RelaunchGate {
    static let argument = "-ShotmoriWaitPID"
    static func waitPID(arguments: [String] = CommandLine.arguments) -> pid_t? {
        guard let i = arguments.firstIndex(of: argument), i + 1 < arguments.count, let n = Int32(arguments[i + 1]) else { return nil }
        return n
    }
    /// `kill(pid, 0)` EPERM dönerse süreç vardır (başka kullanıcıya ait); yalnız ESRCH "yok" demektir.
    static func isAlive(killResult: Int32, errno e: Int32) -> Bool { killResult == 0 || e == EPERM }
    static func isAlive(_ pid: pid_t) -> Bool { let r = kill(pid, 0); return isAlive(killResult: r, errno: errno) }
    /// Süreç bitene ya da süre dolana kadar bekler. Döndürür: süreç bitti mi.
    @discardableResult
    static func wait(for pid: pid_t, timeout: TimeInterval = 5, interval: TimeInterval = 0.05, isAlive: (pid_t) -> Bool = { RelaunchGate.isAlive($0) }) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while isAlive(pid) {
            if Date() >= end { return false }
            Thread.sleep(forTimeInterval: interval)
        }
        return true
    }
}
