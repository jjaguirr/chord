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

    /// The focused window of the focused application, if any.
    static func focusedWindow() -> AXUIElement? {
        guard let app = element(AXUIElementCreateSystemWide(), kAXFocusedApplicationAttribute) else { return nil }
        return element(app, kAXFocusedWindowAttribute)
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
