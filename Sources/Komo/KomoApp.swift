import CoreGraphics
import SwiftUI

@main
struct KomoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var store = StatsStore.shared
    @ObservedObject private var permissions = PermissionHelper.shared
    @ObservedObject private var login = LoginItem.shared

    var body: some Scene {
        MenuBarExtra {
            StatsView()
                .environmentObject(store)
                .environmentObject(permissions)
                .environmentObject(login)
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = InputMonitor(store: .shared)
    private var permissionTimer: Timer?
    private var keyboardActive = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 2 < args.count {
            let granted = !args.contains("--banner")
            SnapshotRenderer.render(lightPath: args[i + 1], darkPath: args[i + 2], permissionGranted: granted)
            exit(0)
        }
        if let i = args.firstIndex(of: "--icon"), i + 1 < args.count {
            let preview = MenuBarIcon.render(points: 256, color: .black, background: .white)
            if let tiff = preview.tiffRepresentation, let bm = NSBitmapImageRep(data: tiff),
               let data = bm.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: args[i + 1]))
            }
            exit(0)
        }
        if let i = args.firstIndex(of: "--appicon"), i + 1 < args.count {
            AppIconRenderer.renderPNG(to: args[i + 1])
            exit(0)
        }

        PermissionHelper.shared.refresh()
        monitor.start()
        keyboardActive = PermissionHelper.shared.hasInputMonitoring

        // Explicitly request Input Monitoring on first launch — this is what
        // registers Komo in the System Settings list and (first time) prompts.
        if !keyboardActive {
            _ = CGRequestListenEventAccess()
        }

        // Re-detect an Input Monitoring grant at runtime so the user doesn't
        // have to relaunch: on a false→true transition, reinstall the monitors
        // and keyDown events start flowing.
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                PermissionHelper.shared.refresh()
                let granted = PermissionHelper.shared.hasInputMonitoring
                if granted && !self.keyboardActive { self.monitor.start() }
                self.keyboardActive = granted
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { StatsStore.shared.flushNow() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        StatsStore.shared.flushNow()
    }
}
