import AppKit
import UniformTypeIdentifiers

/// İzin sınıfı: kullanıcıya eylemin ne tür bir sonucu olduğunu söyler. Aynı liste, farklı rozet.
enum ActionPermissionClass {
    case localFile, systemShare, externalService
    var label: String {
        switch self {
        case .localFile: return S.permLocal
        case .systemShare: return S.permSystemShare
        case .externalService: return S.permExternal
        }
    }
}

enum ActionAvailability { case available, unavailable(reason: String)
    var isAvailable: Bool { if case .available = self { return true }; return false }
    var reason: String? { if case .unavailable(let r) = self { return r }; return nil }
}

struct ActionContext {
    let items: [ShelfItem]
    let anchorView: NSView?
    let store: ShelfStore
    weak var panel: ShelfPresenting?
    var urls: [URL] { items.map(\.url) }
    /// Eylemin rafı: panelin gösterdiği raf (ayrılmış pencerede kendi rafı); panel yoksa nil → etkin raf.
    var shelfID: UUID? { panel?.displayedShelfID }
}

/// Tek aksiyon modeli: "bir aksiyon seçer veya oluştururum, parametrelerini kaydederim, nereden erişeceğimi belirlerim."
/// MVP'de parametreler sabittir; `id` favori çubuğu, liste ve menüde ortak anahtardır.
protocol ShelfAction: AnyObject {
    var id: String { get }
    var scope: ActionScope { get }
    var title: String { get }
    var symbolName: String { get }
    var permission: ActionPermissionClass { get }
    var isDestructive: Bool { get }
    func availability(for items: [ShelfItem]) -> ActionAvailability
    func perform(_ ctx: ActionContext)
    /// Menüde gösterilecek başlık (öğe sayısına göre değişebilir).
    func menuTitle(for items: [ShelfItem]) -> String
}
/// Eylem kapsamı: seçim (bir veya daha çok), tek görüntü, tüm raf. Menü gerekçesi ve Ayarlar'daki kapsam notu aynı kaynaktan.
enum ActionScope { case selection, single, wholeShelf
    var label: String { switch self { case .selection: return S.scopeSelection; case .single: return S.scopeSingleImage; case .wholeShelf: return S.scopeWholeShelf } }
}
extension ShelfAction {
    var isDestructive: Bool { false }
    var scope: ActionScope { .selection }
    func menuTitle(for items: [ShelfItem]) -> String { title }
    /// Ortak ön koşullar: seçim var ve dosyalar diskte.
    func requireExisting(_ items: [ShelfItem], single: Bool = false) -> ActionAvailability {
        if items.isEmpty { return .unavailable(reason: S.reasonNoSelection) }
        if single && items.count > 1 { return .unavailable(reason: S.reasonSingleOnly) }
        if items.contains(where: { !$0.exists }) { return .unavailable(reason: S.reasonMissing) }
        return .available
    }
    /// Düzenle/Boyutlandır: tek, diskte olan görüntü. Uygunluk ana iş parçacığında sık sorulur (menü, favori çubuğu, şerit kapsülü):
    /// dosya açılmaz, uzantının türüne bakılır; çözülemeyen dosya `load` aşamasında (arka planda) "okunamadı" der.
    func requireImage(_ items: [ShelfItem]) -> ActionAvailability {
        let base = requireExisting(items, single: true); guard base.isAvailable else { return base }
        return Self.isImageFile(items[0].url) ? .available : .unavailable(reason: S.reasonImagesOnly)
    }
    static func isImageFile(_ url: URL) -> Bool { UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true }
}

/// Modal paneller (kaydet, uyarı) için uygulamayı geçici olarak öne alır; iş bitince önceki uygulamaya döner.
enum ForegroundHelper {
    static func withActivation(_ body: (@escaping () -> Void) -> Void) {
        let previous = NSWorkspace.shared.frontmostApplication
        NSApp.activate(ignoringOtherApps: true)
        body {
            if let p = previous, p.bundleIdentifier != Bundle.main.bundleIdentifier { p.activate(options: []) }
        }
    }
}

// MARK: - Yerel dosya eylemleri

