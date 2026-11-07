import AppKit
import Combine

/// Şerit üstündeki raf sekmesi (Görev 8 çizer).
struct StripTab: Identifiable, Equatable {
    let id: UUID
    var title: String
    var count: Int
    var active: Bool
    var detached: Bool
    /// Sekme menüsü / VoiceOver "Ayrı pencerede aç" kullanılabilir mi (son takılı raf ayrılamaz).
    var canDetach: Bool = false
}

/// Şerit görünümünün durumu. Denetleyici (Görev 9) yazar, `StripView` okur.
@MainActor
final class StripModel: ObservableObject {
    @Published var items: [ShelfItem] = []
    @Published var newIDs: Set<UUID> = []
    @Published var selection: Set<UUID> = []
    @Published var scrollOffset: CGFloat = 0
    /// Her artışta görünür kartlar esintiyle sallanır.
    @Published var gust: Int = 0
    @Published var copiedID: UUID?
    /// Uçuş/düşme katmanının çizdiği kartlar; yerinde görünmez.
    @Published var flyingIDs: Set<UUID> = []
    @Published var fallingIDs: Set<UUID> = []
    @Published var pressedID: UUID?
    @Published var draggingID: UUID?
    @Published var keyboardFocused = false
    @Published var quickNumbers: [UUID: Int] = [:]
    @Published var tabs: [StripTab] = []
    @Published var capsule: [StripCapsuleEntry] = []
    @Published var notice: StatusMessage?
    /// Kalıcı bildirimin eylem başlığı (denetleyicinin `noticeAction`ı): "Yeniden dene"; nil → bağlantı yok.
    @Published var noticeActionTitle: String?
    @Published var emptyState: StripEmptyState = .none

    /// Tıklama alan dikdörtgenleri, `NSHostingView` küresel (pencere, sol üst) koordinatında.
    /// Anahtar: kart id'si `uuidString`, "left", "right", "notice", "empty". Yayınlanmaz (çizimi tetiklemesin).
    var hitRects: [String: CGRect] = [:]
    let reduceMotion: () -> Bool
    /// Eylem kimliğinden simge ve başlık (denetleyici `ActionRegistry`den doldurur).
    var actionInfo: (String) -> (symbol: String, title: String)? = { _ in nil }

    /// Bu oturumda yerinde görünmüş kartlar: yeniden çizim ve kaydırma düşüşü tekrar oynatmaz.
    private var arrivedIDs: Set<UUID> = []

    init(reduceMotion: @escaping () -> Bool) {
        self.reduceMotion = reduceMotion
    }

    /// Kart ilk kez görünürken yukarıdan düşmeli mi (yan etkisiz).
    func needsArrival(_ id: UUID) -> Bool {
        newIDs.contains(id) && !flyingIDs.contains(id) && !arrivedIDs.contains(id) && !reduceMotion()
    }

    /// Kart görününce bir kez çağrılır: düşmesi gerekiyorsa true döner; kart artık "görülmüş" sayılır.
    func consumeArrival(_ id: UUID) -> Bool {
        let drop = needsArrival(id)
        arrivedIDs.insert(id)
        return drop
    }

    /// Uçuş bitti: kart yerine indi, varış düşüşü oynatılmaz.
    func markArrived(_ id: UUID) { arrivedIDs.insert(id) }
}
