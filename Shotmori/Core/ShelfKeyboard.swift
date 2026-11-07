import AppKit

/// Raf yüzeylerinin (yüzen panel, üst şerit) ortak klavye komutları. Yürütme yüzeye aittir; eşleme burada, görünümden bağımsız.
enum ShelfKeyCommand: Equatable {
    case move(Int, extend: Bool), first, last, selectAll, selectNumber(Int) /* 1…9 */
    case quickLook, actionsMenu, nextShelf, previousShelf, shelfIndex(Int) /* 0…7 */
    case copyAndClose, copy, open, reveal, edit, copyText, remove, close
}

/// Tuş → komut eşlemesi (ANSI tuş kodları; harfler `charactersIgnoringModifiers` ile, klavye düzenine göre).
/// Şerit LTR: en yeni solda; ← soldaki (daha yeni), → sağdaki (daha eski).
enum ShelfKeyboard {
    static let leftArrow: UInt16 = 123, rightArrow: UInt16 = 124
    static let space: UInt16 = 49, tab: UInt16 = 48, returnKey: UInt16 = 36, delete: UInt16 = 51, escape: UInt16 = 53
    /// 1…9 rakam tuşları (ANSI); sıra = rakam - 1.
    static let digitKeyCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
    /// ⌘1…⌘8 raf seçimi; ShelfStore.maxShelves ile aynı sınır.
    static var maxShelfShortcuts: Int { ShelfStore.maxShelves }

    static func command(keyCode: UInt16, characters: String?, flags: NSEvent.ModifierFlags, editingText: Bool) -> ShelfKeyCommand? {
        let mods = flags.intersection([.command, .shift, .option, .control])
        let ch = characters?.lowercased() ?? ""
        // Raf adı düzenlenirken tuşlar metne gider; yalnız kapatma geçer.
        if keyCode == escape { return .close }
        if mods == [.command], ch == "w" { return .close }
        if editingText { return nil }

        switch keyCode {
        case leftArrow, rightArrow:
            let d = keyCode == leftArrow ? -1 : 1
            if mods.isEmpty || mods == [.shift] { return .move(d, extend: mods == [.shift]) }
            if mods == [.command] { return d < 0 ? .first : .last }
            return nil
        case space: return mods.isEmpty ? .quickLook : nil
        case tab:
            if mods.isEmpty { return .nextShelf }
            return mods == [.shift] ? .previousShelf : nil
        case returnKey: return mods.isEmpty ? .copyAndClose : nil
        case delete: return mods.isEmpty ? .remove : nil
        default: break
        }
        if let i = digitKeyCodes.firstIndex(of: keyCode) {
            if mods.isEmpty { return .selectNumber(i + 1) }
            if mods == [.command], i < maxShelfShortcuts { return .shelfIndex(i) }
            return nil
        }
        switch (mods, ch) {
        case ([.command], "a"): return .selectAll
        case ([.command], "k"): return .actionsMenu
        case ([.command], "c"): return .copy
        case ([.command, .shift], "c"): return .copyText
        case ([.command], "o"): return .open
        case ([.command], "r"): return .reveal
        case ([], "e"): return .edit
        default: return nil
        }
    }

    /// Hızlı numaralar: görünen ilk dokuz kare (gösterim sırasıyla) 1…9.
    static func quickNumbers(visible: [UUID]) -> [UUID: Int] {
        var out: [UUID: Int] = [:]
        for id in visible where out[id] == nil {
            guard out.count < digitKeyCodes.count else { break }
            out[id] = out.count + 1
        }
        return out
    }
}
