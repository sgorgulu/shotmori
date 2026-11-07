import Foundation
import Security

/// Anahtar Zinciri deposu: OAuth token'ları ve S3 gizli anahtarı yalnız burada tutulur; tercihlere ve günlüğe yazılmaz.
struct KeychainStore {
    let service: String
    init(service: String = KeychainStore.cloudService) { self.service = service }
    /// Bulut token'larının servisi. Yalıtılmış Debug/QA çalışmasında (`AppPaths.isIsolated`, yalnız Debug) ayrı ve boş bir servis:
    /// QA örneği kullanıcının gerçek Drive/S3 oturumunu okumaz, "Bağlı" göstermez, girişte gerçek kayda yazmaz. Release'te değişmez.
    static var cloudService: String { AppPaths.isIsolated ? "dev.shotmori.qa.cloud" : "dev.shotmori.app.cloud" }

    enum Failure: LocalizedError, Equatable {
        case status(OSStatus)
        var errorDescription: String? {
            #if SHOTMORI_CLOUD
            switch self { case .status(let s): return S.cloudErrKeychain(Int(s)) }
            #else
            return nil // bulutsuz derlemede bulut metin tablosu yok; Anahtar Zinciri hatası kullanıcıya gösterilmez
            #endif
        }
    }

    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    func set(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        var q = query(account)
        let update: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        var status = SecItemUpdate(q as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            q.merge(update) { $1 }
            status = SecItemAdd(q as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw Failure.status(status) }
    }
    func get(_ account: String) -> String? {
        var q = query(account); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    func delete(_ account: String) { SecItemDelete(query(account) as CFDictionary) }
}
