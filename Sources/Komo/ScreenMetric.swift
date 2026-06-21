import AppKit

/// Converts on-screen travel (in points) into a physical distance, using the
/// main display's reported physical size. Falls back to a ~96 dpi estimate
/// when the size is unavailable.
enum ScreenMetric {
    static var pointsPerMeter: Double {
        guard
            let screen = NSScreen.main,
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return fallback }

        let displayID = CGDirectDisplayID(number.uint32Value)
        let mm = CGDisplayScreenSize(displayID) // physical width in millimetres
        let pointWidth = Double(screen.frame.width)
        guard mm.width > 0, pointWidth > 0 else { return fallback }

        let metersWide = mm.width / 1000.0
        return pointWidth / metersWide
    }

    private static let fallback = 3779.5 // 96 dpi expressed as units per metre

    static func meters(fromPoints points: Double) -> Double {
        points / pointsPerMeter
    }
}
