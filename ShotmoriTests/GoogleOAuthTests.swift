#if SHOTMORI_CLOUD // Bulut yalnız bulutlu (Debug) derlemede; Release test derlemesi de derlenebilsin.
import XCTest
@testable import Shotmori

final class GoogleOAuthTests: XCTestCase {
    var keychain: KeychainStore!
    override func setUp() { super.setUp(); MockURLProtocol.reset(); keychain = KeychainStore(service: "dev.shotmori.tests.oauth.\(UUID().uuidString)") }
    override func tearDown() { [CloudAccount.driveRefreshToken, CloudAccount.driveAccessToken, CloudAccount.driveAccessExpiry].forEach { keychain.delete($0) }; MockURLProtocol.reset(); super.tearDown() }

    func testPKCEMatchesRFC7636Example() {
        XCTAssertEqual(PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let p = PKCE.make(); XCTAssertEqual(p.verifier.count, 86); XCTAssertNil(p.verifier.rangeOfCharacter(from: CharacterSet(charactersIn: "+/="))); XCTAssertEqual(p.challenge, PKCE.challenge(for: p.verifier))
    }
    func testAuthorizationURLParameters() throws {
        let u = GoogleOAuth.authorizationURL(clientID: "cid.apps.googleusercontent.com", redirect: URL(string: "http://127.0.0.1:4567/callback")!, pkce: PKCE(verifier: "v", challenge: "c"), state: "st")
        let q = Dictionary(uniqueKeysWithValues: URLComponents(url: u, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(u.host, "accounts.google.com"); XCTAssertEqual(q["scope"], "https://www.googleapis.com/auth/drive.file"); XCTAssertEqual(q["code_challenge_method"], "S256")
        XCTAssertEqual(q["access_type"], "offline"); XCTAssertEqual(q["prompt"], "consent"); XCTAssertEqual(q["redirect_uri"], "http://127.0.0.1:4567/callback"); XCTAssertEqual(q["state"], "st")
    }
    func testLoopbackParseAcceptsOnlyMatchingStateOnCallback() {
        let ok = LoopbackServer.parse(request: "GET /callback?code=abc&state=xyz HTTP/1.1\r\nHost: x\r\n\r\n", expectedState: "xyz")
        XCTAssertTrue(ok.0.hasPrefix("200")); if case .success(let c)? = ok.2 { XCTAssertEqual(c, "abc") } else { XCTFail("kod bekleniyordu") }
        let bad = LoopbackServer.parse(request: "GET /callback?code=abc&state=nope HTTP/1.1\r\n\r\n", expectedState: "xyz"); XCTAssertTrue(bad.0.hasPrefix("400"))
        XCTAssertNil(bad.2, "state uymayan istek girişi bitirmez; bekleme sürer")
        let other = LoopbackServer.parse(request: "GET /favicon.ico HTTP/1.1\r\n\r\n", expectedState: "xyz"); XCTAssertTrue(other.0.hasPrefix("404")); XCTAssertNil(other.2)
        let denied = LoopbackServer.parse(request: "GET /callback?error=access_denied&state=xyz HTTP/1.1\r\n\r\n", expectedState: "xyz")
        if case .failure(let e)? = denied.2 { XCTAssertEqual(e as? CloudError, .authDenied) } else { XCTFail("hata bekleniyordu") }
        XCTAssertEqual(CloudError.authDenied.errorDescription, S.cloudErrAuthDenied)
        // L10N-05: state'i olmayan `error` isteği yabancıdır; girişi iptal etmez.
        let forged = LoopbackServer.parse(request: "GET /callback?error=access_denied HTTP/1.1\r\n\r\n", expectedState: "xyz"); XCTAssertTrue(forged.0.hasPrefix("400")); XCTAssertNil(forged.2)
    }
    /// COR-21: yinelenen sorgu parametresi çökertmez; ilk değer geçerlidir.
    func testLoopbackParseToleratesDuplicateParameters() {
        let dup = LoopbackServer.parse(request: "GET /callback?state=xyz&state=other&code=c1&code=c2 HTTP/1.1\r\n\r\n", expectedState: "xyz")
        if case .success(let c)? = dup.2 { XCTAssertEqual(c, "c1") } else { XCTFail("ilk değerlerle başarı bekleniyordu") }
        let dupBad = LoopbackServer.parse(request: "GET /callback?state=a&state=b HTTP/1.1\r\n\r\n", expectedState: "xyz"); XCTAssertTrue(dupBad.0.hasPrefix("400"))
    }
    /// L10N-05: yenileme belirteci gelmezse yerelleştirilmiş hata; ham metin yok.
    func testSignInWithoutRefreshTokenIsLocalizedError() async {
        MockURLProtocol.handler = { _, _ in (200, [:], Data(#"{"access_token":"AT1","expires_in":3600}"#.utf8)) }
        let o = GoogleOAuth(clientID: "cid", clientSecret: nil, keychain: keychain, session: MockURLProtocol.session(), openURL: { _ in })
        o.codeSource = { _, _ in "c" }
        do { try await o.signIn(); XCTFail("hata bekleniyordu") } catch { XCTAssertEqual(error as? CloudError, .noRefreshToken); XCTAssertEqual(error.localizedDescription, S.cloudErrNoRefreshToken) }
        XCTAssertFalse(o.isSignedIn)
    }
    func testSignInExchangesCodeAndStoresTokens() async throws {
        MockURLProtocol.handler = { req, body in
            let s = String(data: body ?? Data(), encoding: .utf8) ?? ""
            XCTAssertEqual(req.url, GoogleOAuth.tokenEndpoint); XCTAssertTrue(s.contains("grant_type=authorization_code")); XCTAssertTrue(s.contains("code=the-code")); XCTAssertTrue(s.contains("code_verifier="))
            return (200, ["Content-Type": "application/json"], Data(#"{"access_token":"AT1","expires_in":3600,"refresh_token":"RT1"}"#.utf8))
        }
        let o = GoogleOAuth(clientID: "cid", clientSecret: "sec", keychain: keychain, session: MockURLProtocol.session(), openURL: { _ in })
        o.codeSource = { _, _ in "the-code" }
        try await o.signIn()
        XCTAssertTrue(o.isSignedIn); XCTAssertEqual(keychain.get(CloudAccount.driveRefreshToken), "RT1"); XCTAssertEqual(keychain.get(CloudAccount.driveAccessToken), "AT1")
        let tok = try await o.validAccessToken(); XCTAssertEqual(tok, "AT1"); XCTAssertEqual(MockURLProtocol.requests.count, 1, "süresi dolmadan yenileme yok")
    }
    func testExpiredAccessTokenIsRefreshedAndRefreshFailureIsUnauthorized() async throws {
        try keychain.set("RT", account: CloudAccount.driveRefreshToken); try keychain.set("OLD", account: CloudAccount.driveAccessToken); try keychain.set("0", account: CloudAccount.driveAccessExpiry)
        MockURLProtocol.handler = { _, body in
            XCTAssertTrue((String(data: body ?? Data(), encoding: .utf8) ?? "").contains("grant_type=refresh_token"))
            return (200, [:], Data(#"{"access_token":"NEW","expires_in":3600}"#.utf8))
        }
        let o = GoogleOAuth(clientID: "cid", clientSecret: nil, keychain: keychain, session: MockURLProtocol.session(), openURL: { _ in })
        let refreshed = try await o.validAccessToken(); XCTAssertEqual(refreshed, "NEW"); XCTAssertEqual(keychain.get(CloudAccount.driveAccessToken), "NEW")
        // Geçici/istemci kaynaklı ret (invalid_grant değil): belirteçler korunur.
        MockURLProtocol.handler = { _, _ in (401, [:], Data(#"{"error":"invalid_client"}"#.utf8)) }
        do { _ = try await o.validAccessToken(forceRefresh: true); XCTFail("unauthorized bekleniyordu") } catch { XCTAssertEqual(error as? CloudError, .unauthorized) }
        XCTAssertTrue(o.isSignedIn)
        // COR-25: iptal edilmiş yenileme belirteci (invalid_grant) Anahtar Zinciri'nden silinir, oturum "bağlı değil"e döner.
        var expired = 0; o.onSessionExpired = { expired += 1 }
        MockURLProtocol.handler = { _, _ in (400, [:], Data(#"{"error":"invalid_grant"}"#.utf8)) }
        do { _ = try await o.validAccessToken(forceRefresh: true); XCTFail("unauthorized bekleniyordu") } catch { XCTAssertEqual(error as? CloudError, .unauthorized) }
        XCTAssertFalse(o.isSignedIn); XCTAssertNil(keychain.get(CloudAccount.driveAccessToken)); XCTAssertEqual(expired, 1)
        do { _ = try await o.validAccessToken(); XCTFail() } catch { XCTAssertEqual(error as? CloudError, .notConnected, "kuyruk bağlı değil yoluna düşer") }
    }
}
#endif
