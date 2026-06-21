import Foundation
import ServiceManagement

/// Wraps `SMAppService` so the app can register itself as a login item — a
/// stats tracker is only useful if it starts with the session.
@MainActor
final class LoginItem: ObservableObject {
    static let shared = LoginItem()

    @Published private(set) var enabled = false

    private init() { refresh() }

    func refresh() {
        enabled = SMAppService.mainApp.status == .enabled
    }

    func toggle() {
        do {
            if enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Komo: login item toggle failed: \(error)")
        }
        refresh()
    }
}
