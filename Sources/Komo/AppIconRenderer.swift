import AppKit

/// Renders the 1024×1024 app-icon master: a white floppy-eared bunny on the
/// brand-blue squircle. Reuses `MenuBarIcon` so the Dock icon and the menu-bar
/// mark are the exact same bunny. Invoked with `Komo --appicon <path>`.
enum AppIconRenderer {
    static func renderPNG(to path: String, pixels: Int = 1024) {
        let size = CGFloat(pixels)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let ctx = NSGraphicsContext.current!.cgContext

        // Squircle background with the brand-blue gradient.
        let margin = size * 0.10
        let rect = CGRect(x: margin, y: margin, width: size - 2 * margin, height: size - 2 * margin)
        let corner = rect.width * 0.2237
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil))
        ctx.clip()
        let grad = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                NSColor(srgbRed: 0.27, green: 0.50, blue: 1.00, alpha: 1).cgColor,
                NSColor(srgbRed: 0.11, green: 0.31, blue: 0.92, alpha: 1).cgColor
            ] as CFArray,
            locations: [0, 1]
        )!
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.minY), options: [])
        ctx.restoreGState()

        // White bunny, centered, with a soft drop shadow for depth.
        let bunnySize = size * 0.56
        let origin = (size - bunnySize) / 2
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.012),
                      blur: size * 0.04,
                      color: NSColor.black.withAlphaComponent(0.22).cgColor)
        let bunny = MenuBarIcon.render(points: bunnySize, color: .white, background: nil)
        bunny.draw(in: CGRect(x: origin, y: origin, width: bunnySize, height: bunnySize))
        ctx.restoreGState()

        NSGraphicsContext.restoreGraphicsState()

        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}
