import Foundation

/// Testlerde ağ: her isteği yakalar, kayıtlı yanıtı döner. `handler` (URLRequest, gövde) → (durum, başlıklar, gövde).
final class MockURLProtocol: URLProtocol {
    typealias Handler = (URLRequest, Data?) -> (Int, [String: String], Data)
    nonisolated(unsafe) static var handler: Handler?
    nonisolated(unsafe) static var requests: [(URLRequest, Data?)] = []
    static func reset() { handler = nil; requests = [] }
    static func session() -> URLSession { let c = URLSessionConfiguration.ephemeral; c.protocolClasses = [MockURLProtocol.self]; return URLSession(configuration: c) }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open(); var d = Data(); let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 65536); defer { buf.deallocate() }
            while stream.hasBytesAvailable { let n = stream.read(buf, maxLength: 65536); if n <= 0 { break }; d.append(buf, count: n) }
            stream.close(); body = d
        }
        Self.requests.append((request, body))
        let (status, headers, data) = Self.handler?(request, body) ?? (500, [:], Data())
        let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
