import AppKit

/// Raf kapatma kararı (saf): hangi seçenekler sunulur ve dialog yanıtı hangisine düşer.
/// Tek raf kapatılamaz (boş liste); boş raf dialogsuz kapanır (boş liste); dolu rafta Vazgeç · komşuya taşı · listeden düşür.
/// Dosyalara hiçbir seçenek dokunmaz.
enum ShelfCloseDecision {
    enum Option: Equatable { case cancel, move(to: UUID), drop }

    /// Komşu: önceki raf, ilk raf kapanıyorsa sonraki.
    static func neighbor(shelfIDs: [UUID], closing: UUID) -> UUID? {
        guard shelfIDs.count > 1, let i = shelfIDs.firstIndex(of: closing) else { return nil }
        return shelfIDs[i == 0 ? 1 : i - 1]
    }
    static func options(shelfIDs: [UUID], closing: UUID, itemCount: Int) -> [Option] {
        guard let n = neighbor(shelfIDs: shelfIDs, closing: closing), itemCount > 0 else { return [] }
        return [.cancel, .move(to: n), .drop]
    }
    /// NSAlert düğme sırası = seçenek sırası (ilk düğme güvenli).
    static func option(for r: NSApplication.ModalResponse, options: [Option]) -> Option {
        let i: Int
        switch r { case .alertFirstButtonReturn: i = 0; case .alertSecondButtonReturn: i = 1; case .alertThirdButtonReturn: i = 2; default: i = 0 }
        return options.indices.contains(i) ? options[i] : .cancel
    }
}
