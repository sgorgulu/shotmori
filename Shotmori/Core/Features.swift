import Foundation

/// Derleme bayrakları. 27.10.2026: bulut (kullanıcının kendi Google Drive / S3 hesabı; Shotmori sunucusu yok) **1.0'da açık**:
/// `SHOTMORI_CLOUD` Debug ve Release'te tanımlı. Bayrak kapalı derlenirse bulut kodu hiç derlenmez: `Cloud/` altındaki
/// sağlayıcı/kuyruk/oturum dosyaları, `CloudActions`, `CloudSettingsView` ve bunlara başvuran üyeler `#if SHOTMORI_CLOUD` içindedir;
/// bulut metinleri ayrı `Cloud.strings` tablosundadır. Yalnız veri modeli (`CloudModels`) her derlemede durur (shelf.json uyumu).
/// Denetim: `scripts/check-release-binary.sh <Shotmori.app>` bulutun eksiksiz paketlendiğini ve ağ izinlerini doğrular.
enum Features {
    #if SHOTMORI_CLOUD
    static let cloud = true
    #else
    static let cloud = false
    #endif
}
