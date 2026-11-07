import AppKit

/// `undo:` / `redo:` yanıt zinciri eylemleri (NSTextView ve editör tuvali uygular); AppKit bunları açık bir türde bildirmez,
/// bu protokol yalnız `#selector` ile derleyici denetimli seçici üretmek içindir.
@objc private protocol UndoRedoActions {
    func undo(_ sender: Any?)
    func redo(_ sender: Any?)
}

/// Ana menü: `.accessory` uygulamada görünmez ama ⌘C/⌘V/⌘A/⌘Z gibi Düzen kısayollarını pencerelerdeki
/// alanlara (NSTextField, editör tuvali) ileten tek yol budur. Hedefler nil: eylem yanıt zincirinden gider.
enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()
        func add(_ menu: NSMenu, _ title: String, _ sel: Selector?, _ key: String, _ mods: NSEvent.ModifierFlags = [.command]) {
            let it = NSMenuItem(title: title, action: sel, keyEquivalent: key); it.keyEquivalentModifierMask = mods; menu.addItem(it)
        }
        func submenu(_ title: String, _ build: (NSMenu) -> Void) {
            let host = NSMenuItem(); let m = NSMenu(title: title); build(m); host.submenu = m; main.addItem(host)
        }
        submenu("Shotmori") { m in
            add(m, S.menuAbout, #selector(AppDelegate.showAbout), "")
            m.addItem(.separator())
            add(m, S.menuSettings, #selector(AppDelegate.openSettings), ",")
            m.addItem(.separator())
            add(m, S.menuHideApp, #selector(NSApplication.hide(_:)), "h")
            m.addItem(.separator())
            add(m, S.menuQuit, #selector(NSApplication.terminate(_:)), "q")
        }
        submenu(S.menuEdit) { m in
            add(m, S.menuUndo, #selector(UndoRedoActions.undo(_:)), "z")
            add(m, S.menuRedo, #selector(UndoRedoActions.redo(_:)), "z", [.command, .shift])
            m.addItem(.separator())
            add(m, S.menuCut, #selector(NSText.cut(_:)), "x")
            add(m, S.menuCopy, #selector(NSText.copy(_:)), "c")
            add(m, S.menuPaste, #selector(NSText.paste(_:)), "v")
            add(m, S.menuSelectAll, #selector(NSText.selectAll(_:)), "a")
        }
        submenu(S.menuWindow) { m in
            add(m, S.menuClose, #selector(NSWindow.performClose(_:)), "w")
            add(m, S.menuMinimize, #selector(NSWindow.performMiniaturize(_:)), "m")
        }
        return main
    }
}
