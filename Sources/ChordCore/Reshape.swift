/// A width and height in logical points.
public struct ActionSize: Equatable, Sendable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

/// The frame a reshape step produces. Pure: the caller supplies the window's
/// current frame, the visible frame, and the app's minimum size.
///
/// Deltas are in log space: `aspectDelta` moves ln(width/height), `areaDelta`
/// moves ln(width*height). The window resizes about its center, each side is
/// clamped to the app minimum and the visible frame (the visible frame wins if
/// the minimum does not fit), the result is rounded to whole points, and the
/// frame is slid back inside the visible frame. A reshape already at a clamp
/// returns the same size.
///
/// Size is only ever changed by a user action; this function has no other caller.
public func reshapedFrame(
    _ rect: ActionRect, aspectDelta: Double, areaDelta: Double,
    within visible: ActionRect, minimumSize: ActionSize
) -> ActionRect {
    guard rect.width > 0, rect.height > 0, rect.width.isFinite, rect.height.isFinite else {
        return rect
    }
    let logAspect = naturalLog(rect.width / rect.height) + aspectDelta
    let logArea = naturalLog(rect.width * rect.height) + areaDelta
    let rawWidth = naturalExp((logArea + logAspect) / 2)
    let rawHeight = naturalExp((logArea - logAspect) / 2)

    let width = clamp(rawWidth.rounded(), low: minimumSize.width.rounded(.up), high: visible.width.rounded(.down))
    let height = clamp(rawHeight.rounded(), low: minimumSize.height.rounded(.up), high: visible.height.rounded(.down))

    let centerX = rect.x + rect.width / 2
    let centerY = rect.y + rect.height / 2
    let x = clamp((centerX - width / 2).rounded(), low: visible.x.rounded(.up), high: (visible.x + visible.width).rounded(.down) - width)
    let y = clamp((centerY - height / 2).rounded(), low: visible.y.rounded(.up), high: (visible.y + visible.height).rounded(.down) - height)
    return ActionRect(x: x, y: y, width: width, height: height)
}
/// Converts a reshape intent into the reversible typed action the Executor applies.
/// Returns `nil` for intents that do not request a reshape or cannot change the frame.
public func reshapeAction(
    for intent: KeyIntent, windowID: Int, from rect: ActionRect,
    within visible: ActionRect, minimumSize: ActionSize
) -> Action? {
    guard case .reshape(let aspectDelta, let areaDelta) = intent else { return nil }
    let to = reshapedFrame(
        rect, aspectDelta: aspectDelta, areaDelta: areaDelta,
        within: visible, minimumSize: minimumSize)
    guard to != rect else { return nil }
    return .reshape(
        windowID: windowID, aspectDelta: aspectDelta, areaDelta: areaDelta,
        from: rect, to: to)
}

/// `value` limited to `low...high`; `high` wins when the range is empty.
private func clamp(_ value: Double, low: Double, high: Double) -> Double {
    min(max(value, low), high)
}
