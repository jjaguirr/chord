import ChordCore

/// The focused window's frame and its monitor's visible frame, in top-left screen points,
/// for the `KeyStateMachine`'s carry edge-magnets. Read-only.
///
/// A held carry asks every timer tick; a short cache keeps that to a few AX reads per
/// carry step instead of per tick. When nothing is focused or readable it answers the
/// stand-in, and the Executor then finds no focused window and moves nothing.
@MainActor
final class FocusedGeometry {
    /// Longer than a timer tick, much shorter than the 100 ms between carry steps.
    static let cacheSeconds = 0.05

    private let clock: InputClock
    private let readFrame: () -> ScreenRect?
    private let readMonitors: () -> [MonitorSnapshot]
    private var cached: (at: Double, value: InputGeometry)?

    init(
        clock: InputClock,
        readFrame: @escaping () -> ScreenRect? = { AXReading.focusedWindow().flatMap { AXReading.frame(of: $0) } },
        readMonitors: @escaping () -> [MonitorSnapshot] = { ScreenGeometry.monitors() }
    ) {
        self.clock = clock
        self.readFrame = readFrame
        self.readMonitors = readMonitors
    }

    func current() -> InputGeometry {
        let now = clock.now()
        if let cached, now - cached.at < Self.cacheSeconds { return cached.value }
        guard let window = readFrame(),
            let visible = ScreenGeometry.visibleFrame(holding: window, monitors: readMonitors())
        else { return .standIn }
        let value = InputGeometry(
            rect: PickerRect(x: window.x, y: window.y, width: window.width, height: window.height),
            edges: KeyStateMachine.Edges(
                left: visible.x, right: visible.x + visible.width,
                top: visible.y, bottom: visible.y + visible.height))
        cached = (now, value)
        return value
    }
}
