/// A rectangle in screen points, before rounding. Origin is top-left of the
/// rect in the same coordinate space as the screen's visible frame.
public struct UnfoldRect: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// Injected monotonic time source, in seconds. Must never go backward.
public protocol UnfoldClock {
    func now() -> Double
}

/// Timing for the Unfold move (issue #11).
public struct UnfoldConfig: Equatable, Sendable {
    /// Current rect -> `frame(0)`, seconds.
    public var shrinkDuration: Double
    /// A5 pause at S1, seconds. Skipped when S1 does not fit inside S2.
    public var holdDuration: Double
    /// `t` from 0 to 1, seconds, not counting the hold.
    public var growDuration: Double
    /// Passed to `frame()`.
    public var margin: Double

    public init(
        shrinkDuration: Double = 0.3,
        holdDuration: Double = 0.2,
        growDuration: Double = 2.4,
        margin: Double = 0
    ) {
        precondition(shrinkDuration > 0 && growDuration > 0, "durations must be positive")
        precondition(holdDuration >= 0, "hold must not be negative")
        self.shrinkDuration = shrinkDuration
        self.holdDuration = holdDuration
        self.growDuration = growDuration
        self.margin = margin
    }
}

public enum UnfoldPhase: Equatable, Sendable {
    case idle
    case shrink
    case grow
}

/// Pure Unfold state machine: `idle -> shrink -> grow -> idle`.
///
/// It never touches a window. The caller feeds it presses and ticks and applies
/// the rects it returns through the Executor. The current rect lives in this
/// state and is never read back from a window while an animation runs; only a
/// press from `idle` takes the window's real rect.
///
/// There is exactly one timeline, so animations can never stack. A press while
/// running restarts `shrink` from the rect the animation is at right now. A
/// press from `idle` (never started, or finished) starts fresh from the rect
/// the caller reports.
///
/// Elapsed time, not tick count, decides the rect: a late tick skips frames
/// and lands where the timeline says.
public struct UnfoldAnimator {
    public let config: UnfoldConfig
    private let clock: any UnfoldClock

    public private(set) var phase: UnfoldPhase = .idle
    /// Last rect this animator produced, or nil before the first run.
    public private(set) var currentRect: UnfoldRect?

    private var startTime = 0.0
    private var from = UnfoldRect(x: 0, y: 0, width: 0, height: 0)
    private var screen = UnfoldRect(x: 0, y: 0, width: 0, height: 0)
    private var holdSeconds = 0.0

    public init(config: UnfoldConfig = UnfoldConfig(), clock: any UnfoldClock) {
        self.config = config
        self.clock = clock
    }

    /// Handles an Unfold press and returns the first rect to apply (the start of
    /// `shrink`, i.e. the current rect).
    ///
    /// - Parameters:
    ///   - window: the focused window's real rect. Used only when idle.
    ///   - visibleFrame: visible frame of the window's own screen. Re-read on
    ///     every press, so a window on another screen unfolds there.
    @discardableResult
    public mutating func press(window: UnfoldRect, visibleFrame: UnfoldRect) -> UnfoldRect {
        let now = clock.now()
        let start: UnfoldRect
        if phase == .idle {
            start = window
        } else {
            start = rect(at: max(0, now - startTime)).rect
        }
        from = start
        screen = visibleFrame
        startTime = now
        holdSeconds = holdApplies(on: visibleFrame) ? config.holdDuration : 0
        phase = .shrink
        currentRect = start
        return start
    }

    /// Advances to the clock's now. Returns the rect to apply, or nil when idle.
    /// The final call of a run returns the exact `frame(1)` box and goes idle.
    public mutating func tick() -> UnfoldRect? {
        guard phase != .idle else { return nil }
        let sample = rect(at: max(0, clock.now() - startTime))
        phase = sample.phase
        currentRect = sample.rect
        return sample.rect
    }

    // MARK: Timeline

    private func holdApplies(on visible: UnfoldRect) -> Bool {
        let s1 = Unfold.largeStop
        let s2 = frame(1, screenW: visible.width, screenH: visible.height, margin: config.margin)
        return !(s1.w > s2.w || s1.h > s2.h)
    }

    private func place(t: Double) -> UnfoldRect {
        let f = frame(t, screenW: screen.width, screenH: screen.height, margin: config.margin)
        return UnfoldRect(x: screen.x + f.x, y: screen.y + f.y, width: f.w, height: f.h)
    }

    private func rect(at elapsed: Double) -> (rect: UnfoldRect, phase: UnfoldPhase) {
        let shrink = config.shrinkDuration
        if elapsed < shrink {
            let u = smootherstep(elapsed / shrink)
            let to = place(t: 0)
            return (
                UnfoldRect(
                    x: from.x + (to.x - from.x) * u,
                    y: from.y + (to.y - from.y) * u,
                    width: from.width + (to.width - from.width) * u,
                    height: from.height + (to.height - from.height) * u
                ),
                .shrink
            )
        }
        let g = elapsed - shrink
        let grow = config.growDuration
        let kneeEnd = grow * Unfold.knot
        let t: Double
        if g < kneeEnd {
            t = g / grow
        } else if g < kneeEnd + holdSeconds {
            t = Unfold.knot
        } else {
            t = (g - holdSeconds) / grow
        }
        if t >= 1 { return (place(t: 1), .idle) }
        return (place(t: t), .grow)
    }
}
