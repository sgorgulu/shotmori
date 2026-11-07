#if SHOTMORI_CLOUD // Bulut kodu SHOTMORI_CLOUD bayrağıyla derlenir (Debug ve Release 1.0'da açık, bkz. Features.swift); bayrak kaldırılırsa derlenmez.
import AppKit

/// "Drive'a yükle" / "S3'e yükle": seçili (var olan) dosyaları kuyruğa alır; link bitince panoya gelir.
final class UploadAction: ShelfAction {
    let provider: CloudProviderID
    private weak var cloud: CloudCenter?
    let permission = ActionPermissionClass.externalService
    init(provider: CloudProviderID, cloud: CloudCenter?) { self.provider = provider; self.cloud = cloud }
    var id: String { provider == .googleDrive ? "upload-drive" : "upload-s3" }
    var title: String { provider == .googleDrive ? S.actionUploadDrive : S.actionUploadS3 }
    var symbolName: String { "icloud.and.arrow.up" }
    func availability(for items: [ShelfItem]) -> ActionAvailability {
        guard cloud?.isConnected(provider) == true else { return .unavailable(reason: S.cloudNotConnected(provider.title)) }
        return requireExisting(items)
    }
    func perform(_ ctx: ActionContext) { cloud?.panel = ctx.panel ?? cloud?.panel; cloud?.share(items: ctx.items, to: provider) }
}

/// Tek öğenin bulut kopyaları için alt menü: Linki kopyala · Tarayıcıda aç · Erişimi değiştir ▸ · Buluttan sil…
enum CloudMenuBuilder {
    /// Menü hedefi (`CloudMenuTarget`) öğelerin `representedObject`'inde taşınır: menü yaşadıkça hedef de yaşar (küresel havuz yok).
    static func submenu(for item: ShelfItem, cloud: CloudCenter) -> NSMenu? {
        guard !item.cloud.isEmpty else { return nil }
        let m = NSMenu()
        for (i, obj) in item.cloud.enumerated() {
            if item.cloud.count > 1 { let h = NSMenuItem(title: obj.provider.title, action: nil, keyEquivalent: ""); h.isEnabled = false; m.addItem(h) }
            let target = CloudMenuTarget(item: item, object: obj, cloud: cloud)
            let copy = NSMenuItem(title: S.cloudCopyLink, action: #selector(CloudMenuTarget.copyLink), keyEquivalent: ""); copy.target = target; copy.representedObject = target; copy.isEnabled = obj.link != nil; copy.image = NSImage(systemSymbolName: "link", accessibilityDescription: nil); m.addItem(copy)
            let open = NSMenuItem(title: S.cloudOpenLink, action: #selector(CloudMenuTarget.openLink), keyEquivalent: ""); open.target = target; open.representedObject = target; open.isEnabled = obj.link != nil; open.image = NSImage(systemSymbolName: "safari", accessibilityDescription: nil); m.addItem(open)
            let access = NSMenuItem(title: S.cloudAccessMenu, action: nil, keyEquivalent: ""); access.image = NSImage(systemSymbolName: "lock.open", accessibilityDescription: nil); access.representedObject = target
            let sub = NSMenu()
            for (title, value) in accessOptions(for: obj.provider, presign: cloud.prefs.s3PresignSeconds) {
                let mi = NSMenuItem(title: title, action: #selector(CloudMenuTarget.setAccess(_:)), keyEquivalent: ""); mi.target = target; mi.representedObject = AccessBox(value); mi.state = sameKind(obj.access, value) ? .on : .off; sub.addItem(mi)
            }
            access.submenu = sub; m.addItem(access)
            let del = NSMenuItem(title: S.cloudDelete, action: #selector(CloudMenuTarget.deleteRemote), keyEquivalent: ""); del.target = target; del.representedObject = target; del.image = NSImage(systemSymbolName: "icloud.slash", accessibilityDescription: nil); m.addItem(del)
            if i < item.cloud.count - 1 { m.addItem(.separator()) }
        }
        return m
    }
    static func accessOptions(for p: CloudProviderID, presign: Int) -> [(String, LinkAccess)] {
        switch p {
        case .googleDrive: return [(S.cloudAccessAnyone, .anyoneWithLink), (S.cloudAccessOwner, .ownerOnly)]
        case .s3: return [(S.cloudAccessPublic, .publicObject), (S.cloudAccessPresigned(durationText(presign)), .presigned(seconds: presign))]
        }
    }
    static func sameKind(_ a: LinkAccess, _ b: LinkAccess) -> Bool {
        switch (a, b) { case (.presigned, .presigned): return true; default: return a == b }
    }
    static func durationText(_ s: Int) -> String {
        let f = DateComponentsFormatter(); f.allowedUnits = s >= 86_400 ? [.day] : (s >= 3600 ? [.hour] : [.minute]); f.unitsStyle = .full
        return readableSpaces(f.string(from: TimeInterval(s)) ?? "\(s) s")
    }
    /// Biçimleyici bazı dillerde (TR "1 gün") sayı ile birim arasına dar bölünmez boşluk (U+202F) koyar; sistem yazısında
    /// bitişik görünür ("1gün"). Tam genişlikte bölünmez boşluk (U+00A0) okunur kalır ve satır yine bölünmez.
    static func readableSpaces(_ t: String) -> String { t.replacingOccurrences(of: "\u{202F}", with: "\u{00A0}") }
    /// Buluttan sil onay metni: yerel kopya yedekten sonra Çöp'e taşındıysa bulut kopyası tek kopya olabilir, açıkça uyarılır.
    static func deleteBody(provider: CloudProviderID, localTrashed: Bool) -> String {
        localTrashed ? S.cloudDeleteBodyLocalTrashed(provider.title) : S.cloudDeleteBody(provider.title)
    }
}
final class AccessBox: NSObject { let value: LinkAccess; init(_ v: LinkAccess) { value = v } }
final class CloudMenuTarget: NSObject {
    let item: ShelfItem; let object: CloudObject; weak var cloud: CloudCenter?
    init(item: ShelfItem, object: CloudObject, cloud: CloudCenter) { self.item = item; self.object = object; self.cloud = cloud }
    @objc func copyLink() { cloud?.copyLink(object, fileName: item.fileName); cloud?.panel?.showToast(S.copiedToast) }
    @objc func openLink() { if let l = object.link { NSWorkspace.shared.open(l) } }
    @objc func setAccess(_ sender: NSMenuItem) { guard let a = (sender.representedObject as? AccessBox)?.value else { return }; cloud?.changeAccess(item: item, object: object, to: a) }
    @objc func deleteRemote() {
        guard let cloud = cloud else { return }
        let localTrashed = cloud.store.allItems.first { $0.id == item.id }?.localTrashed ?? item.localTrashed
        ForegroundHelper.withActivation { done in
            let a = NSAlert(); a.alertStyle = .warning; a.messageText = S.cloudDeleteTitle; a.informativeText = CloudMenuBuilder.deleteBody(provider: self.object.provider, localTrashed: localTrashed)
            ConfirmDialog.configure(a, safe: S.cancel, proceed: S.cloudDeleteButton, destructive: true, symbol: "icloud.slash")
            let r = ConfirmDialog.run(a); done()
            if ConfirmDialog.shouldProceed(r) { cloud.deleteRemote(item: self.item, object: self.object) }
        }
    }
}
#endif