final class CopyImageAction: ShelfAction {
    let id = "copy-image"; let title = S.actionCopyImage; let symbolName = "doc.on.doc"; let permission = ActionPermissionClass.localFile
    func availability(for items: [ShelfItem]) -> ActionAvailability { requireExisting(items) }
    func menuTitle(for items: [ShelfItem]) -> String { S.actionCopyImages(items.count) }
    func perform(_ ctx: ActionContext) {
        let pb = NSPasteboard.general
        // Tek görüntü: dosyanın kendi verisi + dosya URL'si; PNG yalnız yapıştıran isterse tembel çözülür (ana iş parçacığında çözme yok).
        if ctx.items.count == 1, let url = ctx.urls.first, ClipboardWriter.writeImage(url, to: pb) {} else { pb.clearContents(); pb.writeObjects(ctx.urls as [NSURL]) }
        Log.info("Kopyalandı: \(ctx.items.count) öğe")
        ctx.panel?.showToast(S.copiedToast)
    }
}

final class OpenAction: ShelfAction {
    let id = "open"; let title = S.actionOpen; let symbolName = "arrow.up.forward.app"; let permission = ActionPermissionClass.localFile
    func availability(for items: [ShelfItem]) -> ActionAvailability { requireExisting(items) }
    func perform(_ ctx: ActionContext) { ctx.urls.prefix(10).forEach { NSWorkspace.shared.open($0) } }
}

final class OpenWithAction: ShelfAction {
    let id = "open-with"; let title = S.actionOpenWith; let symbolName = "square.grid.2x2"; let permission = ActionPermissionClass.localFile
    func availability(for items: [ShelfItem]) -> ActionAvailability { requireExisting(items) }
    func perform(_ ctx: ActionContext) {
        guard let first = ctx.urls.first else { return }
        let apps = NSWorkspace.shared.urlsForApplications(toOpen: first)
        let menu = NSMenu()
        for app in apps {
            let name = FileManager.default.displayName(atPath: app.path)
            let mi = NSMenuItem(title: name, action: #selector(MenuTarget.openWith(_:)), keyEquivalent: "")
            let icon = NSWorkspace.shared.icon(forFile: app.path); icon.size = NSSize(width: 16, height: 16); mi.image = icon
            mi.representedObject = app; mi.target = MenuTarget.shared
            MenuTarget.shared.pendingURLs = ctx.urls
            menu.addItem(mi)
        }
        if menu.items.isEmpty { menu.addItem(NSMenuItem(title: S.noSuitableApp, action: nil, keyEquivalent: "")) }
        if let v = ctx.anchorView { menu.popUp(positioning: nil, at: NSPoint(x: 0, y: v.bounds.height + 4), in: v) }
        else { menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil) }
    }
    /// Menü hedefi: seçilen uygulamayla aç.
    final class MenuTarget: NSObject {
        static let shared = MenuTarget()
        var pendingURLs: [URL] = []
        @objc func openWith(_ sender: NSMenuItem) {
            guard let app = sender.representedObject as? URL else { return }
            NSWorkspace.shared.open(pendingURLs, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, err in
                if let err = err { Log.error("Birlikte aç başarısız: \(Log.describe(err))") }
            }
        }
    }
}

final class RevealInFinderAction: ShelfAction {
    let id = "reveal-in-finder"; let title = S.actionRevealInFinder; let symbolName = "folder"; let permission = ActionPermissionClass.localFile
    func availability(for items: [ShelfItem]) -> ActionAvailability { requireExisting(items) }
    func perform(_ ctx: ActionContext) { NSWorkspace.shared.activateFileViewerSelecting(ctx.urls) }
}

