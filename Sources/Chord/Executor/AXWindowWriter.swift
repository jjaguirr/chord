import ApplicationServices
import ChordCore
import Foundation

/// The only place Chord writes a window attribute through Accessibility. It lives in the
/// Executor directory because the one-writer rule allows window mutation nowhere else;
/// `AXWindowBackend` calls it on the Executor's behalf.
struct AXWindowWriter {
    /// Sets size, then position, then size again, exactly as given. The first size keeps a
    /// shrinking window from extending past the screen edge on the way; the second lets a
    /// growing window reach its full size once it has moved, since a size that does not fit
    /// at the old origin may have been clamped. Returns the first failure, or `.success`.
    /// Nothing is read back.
    func writeFrame(_ window: AXUIElement, to frame: ScreenRect) -> AXError {
        var size = CGSize(width: frame.width, height: frame.height)
        var origin = CGPoint(x: frame.x, y: frame.y)
        guard let sizeValue = AXValueCreate(.cgSize, &size),
            let originValue = AXValueCreate(.cgPoint, &origin)
        else { return .illegalArgument }
        let sized = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        guard sized == .success else { return sized }
        let moved = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, originValue)
        guard moved == .success else { return moved }
        return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
    }

    /// Raises one window without raising its siblings.
    func bringForward(_ window: AXUIElement) -> AXError {
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    /// Makes the app frontmost and the window its main window, then raises that window.
    func focus(_ window: AXUIElement) -> AXError {
        var pid: pid_t = 0
        if AXUIElementGetPid(window, &pid) == .success {
            _ = AXUIElementSetAttributeValue(
                AXUIElementCreateApplication(pid), kAXFrontmostAttribute as CFString, NSNumber(value: true))
        }
        _ = AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, NSNumber(value: true))
        return bringForward(window)
    }
}
