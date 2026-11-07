// Sentetik "ekran görüntüsü" üretici (QA): mkshot <çıktı.png> <genişlik> <yükseklik> <başlık> <tema:light|dark|code|chart>
// Gerçek içerik yok; kMDItemIsScreenCapture xattr'ı ile Shotmori izleyicisi tarafından tanınır.
import AppKit
let a = CommandLine.arguments
let url = URL(fileURLWithPath: a[1]); let w = Int(a[2]) ?? 1600, h = Int(a[3]) ?? 1000; let title = a.count > 4 ? a[4] : "Örnek"; let theme = a.count > 5 ? a[5] : "light"
let img = NSImage(size: NSSize(width: w, height: h), flipped: true) { r in
    let bg: NSColor, fg: NSColor
    switch theme { case "dark", "code": bg = NSColor(srgbRed: 0.16, green: 0.17, blue: 0.2, alpha: 1); fg = .white
                   case "chart": bg = NSColor(srgbRed: 0.97, green: 0.96, blue: 0.94, alpha: 1); fg = NSColor(srgbRed: 0.16, green: 0.16, blue: 0.18, alpha: 1)
                   default: bg = NSColor(srgbRed: 0.99, green: 0.99, blue: 0.98, alpha: 1); fg = NSColor(srgbRed: 0.16, green: 0.16, blue: 0.18, alpha: 1) }
    bg.setFill(); r.fill()
    // sahte pencere çubuğu
    NSColor(white: theme == "dark" || theme == "code" ? 0.22 : 0.92, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: r.width, height: r.height * 0.06).fill()
    for (i, c) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() { c.setFill(); NSBezierPath(ovalIn: NSRect(x: 18 + CGFloat(i) * 22, y: r.height * 0.03 - 7, width: 14, height: 14)).fill() }
    let font = NSFont.systemFont(ofSize: r.height * 0.06, weight: .semibold)
    (title as NSString).draw(at: NSPoint(x: r.width * 0.08, y: r.height * 0.16), withAttributes: [.font: font, .foregroundColor: fg])
    switch theme {
    case "code":
        let mono = NSFont.monospacedSystemFont(ofSize: r.height * 0.035, weight: .regular)
        for (i, line) in ["struct Demo: View {", "    var body: some View {", "        Text(\"Merhaba\")", "    }", "}"].enumerated() {
            (line as NSString).draw(at: NSPoint(x: r.width * 0.08, y: r.height * (0.3 + CGFloat(i) * 0.07)), withAttributes: [.font: mono, .foregroundColor: fg])
        }
    case "chart":
        let bars: [CGFloat] = [0.35, 0.6, 0.45, 0.8, 0.5, 0.3, 0.65]
        for (i, b) in bars.enumerated() { (i == 3 ? NSColor(srgbRed: 0.42, green: 0.33, blue: 0.68, alpha: 1) : NSColor(srgbRed: 0.75, green: 0.7, blue: 0.9, alpha: 1)).setFill()
            NSRect(x: r.width * (0.1 + CGFloat(i) * 0.12), y: r.height * (0.85 - b * 0.5), width: r.width * 0.07, height: r.height * b * 0.5).fill() }
    default:
        for i in 0..<5 { NSColor(white: theme == "dark" ? 0.3 : 0.88, alpha: 1).setFill(); NSRect(x: r.width * 0.08, y: r.height * (0.32 + CGFloat(i) * 0.1), width: r.width * (0.3 + CGFloat((i * 7) % 5) * 0.1), height: r.height * 0.035).fill() }
        NSColor(srgbRed: 0.6, green: 0.65, blue: 0.5, alpha: 1).setFill(); NSRect(x: r.width * 0.6, y: r.height * 0.3, width: r.width * 0.3, height: r.height * 0.4).fill()
    }
    return true
}
try! NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: url)
let plist = try! PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0)
_ = plist.withUnsafeBytes { setxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", $0.baseAddress, plist.count, 0, 0) }
print("yazıldı: \(url.lastPathComponent) \(w)×\(h)")
