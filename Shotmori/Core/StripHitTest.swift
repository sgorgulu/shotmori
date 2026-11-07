import CoreGraphics

/// Şeridin tıklama geçirgenliği: nokta yalnız bir isabet dikdörtgenine (4 pt pay ile) düşerse pencere olayı alır.
enum StripHitTest {
    static func accepts(_ p: CGPoint, rects: [CGRect]) -> Bool {
        rects.contains { $0.insetBy(dx: -4, dy: -4).contains(p) }
    }
}
