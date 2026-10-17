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
///
/// Unfold is a press-and-timer stepper, not an autonomous grow: the first press
/// shrinks to the baby A5 size, every further press inside the timer window
/// steps one size up the `frame(t)` path, and an expired timer returns to idle.
public struct UnfoldConfig: Equatable, Sendable {
    /// ASSUMPTION (captain will tune): time after a press in which another press
    /// steps up instead of resetting. Config key `unfold_step_window_ms` is
    /// wired later.
    public static let defaultStepWindow = 0.6

    /// Current rect -> A5 (`frame(0)`) on the first press, seconds.
    public var shrinkDuration: Double
    /// Ease between two steps, seconds.
    public var stepDuration: Double
    /// Timer restarted by every press, seconds.
    public var stepWindow: Double
    /// Number of sizes, A5 included: step `k` sits at `t = k / (stepCount - 1)`.
    public var stepCount: Int
    /// Passed to `frame()`.
    public var margin: Double

    public init(
        shrinkDuration: Double = 0.3,
        stepDuration: Double = 0.15,
        stepWindow: Double = UnfoldConfig.defaultStepWindow,
        stepCount: Int = 6,
        margin: Double = 0
    ) {
        precondition(shrinkDuration > 0 && stepDuration > 0, "durations must be positive")
        precondition(stepWindow > 0, "step window must be positive")
        precondition(stepCount >= 2, "need at least A5 and the largest size")
        self.shrinkDuration = shrinkDuration
        self.stepDuration = stepDuration
        self.stepWindow = stepWindow
        self.stepCount = stepCount
        self.margin = margin
    }
}

public enum UnfoldPhase: Equatable, Sendable {
    /// No timer running. The window keeps whatever size it has.
    case idle
    /// First press: easing from the window's rect to A5.
    case shrink
    /// A later press: easing to the next size.
    case step
    /// Eased to its size, timer still running.
    case waiting
}

/// Pure Unfold state machine: `idle -> shrink -> (step | waiting)* -> idle`.
///
/// It never touches a window. The caller feeds it presses and ticks and applies
/// the rects it returns through the Executor. The current rect lives in this
/// state and is never read back from a window while the timer runs; only a
/// press from `idle` takes the window's real rect.
///
/// - Press from idle: ease from the window's rect to A5 (centered), start timer.
/// - Press with the timer running: ease to the next size (clamped at the
///   largest 16:9 that fits), restart timer. A press mid-ease retargets from the
///   interpolated rect, so there is only ever one animation.
/// - Timer expiry with no press: back to idle, window stays where it is; the
///   next press starts again at A5.
///
/// Elapsed time, not tick count, decides the rect.
public struct UnfoldAnimator {
    public let config: UnfoldConfig
    private let clock: any UnfoldClock

    public private(set) var phase: UnfoldPhase = .idle
    /// Last rect this animator produced, or nil before the first press.
    public private(set) var currentRect: UnfoldRect?
    /// Index of the size being eased to or rested at; 0 is A5.
    public private(set) var step = 0

    private var easeStart = 0.0
    private var easeDuration = 0.0
    private var deadline = 0.0
    private var from = UnfoldRect(x: 0, y: 0, width: 0, height: 0)
    private var to = UnfoldRect(x: 0, y: 0, width: 0, height: 0)
    private var screen = UnfoldRect(x: 0, y: 0, width: 0, height: 0)

    public init(config: UnfoldConfig = UnfoldConfig(), clock: any UnfoldClock) {
        self.config = config
        self.clock = clock
    }

    /// Handles an Unfold press and returns the rect to apply now (the start of
    /// the new ease, i.e. the current rect).
    ///
    /// - Parameters:
    ///   - window: the focused window's real rect. Used only when idle.
    ///   - visibleFrame: visible frame of the window's own screen. Used when the
    ///     sequence starts; a running sequence stays on its screen.
    @discardableResult
    public mutating func press(window: UnfoldRect, visibleFrame: UnfoldRect) -> UnfoldRect {
        let now = clock.now()
        refresh(at: now)
        let start: UnfoldRect
        if phase == .idle {
            start = window
            screen = visibleFrame
            step = 0
            easeDuration = config.shrinkDuration
            phase = .shrink
        } else {
            start = rect(at: now)
            step = min(step + 1, config.stepCount - 1)
            easeDuration = config.stepDuration
            phase = .step
        }
        from = start
        to = place(t: Double(step) / Double(config.stepCount - 1))
        easeStart = now
        deadline = now + config.stepWindow
        currentRect = start
        return start
    }

    /// Advances to the clock's now. Returns the rect to apply, or nil when idle.
    /// The tick that finds the timer expired returns the final rect and goes idle.
    public mutating func tick() -> UnfoldRect? {
        guard phase != .idle else { return nil }
        let now = clock.now()
        let r = rect(at: now)
        refresh(at: now)
        currentRect = r
        return r
    }

    // MARK: Timeline

    /// Updates `phase` for time `now`.
    private mutating func refresh(at now: Double) {
        guard phase != .idle else { return }
        let easing = now - easeStart < easeDuration
        if easing { return }
        phase = now >= deadline ? .idle : .waiting
    }

    private func place(t: Double) -> UnfoldRect {
        let f = frame(t, screenW: screen.width, screenH: screen.height, margin: config.margin)
        return UnfoldRect(x: screen.x + f.x, y: screen.y + f.y, width: f.w, height: f.h)
    }

    private func rect(at now: Double) -> UnfoldRect {
        let p = min(max((now - easeStart) / easeDuration, 0), 1)
        if p >= 1 { return to }
        let u = smootherstep(p)
        return UnfoldRect(
            x: from.x + (to.x - from.x) * u,
            y: from.y + (to.y - from.y) * u,
            width: from.width + (to.width - from.width) * u,
            height: from.height + (to.height - from.height) * u
        )
    }
}
