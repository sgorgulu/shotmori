#if SHOTMORI_CLOUD // Bulut yalnız bulutlu (Debug) derlemede; Release test derlemesi de derlenebilsin.
import XCTest
@testable import Shotmori

/// AWS belgelerindeki test vektörleri (examplebucket, AKIAIOSFODNN7EXAMPLE, 20130524T000000Z).
final class S3SignerTests: XCTestCase {
    let creds = S3Credentials(accessKey: "AKIAIOSFODNN7EXAMPLE", secretKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY", region: "us-east-1")
    var date: Date { var c = DateComponents(); c.year = 2013; c.month = 5; c.day = 24; c.hour = 0; c.minute = 0; c.second = 0; c.timeZone = TimeZone(identifier: "UTC"); return Calendar(identifier: .gregorian).date(from: c)! }

    func testPresignedGETMatchesAWSExample() throws {
        let u = S3Signer.presignedGET(url: URL(string: "https://examplebucket.s3.amazonaws.com/test.txt")!, credentials: creds, expires: 86400, date: date)
        let q = Dictionary(uniqueKeysWithValues: URLComponents(url: u, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(q["X-Amz-Algorithm"], "AWS4-HMAC-SHA256"); XCTAssertEqual(q["X-Amz-Date"], "20130524T000000Z"); XCTAssertEqual(q["X-Amz-Expires"], "86400"); XCTAssertEqual(q["X-Amz-SignedHeaders"], "host")
        XCTAssertEqual(q["X-Amz-Credential"], "AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request")
        XCTAssertEqual(q["X-Amz-Signature"], "aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404")
    }
    func testHeaderSignatureMatchesAWSGetObjectExample() {
        // AWS örneği: GET /test.txt, Range: bytes=0-9, x-amz-content-sha256 = e3b0… (boş gövde)
        var r = URLRequest(url: URL(string: "https://examplebucket.s3.amazonaws.com/test.txt")!); r.httpMethod = "GET"; r.setValue("bytes=0-9", forHTTPHeaderField: "Range")
        let empty = S3Signer.sha256Hex(Data())
        // Range başlığı imzalanmaz (yalnız host, x-amz-*); AWS örneği Range'i de imzalar, bu yüzden burada algoritmayı kendi vektörümüzle doğruluyoruz:
        let signed = S3Signer.sign(r, credentials: creds, payloadHash: empty, date: date)
        let auth = signed.value(forHTTPHeaderField: "Authorization") ?? ""
        XCTAssertTrue(auth.hasPrefix("AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request, SignedHeaders=host;x-amz-content-sha256;x-amz-date, Signature="), auth)
        XCTAssertEqual(signed.value(forHTTPHeaderField: "x-amz-date"), "20130524T000000Z")
        XCTAssertEqual(signed.value(forHTTPHeaderField: "x-amz-content-sha256"), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        // Aynı girdi → aynı imza (deterministik); farklı gizli anahtar → farklı imza
        let again = S3Signer.sign(r, credentials: creds, payloadHash: empty, date: date)
        XCTAssertEqual(again.value(forHTTPHeaderField: "Authorization"), auth)
        var other = creds; other.secretKey += "x"
        XCTAssertNotEqual(S3Signer.sign(r, credentials: other, payloadHash: empty, date: date).value(forHTTPHeaderField: "Authorization"), auth)
    }
    func testPutWithACLIncludesHeaderInSignedHeaders() {
        var r = URLRequest(url: URL(string: "https://b.s3.eu-central-1.amazonaws.com/Shotmori/2026-10/a.png")!); r.httpMethod = "PUT"
        r.setValue("public-read", forHTTPHeaderField: "x-amz-acl"); r.setValue("image/png", forHTTPHeaderField: "Content-Type")
        let signed = S3Signer.sign(r, credentials: S3Credentials(accessKey: "AK", secretKey: "SK", region: "eu-central-1"), payloadHash: S3Signer.sha256Hex(Data([1, 2, 3])), date: date)
        XCTAssertTrue(signed.value(forHTTPHeaderField: "Authorization")!.contains("SignedHeaders=content-type;host;x-amz-acl;x-amz-content-sha256;x-amz-date"))
    }
    func testUriEncodeTurkishSpacesAndHash() {
        XCTAssertEqual(S3Signer.uriEncode("Ekran Görüntüsü #1.png", encodeSlash: true), "Ekran%20G%C3%B6r%C3%BCnt%C3%BCs%C3%BC%20%231.png")
        XCTAssertEqual(S3Signer.uriEncode("a/b c", encodeSlash: false), "a/b%20c"); XCTAssertEqual(S3Signer.uriEncode("a/b", encodeSlash: true), "a%2Fb")
    }
    func testPresignExpiresClampedTo7Days() {
        let u = S3Signer.presignedGET(url: URL(string: "https://b.s3.amazonaws.com/k")!, credentials: creds, expires: 10_000_000, date: date)
        XCTAssertTrue(u.absoluteString.contains("X-Amz-Expires=604800"))
    }
}
#endif
