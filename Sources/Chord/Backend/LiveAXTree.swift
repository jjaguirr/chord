import AppKit
import ApplicationServices

/// The real Accessibility tree behind `AXTree`.
struct LiveAXTree: AXTree {
    func focusedApplication() -> Result<AXUIElement, AXFailure> {
        element(of: AXUIElementCreateSystemWide(), attribute: kAXFocusedApplicationAttribute)
    }

    func element(of parent: AXUIElement, attribute: String) -> Result<AXUIElement, AXFailure> {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(parent, attribute as CFString, &value)
        guard status == .success else { return .failure(AXFailure(code: status)) }
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return .failure(AXFailure(code: .noValue))
        }
        return .success(unsafeDowncast(value, to: AXUIElement.self))
    }

    func isChromiumBased(_ app: AXUIElement) -> Bool {
        var pid: pid_t = 0
        AXUIElementGetPid(app, &pid)
        guard let running = NSRunningApplication(processIdentifier: pid) else { return false }
        return Self.isChromiumBased(bundleID: running.bundleIdentifier, bundleURL: running.bundleURL)
    }

    private static let chromiumBundlePrefixes = [
        "com.google.Chrome",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "company.thebrowser.Browser",
        "org.chromium.Chromium",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
    ]

    private static let chromiumFrameworks = [
        "Electron Framework.framework",
        "Chromium Embedded Framework.framework",
    ]

    static func isChromiumBased(bundleID: String?, bundleURL: URL?) -> Bool {
        if let bundleID, chromiumBundlePrefixes.contains(where: { bundleID.hasPrefix($0) }) { return true }
        guard let bundleURL else { return false }
        let frameworks = bundleURL.appendingPathComponent("Contents/Frameworks", isDirectory: true)
        return chromiumFrameworks.contains {
            FileManager.default.fileExists(atPath: frameworks.appendingPathComponent($0).path)
        }
    }

    func setBool(_ attribute: String, on app: AXUIElement) -> AXError {
        AXAppAccessibility.set(attribute, on: app)
    }
}
