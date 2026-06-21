import SwiftUI

/// Sequential cool→warm color ramp for the keyboard heat-map. Encoding heat as
/// hue (not just opacity) keeps low-count keys legible and reads instantly as
/// "hot vs cold". A gamma boost gives low counts a perceptual lift. The ramp
/// runs blue → violet → orange (plasma-like) so mid-range keys separate cleanly
/// instead of collapsing into a muddy lavender band.
enum HeatColor {
    // Ramp stops (low → high), mode-agnostic so they read on light and dark.
    private static let stops: [(t: Double, rgb: SIMD3<Double>)] = [
        (0.00, SIMD3(0.40, 0.70, 1.00)),  // #66B3FF  sky blue
        (0.35, SIMD3(0.20, 0.45, 1.00)),  // #3373FF  brand blue
        (0.65, SIMD3(0.66, 0.32, 0.90)),  // #A852E6  violet
        (1.00, SIMD3(1.00, 0.45, 0.22))   // #FF7338  warm orange
    ]

    /// Lightest pressed key still gets a clearly tinted floor.
    static let floor = 0.14

    static func fill(intensity: Double) -> Color {
        let c = sample(curve(intensity))
        return Color(.sRGB, red: c.x, green: c.y, blue: c.z, opacity: 1)
    }

    /// Label color chosen from the actual fill luminance, not a magic threshold.
    static func label(intensity: Double) -> Color {
        let c = sample(curve(intensity))
        let lum = 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z
        return lum > 0.6 ? Color.black.opacity(0.82) : Color.white
    }

    /// Legend gradient — sampled through the SAME curve+ramp the keys use, so
    /// the bar's colors line up exactly with the keycaps it labels.
    static var gradient: Gradient {
        let steps = 10
        let colors = (0...steps).map { fill(intensity: Double($0) / Double(steps)) }
        return Gradient(colors: colors)
    }

    private static func curve(_ intensity: Double) -> Double {
        let clamped = max(0, min(1, intensity))
        return pow(clamped, 0.7)
    }

    private static func sample(_ t: Double) -> SIMD3<Double> {
        for i in 1..<stops.count where t <= stops[i].t {
            let lo = stops[i - 1], hi = stops[i]
            let f = (t - lo.t) / (hi.t - lo.t)
            return lo.rgb + (hi.rgb - lo.rgb) * f
        }
        return stops.last!.rgb
    }
}

extension Color {
    /// Fixed brand color so the app's identity doesn't shift with the user's
    /// system accent. Standard interactive controls still use `.tint`.
    static let komoBrand = Color(.sRGB, red: 0.18, green: 0.42, blue: 1.0, opacity: 1)
}
