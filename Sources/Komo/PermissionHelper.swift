import AppKit
import CoreGraphics

/// Tracks whether the app holds Input Monitoring permission, which macOS
/// requires before global keyboard events are delivered. Mouse events flow
/// without it.
@MainActor
final class PermissionHelper: ObservableObject {
    static let shared = PermissionHelper()

    @Published private(set) var hasInputMonitoring = false
    private var locked = false

    private init() { refresh() }

    func refresh() {
        guard !locked else { return }
        hasInputMonitoring = CGPreflightListenEventAccess()
    }

    /// Triggers the system prompt the first time; afterwards it is a no-op and
    /// the user must toggle the switch in System Settings.
    func request() {
        _ = CGRequestListenEventAccess()
        refresh()
    }

    func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }

    /// Pins a value for offscreen UI snapshots so `refresh()` can't clobber it.
    func overrideForSnapshot(_ value: Bool) {
        hasInputMonitoring = value
        locked = true
    }
}
