import AppKit

extension NSToolbarItem.Identifier {
    static let editorTools = Self("editor.tools"), editorAspect = Self("editor.aspect"), editorUndo = Self("editor.undo"), editorRedo = Self("editor.redo")
    static let editorZoomOut = Self("editor.zoomOut"), editorZoomLabel = Self("editor.zoomLabel"), editorZoomIn = Self("editor.zoomIn"), editorZoomFit = Self("editor.zoomFit")
}

/// Editör araç çubuğu (gerçek `NSToolbar` → macOS 26+'da cam başlık çubuğu): Kırp/Gizle · Oran · Geri/Yinele · … · −/%/+ · Sığdır.
/// Görünümler denetleyicide yaşar; burada yalnız öğe sırası ve öğe üretimi.
final class EditorToolbar: NSObject, NSToolbarDelegate {
    static let itemOrder: [NSToolbarItem.Identifier] = [.editorTools, .editorAspect, .editorUndo, .editorRedo, .flexibleSpace, .editorZoomOut, .editorZoomLabel, .editorZoomIn, .editorZoomFit]
    struct Views {
        let tools: NSSegmentedControl, aspect: NSPopUpButton, undo: NSButton, redo: NSButton, zoomOut: NSButton, zoomLabel: NSTextField, zoomIn: NSButton, zoomFit: NSButton
    }
    private let views: Views
    init(views: Views) { self.views = views }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { Self.itemOrder }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { Self.itemOrder }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let view: NSView, label: String
        switch id {
        case .editorTools: view = views.tools; label = S.editToolAX
        case .editorAspect: view = views.aspect; label = S.editAspect
        case .editorUndo: view = views.undo; label = S.editUndo
        case .editorRedo: view = views.redo; label = S.editRedo
        case .editorZoomOut: view = views.zoomOut; label = S.editZoomOut
        case .editorZoomLabel: view = views.zoomLabel; label = S.editZoomAX
        case .editorZoomIn: view = views.zoomIn; label = S.editZoomIn
        case .editorZoomFit: view = views.zoomFit; label = S.editZoomFit
        default: return nil
        }
        let item = NSToolbarItem(itemIdentifier: id); item.view = view; item.label = label; item.paletteLabel = label; item.toolTip = view.toolTip ?? label
        // Dar pencerede » menüsüne düşen öğeler çalışmalı: her öğenin menü biçimi var. Araçlar en son taşar, yüzde etiketi ilk.
        item.menuFormRepresentation = menuForm(for: id, label: label)
        item.visibilityPriority = id == .editorTools ? .high : (id == .editorZoomLabel ? .low : .standard)
        return item
    }
    private func menuForm(for id: NSToolbarItem.Identifier, label: String) -> NSMenuItem {
        let mi = NSMenuItem(title: label, action: nil, keyEquivalent: "")
        switch id {
        case .editorTools:
            let sub = NSMenu()
            for (i, t) in [S.editToolCrop, S.editToolRedact].enumerated() {
                let si = NSMenuItem(title: t, action: #selector(selectTool(_:)), keyEquivalent: ""); si.target = self; si.tag = i; si.state = views.tools.selectedSegment == i ? .on : .off; sub.addItem(si)
            }
            mi.submenu = sub
        case .editorAspect:
            let sub = NSMenu()
            for i in 0..<views.aspect.numberOfItems {
                let si = NSMenuItem(title: views.aspect.itemTitle(at: i), action: #selector(selectAspect(_:)), keyEquivalent: ""); si.target = self; si.tag = i; si.state = views.aspect.indexOfSelectedItem == i ? .on : .off; sub.addItem(si)
            }
            mi.submenu = sub
        case .editorZoomLabel:
            mi.title = "\(label): \(views.zoomLabel.stringValue)"; mi.isEnabled = false
        default:
            let b: NSButton? = [NSToolbarItem.Identifier.editorUndo: views.undo, .editorRedo: views.redo, .editorZoomOut: views.zoomOut, .editorZoomIn: views.zoomIn, .editorZoomFit: views.zoomFit][id]
            mi.target = b?.target; mi.action = b?.action; mi.isEnabled = b?.isEnabled ?? true
        }
        return mi
    }
    @objc private func selectTool(_ sender: NSMenuItem) { views.tools.selectedSegment = sender.tag; views.tools.sendAction(views.tools.action, to: views.tools.target) }
    @objc private func selectAspect(_ sender: NSMenuItem) { views.aspect.selectItem(at: sender.tag); views.aspect.sendAction(views.aspect.action, to: views.aspect.target) }
}
