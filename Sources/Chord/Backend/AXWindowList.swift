import AppKit
import ApplicationServices
import ChordCore

/// Read-only enumeration of the windows Look may target: the standard, non-minimized
/// windows of every visible regular app that overlap a monitor. Nothing here changes a
/// window or shows a prompt.
///
/// AX answers for the current Space only, so windows on other Spaces are not listed.
/// Accessibility trust must already be granted; without it every read fails and the list
/// is empty.
enum AXWindowList {
    static func visibleWindows(monitors: [MonitorSnapshot]) -> [AXUIElement] {
        let me = ProcessInfo.processInfo.processIdentifier
        var found: [AXUIElement] = []
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && !app.isHidden && !app.isTerminated
            && app.processIdentifier != me
        {
            var value: CFTypeRef?
            let element = AXUIElementCreateApplication(app.processIdentifier)
            guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
                let windows = value as? [AXUIElement]
            else { continue }
            found.append(contentsOf: windows.filter { isCandidate($0, monitors: monitors) })
        }
        return found
    }

    private static func isCandidate(_ window: AXUIElement, monitors: [MonitorSnapshot]) -> Bool {
        guard string(window, kAXSubroleAttribute) == kAXStandardWindowSubrole as String,
            !bool(window, kAXMinimizedAttribute),
            let frame = AXReading.frame(of: window), frame.width > 0, frame.height > 0
        else { return false }
        return monitors.contains { monitor in
            let bounds = monitor.bounds
            return min(frame.x + frame.width, bounds.x + bounds.width) - max(frame.x, bounds.x) > 0
                && min(frame.y + frame.height, bounds.y + bounds.height) - max(frame.y, bounds.y) > 0
        }
    }

    private static func string(_ window: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func bool(_ window: AXUIElement, _ attribute: String) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, attribute as CFString, &value) == .success else { return false }
        return (value as? Bool) ?? false
    }
}
