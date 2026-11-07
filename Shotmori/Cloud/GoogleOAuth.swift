#if SHOTMORI_CLOUD // Bulut kodu SHOTMORI_CLOUD bayrağıyla derlenir (Debug ve Release 1.0'da açık, bkz. Features.swift); bayrak kaldırılırsa derlenmez.
import Foundation
import AppKit
import CryptoKit

/// PKCE çifti: verifier 64 rastgele bayt (base64url, 86 karakter), challenge = base64url(SHA-256(verifier)).
struct PKCE: Equatable {
    let verifier: String
    let challenge: String
    static func make() -> PKCE {
        var bytes = [UInt8](repeating: 0, count: 64); _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = base64url(Data(bytes))
        return PKCE(verifier: verifier, challenge: challenge(for: verifier))
    }
    static func challenge(for verifier: String) -> String { base64url(Data(SHA256.hash(data: Data(verifier.utf8)))) }
    static func base64url(_ d: Data) -> String { d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}

/// Google "Masaüstü uygulaması" OAuth istemcisi: tarayıcıda giriş, yerel geri dönüş (127.0.0.1), PKCE, yenileme belirteci.
/// Token'lar yalnız Anahtar Zinciri'nde. Kapsam: drive.file (yalnız uygulamanın oluşturduğu dosyalar).
final class GoogleOAuth {
    static let scope = "https://www.googleapis.com/auth/drive.file"
    static let authEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    static let revokeEndpoint = URL(string: "https://oauth2.googleapis.com/revoke")!

    let clientID: String
    private let clientSecret: String?
    private let keychain: KeychainStore
    private let session: URLSession
    private let openURL: (URL) -> Void
    var now: () -> Date = Date.init
    /// Test/QA: yerel sunucu yerine kodu doğrudan sağlayan kanca.
    var codeSource: ((URL, String) async throws -> String)?

    init(clientID: String, clientSecret: String?, keychain: KeychainStore, session: URLSession = .shared, openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }) {
        self.clientID = clientID; self.clientSecret = clientSecret; self.keychain = keychain; self.session = session; self.openURL = openURL
    }
    var isSignedIn: Bool { !(keychain.get(CloudAccount.driveRefreshToken) ?? "").isEmpty }

