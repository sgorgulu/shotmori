import XCTest
import AppKit
@testable import Shotmori

final class ThumbnailCacheTests: XCTestCase {
    func testConcurrentRequestsForSamePathDecodeOnce() {
        let lock = NSLock(); var calls = 0
        let cache = ThumbnailCache(generate: { _, _ in
            lock.lock(); calls += 1; lock.unlock()
            Thread.sleep(forTimeInterval: 0.1) // aynı anda gelen istekler çözme bitmeden kuyruğa girsin
            return NSImage(size: NSSize(width: 4, height: 4))
        })
        let url = URL(fileURLWithPath: "/tmp/shotmori-thumb-test.png")
        let done = expectation(description: "5 tamamlama"); done.expectedFulfillmentCount = 5
        for _ in 0..<5 { cache.thumbnail(for: url) { img in XCTAssertNotNil(img); done.fulfill() } }
        wait(for: [done], timeout: 5)
        lock.lock(); let n = calls; lock.unlock()
        XCTAssertEqual(n, 1)
        XCTAssertNotNil(cache.cached(url))
    }

    /// Geçici dosya: içerik uzunluğu küçük resim boyutuna yansır, böylece hangi sürümün çözüldüğü görülür.
    private func tempFile(_ bytes: Int, mtime: Date) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("thumb-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("a.png"); try rewrite(url, bytes: bytes, mtime: mtime); return url
    }
    private func rewrite(_ url: URL, bytes: Int, mtime: Date) throws {
        try Data(repeating: 7, count: bytes).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: url.path)
    }
    private static func sizeImage(_ url: URL) -> NSImage? {
        let n = (try? Data(contentsOf: url))?.count ?? 0; return NSImage(size: NSSize(width: n, height: n))
    }
    func testOverwrittenFileIsRedecoded() throws {
        let lock = NSLock(); var calls = 0
        let cache = ThumbnailCache(generate: { url, _ in lock.lock(); calls += 1; lock.unlock(); return Self.sizeImage(url) })
        let url = try tempFile(10, mtime: Date(timeIntervalSince1970: 1_800_000_000))
        func request() -> NSImage? {
            let ex = expectation(description: "küçük resim"); var out: NSImage?
            cache.thumbnail(for: url) { out = $0; ex.fulfill() }
            wait(for: [ex], timeout: 5); return out
        }
        XCTAssertEqual(request()?.size.width, 10)
        try rewrite(url, bytes: 20, mtime: Date(timeIntervalSince1970: 1_800_000_060)) // ör. Önizleme'nin aynı yola kaydı
        XCTAssertEqual(cache.cached(url)?.size.width, nil, "değişen dosya eski küçük resmi göstermemeli")
        XCTAssertEqual(request()?.size.width, 20)
        lock.lock(); let n = calls; lock.unlock()
        XCTAssertEqual(n, 2)
        XCTAssertEqual(cache.cached(url)?.size.width, 20)
    }
    func testRequestAfterOverwriteDoesNotJoinStaleInFlightDecode() throws {
        let lock = NSLock(); var calls = 0
        let started = DispatchSemaphore(value: 0), gate = DispatchSemaphore(value: 0)
        let cache = ThumbnailCache(generate: { url, _ in
            let img = Self.sizeImage(url) // dosya önce okunur, sonra bekletilir: ilk çözme eski sürümü taşır
            lock.lock(); calls += 1; lock.unlock()
            started.signal(); gate.wait(); return img
        })
        let url = try tempFile(10, mtime: Date(timeIntervalSince1970: 1_800_000_000))
        let ex1 = expectation(description: "ilk"), ex2 = expectation(description: "ikinci")
        var first: NSImage?, second: NSImage?
        cache.thumbnail(for: url) { first = $0; ex1.fulfill() }
        XCTAssertEqual(started.wait(timeout: .now() + 5), .success)
        try rewrite(url, bytes: 20, mtime: Date(timeIntervalSince1970: 1_800_000_060))
        cache.thumbnail(for: url) { second = $0; ex2.fulfill() }
        gate.signal(); gate.signal()
        wait(for: [ex1, ex2], timeout: 5)
        XCTAssertEqual(first?.size.width, 10); XCTAssertEqual(second?.size.width, 20)
        lock.lock(); let n = calls; lock.unlock()
        XCTAssertEqual(n, 2)
        XCTAssertEqual(cache.cached(url)?.size.width, 20)
    }
    func testInvalidateDropsCacheAndInFlightWithoutLosingWaiters() throws {
        let lock = NSLock(); var calls = 0
        let started = DispatchSemaphore(value: 0), gate = DispatchSemaphore(value: 0)
        let cache = ThumbnailCache(generate: { url, _ in
            let img = Self.sizeImage(url); lock.lock(); calls += 1; lock.unlock(); started.signal(); gate.wait(); return img
        })
        let url = try tempFile(10, mtime: Date(timeIntervalSince1970: 1_800_000_000))
        let ex1 = expectation(description: "ilk"), ex2 = expectation(description: "ikinci")
        cache.thumbnail(for: url) { XCTAssertNotNil($0); ex1.fulfill() }
        XCTAssertEqual(started.wait(timeout: .now() + 5), .success)
        cache.invalidate(url)
        cache.thumbnail(for: url) { XCTAssertNotNil($0); ex2.fulfill() } // geçersiz kılınan çözmeye katılmaz
        gate.signal(); gate.signal()
        wait(for: [ex1, ex2], timeout: 5)
        lock.lock(); let n = calls; lock.unlock()
        XCTAssertEqual(n, 2)
    }
}
