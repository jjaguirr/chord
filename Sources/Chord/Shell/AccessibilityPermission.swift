import AppKit
import ApplicationServices

/// Accessibility (TCC) permission: detection, the request that registers Chord in the
/// Accessibility list, and the System Settings pane. Nothing here touches windows.
enum AccessibilityPermission {
    static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt and adds Chord to the Accessibility list. Returns the current trust.
    @discardableResult
    static func requestWithPrompt() -> Bool {
        // Literal value of kAXTrustedCheckOptionPrompt, avoiding a non-Sendable global in Swift 6 mode.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openSettingsPane() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
