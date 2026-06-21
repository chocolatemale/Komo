import AppKit
import SwiftUI

/// Renders the popover UI to PNG files offscreen via `ImageRenderer`, used for
/// design review. Triggered with `Komo --snapshot <lightPath> <darkPath>`.
@MainActor
enum SnapshotRenderer {
    static func render(lightPath: String, darkPath: String, permissionGranted: Bool) {
        let store = StatsStore.shared
        store.loadDemoData()
        PermissionHelper.shared.overrideForSnapshot(permissionGranted)

        write(scheme: .light, to: lightPath, store: store)
        write(scheme: .dark, to: darkPath, store: store)
    }

    private static func write(scheme: ColorScheme, to path: String, store: StatsStore) {
        let canvas = scheme == .dark
            ? Color(nsColor: NSColor(calibratedWhite: 0.13, alpha: 1))
            : Color(nsColor: NSColor(calibratedWhite: 0.96, alpha: 1))

        let content = StatsView()
            .environmentObject(store)
            .environmentObject(PermissionHelper.shared)
            .environmentObject(LoginItem.shared)
            .environment(\.colorScheme, scheme)
            .background(canvas)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2

        guard
            let image = renderer.nsImage,
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
        else {
            FileHandle.standardError.write(Data("snapshot: render failed for \(path)\n".utf8))
            return
        }
        try? png.write(to: URL(fileURLWithPath: path))
        FileHandle.standardError.write(Data("snapshot: wrote \(path)\n".utf8))
    }
}
