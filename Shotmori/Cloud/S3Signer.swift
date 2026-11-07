#if SHOTMORI_CLOUD // Bulut kodu SHOTMORI_CLOUD bayrağıyla derlenir (Debug ve Release 1.0'da açık, bkz. Features.swift); bayrak kaldırılırsa derlenmez.
import Foundation
import CryptoKit

struct S3Credentials: Equatable {
    var accessKey: String
    var secretKey: String
    var region: String
    var service: String = "s3"
}

/// AWS Signature Version 4 (S3): başlık imzası ve sorgu dizesiyle ön imzalı GET. Bağımlılık yok; CryptoKit.
enum S3Signer {
    static let unsignedPayload = "UNSIGNED-PAYLOAD"

    static func sha256Hex(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func hmac(_ key: Data, _ msg: String) -> Data { Data(HMAC<SHA256>.authenticationCode(for: Data(msg.utf8), using: SymmetricKey(data: key))) }
    private static func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }

    /// AWS URI kodlaması: `A-Z a-z 0-9 - _ . ~` dışındaki her bayt `%XX`; `/` isteğe bağlı korunur.
    private static let unreserved: Set<UInt8> = {
        var set = Set<UInt8>()
        for b in UInt8(ascii: "A")...UInt8(ascii: "Z") { set.insert(b) }
        for b in UInt8(ascii: "a")...UInt8(ascii: "z") { set.insert(b) }
        for b in UInt8(ascii: "0")...UInt8(ascii: "9") { set.insert(b) }
        for ch in ["-", "_", ".", "~"] { set.insert(UInt8(ascii: Unicode.Scalar(ch)!)) }
        return set
    }()
    static func uriEncode(_ s: String, encodeSlash: Bool) -> String {
        var out = ""
        let slash = UInt8(ascii: "/")
        for b in s.utf8 {
            if unreserved.contains(b) { out.append(Character(UnicodeScalar(b))) }
            else if b == slash && !encodeSlash { out.append("/") }
            else { out += String(format: "%%%02X", b) }
        }
        return out
    }
    private static let dateFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"; f.timeZone = TimeZone(identifier: "UTC"); f.locale = Locale(identifier: "en_US_POSIX"); return f }()
    static func amzDate(_ d: Date) -> String { dateFmt.string(from: d) }
    private static func signingKey(_ c: S3Credentials, dateStamp: String) -> Data {
        let kDate = hmac(Data("AWS4\(c.secretKey)".utf8), dateStamp)
        let kRegion = hmac(kDate, c.region); let kService = hmac(kRegion, c.service)
        return hmac(kService, "aws4_request")
    }
    private static func canonicalQuery(_ items: [URLQueryItem]) -> String {
        struct Pair { let k: String; let v: String }
        var pairs: [Pair] = items.map { Pair(k: uriEncode($0.name, encodeSlash: true), v: uriEncode($0.value ?? "", encodeSlash: true)) }
        pairs.sort { a, b in a.k == b.k ? a.v < b.v : a.k < b.k }
        return pairs.map { "\($0.k)=\($0.v)" }.joined(separator: "&")
    }
    private static func canonicalPath(_ url: URL) -> String {
        let p = url.path.isEmpty ? "/" : url.path
        return uriEncode(p, encodeSlash: false)
    }

    /// Başlık imzası (PUT/HEAD/DELETE/GET). `payloadHash` = SHA-256 hex veya `UNSIGNED-PAYLOAD`.
    static func sign(_ request: URLRequest, credentials c: S3Credentials, payloadHash: String, date: Date) -> URLRequest {
        var r = request
        guard let url = r.url, let host = url.host else { return r }
        let amz = amzDate(date), stamp = String(amz.prefix(8))
        let hostHeader = url.port.map { "\(host):\($0)" } ?? host
        r.setValue(hostHeader, forHTTPHeaderField: "Host")
        r.setValue(amz, forHTTPHeaderField: "x-amz-date")
        r.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")
        var headers: [(String, String)] = []
        for (k, v) in r.allHTTPHeaderFields ?? [:] {
            let lk = k.lowercased()
            if lk == "host" || lk.hasPrefix("x-amz-") || lk == "content-type" || lk == "content-md5" { headers.append((lk, v.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "  ", with: " "))) }
        }
        headers.sort { $0.0 < $1.0 }
        let signedHeaders = headers.map(\.0).joined(separator: ";")
        let canonicalHeaders = headers.map { "\($0.0):\($0.1)\n" }.joined()
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let canonical = [r.httpMethod ?? "GET", canonicalPath(url), canonicalQuery(comps?.queryItems ?? []), canonicalHeaders, signedHeaders, payloadHash].joined(separator: "\n")
        let scope = "\(stamp)/\(c.region)/\(c.service)/aws4_request"
        let toSign = ["AWS4-HMAC-SHA256", amz, scope, sha256Hex(Data(canonical.utf8))].joined(separator: "\n")
        let sig = hex(hmac(signingKey(c, dateStamp: stamp), toSign))
        r.setValue("AWS4-HMAC-SHA256 Credential=\(c.accessKey)/\(scope), SignedHeaders=\(signedHeaders), Signature=\(sig)", forHTTPHeaderField: "Authorization")
        return r
    }

    /// Ön imzalı GET (paylaşım linki). `expires` 1…604800 saniyeye sıkıştırılır.
    static func presignedGET(url: URL, credentials c: S3Credentials, expires: Int, date: Date) -> URL {
        let amz = amzDate(date), stamp = String(amz.prefix(8))
        let scope = "\(stamp)/\(c.region)/\(c.service)/aws4_request"
        let exp = min(max(expires, 1), LinkAccess.maxPresignSeconds)
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false), let host = url.host else { return url }
        var items = comps.queryItems ?? []
        items += [URLQueryItem(name: "X-Amz-Algorithm", value: "AWS4-HMAC-SHA256"), URLQueryItem(name: "X-Amz-Credential", value: "\(c.accessKey)/\(scope)"),
                  URLQueryItem(name: "X-Amz-Date", value: amz), URLQueryItem(name: "X-Amz-Expires", value: String(exp)), URLQueryItem(name: "X-Amz-SignedHeaders", value: "host")]
        let hostHeader = url.port.map { "\(host):\($0)" } ?? host
        let canonical = ["GET", canonicalPath(url), canonicalQuery(items), "host:\(hostHeader)\n", "host", unsignedPayload].joined(separator: "\n")
        let toSign = ["AWS4-HMAC-SHA256", amz, scope, sha256Hex(Data(canonical.utf8))].joined(separator: "\n")
        let sig = hex(hmac(signingKey(c, dateStamp: stamp), toSign))
        comps.percentEncodedQuery = canonicalQuery(items) + "&X-Amz-Signature=\(sig)"
        return comps.url ?? url
    }
}
#endif
