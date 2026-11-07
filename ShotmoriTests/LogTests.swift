import XCTest
@testable import Shotmori

final class LogTests: XCTestCase {
    private func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("shotmori-log-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); return d
    }

    func testRotateMovesOversizedLogAside() throws {
        let d = try tempDir(), u = d.appendingPathComponent("Shotmori.log"), old = d.appendingPathComponent("Shotmori.log.1")
        try Data("eski".utf8).write(to: old) // önceki .1 yenisiyle değişir
        try Data(count: 1_100_000).write(to: u)
        Log.rotateIfNeeded(url: u)
        XCTAssertFalse(FileManager.default.fileExists(atPath: u.path))
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: old.path)[.size] as? Int), 1_100_000)
    }
    func testRotateLeavesSmallLogInPlace() throws {
        let d = try tempDir(), u = d.appendingPathComponent("Shotmori.log")
        try Data(count: 10_000).write(to: u)
        Log.rotateIfNeeded(url: u)
        XCTAssertTrue(FileManager.default.fileExists(atPath: u.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: d.appendingPathComponent("Shotmori.log.1").path))
    }
    /// `.1` taşınamıyorsa (dolu klasör, izin) günlük yerinde sıfırlanır; boyut sınırsız büyümez.
    func testRotateBoundsSizeWhenRenameFails() throws {
        let d = try tempDir(), u = d.appendingPathComponent("Shotmori.log"), old = d.appendingPathComponent("Shotmori.log.1", isDirectory: true)
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true); try Data("x".utf8).write(to: old.appendingPathComponent("dolu"))
        try Data(count: 1_100_000).write(to: u)
        Log.rotateIfNeeded(url: u)
        let size = (try? FileManager.default.attributesOfItem(atPath: u.path)[.size] as? Int) ?? 0
        XCTAssertLessThanOrEqual(size, 1_000_000)
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.appendingPathComponent("dolu").path), ".1 klasörüne dokunulmaz")
    }
    func testDescribeGivesDomainAndCodeOnly() {
        let e = NSError(domain: NSCocoaErrorDomain, code: 4, userInfo: [NSFilePathErrorKey: "/Users/kisi/Gizli.png"])
        XCTAssertEqual(Log.describe(e), "NSCocoaErrorDomain 4")
    }

    /// Kaynak tarama: günlük çağrılarında yol, dosya adı, URL, uygulama adı veya ham hata metni yok (bulut dosyaları dahil).
    /// Dosyanın tamamı taranır: satırlara bölünmüş `Log.info(` çağrısı da sonuna kadar okunur.
    func testNoLogCallInterpolatesPathOrFileName() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Shotmori", isDirectory: true)
        let forbidden = [".path", "fileName", "filePath", "lastPathComponent", "localizedName", "localizedDescription", ".absoluteString",
                         "\\(error)", "\\(err)", "\\(e)", "\\(url", "\\(u)", "\\(item", "\\(it)"]
        guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return XCTFail("kaynak kök yok: \(root.path)") }
        var files = 0, calls = 0, offenders: [String] = []
        for case let u as URL in en where u.pathExtension == "swift" {
            files += 1
            for c in Self.logCalls(in: try String(contentsOf: u, encoding: .utf8)) {
                calls += 1
                // Sayı ve kimlik serbest (`\(items.count)`, `\(item.id)`): yasak önek taramasından önce çıkarılır.
                let arg = c.argument.replacingOccurrences(of: #"\\\(\w+\.(count|id)\)"#, with: "", options: .regularExpression)
                if let bad = forbidden.first(where: { arg.contains($0) }) { offenders.append("\(u.lastPathComponent):\(c.line) [\(bad)]") }
            }
        }
        XCTAssertGreaterThan(files, 50); XCTAssertGreaterThan(calls, 30)
        XCTAssertTrue(offenders.isEmpty, "Günlükte yasak içerik:\n" + offenders.joined(separator: "\n"))
    }
    /// Metindeki her `Log.info(`/`Log.error(` çağrısının argüman metni ve başladığı satır (1'den; parantez dengesi satır sonlarını aşar; aynı satırdaki UI kodu sayılmaz).
    static func logCalls(in text: String) -> [(line: Int, argument: String)] {
        var out: [(line: Int, argument: String)] = [], rest = Substring(text), line = 1, counted = text.startIndex
        while let r = ["Log.info(", "Log.error("].compactMap({ rest.range(of: $0) }).min(by: { $0.lowerBound < $1.lowerBound }) {
            line += text[counted..<r.lowerBound].reduce(0) { $1 == "\n" ? $0 + 1 : $0 }; counted = r.lowerBound
            var depth = 1, end = r.upperBound
            while end < rest.endIndex, depth > 0 { if rest[end] == "(" { depth += 1 } else if rest[end] == ")" { depth -= 1 }; end = rest.index(after: end) }
            out.append((line, String(rest[r.upperBound..<end]))); rest = rest[end...]
        }
        return out
    }
    static func logArguments(in text: String) -> [String] { logCalls(in: text).map(\.argument) }
    func testLogArgumentsIgnoresSameLineUICode() {
        XCTAssertEqual(LogTests.logArguments(in: #"catch { Log.error("x: \(Log.describe(error))"); show(error.localizedDescription) }"#), [#""x: \(Log.describe(error))")"#])
        XCTAssertEqual(LogTests.logArguments(in: #"Log.info("a \(u.path)"); Log.error("b")"#).count, 2)
    }
    func testLogArgumentsSpanLines() {
        let src = "let a = 1\nLog.info(\"Yükleme: \\(n) öğe, \" +\n    \"\\(u.path)\")\nshow(x)\nLog.error(\"b\")"
        let calls = LogTests.logCalls(in: src)
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls.first?.line, 2); XCTAssertTrue(calls.first?.argument.contains("\\(u.path)") == true, calls.first?.argument ?? "")
        XCTAssertFalse(calls.first?.argument.contains("show") == true)
        XCTAssertEqual(calls.last?.line, 5)
    }
}