final class SaveAsAction: ShelfAction {
    let id = "save-as"; let title = S.actionSaveAs; let symbolName = "square.and.arrow.down"; let permission = ActionPermissionClass.localFile
    func availability(for items: [ShelfItem]) -> ActionAvailability { requireExisting(items) }
    func perform(_ ctx: ActionContext) {
        let urls = ctx.urls
        ForegroundHelper.withActivation { done in
            if urls.count == 1, let src = urls.first { self.saveSingle(src, panel: ctx.panel, done: done) }
            else { self.saveMany(urls, panel: ctx.panel, done: done) }
        }
    }
    /// Tek dosya: NSSavePanel var olan farklı bir hedef için kendi değiştirme onayını sorar; kaynağın kendisi hedef seçilirse reddedilir ve yeniden seçim sunulur.
    private func saveSingle(_ src: URL, panel: ShelfPresenting?, done: @escaping () -> Void) {
        let p = NSSavePanel(); p.nameFieldStringValue = src.lastPathComponent; p.canCreateDirectories = true
        p.begin { r in
            guard r == .OK, let dst = p.url else { done(); return }
            do { try SafeFileCopy.copy(src, to: dst, replace: true); panel?.showToast(S.saveAsCopiedToast(1)); done() }
            catch SafeFileCopy.Failure.sameFile {
                let a = NSAlert(); a.alertStyle = .warning; a.messageText = S.saveAsSameFileTitle; a.informativeText = S.saveAsSameFileBody
                a.addButton(withTitle: S.saveAsChooseAnother); a.addButton(withTitle: S.cancel)
                if a.runModal() == .alertFirstButtonReturn { self.saveSingle(src, panel: panel, done: done) } else { done() }
            }
            catch { Log.error("Farklı kaydet başarısız: \(Log.describe(error))"); Self.showError(error.localizedDescription); done() }
        }
    }
    /// Çoklu: klasöre kendi adlarıyla kopyalar; aynı dosya veya var olan ad sessizce ezilmez, atlanır ve bildirilir.
    private func saveMany(_ urls: [URL], panel: ShelfPresenting?, done: @escaping () -> Void) {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true; p.prompt = S.copyHerePrompt
        p.begin { r in
            guard r == .OK, let dir = p.url else { done(); return }
            // Kopyalama arka planda; sonuç ana kuyrukta gösterilir ve bittiğinde önceki uygulamaya dönülür.
            DispatchQueue.global(qos: .userInitiated).async {
                let result = SafeFileCopy.copyAll(urls, into: dir)
                DispatchQueue.main.async {
                    defer { done() }
                    Log.info("Buraya kopyala: \(result.copied.count) kopyalandı, \(result.skipped.count) atlandı")
                    if result.skipped.isEmpty { panel?.showToast(S.saveAsCopiedToast(result.copied.count)); return }
                    let a = NSAlert(); a.alertStyle = .warning; a.messageText = S.saveAsSkippedTitle
                    a.informativeText = S.saveAsSkippedBody(result.copied.count, result.skipped.count) + "\n\n" + S.trashConfirmList(result.skipped.map { "\($0.0.lastPathComponent) — \($0.1.localizedDescription)" })
                    a.addButton(withTitle: S.ok); a.runModal()
                }
            }
        }
    }
    private static func showError(_ m: String) { let a = NSAlert(); a.alertStyle = .warning; a.messageText = S.outputErrorTitle; a.informativeText = m; a.runModal() }
}

// MARK: - Sistem paylaşımı

final class ShareAction: ShelfAction {
    let id = "share"; let title = S.actionShare; let symbolName = "square.and.arrow.up"; let permission = ActionPermissionClass.systemShare
    func availability(for items: [ShelfItem]) -> ActionAvailability { requireExisting(items) }
    func perform(_ ctx: ActionContext) {
        guard let v = ctx.anchorView else { return }
        let picker = NSSharingServicePicker(items: ctx.urls)
        SharePickerTracker.track(picker)
        picker.show(relativeTo: v.bounds, of: v, preferredEdge: .maxY)
    }
}

/// Açık paylaşım seçicileri. Seçici kipsizdir (menü izleme bitince de açık kalır): şerit açık olduğunu buradan okur ve
/// o sürede kendiliğinden çekilmez. Seçici kapanınca (hizmet seçildi ya da vazgeçildi) `didChoose` gelir ve kayıt düşer.
final class SharePickerTracker: NSObject, NSSharingServicePickerDelegate {
    /// Seçicinin temsilcisi zayıf tutulur: izleyiciler burada yaşar.
    private(set) static var active: [SharePickerTracker] = []
    static var isOpen: Bool { !active.isEmpty }

    static func track(_ picker: NSSharingServicePicker) {
        let t = SharePickerTracker()
        picker.delegate = t
        active.append(t)
    }
    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        Self.active.removeAll { $0 === self }
    }
}

