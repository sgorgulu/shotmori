#if SHOTMORI_CLOUD // Bulut kodu SHOTMORI_CLOUD bayrağıyla derlenir (Debug ve Release 1.0'da açık, bkz. Features.swift); bayrak kaldırılırsa derlenmez.
import AppKit

/// Menü çubuğu › Son yüklemeler: her kayıt için Linki kopyala · Tarayıcıda aç · Buluttan sil… · Listeden kaldır.
enum RecentUploadsMenu {
    static func build(cloud: CloudCenter, limit: Int = 12) -> NSMenu {
        let m = NSMenu()
        let recs = Array(cloud.history.records.prefix(limit))
        if recs.isEmpty { let e = NSMenuItem(title: S.cloudRecentEmpty, action: nil, keyEquivalent: ""); e.isEnabled = false; m.addItem(e); return m }
        for r in recs {
            let mi = NSMenuItem(title: r.fileName, action: nil, keyEquivalent: ""); mi.image = NSImage(systemSymbolName: r.object.provider == .googleDrive ? "externaldrive" : "shippingbox", accessibilityDescription: r.object.provider.title)
            mi.toolTip = "\(r.object.provider.title) · \(r.object.remotePath)"
            mi.submenu = submenu(for: r, cloud: cloud); m.addItem(mi)
        }
        return m
    }
    static func submenu(for r: UploadRecord, cloud: CloudCenter) -> NSMenu {
        // Hedef öğelerin `representedObject`'inde taşınır: alt menü yaşadıkça hedef de yaşar (küresel havuz yok).
        let sub = NSMenu(); let t = RecentUploadTarget(record: r, cloud: cloud)
        let copy = NSMenuItem(title: S.cloudCopyLink, action: #selector(RecentUploadTarget.copyLink), keyEquivalent: ""); copy.target = t; copy.representedObject = t; copy.isEnabled = r.object.link != nil; sub.addItem(copy)
        let open = NSMenuItem(title: S.cloudOpenLink, action: #selector(RecentUploadTarget.openLink), keyEquivalent: ""); open.target = t; open.representedObject = t; open.isEnabled = r.object.link != nil; sub.addItem(open)
        sub.addItem(.separator())
        let del = NSMenuItem(title: S.cloudDelete, action: #selector(RecentUploadTarget.deleteRemote), keyEquivalent: ""); del.target = t; del.representedObject = t; sub.addItem(del)
        let rm = NSMenuItem(title: S.cloudRemoveFromList, action: #selector(RecentUploadTarget.removeFromList), keyEquivalent: ""); rm.target = t; rm.representedObject = t; sub.addItem(rm)
        return sub
    }
    /// Test için: başlık listesi.
    static func titles(cloud: CloudCenter, limit: Int = 12) -> [String] { build(cloud: cloud, limit: limit).items.map(\.title) }
}
final class RecentUploadTarget: NSObject {
    let record: UploadRecord; weak var cloud: CloudCenter?
    init(record: UploadRecord, cloud: CloudCenter) { self.record = record; self.cloud = cloud }
    @objc func copyLink() { cloud?.copyLink(record.object, fileName: record.fileName) }
    @objc func openLink() { if let l = record.object.link { NSWorkspace.shared.open(l) } }
    @objc func removeFromList() { cloud?.history.remove(id: record.id) }
    @objc func deleteRemote() {
        guard let cloud = cloud else { return }
        let item = cloud.store.allItems.first { $0.id == record.itemID }
        ForegroundHelper.withActivation { done in
            let a = NSAlert(); a.alertStyle = .warning; a.messageText = S.cloudDeleteTitle; a.informativeText = CloudMenuBuilder.deleteBody(provider: self.record.object.provider, localTrashed: item?.localTrashed == true)
            ConfirmDialog.configure(a, safe: S.cancel, proceed: S.cloudDeleteButton, destructive: true, symbol: "icloud.slash")
            let r = ConfirmDialog.run(a); done()
            if ConfirmDialog.shouldProceed(r) { cloud.deleteRemote(item: item, object: self.record.object) }
        }
    }
}
#endif
