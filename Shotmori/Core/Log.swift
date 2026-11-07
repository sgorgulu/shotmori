import Foundation
import os

/// os_log + ~/Library/Logs/Shotmori.log (tanılama için okunabilir metin).
/// Mesajlar yol, dosya adı, uygulama adı, OCR metni, URL veya token içermez (sayı ve kimlik); os_log yine de `.private` işaretler.
enum Log {
    private static let logger = Logger(subsystem: "dev.shotmori.app", category: "app")
    static let fileURL: URL = {
        let dir = AppPaths.logs
        return dir.appendingPathComponent("Shotmori.log")
    }()
    private static let queue = DispatchQueue(label: "dev.shotmori.log")
    private static let fmt: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()

    static func info(_ message: String) { logger.info("\(message, privacy: .private)"); write("INFO", message) }
    static func error(_ message: String) { logger.error("\(message, privacy: .private)"); write("ERROR", message) }
    /// Hata için yalnız alan + kod; `localizedDescription`/`userInfo` dosya yolu ve adı taşıyabilir.
    static func describe(_ error: Error) -> String { let e = error as NSError; return "\(e.domain) \(e.code)" }

    /// Dosya `limit` baytı aşınca `<ad>.1` olur (öncekinin yerine; tek kuşak). `rename(2)` hedefi atomik değiştirir.
    /// Taşınamazsa (`.1` klasör, izin yok) günlük yerinde sıfırlanır, boyut sınırlı kalır; bu bir kez yalnız os_log'a yazılır (`Log` değil: özyineleme olmasın).
    static func rotateIfNeeded(url: URL, limit: Int = 1_000_000) {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int, size > limit else { return }
        let old = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".1")
        guard Darwin.rename(url.path, old.path) != 0 else { return }
        let renameErr = errno, cut = Darwin.truncate(url.path, 0) == 0 ? 0 : errno
        if !rotateFailureReported { rotateFailureReported = true; logger.error("Günlük döndürülemedi (errno \(renameErr)); yerinde sıfırlama errno \(cut)") }
    }
    private static var rotateFailureReported = false

    private static func write(_ level: String, _ message: String) {
        let line = "\(fmt.string(from: Date())) [\(level)] \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            rotateIfNeeded(url: fileURL)
            if let h = try? FileHandle(forWritingTo: fileURL) { defer { try? h.close() }; _ = try? h.seekToEnd(); try? h.write(contentsOf: data) }
            else { try? data.write(to: fileURL) }
        }
    }
}
