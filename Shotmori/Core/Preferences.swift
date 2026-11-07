import Foundation
import AppKit

/// Raf görünümü: imlecin yanında yüzen panel ya da ekranın üst kenarından inen şerit.
enum ShelfStyle: String { case floating, strip }
/// Üst şeritte yeni kare gelince: kısa süre göster (kendiliğinden çekilir) ya da kapatılana kadar açık.
enum NewCaptureStripMode: String { case peek, stay }

/// Kullanıcı tercihleri. Anahtarlar sabit; her bölüm `reset…` ile varsayılana döner.
final class Preferences {
    static let shared = Preferences(defaults: AppPaths.defaults)
    private let d: UserDefaults
    init(defaults: UserDefaults = .standard) { d = defaults }

    enum Key: String {
        case onboardingDone, customFolderPath, screenshotFolderBookmark, previousFolderBookmarks, maxItems, hideAfterDrop, favoriteActionIDs
        case hotKeyCode, hotKeyModifiers, lastSeenCaptureDate, uiLanguage
        case keepShelfOpen, showShelfOnNewScreenshot, shelfStyle, newCaptureStripMode, stripRevealFromMenuBar
        case urlSchemeEnabled, urlSchemeAsked
        case driveClientID, driveLinkAccess, driveFolderTemplate, s3Config, s3LinkAccess, s3PresignSeconds, s3PathTemplate, linkFormat, backupProvider, backupIncludesDerivatives, trashLocalAfterBackup
    }
    static let defaultMaxItems = 30
    static let defaultFavorites = ["copy-image", "reveal-in-finder", "share", "open-with"]
    static let defaultHotKeyCode: UInt32 = 1 // kVK_ANSI_S
    static let defaultHotKeyModifiers: NSEvent.ModifierFlags = [.control, .option, .command]