// MARK: - Raf yaşam döngüsü (dosyaya dokunmayanlar ayrı, Çöp ayrı)

/// Raftan kaldırma: dosyaya dokunmaz. Tek öğe (✕) veya "Seçilenleri Raftan Kaldır (N)".
/// "Rafa taşı ▸": seçili öğeleri başka rafa taşır (menüde alt menü; dosyalar yerinde kalır). Kendi başına çalıştırılmaz.
final class MoveToShelfAction: ShelfAction {
    let id = "move-to-shelf"; let title = S.actionMoveToShelf; let symbolName = "tray.2"; let permission = ActionPermissionClass.localFile
    func availability(for items: [ShelfItem]) -> ActionAvailability { items.isEmpty ? .unavailable(reason: S.reasonNoSelection) : .available }
    func perform(_ ctx: ActionContext) {}
}
/// Alt menü yükü: belirli bir rafa (`shelfID`) ya da yeni rafa (nil) taşıma. Menü öğesinin `representedObject`'ı olarak
/// menüyle birlikte yaşar; ortak hedef `MoveToShelfMenuTarget` çalıştırır (ActionMenuTarget deseni, statik havuz yok).
final class MoveToShelfTarget: NSObject {
    let ids: Set<UUID>; let shelfID: UUID?; let store: ShelfStore; weak var panel: ShelfPresenting?
    init(ids: Set<UUID>, shelfID: UUID?, store: ShelfStore, panel: ShelfPresenting?) { self.ids = ids; self.shelfID = shelfID; self.store = store; self.panel = panel }
    func move() {
        let target: Shelf?
        if let id = shelfID { target = store.shelves.first { $0.id == id } } else { target = store.addShelf() }
        guard let t = target else { return }
        let trimmed = store.move(ids: ids, to: t.id)
        if shelfID == nil, panel?.showsTabs != false { panel?.activateShelf(t.id) } // ayrılmış pencerede ana panelin etkin rafı değişmez
        // Hedef raf sınırını aştıysa en eskiler listeden düştü: sessizce geçilmez, bildirilir (dosyalar diskte kalır).
        panel?.showToast(trimmed > 0 ? S.moveTrimmedToast(trimmed) : S.movedToShelfToast(ids.count, t.name))
    }
}
final class MoveToShelfMenuTarget: NSObject {
    static let shared = MoveToShelfMenuTarget()
    @objc func move(_ sender: NSMenuItem) { (sender.representedObject as? MoveToShelfTarget)?.move() }
}

final class RemoveFromShelfAction: ShelfAction {
    let id = "remove-from-shelf"; let title = S.actionRemoveFromShelf; let symbolName = "minus.circle"; let permission = ActionPermissionClass.localFile
    func availability(for items: [ShelfItem]) -> ActionAvailability { items.isEmpty ? .unavailable(reason: S.reasonNoSelection) : .available }
    func menuTitle(for items: [ShelfItem]) -> String { items.count > 1 ? S.actionRemoveSelected(items.count) : S.actionRemoveFromShelf }
    func perform(_ ctx: ActionContext) { ctx.store.remove(ids: Set(ctx.items.map(\.id))) }
}

final class NewGroupAction: ShelfAction {
    var scope: ActionScope { .single }
    let id = "new-group"; let title = S.actionNewGroup; let symbolName = "rectangle.split.2x1"; let permission = ActionPermissionClass.localFile
    func availability(for items: [ShelfItem]) -> ActionAvailability { items.count == 1 ? .available : .unavailable(reason: S.reasonSingleOnly) }
    func menuTitle(for items: [ShelfItem]) -> String { (items.first?.startsGroup ?? false) ? S.actionEndGroup : S.actionNewGroup }
    func perform(_ ctx: ActionContext) { if let it = ctx.items.first { ctx.store.startGroup(at: it.id) } }
}

