import Foundation
import AppIntents

/// Kestirmeler/Spotlight eylemlerinin kullanıcıya görünen hataları; metinler ana tablodan (T).
enum IntentError: Error, Equatable, LocalizedError, CustomLocalizedStringResourceConvertible {
    case notReady, noImages, shelfNotFound, fileRejected, tooMany
    /// Görüntü `InboundImport.maxBytes` (50 MB) üstünde.
    case tooLarge
    /// Bağlı olmayan hizmetin görünen adı (ör. "Google Drive").
    case notConnected(String)
    case uploadStillRunning, clipboardEmpty

    var errorDescription: String? {
        switch self {
        case .notReady: return S.intentErrNotReady
        case .noImages: return S.intentErrNoImages
        case .shelfNotFound: return S.intentErrShelfNotFound
        case .fileRejected: return S.intentErrFileRejected
        case .tooMany: return S.intentErrTooMany
        case .tooLarge: return S.inboundTooLarge
        case .notConnected(let provider): return S.intentErrNotConnected(provider)
        case .uploadStillRunning: return S.intentErrUploadRunning
        case .clipboardEmpty: return S.intentErrClipboardEmpty
        }
    }
    /// Kestirmeler hata iletisi: metin zaten yerelleştirilmiş (tablo T); kaynak olarak aynen verilir.
    var localizedStringResource: LocalizedStringResource { LocalizedStringResource(stringLiteral: errorDescription ?? "") }
}
