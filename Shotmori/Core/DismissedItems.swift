import Foundation

/// Kullanıcının raftan kaldırdığı (ya da kırpmayla düşen) karenin izi: izleyici/yakalama aynı kareyi geri getirmesin.
/// Yeni kare aynı yolu kullansa da `capturedAt` farklıdır → eşleşmez, eklenir.
struct DismissedKey: Codable, Equatable {
    let path: String
    let fileID: String?
    let capturedAt: Date
    init(path: String, fileID: String?, capturedAt: Date) { self.path = path; self.fileID = fileID; self.capturedAt = capturedAt }
    init(_ item: ShelfItem) { self.init(path: item.path, fileID: item.fileID, capturedAt: item.capturedAt) }
    /// (yol eşit || dosya kimliği eşit ve nil değil) && çekim zamanı farkı < 1 sn.
    func matches(_ item: ShelfItem) -> Bool {
        (path == item.path || (fileID != nil && fileID == item.fileID)) && abs(capturedAt.timeIntervalSince(item.capturedAt)) < 1
    }
}