final class ClearShelfAction: ShelfAction {
    var scope: ActionScope { .wholeShelf }
    let id = "clear-shelf"; let title = S.actionClearShelf; let symbolName = "xmark.bin"; let permission = ActionPermissionClass.localFile
    func availability(for items: [ShelfItem]) -> ActionAvailability { .available }
    func perform(_ ctx: ActionContext) {
        ForegroundHelper.withActivation { done in
            let snapshot = Set((ctx.store.shelves.first { $0.id == ctx.shelfID }?.items ?? ctx.store.items).map(\.id)) // onay anındaki öğeler
            let count = snapshot.count
            let a = NSAlert(); a.messageText = S.clearShelfTitle(count); a.informativeText = S.clearShelfBody
            ConfirmDialog.configure(a, safe: S.cancel, proceed: S.clearShelfButton, destructive: false, symbol: "tray") // nötr: dosya silmez
            let r = ConfirmDialog.run(a); done()
            if ConfirmDialog.shouldProceed(r) { ctx.store.clear(shelfID: ctx.shelfID, onlyIDs: snapshot) } // panelin kendi rafı, yalnız onay anındaki öğeler; dosyalara dokunulmaz
        }
    }
}

/// Dosyayı Çöp'e taşıma: yalnızca açıkça adlandırılmış menü eylemi; etkilenecek dosyaları listeleyen onay ister.
final class MoveToTrashAction: ShelfAction {
    let id = "move-to-trash"; let title = S.actionMoveToTrash; let symbolName = "trash"; let permission = ActionPermissionClass.localFile
    let isDestructive = true
    /// Test için enjekte edilebilir: onay ve çöpe taşıma.
    var confirm: ([ShelfItem]) -> Bool = MoveToTrashAction.defaultConfirm
    var trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }

    func availability(for items: [ShelfItem]) -> ActionAvailability { requireExisting(items) }
    func menuTitle(for items: [ShelfItem]) -> String { items.count > 1 ? S.actionMoveToTrashMany(items.count) : S.actionMoveToTrash }
    func perform(_ ctx: ActionContext) {
        let items = ctx.items
        guard !items.isEmpty, confirm(items) else { Log.info("Çöp'e taşıma iptal edildi (\(items.count) öğe)"); return }
        // Çöp'e taşıma arka planda; raf kaydı ana kuyrukta, yalnız taşınanlar için düşer.
        let trash = self.trash, store = ctx.store
        DispatchQueue.global(qos: .userInitiated).async {
            var removed = Set<UUID>()
            for it in items {
                do { try trash(it.url); removed.insert(it.id) }
                catch { Log.error("Çöp'e taşınamadı: \(Log.describe(error))") }
            }
            DispatchQueue.main.async {
                store.remove(ids: removed)
                Log.info("Çöp'e taşındı: \(removed.count)/\(items.count)")
                self.onFinished?()
            }
        }
    }
    /// Test için: çöpe taşıma ve raf güncellemesi bittiğinde (ana kuyrukta) çağrılır.
    var onFinished: (() -> Void)?
    static func defaultConfirm(_ items: [ShelfItem]) -> Bool {
        var result = false
        ForegroundHelper.withActivation { done in
            let a = NSAlert(); a.alertStyle = .warning
            a.messageText = items.count == 1 ? S.trashConfirmTitle : S.trashConfirmTitleMany(items.count)
            a.informativeText = S.trashConfirmBody(items.count)
            a.accessoryView = ConfirmDialog.fileListAccessory(items.map(\.fileName)) // tam adlar, klavyeyle incelenebilir
            ConfirmDialog.configure(a, safe: S.cancel, proceed: S.trashConfirmButtonMany(items.count), destructive: true, symbol: "trash")
            result = ConfirmDialog.shouldProceed(ConfirmDialog.run(a)); done()
        }
        return result
    }
}

// MARK: - Görüntü işlemleri (yerel)

/// Metni Kopyala: Apple Vision ile cihazda OCR. Tek görüntü; boş sonuç veya hata panoyu değiştirmez.
final class CopyTextAction: ShelfAction {
    var scope: ActionScope { .single }
    let id = "copy-text"; let title = S.actionCopyText; let symbolName = "text.viewfinder"; let permission = ActionPermissionClass.localFile
    func availability(for items: [ShelfItem]) -> ActionAvailability { requireExisting(items, single: true) }
    func perform(_ ctx: ActionContext) {
        guard let url = ctx.urls.first else { return }
        if ctx.panel?.isBusy == true { return } // sürerken yeniden tetiklenmez
        ctx.panel?.setBusy(S.ocrBusy)
        TextRecognizer.shared.recognize(url) { result in
            ctx.panel?.setBusy(nil)
            let outcome = OCRClipboardPolicy.apply(result) { text in
                let pb = NSPasteboard.general; pb.clearContents(); pb.setString(text, forType: .string)
            }
            switch outcome {
            case .copied(let n): ctx.panel?.showToast(S.ocrCopied(n)); Log.info("OCR tamamlandı (\(n) karakter)")
            case .empty: ctx.panel?.showNotice(S.ocrEmpty); Log.info("OCR: metin bulunamadı")   // kalıcı: kapatılana veya sonraki işleme kadar
            case .failed(let m): ctx.panel?.showNotice(m); Log.error("OCR hatası")
            }
        }
    }
}

