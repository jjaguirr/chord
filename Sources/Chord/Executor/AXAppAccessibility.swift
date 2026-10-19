import ApplicationServices

/// Tells an application it has an assistive client, so Chromium and Electron build their
/// accessibility tree. Changes no window.
enum AXAppAccessibility {
    static func set(_ attribute: String, on app: AXUIElement) -> AXError {
        AXUIElementSetAttributeValue(app, attribute as CFString, kCFBooleanTrue)
    }
}