    static func authorizationURL(clientID: String, redirect: URL, pkce: PKCE, state: String) -> URL {
        var c = URLComponents(url: authEndpoint, resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "client_id", value: clientID), URLQueryItem(name: "redirect_uri", value: redirect.absoluteString), URLQueryItem(name: "response_type", value: "code"),
                        URLQueryItem(name: "scope", value: scope), URLQueryItem(name: "code_challenge", value: pkce.challenge), URLQueryItem(name: "code_challenge_method", value: "S256"),
                        URLQueryItem(name: "state", value: state), URLQueryItem(name: "access_type", value: "offline"), URLQueryItem(name: "prompt", value: "consent")]
        return c.url!
    }

    /// Tarayıcıda onay → yerel sunucuya kod → token değişimi → Anahtar Zinciri.
    func signIn() async throws {
        let pkce = PKCE.make(), state = PKCE.base64url(Data((0..<16).map { _ in UInt8.random(in: 0...255) }))
        let code: String; let redirect: URL
        if let src = codeSource {
            redirect = URL(string: "http://127.0.0.1:1/callback")!
            code = try await src(Self.authorizationURL(clientID: clientID, redirect: redirect, pkce: pkce, state: state), state)
        } else {
            let server = try LoopbackServer()
            redirect = URL(string: "http://127.0.0.1:\(server.port)/callback")!
            openURL(Self.authorizationURL(clientID: clientID, redirect: redirect, pkce: pkce, state: state))
            defer { server.stop() }
            code = try await server.waitForCode(state: state, timeout: 300)
        }
        var form = ["code": code, "client_id": clientID, "redirect_uri": redirect.absoluteString, "grant_type": "authorization_code", "code_verifier": pkce.verifier]
        if let s = clientSecret, !s.isEmpty { form["client_secret"] = s }
        let t: TokenResponse
        do { t = try await tokenRequest(form) } catch TokenFailure.invalidGrant { throw CloudError.unauthorized }
        guard let refresh = t.refresh_token else { throw CloudError.noRefreshToken }
        try keychain.set(refresh, account: CloudAccount.driveRefreshToken)
        try store(access: t)
    }
    private struct TokenResponse: Decodable { let access_token: String; let expires_in: Int?; let refresh_token: String? }
    /// Belirteç uç noktası `invalid_grant` döndü: yenileme belirteci iptal edilmiş ya da süresi dolmuş.
    private enum TokenFailure: Error { case invalidGrant }
    private func store(access t: TokenResponse) throws {
        try keychain.set(t.access_token, account: CloudAccount.driveAccessToken)
        try keychain.set(String(Int(now().timeIntervalSince1970) + (t.expires_in ?? 3600) - 60), account: CloudAccount.driveAccessExpiry)
    }
    private func tokenRequest(_ form: [String: String]) async throws -> TokenResponse {
        var r = URLRequest(url: Self.tokenEndpoint); r.httpMethod = "POST"; r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.httpBody = Data(form.map { "\($0.key)=\(Self.formEncode($0.value))" }.sorted().joined(separator: "&").utf8)
        let (data, http) = try await CloudHTTP.send(r, session: session)
        if http.statusCode == 400 || http.statusCode == 401 {
            if ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["error"] as? String == "invalid_grant" { throw TokenFailure.invalidGrant }
            throw CloudError.unauthorized
        }
        if let e = CloudError.from(status: http.statusCode, body: data) { throw e }
        do { return try JSONDecoder().decode(TokenResponse.self, from: data) } catch { throw CloudError.invalidResponse }
    }
    static func formEncode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
    /// Geçerli erişim belirteci; süresi dolmuşsa yeniler. Yenileme `invalid_grant` ile reddedilirse (belirteç iptal edilmiş)
    /// belirteçler Anahtar Zinciri'nden silinir, `onSessionExpired` çağrılır ve `.unauthorized` atılır: Drive "bağlı değil" görünür,
    /// kuyruk `.notConnected` yoluna düşer, kullanıcı yeniden giriş yapar.
    func validAccessToken(forceRefresh: Bool = false) async throws -> String {
        guard let refresh = keychain.get(CloudAccount.driveRefreshToken), !refresh.isEmpty else { throw CloudError.notConnected }
        let expiry = TimeInterval(keychain.get(CloudAccount.driveAccessExpiry) ?? "") ?? 0
        if !forceRefresh, let access = keychain.get(CloudAccount.driveAccessToken), !access.isEmpty, now().timeIntervalSince1970 < expiry { return access }
        var form = ["refresh_token": refresh, "client_id": clientID, "grant_type": "refresh_token"]
        if let s = clientSecret, !s.isEmpty { form["client_secret"] = s }
        let t: TokenResponse
        do { t = try await tokenRequest(form) }
        catch TokenFailure.invalidGrant { clearTokens(); onSessionExpired?(); throw CloudError.unauthorized }
        try store(access: t)
        return t.access_token
    }
    /// Yenileme belirteci geçersiz kılındığında (her iş parçacığından çağrılabilir; alıcı ana iş parçacığına kendisi geçer).
    var onSessionExpired: (() -> Void)?
    func signOut() async {
        if let refresh = keychain.get(CloudAccount.driveRefreshToken) {
            var r = URLRequest(url: Self.revokeEndpoint); r.httpMethod = "POST"; r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type"); r.httpBody = Data("token=\(Self.formEncode(refresh))".utf8)
            _ = try? await CloudHTTP.send(r, session: session)
        }
        clearTokens()
    }
    private func clearTokens() { [CloudAccount.driveRefreshToken, CloudAccount.driveAccessToken, CloudAccount.driveAccessExpiry].forEach { keychain.delete($0) } }
}
#endif