/// Düzenle…: kırp + opak gizleme; tek görüntü; orijinale dokunmaz, düzleştirilmiş türev üretir.
final class EditAction: ShelfAction {
    var scope: ActionScope { .single }
    let id = "edit"; let title = S.actionEdit; let symbolName = "crop"; let permission = ActionPermissionClass.localFile
    func availability(for items: [ShelfItem]) -> ActionAvailability { requireImage(items) }
    func perform(_ ctx: ActionContext) {
        guard let item = ctx.items.first else { return }
        if ctx.panel?.isBusy == true { return } // hazırlanırken yeniden tetiklenmez
        if let cur = EditorWindowController.current { if cur.window?.isMiniaturized == true { cur.window?.deminiaturize(nil) }; cur.window?.performClose(nil); if EditorWindowController.current != nil { return } }
        EditorWindowController.load(item: item, store: ctx.store, panel: ctx.panel) { wc in
            guard let wc = wc else { ctx.panel?.showToast(S.resizeErrorUnreadable); return }
            EditorWindowController.current = wc
            NSApp.activate(ignoringOtherApps: true); wc.showWindow(nil)
        }
    }
}

/// Boyutlandır…: native ImageIO; orijinale dokunmaz, türev üretir.
final class ResizeAction: ShelfAction {
    var scope: ActionScope { .single }
    let id = "resize"; let title = S.actionResize; let symbolName = "arrow.down.right.and.arrow.up.left.rectangle"; let permission = ActionPermissionClass.localFile
    func availability(for items: [ShelfItem]) -> ActionAvailability { requireImage(items) }
    func perform(_ ctx: ActionContext) {
        guard let item = ctx.items.first else { return }
        if ctx.panel?.isBusy == true { return } // hazırlanırken yeniden tetiklenmez
        ResizeWindowController.current?.close()
        ResizeWindowController.load(item: item, store: ctx.store, panel: ctx.panel) { wc in
            guard let wc = wc else { ctx.panel?.showToast(S.resizeErrorUnreadable); return }
            ResizeWindowController.current = wc
            NSApp.activate(ignoringOtherApps: true); wc.showWindow(nil)
        }
    }
}

// MARK: - Kayıt

/// Eylem yürütme sonucu (X-03): `.ran` çalıştı (ya da `authorize`'da: çalışabilir),
/// `.unavailable` uygunluk denetimi geçmedi (neden), `.unknown` kimlik kayıtlı değil.
enum ExecuteResult: Equatable { case ran, unavailable(String), unknown }

final class ActionRegistry {
    let all: [ShelfAction]
    let prefs: Preferences
    private static func localActions() -> [ShelfAction] {
        [CopyImageAction(), OpenAction(), OpenWithAction(), RevealInFinderAction(), SaveAsAction(), ShareAction(),
         EditAction(), CopyTextAction(), ResizeAction(),
         NewGroupAction(), MoveToShelfAction(), RemoveFromShelfAction(), ClearShelfAction(), MoveToTrashAction()]
    }
    #if SHOTMORI_CLOUD
    weak var cloud: CloudCenter?
    init(prefs: Preferences, cloud: CloudCenter? = nil) {
        self.prefs = prefs; self.cloud = cloud
        var list = Self.localActions()
        if let c = cloud { list += [UploadAction(provider: .googleDrive, cloud: c), UploadAction(provider: .s3, cloud: c)] }
        all = list
    }
    #else
    /// Bulutsuz derleme (SHOTMORI_CLOUD Debug ve Release'te açık; yalnız bayrak kaldırılınca): yükleme eylemleri ve "Bulut ▸" menüsü yok.
    init(prefs: Preferences) { self.prefs = prefs; all = Self.localActions() }
    #endif
    /// Testler: verilen eylem listesiyle (casus eylemler).
    init(prefs: Preferences, actions: [ShelfAction]) { self.prefs = prefs; all = actions }

