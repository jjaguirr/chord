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

    func windows(of app: AXUIElement) -> Result<[AXUIElement], AXFailure> {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
        guard status == .success else { return .failure(AXFailure(code: status)) }
        return .success((value as? [AXUIElement]) ?? [])
    }

    func subrole(of window: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    func setBool(_ attribute: String, on app: AXUIElement) -> AXError {
        AXAppAccessibility.set(attribute, on: app)
    }
}
