import AppKit
import ChordCore

/// Screen facts in the one coordinate space the Accessibility backend uses: points,
/// origin at the top-left of the primary display, y growing downward. Cocoa's own
/// space has its origin at the bottom-left, so every NSScreen rect is converted here
/// and nowhere else.
enum ScreenGeometry {
    /// A Cocoa rect (origin bottom-left of the primary display) in top-left space.
    static func topLeftRect(fromCocoa rect: CGRect, primaryHeight: Double) -> ScreenRect {
        ScreenRect(
            x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The visible frame of the monitor holding the center of `rect`; the primary
    /// monitor (else the first) when none holds it.
    static func visibleFrame(holding rect: ScreenRect, monitors: [MonitorSnapshot]) -> ScreenRect? {
        let cx = rect.x + rect.width / 2
        let cy = rect.y + rect.height / 2
        let holding = monitors.first {
            $0.bounds.x <= cx && cx < $0.bounds.x + $0.bounds.width
                && $0.bounds.y <= cy && cy < $0.bounds.y + $0.bounds.height
        }
        return (holding ?? monitors.first(where: \.isPrimary) ?? monitors.first)?.bounds
    }

    /// Every connected screen as a monitor whose `bounds` is its visible frame (the menu
    /// bar and Dock excluded). Safe from any thread: AppKit is read on the main thread.
    static func monitors() -> [MonitorSnapshot] {
        if Thread.isMainThread { return MainActor.assumeIsolated { readMonitors() } }
        return DispatchQueue.main.sync { MainActor.assumeIsolated { readMonitors() } }
    }

    @MainActor
    private static func readMonitors() -> [MonitorSnapshot] {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return [] }
        let primaryHeight = primary.frame.height
        return screens.enumerated().map { index, screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            return MonitorSnapshot(
                id: MonitorID(number?.intValue ?? index),
                bounds: topLeftRect(fromCocoa: screen.visibleFrame, primaryHeight: primaryHeight),
                isPrimary: index == 0)
        }
    }
}
