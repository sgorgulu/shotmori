import Foundation
import Vision
import ImageIO

/// Yerel OCR (Apple Vision). Yalnızca kullanıcı istediğinde çalışır; ağ yok, Screen Recording izni gerekmez.
/// Metin içeriği hiçbir yere loglanmaz. Değişmemiş dosya için küçük bir bellek içi önbellek tutar.
final class TextRecognizer {
    static let shared = TextRecognizer()
    struct Key: Hashable { let path: String; let size: Int; let modified: Date }
    private var cache: [Key: String] = [:]
    private var cacheOrder: [Key] = []
    private let cacheLimit = 20
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "dev.shotmori.ocr", qos: .userInitiated)

    enum OCRError: LocalizedError {
        case unreadable, failed(String)
        var errorDescription: String? {
            switch self { case .unreadable: return S.ocrErrorUnreadable; case .failed(let m): return S.ocrErrorFailed(m) }
        }
    }
    /// Hedef diller; Vision'ın bu sürümde desteklediklerine göre süzülür (doğrulanmamış dil vaat edilmez).
    static let preferredLanguages = ["tr-TR", "en-US"]
    static func availableLanguages() -> [String] {
        let req = VNRecognizeTextRequest(); req.recognitionLevel = .accurate
        let supported = (try? req.supportedRecognitionLanguages()) ?? []
        let chosen = preferredLanguages.filter { pref in supported.contains { $0.hasPrefix(pref.prefix(2)) } }
        return chosen.isEmpty ? Array(supported.prefix(1)) : chosen
    }

    func cacheKey(for url: URL) -> Key? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: url.path), let size = a[.size] as? Int, let m = a[.modificationDate] as? Date else { return nil }
        return Key(path: url.path, size: size, modified: m)
    }
    /// Sonuç ana iş parçacığında döner. Boş metin → "" (çağıran panoya dokunmaz).
    func recognize(_ url: URL, completion: @escaping (Result<String, Error>) -> Void) {
        let key = cacheKey(for: url)
        if let k = key { lock.lock(); let hit = cache[k]; lock.unlock(); if let hit = hit { completion(.success(hit)); return } }
        queue.async {
            let result = Self.recognizeSync(url)
            if case .success(let text) = result, let k = key, !text.isEmpty { self.store(k, text) }
            DispatchQueue.main.async { completion(result) }
        }
    }
    private func store(_ k: Key, _ text: String) {
        lock.lock(); defer { lock.unlock() }
        cache[k] = text; cacheOrder.append(k)
        while cacheOrder.count > cacheLimit { let old = cacheOrder.removeFirst(); cache[old] = nil }
    }
    /// Satır sırası: üstten alta, soldan sağa; satır aralığı büyük olan yerlerde paragraf boşluğu.
    /// Kaynak `maxPixels`'ı aşarsa okunmaz; `pixelBudget`'ı aşarsa en-boy korunarak bu piksel sayısına küçültülerek çözülür
    /// (dev/bozuk görüntüde sınırsız bellek yok; ekran görüntüsü boyutları — uzun kaydırmalı kareler dahil — tam çözünürlükte kalır).
    static func recognizeSync(_ url: URL, maxPixels: Int = ImageResizer.maxSourcePixels, pixelBudget: Int = ocrPixelBudget) -> Result<String, Error> {
        guard let info = ImageResizer.sourceInfo(url), info.pixelSize.width * info.pixelSize.height <= maxPixels,
              let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return .failure(OCRError.unreadable) }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceThumbnailMaxPixelSize: decodeMaxSide(width: info.pixelSize.width, height: info.pixelSize.height, budget: pixelBudget),
                                     kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return .failure(OCRError.unreadable) }
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        req.recognitionLanguages = availableLanguages()
        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:]) // yön çözmede uygulandı
        do { try handler.perform([req]) } catch { return .failure(OCRError.failed(error.localizedDescription)) }
        let obs = (req.results ?? []).compactMap { o -> (String, CGRect)? in
            guard let c = o.topCandidates(1).first else { return nil }; return (c.string, o.boundingBox)
        }
        return .success(assemble(obs))
    }
    static func assemble(_ lines: [(String, CGRect)]) -> String {
        // Vision koordinatları alt-sol kökenli; yukarıdan aşağı sırala, aynı satırdakileri soldan sağa.
        let sorted = lines.sorted { a, b in
            let dy = a.1.midY - b.1.midY
            if abs(dy) > min(a.1.height, b.1.height) * 0.5 { return dy > 0 }
            return a.1.minX < b.1.minX
        }
        var out: [String] = []; var prev: CGRect?
        for (t, r) in sorted {
            if let p = prev {
                let gap = p.minY - r.maxY
                if gap > max(p.height, r.height) * 1.2 { out.append("") } // paragraf boşluğu
            }
            out.append(t); prev = r
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    /// OCR'a verilen en büyük piksel sayısı (≈ 50 MP; 8K ekranın iki katı).
    static let ocrPixelBudget = 50_000_000
    /// Çözmede en uzun kenar: piksel sayısı `budget` içindeyse tam boy, değilse en-boy korunarak `budget`'a inecek boy (en az 1).
    static func decodeMaxSide(width: Int, height: Int, budget: Int) -> Int {
        let side = max(width, height), pixels = Double(width) * Double(height)
        guard pixels > Double(budget), pixels > 0 else { return max(side, 1) }
        return max(Int((Double(side) * (Double(budget) / pixels).squareRoot()).rounded(.down)), 1)
    }
}

/// OCR sonucunun panoya yazılma kuralı (test edilebilir): boş sonuç veya hata panoyu değiştirmez.
enum OCRClipboardPolicy {
    enum Outcome: Equatable { case copied(characters: Int), empty, failed(String) }
    static func apply(_ result: Result<String, Error>, write: (String) -> Void) -> Outcome {
        switch result {
        case .failure(let e): return .failed(e.localizedDescription)
        case .success(let text):
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { return .empty }
            write(t); return .copied(characters: t.count)
        }
    }
}
