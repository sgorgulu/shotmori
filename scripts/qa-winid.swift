// QA: verilen pid'e ait, başlığı <istenen> metni içeren (ya da "any") ilk ekrandaki pencerenin kimliğini yazar.
// Kullanım: winid <pid> <başlık-parçası|any>
import AppKit
let a = CommandLine.arguments
guard a.count >= 3, let pid = Int(a[1]) else { exit(2) }
let want = a[2]
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
var fallback: Int?
var fallbackBounds: [String: Any]?
for w in list {
    guard (w["kCGWindowOwnerPID"] as? Int) == pid, let b = w["kCGWindowBounds"] as? [String: Any],
          (b["Width"] as? Double ?? 0) >= 120, (b["Height"] as? Double ?? 0) >= 60, let n = w["kCGWindowNumber"] as? Int else { continue }
    let name = w["kCGWindowName"] as? String ?? ""
    // Üçüncü argüman "bounds": "id x y w h" (saydam pencereler ekran bölgesinden yakalanır)
    func out(_ n: Int, _ b: [String: Any]) { if a.count > 3 && a[3] == "bounds" { print(n, Int(b["X"] as? Double ?? 0), Int(b["Y"] as? Double ?? 0), Int(b["Width"] as? Double ?? 0), Int(b["Height"] as? Double ?? 0)) } else { print(n) } }
    if want == "any" || name.localizedCaseInsensitiveContains(want) { out(n, b); exit(0) }
    if fallback == nil, (w["kCGWindowLayer"] as? Int ?? 0) > 0 { fallback = n; fallbackBounds = b }
}
if let f = fallback, let b = fallbackBounds { if a.count > 3 && a[3] == "bounds" { print(f, Int(b["X"] as? Double ?? 0), Int(b["Y"] as? Double ?? 0), Int(b["Width"] as? Double ?? 0), Int(b["Height"] as? Double ?? 0)) } else { print(f) } }
