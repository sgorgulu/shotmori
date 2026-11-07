#if SHOTMORI_CLOUD // Bulut kodu SHOTMORI_CLOUD bayrağıyla derlenir (Debug ve Release 1.0'da açık, bkz. Features.swift); bayrak kaldırılırsa derlenmez.
import Foundation

// `KeychainStore` Core/KeychainStore.swift dosyasında (bulutsuz derlemede de derlenir).

/// Anahtar Zinciri hesap adları.
enum CloudAccount {
    static let driveRefreshToken = "drive.refresh"
    static let driveAccessToken = "drive.access"
    static let driveAccessExpiry = "drive.expiry"
    static let driveClientSecret = "drive.clientSecret"
    static let s3Secret = "s3.secret"
}
#endif