    // MARK: Tek yürütme noktası (X-03)
    /// Uygunluk denetimi; perform etmez (şeridin düşme animasyonu gibi gecikmeli yürütmeler için). Sonuç `.ran` = çalışabilir.
    func authorize(_ id: String, items: [ShelfItem]) -> (ShelfAction?, ExecuteResult) {
        guard let a = action(id) else { return (nil, .unknown) }
        return (a, authorize(a, items: items))
    }
    private func authorize(_ a: ShelfAction, items: [ShelfItem]) -> ExecuteResult {
        let av = a.availability(for: items)
        return av.isAvailable ? .ran : .unavailable(av.reason ?? "")
    }
    /// Tüm eylemler buradan yürür (panel, şerit, bağlam/"…" menüsü, menü çubuğu, Kestirmeler): uygunluk → perform.
    /// Yeni bir doğrudan `perform` yolu eklenmez (`ActionExecuteTests` değişmez denetimi).
    @discardableResult
    func execute(_ a: ShelfAction, ctx: ActionContext) -> ExecuteResult {
        let r = authorize(a, items: ctx.items)
        guard r == .ran else { return r }
        a.perform(ctx)
        return .ran
    }
    @discardableResult
    func execute(_ id: String, ctx: ActionContext) -> ExecuteResult {
        guard let a = action(id) else { return .unknown }
        return execute(a, ctx: ctx)
    }
    func action(_ id: String) -> ShelfAction? { all.first { $0.id == id } }
    /// Favori sırası kullanıcı değiştirmedikçe sabittir.
    var favorites: [ShelfAction] { prefs.favoriteActionIDs.compactMap { action($0) } }
    var favoriteCandidates: [ShelfAction] { all.filter { !$0.isDestructive && $0.id != "clear-shelf" && $0.id != "new-group" && $0.id != "move-to-shelf" } }

