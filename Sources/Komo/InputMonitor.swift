import AppKit
import CoreGraphics

/// Captures global input and funnels counts into the store.
///
/// - **Keyboard** uses a listen-only `CGEventTap`. Creating the tap is what makes
///   macOS register Komo in the *Input Monitoring* list and show the permission
///   prompt; once granted, keyDown events flow reliably. (Plain `NSEvent` global
///   monitors neither register the app nor prompt, which is why they silently
///   counted nothing.)
/// - **Mouse** uses `NSEvent` global monitors — clicks and movement need no
///   permission, and global-only means Komo's own popover never inflates stats.
@MainActor
final class InputMonitor {
    let store: StatsStore

    private var mouseMonitors: [Any] = []
    private(set) var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(store: StatsStore) { self.store = store }

    func start() {
        stop()
        startMouse()
        startKeyboardTap()
    }

    func stop() {
        for m in mouseMonitors { NSEvent.removeMonitor(m) }
        mouseMonitors.removeAll()

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
    }

    /// True once the keyboard tap is live (i.e. Input Monitoring is granted).
    var keyboardTapActive: Bool { eventTap != nil }

    // MARK: Keyboard (CGEventTap)

    private func startKeyboardTap() {
        let mask = CGEventMask(1) << CGEventMask(CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: komoKeyTapCallback,
            userInfo: refcon
        ) else {
            // Not authorized yet. AppDelegate's explicit CGRequestListenEventAccess
            // registers Komo in the Input Monitoring list; the permission re-check
            // timer recreates this tap the moment access is granted.
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
    }

    fileprivate func handleTapKey(keyCode: UInt16) {
        store.recordKey(label: KeyCodeMap.labels[keyCode])
    }

    fileprivate func reenableTap() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    // MARK: Mouse (NSEvent)

    private func startMouse() {
        addGlobal([.leftMouseDown, .rightMouseDown]) { [weak self] e in self?.handleClick(e) }
        addGlobal([.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] e in self?.handleMove(e) }
    }

    private func addGlobal(_ mask: NSEvent.EventTypeMask, _ handler: @escaping (NSEvent) -> Void) {
        if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) {
            mouseMonitors.append(m)
        }
    }

    private func handleClick(_ e: NSEvent) {
        switch e.type {
        case .leftMouseDown: store.recordLeftClick()
        case .rightMouseDown: store.recordRightClick()
        default: break
        }
    }

    private func handleMove(_ e: NSEvent) {
        let dist = (e.deltaX * e.deltaX + e.deltaY * e.deltaY).squareRoot()
        store.recordMouseMove(points: dist)
    }
}

/// C callback for the keyboard tap. Must not capture context — state is reached
/// through `refcon`. Runs on the main run loop, so hopping to the main actor is
/// sound.
private func komoKeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<InputMonitor>.fromOpaque(refcon).takeUnretainedValue()

    switch type {
    case .keyDown:
        let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if !isRepeat {
            MainActor.assumeIsolated { monitor.handleTapKey(keyCode: keyCode) }
        }
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        MainActor.assumeIsolated { monitor.reenableTap() }
    default:
        break
    }
    return Unmanaged.passUnretained(event)
}
