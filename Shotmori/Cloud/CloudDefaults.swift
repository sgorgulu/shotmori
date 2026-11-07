#if SHOTMORI_CLOUD // Bulut kodu SHOTMORI_CLOUD bayrağıyla derlenir (Debug ve Release 1.0'da açık, bkz. Features.swift); bayrak kaldırılırsa derlenmez.
import Foundation

/// Uygulamaya gömülü bulut varsayılanları.
/// Google: geliştiricinin "Masaüstü uygulaması" türü OAuth istemcisi. Kimlik herkese açıktır; gizli anahtar açık kaynak depoda
/// yayınlanmaz, git dışı `CloudSecrets.swift`'ten gelir (bkz. `CloudSecrets.swift.example`, `scripts/bootstrap.sh`). PKCE zorunludur;
/// kullanıcı token'ları yalnız kendi Anahtar Zinciri'nde tutulur.
/// Boş bırakılırsa Ayarlar › Bulut'ta kullanıcı kendi istemcisini girer (eski davranış).
enum CloudDefaults {
    static let googleClientID = "1065557407629-nn8ptbnj7h0k3q6jfkl1e6kqbk9rotjv.apps.googleusercontent.com"
    static let googleClientSecret: String? = CloudSecrets.googleClientSecret
    static var hasEmbeddedGoogleClient: Bool { !googleClientID.isEmpty }

    /// Kullanıcının girdiği istemci öncelikli; boşsa gömülü istemci; ikisi de yoksa nil (giriş düğmesi pasif).
    static func effectiveDriveClient(customID: String, customSecret: String?, embedded: (id: String, secret: String?) = (googleClientID, googleClientSecret)) -> (id: String, secret: String?)? {
        let c = customID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !c.isEmpty { return (c, customSecret) }
        return embedded.id.isEmpty ? nil : embedded
    }
}
#endif