    var onboardingDone: Bool { get { d.bool(forKey: Key.onboardingDone.rawValue) } set { d.set(newValue, forKey: Key.onboardingDone.rawValue) } }
    /// Eski (sandbox öncesi) yol tabanlı klasör seçimi. Yalnız öneri olarak okunur; DEBUG'da QA betiği klasörü bununla verir.
    var customFolderPath: String? { get { d.string(forKey: Key.customFolderPath.rawValue) } set { d.set(newValue, forKey: Key.customFolderPath.rawValue) } }
    /// İzlenen klasörün security-scoped bookmark'ı (`FolderBookmark`).
    var folderBookmark: Data? { d.data(forKey: Key.screenshotFolderBookmark.rawValue) }
    /// Önceki klasörlerin bookmark'ları (en yeni önce, en çok 3): eski klasördeki raf öğeleri erişilebilir kalır.
    var previousFolderBookmarks: [Data] { (d.array(forKey: Key.previousFolderBookmarks.rawValue) as? [Data]) ?? [] }
    static let maxPreviousFolders = 3
    /// Bayat bookmark yenilenirken: güncel değeri değiştirir, öncekiler listesine eklemez.
    func replaceFolderBookmark(_ data: Data) { d.set(data, forKey: Key.screenshotFolderBookmark.rawValue) }
    /// Yeni klasörü güncel yapar; eskisi öncekilerin başına geçer. Aynı veri yeniden seçilirse değişiklik yok.
    /// `sameFolder`: aynı klasörü gösteren eski kayıtlar (bayt farklı olsa da) listeden düşer.
    func setFolderBookmark(_ data: Data, sameFolder: (Data) -> Bool = { _ in false }) {
        guard data != folderBookmark else { return }
        var prev = previousFolderBookmarks
        if let cur = folderBookmark { prev.removeAll { $0 == cur }; prev.insert(cur, at: 0) }
        prev.removeAll { $0 == data || sameFolder($0) }
        d.set(data, forKey: Key.screenshotFolderBookmark.rawValue)
        d.set(Array(prev.prefix(Self.maxPreviousFolders)), forKey: Key.previousFolderBookmarks.rawValue)
    }
    var maxItems: Int { get { let v = d.integer(forKey: Key.maxItems.rawValue); return v > 0 ? v : Self.defaultMaxItems } set { d.set(newValue, forKey: Key.maxItems.rawValue) } }
    var hideAfterDrop: Bool { get { d.object(forKey: Key.hideAfterDrop.rawValue) == nil ? true : d.bool(forKey: Key.hideAfterDrop.rawValue) } set { d.set(newValue, forKey: Key.hideAfterDrop.rawValue) } }
    /// Yeni ekran görüntüsü diske düşünce panel imlecin yanında kendiliğinden açılır (odak çalmadan). Varsayılan açık.
    var showShelfOnNewScreenshot: Bool { get { d.object(forKey: Key.showShelfOnNewScreenshot.rawValue) == nil ? true : d.bool(forKey: Key.showShelfOnNewScreenshot.rawValue) } set { d.set(newValue, forKey: Key.showShelfOnNewScreenshot.rawValue) } }
    var shelfStyle: ShelfStyle { get { d.string(forKey: Key.shelfStyle.rawValue).flatMap(ShelfStyle.init(rawValue:)) ?? .floating } set { d.set(newValue.rawValue, forKey: Key.shelfStyle.rawValue) } }
    var newCaptureStripMode: NewCaptureStripMode { get { d.string(forKey: Key.newCaptureStripMode.rawValue).flatMap(NewCaptureStripMode.init(rawValue:)) ?? .peek } set { d.set(newValue.rawValue, forKey: Key.newCaptureStripMode.rawValue) } }
    /// Üst şerit: imleç menü çubuğunda durunca şerit iner. Varsayılan açık.
    var stripRevealFromMenuBar: Bool { get { d.object(forKey: Key.stripRevealFromMenuBar.rawValue) == nil ? true : d.bool(forKey: Key.stripRevealFromMenuBar.rawValue) } set { d.set(newValue, forKey: Key.stripRevealFromMenuBar.rawValue) } }
    var favoriteActionIDs: [String] { get { d.stringArray(forKey: Key.favoriteActionIDs.rawValue) ?? Self.defaultFavorites } set { d.set(newValue, forKey: Key.favoriteActionIDs.rawValue) } }
    var hotKeyCode: UInt32 { get { d.object(forKey: Key.hotKeyCode.rawValue) == nil ? Self.defaultHotKeyCode : UInt32(clamping: d.integer(forKey: Key.hotKeyCode.rawValue)) } set { d.set(Int(newValue), forKey: Key.hotKeyCode.rawValue) } }
    var hotKeyModifiers: NSEvent.ModifierFlags {
        get { d.object(forKey: Key.hotKeyModifiers.rawValue) == nil ? Self.defaultHotKeyModifiers : NSEvent.ModifierFlags(rawValue: UInt(truncatingIfNeeded: d.integer(forKey: Key.hotKeyModifiers.rawValue))) }
        set { d.set(Int(newValue.rawValue), forKey: Key.hotKeyModifiers.rawValue) }
    }
    /// Arayüz dili: nil → sistem dili; "tr" / "en" → uygulamaya özel `AppleLanguages` (bir sonraki açılışta geçerli).
    var uiLanguage: String? {
        get { d.string(forKey: Key.uiLanguage.rawValue) }
        set {
            if let code = newValue { d.set(code, forKey: Key.uiLanguage.rawValue); d.set([code], forKey: "AppleLanguages") }
            else { d.removeObject(forKey: Key.uiLanguage.rawValue); d.removeObject(forKey: "AppleLanguages") }
        }
    }
    var lastSeenCaptureDate: Date? { get { d.object(forKey: Key.lastSeenCaptureDate.rawValue) as? Date } set { d.set(newValue, forKey: Key.lastSeenCaptureDate.rawValue) } }

