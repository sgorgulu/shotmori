import AppKit

/// Menü çubuğu simgesine bırakma: düğmenin üstünde saydam katman. Fare tıklamaları düğmeye geçer (`hitTest` → nil),
/// yalnız sürükleme hedefi olur. `NSStatusBarWindow` temsilcisine dokunulmaz; sol/sağ tık ve popover davranışı değişmez.
final class StatusDropView: NSView {
    static let acceptedTypes: [NSPasteboard.PasteboardType] = [.fileURL, .png, .tiff]

    /// Bırakılan dosya URL'leri (öncelikli) ya da URL yoksa görsel verisi (veri, uzantı).
    var onDrop: ((_ urls: [URL], _ data: (Data, String)?) -> Void)?
    /// Vurgu için düğme (zayıf: düğme bu görünümün üst görünümüdür).
    weak var button: NSButton?

    override init(frame: NSRect) {
        super.init(frame: frame)
        autoresizingMask = [.width, .height]
        registerForDraggedTypes(Self.acceptedTypes)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) kullanılmaz") }

    /// Tıklamalar alttaki düğmeye geçer; sürükleme hedefliği `hitTest`'ten bağımsızdır.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Saf karar: raftan gelen iç sürükleme (`internalType`) reddedilir; dosya URL'si / PNG / TIFF → kopya; başka tür → yok.
    static func operation(for types: [NSPasteboard.PasteboardType], internalType: NSPasteboard.PasteboardType = ShelfPanelController.internalItemsType) -> NSDragOperation {
        if types.contains(internalType) { return [] }
        return types.contains(where: acceptedTypes.contains) ? .copy : []
    }

    /// Sürükleme başında verilen karar: `draggingUpdated`/`prepareForDragOperation` her güncellemede pano verisini okumaz (PERF-06).
    private var currentOperation: NSDragOperation = []

    /// Pano kararı (kaynak denetimi hariç): dosya varsa en az biri görsel olmalı; dosya yoksa PNG/TIFF türü bulunmalı.
    /// Görsel verisi burada okunmaz (yalnız tür varlığı); veri yalnız `performDragOperation`'da okunur.
    static func operation(for pb: NSPasteboard) -> NSDragOperation {
        guard operation(for: pb.types ?? []) == .copy else { return [] }
        let urls = ServicePasteboard.fileURLs(from: pb)
        if !urls.isEmpty { return urls.contains(where: InboundImport.accepts) ? .copy : [] }
        return pb.availableType(from: [.png, .tiff]) == nil ? [] : .copy
    }

    /// Uygulama içi kaynak (panel, popover) reddedilir.
    private func operation(for sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingSource == nil else { return [] }
        return Self.operation(for: sender.draggingPasteboard)
    }

    private func setHighlight(_ on: Bool) { button?.highlight(on) }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        currentOperation = operation(for: sender); setHighlight(currentOperation == .copy); return currentOperation
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { currentOperation }
    override func draggingExited(_ sender: NSDraggingInfo?) { setHighlight(false); currentOperation = [] }
    override func draggingEnded(_ sender: NSDraggingInfo) { setHighlight(false); currentOperation = [] }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { currentOperation == .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        setHighlight(false)
        let pb = sender.draggingPasteboard
        let urls = ServicePasteboard.fileURLs(from: pb)
        let data = urls.isEmpty ? ServicePasteboard.imageData(from: pb) : nil
        guard !urls.isEmpty || data != nil else { return false }
        onDrop?(urls, data)
        return true
    }
}
