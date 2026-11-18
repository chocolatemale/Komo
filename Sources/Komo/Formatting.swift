import Foundation

/// Number formatting shared by every stats surface, so the popover, the
/// heat-map legend and the trend chart all render counts identically.

func grouped(_ n: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    return f.string(from: NSNumber(value: n)) ?? "\(n)"
}

func abbreviated(_ n: Int) -> String {
    switch n {
    case 1_000_000...: return String(format: "%.2fM", Double(n) / 1_000_000)
    case 100_000...:   return String(format: "%.0fk", Double(n) / 1_000)
    case 10_000...:    return String(format: "%.1fk", Double(n) / 1_000)
    default:           return grouped(n)
    }
}

/// On-screen travel rendered at a sensible unit for its magnitude.
func distanceText(points: Double) -> String {
    let meters = ScreenMetric.meters(fromPoints: points)
    if meters < 1 { return String(format: "%.0f cm", meters * 100) }
    if meters < 1000 { return String(format: "%.1f m", meters) }
    return String(format: "%.2f km", meters / 1000)
}