    /// Menü: gruplu; geçersiz eylemler gizlenmez, pasif + neden.
    func menu(for items: [ShelfItem], store: ShelfStore, anchor: NSView?, panel: ShelfPresenting?) -> NSMenu {
        let menu = NSMenu()
        // Başlık: kapsam (seçim sayısı); eylem değil
        let header = NSMenuItem(title: S.selectedCount(items.count), action: nil, keyEquivalent: ""); header.isEnabled = false; menu.addItem(header)
        #if SHOTMORI_CLOUD
        // Tek öğenin bulut kopyaları: "Bulut ▸" alt menüsü
        if items.count == 1, let c = cloud, let sub = CloudMenuBuilder.submenu(for: items[0], cloud: c) {
            menu.addItem(.separator()); let mi = NSMenuItem(title: S.cloudMenu, action: nil, keyEquivalent: ""); mi.image = NSImage(systemSymbolName: "icloud", accessibilityDescription: nil); mi.submenu = sub; menu.addItem(mi)
        }
        #endif
        // Çubuğa sığmayan favoriler ayrı bölüm olarak yinelenmez; her eylem kendi grubunda bir kez listelenir.
        // Ayırıcı yalnız en az bir eylemi çözülen grubun önüne: bulutsuz derlemede boş yükleme grubu art arda iki ayırıcı bırakmaz.
        for g in Self.visibleGroups(Self.menuGroups, resolves: { action($0) != nil }) {
            menu.addItem(.separator())
            for id in g {
                guard let a = action(id) else { continue }
                let av = a.availability(for: items)
                var t = a.menuTitle(for: items)
                if !av.isAvailable, let r = av.reason { t += " — \(r)" } else if id == "clear-shelf" { t += " — \(S.scopeWholeShelf)" }
                let mi = NSMenuItem(title: t, action: #selector(ActionMenuTarget.run(_:)), keyEquivalent: "")
                if let k = Self.menuKeys[id] { mi.keyEquivalent = k.0; mi.keyEquivalentModifierMask = k.1 } // raf klavye kısayollarının göstergesi
                mi.image = NSImage(systemSymbolName: a.symbolName, accessibilityDescription: a.title)
                mi.isEnabled = av.isAvailable
                if id == "move-to-shelf", av.isAvailable {
                    let sub = NSMenu(); let ids = Set(items.map(\.id))
                    for e in Self.moveSubmenuEntries(shelves: store.shelves.map { ($0.id, $0.name, $0.items.count) }, active: panel?.displayedShelfID ?? store.activeShelfID) {
                        if e.target == nil, sub.items.count > 0 { sub.addItem(.separator()) }
                        let si = NSMenuItem(title: e.title, action: #selector(MoveToShelfMenuTarget.move(_:)), keyEquivalent: "")
                        si.target = MoveToShelfMenuTarget.shared; si.representedObject = MoveToShelfTarget(ids: ids, shelfID: e.target, store: store, panel: panel)
                        si.isEnabled = e.target != nil || store.shelves.count < ShelfStore.maxShelves; sub.addItem(si)
                    }
                    mi.submenu = sub; menu.addItem(mi); continue
                }
                mi.target = ActionMenuTarget.shared
                mi.representedObject = ActionInvocation(action: a, ctx: ActionContext(items: items, anchorView: anchor, store: store, panel: panel), registry: self)
                menu.addItem(mi)
            }
        }
        menu.autoenablesItems = false
        return menu
    }
}
extension ActionRegistry {
    /// Sıklığa göre: kopyala/paylaş/kaydet → düzenle/OCR/boyutlandır → aç/şununla aç/Finder → raf yönetimi → ayrı Çöp.
    /// Hiçbir eylemi çözülmeyen grupları (ör. bulutsuz derlemede yükleme grubu) atar; sıra korunur.
    static func visibleGroups(_ groups: [[String]], resolves: (String) -> Bool) -> [[String]] { groups.filter { $0.contains(where: resolves) } }
    static let menuGroups: [[String]] = [["copy-image", "share", "save-as"], ["upload-drive", "upload-s3"], ["edit", "copy-text", "resize"], ["open", "open-with", "reveal-in-finder"], ["new-group", "move-to-shelf", "remove-from-shelf", "clear-shelf"], ["move-to-trash"]]
    /// Raf panelindeki klavye kısayollarıyla aynı (yalnızca gösterim; menü açıkken de çalışır).
    /// "Rafa taşı ▸" alt menüsü: etkin raf dışındaki raflar ("ad · N", boşsa yalnız ad), sonra "Yeni rafa…" (hedef nil).
    static func moveSubmenuEntries(shelves: [(UUID, String, Int)], active: UUID) -> [(title: String, target: UUID?)] {
        shelves.filter { $0.0 != active }.map { (title: $0.2 > 0 ? "\($0.1) · \($0.2)" : $0.1, target: Optional($0.0)) } + [(title: S.moveToNewShelf, target: nil)]
    }
    static let menuKeys: [String: (String, NSEvent.ModifierFlags)] = ["copy-image": ("c", [.command]), "reveal-in-finder": ("r", [.command]), "open": ("o", [.command]), "remove-from-shelf": ("\u{8}", []),
                                                                      "edit": ("e", []), "copy-text": ("c", [.command, .shift])]
}
final class ActionInvocation: NSObject {
    let action: ShelfAction; let ctx: ActionContext
    /// Yürütme kaydı (zayıf: menüyü kuran kayıt uygulama ömrü boyunca yaşar).
    weak var registry: ActionRegistry?
    init(action: ShelfAction, ctx: ActionContext, registry: ActionRegistry? = nil) { self.action = action; self.ctx = ctx; self.registry = registry }
}
final class ActionMenuTarget: NSObject {
    static let shared = ActionMenuTarget()
    /// Bağlam ve "…" menüsü: uygunluk `execute`'ta yeniden denetlenir (menü açıldıktan sonra dosya kaybı).
    @objc func run(_ sender: NSMenuItem) {
        guard let inv = sender.representedObject as? ActionInvocation, let registry = inv.registry else { return }
        if case .unavailable(let reason) = registry.execute(inv.action, ctx: inv.ctx) { inv.ctx.panel?.showToast(reason) }
    }
}
