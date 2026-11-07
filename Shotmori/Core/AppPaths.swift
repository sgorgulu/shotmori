import Foundation
import AppKit

/// Uygulama veri yolları ve tercih deposu. Üretimde macOS varsayılanları kullanılır (sandbox'ta konteyner).
/// Yalnızca Debug'da, test/QA için: `SHOTMORI_DATA_DIR` ayarlıysa raf, türevler ve günlük o dizinin altına yazılır;
/// `SHOTMORI_DEFAULTS_SUITE` ayarlıysa tercihler o ayrı domain'den okunur/yazılır (gerçek `dev.shotmori.app` tercihlerine dokunulmaz).
/// Foundation'ın dizin API'leri HOME ortam değişkenini dikkate almadığı için bu açık anahtarlar gerekir.
enum AppPaths {
    #if DEBUG
    private static let dataOverride: URL? = ProcessInfo.processInfo.environment["SHOTMORI_DATA_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    #else
    private static let dataOverride: URL? = nil
    #endif
    static var isIsolated: Bool { dataOverride != nil }

    /// Kullanıcının gerçek ev dizini. Sandbox'ta `homeDirectoryForCurrentUser` konteyneri verir; bu her zaman `/Users/<ad>`.
    static var realHome: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir { return URL(fileURLWithPath: String(cString: dir), isDirectory: true) }
        return FileManager.default.homeDirectoryForCurrentUser
    }
    /// `~/Library/Application Support/Shotmori` (veya yalıtılmış karşılığı). Bir kez çözülür ve oluşturulur: raf öğesi başına okunur
    /// (`isAccessible`), her erişimde `FileManager.urls` + `mkdir` yapılmaz. Alt klasörler (`Gelen/`, `Pano/`, `Türevler/`) kendi
    /// erişimcilerinde ara dizinleriyle oluşturulduğu için kök sonradan silinse de yazım öncesi yeniden kurulur.
    static let applicationSupport: URL = {
        let u = dataOverride?.appendingPathComponent("Application Support/Shotmori", isDirectory: true)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Shotmori", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true); return u
    }()
    /// Sandbox öncesi kök (`/Users/<ad>/Library/Application Support/Shotmori`). Sandbox dışında `applicationSupport` ile aynıdır.
    static var legacyApplicationSupport: URL { realHome.appendingPathComponent("Library/Application Support/Shotmori", isDirectory: true) }
    /// `~/Library/Logs` (veya yalıtılmış karşılığı); bir kez çözülür ve oluşturulur.
    static let logs: URL = {
        let u = dataOverride?.appendingPathComponent("Logs", isDirectory: true)
            ?? FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true); return u
    }()
    /// Yalnızca QA: `SHOTMORI_APPEARANCE=dark|light` uygulamanın görünümünü sabitler (sistem tercihi değiştirilmeden koyu/açık doğrulama).
    static var forcedAppearance: NSAppearance? {
        #if DEBUG
        guard let a = ProcessInfo.processInfo.environment["SHOTMORI_APPEARANCE"] else { return nil }
        return NSAppearance(named: a == "dark" ? .darkAqua : .aqua)
        #else
        return nil
        #endif
    }
    /// Tercih deposu: üretimde `.standard`; QA'da ayrı suite.
    static let defaults: UserDefaults = {
        #if DEBUG
        if let s = ProcessInfo.processInfo.environment["SHOTMORI_DEFAULTS_SUITE"], !s.isEmpty, let d = UserDefaults(suiteName: s) { return d }
        #endif
        return .standard
    }()
}
