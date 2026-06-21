import AppKit

/// The menu-bar mark: a floppy-eared bunny head, drawn as a monochrome template
/// image so macOS tints it for light/dark menu bars automatically.
enum MenuBarIcon {
    static let image: NSImage = {
        let img = render(points: 18, color: .black, background: nil)
        img.isTemplate = true
        return img
    }()

    /// Brand-blue bunny for in-app placement (the popover header).
    static let brandImage: NSImage = render(
        points: 20,
        color: NSColor(srgbRed: 0.18, green: 0.42, blue: 1.0, alpha: 1),
        background: nil
    )

    /// Drawing is authored in a 48×48 space (matching the design mockup) and
    /// scaled to the requested point size.
    static func render(points: CGFloat, color: NSColor, background: NSColor?) -> NSImage {
        NSImage(size: NSSize(width: points, height: points), flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            if let background {
                ctx.setFillColor(background.cgColor)
                ctx.fill(rect)
            }
            ctx.scaleBy(x: points / 48, y: points / 48)
            ctx.setFillColor(color.cgColor)
            ellipse(ctx, cx: 23, cy: 32, rx: 12, ry: 10.5, deg: 0)    // head
            ellipse(ctx, cx: 18.5, cy: 14, rx: 3.8, ry: 11.5, deg: -11) // upright ear
            ellipse(ctx, cx: 32, cy: 17, rx: 3.5, ry: 11, deg: 64)    // floppy ear
            return true
        }
    }

    private static func ellipse(_ ctx: CGContext, cx: CGFloat, cy: CGFloat,
                                rx: CGFloat, ry: CGFloat, deg: CGFloat) {
        ctx.saveGState()
        ctx.translateBy(x: cx, y: cy)
        ctx.rotate(by: deg * .pi / 180)
        ctx.translateBy(x: -cx, y: -cy)
        ctx.fillEllipse(in: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
        ctx.restoreGState()
    }
}
