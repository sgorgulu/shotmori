import Foundation
import CoreGraphics

/// Editör/Boyutlandır çıktı teslim durumu (G). Render tamamlanması teslim değildir:
/// pencere ancak hedefe yazma, rafa ekleme veya pano yazımı başarıyla bitince "temiz" sayılır.
/// Render sırasında belge değişirse o çıktı eskimiştir ve teslim edilmez.
struct OutputSession<Snapshot: Equatable> {
    private(set) var delivered = false
    private(set) var inFlight: Snapshot?

    /// Render başlarken o anki belge anlık görüntüsü.
    mutating func begin(_ snapshot: Snapshot) { inFlight = snapshot }
    /// Render bitti: teslim yalnızca belge hâlâ aynıysa yapılır.
    func canDeliver(current: Snapshot) -> Bool { inFlight == current }
    /// Hedefe yazıldı / panoya yazıldı / rafa eklendi.
    mutating func markDelivered() { delivered = true; inFlight = nil }
    /// İptal veya hata: hiçbir şey teslim edilmedi, belge kirli kalır.
    mutating func abort() { inFlight = nil }
    /// Kapatırken kaydedilmemiş düzenleme uyarısı gerekir mi?
    func needsCloseConfirmation(hasEdits: Bool) -> Bool { hasEdits && !delivered }
}

/// Editörün teslim karşılaştırması yalnız çıktıyı etkileyen alanlarla: seçili gizleme alanı ya da araç değişimi çıktıyı eskitmez.
struct EditOutputSnapshot: Equatable {
    let crop: CGRect?
    let redactions: [CGRect]
    init(_ s: EditState) { crop = s.crop; redactions = s.redactions }
}

extension ShelfStore {
    /// Editör/Boyutlandır türevi: Shotmori'nin kendi klasöründe, izleyici görmez; kaynağın rafına (ayrılmış penceredeyse oraya)
    /// doğrudan eklenir, kaynak rafı kalmadıysa etkin rafa. Mükerrer eklenmez.
    @discardableResult
    func addDerivative(at url: URL, sourceItemID: UUID) -> Bool {
        add(ShelfItem(path: url.path, fileID: ScreenshotFileInspector.fileIdentifier(url), capturedAt: Date(), source: .derivative), to: shelf(containing: sourceItemID)?.id)
    }
}
