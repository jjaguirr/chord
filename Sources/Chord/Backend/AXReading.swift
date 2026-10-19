import AppKit
import ApplicationServices
import ChordCore

/// Read-only Accessibility access. Nothing here changes a window or shows a prompt;
/// window changes are `AXWindowWriter`, inside the Executor directory.
enum AXReading {
    /// Messaging timeout for every AX call this process makes. The system default is
    /// seconds, which would freeze the main thread on one unresponsive app.
    static let messagingTimeout: Float = 0.25

    static func configureTimeouts() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), messagingTimeout)
    }

    private static let lookupState = LookupState()

    /// The focused window of the focused application, if any. Logs the path that found it
    /// (or why none was found) whenever that differs from the previous lookup's.
    static func focusedWindow() -> AXUIElement? {
        lookupState.find()
    }

    private final class LookupState: @unchecked Sendable {
        private let lock = NSLock()
        private var lastMessage = ""
        private let lookup = FocusedWindowLookup(tree: LiveAXTree()) { app in
            var pid: pid_t = 0
            AXUIElementGetPid(app, &pid)
            return Int(pid)
        }

        func find() -> AXUIElement? {
            lock.lock()
            defer { lock.unlock() }
            let message: String
            let window: AXUIElement?
            switch lookup.find() {
            case .found(let element, let via):
                var pid: pid_t = 0
                AXUIElementGetPid(element, &pid)
                let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid \(pid)"
                message = "focus lookup: \(name): \(via)"
                window = element
            case .notFound(let reason):
                message = "focus lookup: no window: \(reason)"
                window = nil
            }
            if message != lastMessage {
                lastMessage = message
                ActionLog.live.write(message)
            }
            return window
        }
    }

    /// The window's frame in top-left screen points, or nil when it is gone or unreadable.
    static func frame(of window: AXUIElement) -> ScreenRect? {
        guard let origin = point(window, kAXPositionAttribute), let size = size(window, kAXSizeAttribute) else {
            return nil
        }
        return ScreenRect(x: origin.x, y: origin.y, width: size.width, height: size.height)
    }

    static func appName(of window: AXUIElement) -> String {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success else { return "" }
        return NSRunningApplication(processIdentifier: pid)?.localizedName ?? ""
    }

    private static func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, attribute as CFString, &value) == .success,
            let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func axValue(_ element: AXUIElement, _ attribute: String, _ type: AXValueType) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
            let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        return AXValueGetType(axValue) == type ? axValue : nil
    }

    private static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let value = axValue(element, attribute, .cgPoint) else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value, .cgPoint, &point) ? point : nil
    }

    private static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let value = axValue(element, attribute, .cgSize) else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value, .cgSize, &size) ? size : nil
    }
}
