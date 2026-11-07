#if SHOTMORI_CLOUD // Bulut kodu SHOTMORI_CLOUD bayrağıyla derlenir (Debug ve Release 1.0'da açık, bkz. Features.swift); bayrak kaldırılırsa derlenmez.
import Foundation
import Network

/// OAuth geri dönüşü için tek seferlik yerel HTTP sunucusu: 127.0.0.1, rastgele port, yalnız `GET /callback?code=…&state=…`.
/// Yanıt olarak kısa bir HTML sayfası döner; kod teslim edilince kapanır.
/// `@unchecked Sendable`: değişken durum (`continuation`, `expectedState`) yalnız seri `queue` üzerinde okunur/yazılır; `port` yalnız `init`te atanır.
final class LoopbackServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "dev.shotmori.oauth.loopback")
    private var continuation: CheckedContinuation<String, Error>?
    private var expectedState = ""
    private(set) var port: UInt16 = 0

    init() throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: params)
        let ready = DispatchSemaphore(value: 0)
        let l = listener
        var boundPort: UInt16 = 0
        l.stateUpdateHandler = { st in if case .ready = st { boundPort = l.port?.rawValue ?? 0; ready.signal() } else if case .failed = st { ready.signal() } }
        l.newConnectionHandler = { [weak self] c in self?.handle(c) }
        l.start(queue: queue)
        _ = ready.wait(timeout: .now() + 3)
        guard boundPort > 0 else { throw CloudError.network("loopback") }
        port = boundPort
    }
    func waitForCode(state: String, timeout: TimeInterval) async throws -> String {
        return try await withCheckedThrowingContinuation { cont in
            queue.async { self.expectedState = state; self.continuation = cont }
            queue.asyncAfter(deadline: .now() + timeout) { [weak self] in self?.finish(.failure(CloudError.cancelled)) }
        }
    }
    func stop() { listener.cancel() }

    private func finish(_ r: Result<String, Error>) {
        guard let c = continuation else { return }; continuation = nil
        switch r { case .success(let s): c.resume(returning: s); case .failure(let e): c.resume(throwing: e) }
    }
    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, _, _ in
            guard let self = self else { return }
            let text = String(data: data ?? Data(), encoding: .utf8) ?? ""
            let (status, body, result) = Self.parse(request: text, expectedState: self.expectedState)
            let resp = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
            conn.send(content: Data(resp.utf8), completion: .contentProcessed { _ in conn.cancel() })
            if let r = result { self.finish(r) }
        }
    }
    /// İlk satırı çözer; `/callback` dışı istekler 404. Önce state doğrulanır: uymayan ya da eksik istek 400 alır ve
    /// bekleme sürer (sonuç nil; yabancı bir istek girişi bitiremez). State uyarsa `error` → `.authDenied`, `code` → başarı.
    /// Yinelenen sorgu parametresinde ilk değer geçerlidir (çökme yok).
    static func parse(request: String, expectedState: String) -> (String, String, Result<String, Error>?) {
        guard let line = request.components(separatedBy: "\r\n").first, line.hasPrefix("GET "), let target = line.split(separator: " ").dropFirst().first,
              let comps = URLComponents(string: "http://127.0.0.1" + target), comps.path == "/callback" else { return ("404 Not Found", "<html><body>Not found</body></html>", nil) }
        let q = Dictionary((comps.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        guard !expectedState.isEmpty, q["state"] == expectedState else { return ("400 Bad Request", page(S.cloudAuthStateMismatch), nil) }
        if q["error"] != nil { return ("200 OK", page(S.cloudAuthDenied), .failure(CloudError.authDenied)) }
        guard let code = q["code"], !code.isEmpty else { return ("400 Bad Request", page(S.cloudAuthStateMismatch), nil) }
        return ("200 OK", page(S.cloudAuthDone), .success(code))
    }
    private static func page(_ msg: String) -> String { "<!doctype html><html><head><meta charset=\"utf-8\"><title>Shotmori</title></head><body style=\"font-family:-apple-system;padding:40px;color:#28292E;background:#F7F6F3\"><h2>Shotmori</h2><p>\(msg)</p></body></html>" }
}
#endif
