import ApplicationServices
import Foundation

/// Monotonic seconds. Tests drive a fake; the app reads the system uptime clock.
protocol InputClock {
    func now() -> Double
}

struct SystemInputClock: InputClock {
    func now() -> Double { ProcessInfo.processInfo.systemUptime }
}

/// Read-only permission state. Implementations must never show a system prompt.
protocol InputPermissions {
    var accessibilityGranted: Bool { get }
    var inputMonitoringGranted: Bool { get }
}

struct SystemInputPermissions: InputPermissions {
    var accessibilityGranted: Bool { AXIsProcessTrusted() }
    /// Preflight only: `CGRequestListenEventAccess` is the call that prompts, and is never used.
    var inputMonitoringGranted: Bool { CGPreflightListenEventAccess() }
}

/// Receives what a source captured. All calls arrive on the main thread.
protocol HotkeySourceDelegate: AnyObject {
    func hotkeySource(_ path: CapturePath, didReceive event: RawKeyEvent) -> EventDecision
    /// The system turned the source off (event taps are disabled after a timeout or by user input).
    func hotkeySource(_ path: CapturePath, wasDisabledBy cause: String)
}

/// One way of seeing global keys. The app has two (Carbon, event tap); tests drive a fake.
/// Main thread only.
protocol HotkeySource: AnyObject {
    var path: CapturePath { get }
    /// Whether the source is currently delivering. Queried live, never cached.
    var isEnabled: Bool { get }
    func start(bindings: [HotkeyBinding], delegate: HotkeySourceDelegate) -> SourceStartReport
    func stop()
}