    #if SHOTMORI_CLOUD
    // MARK: Bulut (gizli anahtarlar burada değil, Anahtar Zinciri'nde). Anahtar adları her derlemede durur; erişimciler yalnız bulutlu derlemede.
    var driveClientID: String { get { d.string(forKey: Key.driveClientID.rawValue) ?? "" } set { d.set(newValue, forKey: Key.driveClientID.rawValue) } }
    /// Drive varsayılan link gizliliği: "anyone" | "owner" (varsayılan owner: kullanıcı seçmeden herkese açık link yok).
    var driveLinkAccess: LinkAccess { get { d.string(forKey: Key.driveLinkAccess.rawValue) == "anyone" ? .anyoneWithLink : .ownerOnly } set { d.set(newValue == .anyoneWithLink ? "anyone" : "owner", forKey: Key.driveLinkAccess.rawValue) } }
    var driveFolderTemplate: String { get { d.string(forKey: Key.driveFolderTemplate.rawValue) ?? PathTemplate.default } set { d.set(newValue, forKey: Key.driveFolderTemplate.rawValue) } }
    var s3Config: S3Config? {
        get { guard let data = d.data(forKey: Key.s3Config.rawValue) else { return nil }; return try? JSONDecoder().decode(S3Config.self, from: data) }
        set { if let v = newValue, let data = try? JSONEncoder().encode(v) { d.set(data, forKey: Key.s3Config.rawValue) } else { d.removeObject(forKey: Key.s3Config.rawValue) } }
    }
    var s3PresignSeconds: Int { get { let v = d.integer(forKey: Key.s3PresignSeconds.rawValue); return v > 0 ? min(v, LinkAccess.maxPresignSeconds) : 86_400 } set { d.set(min(max(newValue, 60), LinkAccess.maxPresignSeconds), forKey: Key.s3PresignSeconds.rawValue) } }
    /// S3 varsayılan link gizliliği: "public" | "presigned" (varsayılan presigned).
    var s3LinkAccess: LinkAccess { get { d.string(forKey: Key.s3LinkAccess.rawValue) == "public" ? .publicObject : .presigned(seconds: s3PresignSeconds) } set { d.set(newValue == .publicObject ? "public" : "presigned", forKey: Key.s3LinkAccess.rawValue) } }
    var s3PathTemplate: String { get { d.string(forKey: Key.s3PathTemplate.rawValue) ?? PathTemplate.default } set { d.set(newValue, forKey: Key.s3PathTemplate.rawValue) } }
    var linkFormat: LinkFormat { get { LinkFormat(rawValue: d.string(forKey: Key.linkFormat.rawValue) ?? "") ?? .url } set { d.set(newValue.rawValue, forKey: Key.linkFormat.rawValue) } }
    /// Otomatik yedek hedefi; nil → kapalı.
    var backupProvider: CloudProviderID? { get { CloudProviderID(rawValue: d.string(forKey: Key.backupProvider.rawValue) ?? "") } set { d.set(newValue?.rawValue, forKey: Key.backupProvider.rawValue) } }
    var backupIncludesDerivatives: Bool { get { d.bool(forKey: Key.backupIncludesDerivatives.rawValue) } set { d.set(newValue, forKey: Key.backupIncludesDerivatives.rawValue) } }
    /// Yalnız açık seçimle: doğrulanmış yedekten sonra yerel dosya Çöp'e taşınır (kalıcı silinmez).
    var trashLocalAfterBackup: Bool { get { d.bool(forKey: Key.trashLocalAfterBackup.rawValue) } set { d.set(newValue, forKey: Key.trashLocalAfterBackup.rawValue) } }
    func resetCloudSection() { [Key.driveLinkAccess, .driveFolderTemplate, .s3LinkAccess, .s3PresignSeconds, .s3PathTemplate, .linkFormat, .backupProvider, .backupIncludesDerivatives, .trashLocalAfterBackup].forEach { d.removeObject(forKey: $0.rawValue) } }
    #endif

    /// Rafı önde tut: dışarı tıklama ve kabul edilen bırakma rafı kapatmaz; yalnız Esc/Gizle/kısayol kapatır.
    var keepShelfOpen: Bool { get { d.bool(forKey: Key.keepShelfOpen.rawValue) } set { d.set(newValue, forKey: Key.keepShelfOpen.rawValue) } }
    /// Klasör seçimi sıfırlanmaz: sandbox'ta yeniden seçim zorunlu olur ve izleme durur.
    func resetScreenshotsSection() { [Key.maxItems, .hideAfterDrop, .keepShelfOpen, .showShelfOnNewScreenshot, .shelfStyle, .newCaptureStripMode, .stripRevealFromMenuBar].forEach { d.removeObject(forKey: $0.rawValue) } }
    func resetActionsSection() { d.removeObject(forKey: Key.favoriteActionIDs.rawValue) }
    /// `shotmori://` komutlarına izin (varsayılan kapalı); ilk istekte bir kez sorulur.
    var urlSchemeEnabled: Bool { get { d.bool(forKey: Key.urlSchemeEnabled.rawValue) } set { d.set(newValue, forKey: Key.urlSchemeEnabled.rawValue) } }
    /// İzin diyaloğu gösterildi mi ("İzin verme" seçilse de kaydedilir; bir daha sorulmaz).
    var urlSchemeAsked: Bool { get { d.bool(forKey: Key.urlSchemeAsked.rawValue) } set { d.set(newValue, forKey: Key.urlSchemeAsked.rawValue) } }
    func resetGeneralSection() { [Key.hotKeyCode, .hotKeyModifiers, .urlSchemeEnabled, .urlSchemeAsked].forEach { d.removeObject(forKey: $0.rawValue) }; uiLanguage = nil }

    /// Tercihler değişti (Ayarlar kaydı, iğne vb.); dinleyenler kendi değerlerini yeniden okur.
    static let didChange = Notification.Name("dev.shotmori.preferencesDidChange")
    func notifyChanged() { NotificationCenter.default.post(name: Self.didChange, object: self) }
}

extension Notification.Name {
    /// Raf görünümü (yüzen/şerit) değişti; `SettingsModel.save` yalnız saklanan değer değişince yayınlar.
    static let shelfStyleChanged = Notification.Name("dev.shotmori.shelfStyleChanged")
}
