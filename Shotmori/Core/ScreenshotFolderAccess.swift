import AppKit

/// İzlenen ekran görüntüsü klasörü. Sandbox'ta macOS'un `com.apple.screencapture` ayarı okunamaz (D5 deneyi):
/// klasörü kullanıcı seçer, erişim security-scoped bookmark (`FolderBookmark`) ile yeniden açılışta da sürer.
struct FolderAccess {
    enum State: Equatable { case ready(URL), needsSelection(suggested: URL) }
    let prefs: Preferences

    /// Varlık denetimi security scope açıkken yapılır: kapsam dışı `fileExists` sandbox'ta yanlış "yok" verebilir.
    func resolve(start: (URL) -> Bool = { $0.startAccessingSecurityScopedResource() }, stop: (URL) -> Void = { $0.stopAccessingSecurityScopedResource() }) -> State {
        if let data = prefs.folderBookmark, let r = FolderBookmark.resolve(data) {
            let ok = start(r.url); defer { if ok { stop(r.url) } }
            if FileManager.default.fileExists(atPath: r.url.path), !Self.isInTrash(r.url) {
                if r.isStale { refresh(r.url) }
                return .ready(r.url)
            }
        }
        #if DEBUG
        // Yalnız QA (sandbox dışı Debug): `scripts/qa-isolated.sh` klasörü yol olarak verir.
        if prefs.folderBookmark == nil, let p = prefs.customFolderPath { return .ready(URL(fileURLWithPath: p, isDirectory: true)) }
        #endif
        let suggested = prefs.customFolderPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? AppPaths.realHome.appendingPathComponent("Desktop", isDirectory: true)
        return .needsSelection(suggested: suggested)
    }
    /// Kullanıcının NSOpenPanel ile seçtiği klasörü kalıcı erişim olarak kaydeder.
    func choose(_ url: URL) throws {
        let key = Self.key(url)
        prefs.setFolderBookmark(try FolderBookmark.make(for: url), sameFolder: { FolderBookmark.resolve($0).map { Self.key($0.url) == key } ?? false })
    }
    /// Önceki klasörler (çözülebilenler): eski klasördeki raf öğeleri için erişim kapsamı açık tutulur.
    func previousFolders() -> [URL] { prefs.previousFolderBookmarks.compactMap { FolderBookmark.resolve($0)?.url } }
    /// Açık tutulacak erişim kapsamları: güncel klasör (varsa) + öncekiler. Güncel kaybolsa da eski raf öğeleri okunur.
    func scopes(for state: State) -> [URL] {
        if case .ready(let u) = state { return [u] + previousFolders().filter { Self.key($0) != Self.key(u) } }
        return previousFolders()
    }
    /// Bookmark taşınan klasörü izler; Çöp'e atılmış klasör izlenmez.
    static func isInTrash(_ url: URL) -> Bool { url.standardizedFileURL.pathComponents.contains { $0 == ".Trash" || $0 == ".Trashes" } }
    static func key(_ url: URL) -> String { url.standardizedFileURL.resolvingSymlinksInPath().path }
    /// `opendir` başarılı mı: tüm liste okunmaz (büyük klasörde pahalı olurdu).
    static func isReadable(_ url: URL) -> Bool { guard let d = opendir(url.path) else { return false }; closedir(d); return true }

    /// Bayat bookmark: erişim açıkken yeniden üretilir; önceki listeye dokunulmaz.
    private func refresh(_ url: URL) {
        let ok = url.startAccessingSecurityScopedResource(); defer { if ok { url.stopAccessingSecurityScopedResource() } }
        if let data = try? FolderBookmark.make(for: url) { prefs.replaceFolderBookmark(data) }
    }
}

/// Açık security-scoped erişim kapsamları. `activate` farkı uygular: çıkanları kapatır, yenileri açar, ortaklara dokunmaz.
final class FolderAccessSession {
    private let start: (URL) -> Bool
    private let stop: (URL) -> Void
    private(set) var active: [URL] = []
    /// Yalnız `start`'ı `true` dönenler kapatılır (Apple kuralı); sandbox dışında yol tabanlı URL'lerde `false` döner.
    private var started: Set<String> = []
    init(start: @escaping (URL) -> Bool = { $0.startAccessingSecurityScopedResource() }, stop: @escaping (URL) -> Void = { $0.stopAccessingSecurityScopedResource() }) {
        self.start = start; self.stop = stop
    }
    deinit { endAll() }

    func activate(_ urls: [URL]) {
        let key = { (u: URL) in u.standardizedFileURL.path }
        let wanted = Set(urls.map(key))
        for u in active where !wanted.contains(key(u)) { release(u) }
        var kept = active.filter { wanted.contains(key($0)) }
        var keys = Set(kept.map(key))
        for u in urls where keys.insert(key(u)).inserted { if start(u) { started.insert(key(u)) }; kept.append(u) }
        active = kept
    }
    func endAll() { active.forEach(release); active = [] }
    /// Yol bir açık kapsamın ya da verilen köklerin (Shotmori'nin kendi klasörü) içinde mi: dışındaki raf öğesi okunamaz.
    func covers(_ path: String, extraRoots: [URL] = []) -> Bool {
        let p = URL(fileURLWithPath: path).standardizedFileURL.path
        return (active + extraRoots).contains { let r = $0.standardizedFileURL.path; return p.hasPrefix(r.hasSuffix("/") ? r : r + "/") }
    }
    private func release(_ u: URL) { if started.remove(u.standardizedFileURL.path) != nil { stop(u) } }
}

/// Klasör seçilmemişken (kurulum yarıda kapandı, klasör silindi) kullanıcıya yol gösteren metinler: menü öğesi ve boş raf.
enum FolderPrompt {
    static func menuTitle(folder: URL?) -> String? { folder == nil ? S.menuChooseFolder : nil }
    static func emptyBody(folder: URL?, otherwise: String) -> String { folder == nil ? S.emptyNoFolderBody : otherwise }
    /// Kullanıcının başlattığı işlem başarısız olunca (klasör kaydı, yeniden başlatma) yalnız günlük yetmez: kısa uyarı.
    static func showError(_ message: String) {
        let a = NSAlert(); a.messageText = message; a.alertStyle = .warning; a.addButton(withTitle: S.ok); a.runModal()
    }
}
