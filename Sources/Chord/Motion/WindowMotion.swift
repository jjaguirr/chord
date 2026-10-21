import ChordCore
import Foundation

/// Turns captured key intents into window motion by handing them to the Executor. It
/// makes no window call of its own: every change goes through `Executor`, which is the
/// only writer.
///
/// - Unfold: runs the pure `UnfoldAnimator` stepper. The first press opens a frame run
///   on the focused window; a timer then applies the animator's rect for the clock's
///   *now* (a slow AX call skips frames instead of lagging) until the step window
///   expires, and the run closes as one undoable change.
/// - Reshape: one log-space aspect/area step per Option+R+hjkl press.
/// - Carry: one move per carry intent, with the edge-magnet distance the state machine
///   already computed.
/// - Look: focus moves at once to the Picker's nearest visible window in that direction,
///   across monitors (`Look`); no preview, no latch.
///
/// Commands run strictly one at a time, in the order they arrive, so a press never
/// interleaves with a frame step. Main thread only.
@MainActor
final class WindowMotion {
    enum Command: Equatable {
        case intents([KeyIntent])
        /// Internal: advance the Unfold animation to now.
        case tick
    }

    /// Seconds between frame steps while easing, and while resting inside the step window.
    static let easingInterval = 1.0 / 60
    static let restingInterval = 0.05

    /// Floor for a reshape. AX gives no per-app minimum size, so a window is never made
    /// smaller than this; the app may refuse more.
    // DECISION: a fixed floor. The alternative is reading AXMinimumSize where an app
    // exposes it, which needs real apps to check; unverified.
    static let minimumWindowSize = ActionSize(width: 120, height: 80)

    private let executor: Executor
    private let clock: InputClock
    private let config: UnfoldConfig
    private let sleep: @Sendable (Double) async -> Void
    private let log: @Sendable (String) -> Void

    private var animator: UnfoldAnimator
    /// A frame run is open on the Executor.
    private var running = false
    private var visibleFrame: UnfoldRect?
    private var tickScheduled = false
    private var commands: AsyncStream<Command>.Continuation?

    init(
        executor: Executor,
        clock: InputClock,
        stepWindow: Double = UnfoldConfig.defaultStepWindow,
        sleep: @escaping @Sendable (Double) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0 * 1e9)) },
        log: @escaping @Sendable (String) -> Void
    ) {
        self.executor = executor
        self.clock = clock
        self.config = UnfoldConfig(stepWindow: stepWindow)
        self.sleep = sleep
        self.log = log
        animator = UnfoldAnimator(config: config, clock: Self.unfoldClock(clock))
    }

    // MARK: Queue

    /// Starts the single consumer that runs commands in arrival order. Idempotent.
    func start() {
        guard commands == nil else { return }
        tickScheduled = false
        let (stream, continuation) = AsyncStream.makeStream(of: Command.self)
        commands = continuation
        Task { [weak self] in
            for await command in stream {
                guard let self else { return }
                await self.handle(command)
            }
        }
    }

    /// Stops accepting commands. `cancel()` closes a frame run that is still open.
    func stop() {
        commands?.finish()
        commands = nil
    }

    func submit(_ command: Command) {
        commands?.yield(command)
    }

    /// Closes any open Unfold run now (a pause or a permission change). Inverse of nothing:
    /// it only stops further steps; the window stays where the last step left it.
    func cancel() async {
        await finishRun(reason: "cancelled")
    }

    // MARK: Commands

    func handle(_ command: Command) async {
        switch command {
        case .intents(let intents):
            for intent in intents { await handle(intent) }
        case .tick:
            await tick()
        }
    }

    private func handle(_ intent: KeyIntent) async {
        switch intent {
        case .unfold:
            await unfold()
        case .reshape(let aspect, let area):
            await finishRun(reason: "reshape")
            do {
                let changes = try await executor.reshapeFocused(
                    aspectDelta: aspect, areaDelta: area, minimumSize: Self.minimumWindowSize)
                if changes.isEmpty { log("reshape: already at its limit; nothing changed") }
            } catch {
                log("reshape: \(Self.describe(error))")
            }
        case .carry(let dx, let dy):
            await finishRun(reason: "carry")
            do {
                let changes = try await executor.carry(dx: dx, dy: dy)
                if changes.isEmpty { log("carry: already at the edge; nothing moved") }
            } catch {
                log("carry: \(Self.describe(error))")
            }
        case .carryAcross(let direction, let dx, let dy):
            await finishRun(reason: "carry")
            do {
                // The Executor logs the carry or why nothing moved.
                try await executor.carryAcross(direction, dx: dx, dy: dy)
            } catch {
                log("carry \(direction.keys): \(Self.describe(error))")
            }
        case .look(let direction):
            await finishRun(reason: "look")
            do {
                // The Executor logs the key, the candidates, and the pick or why none.
                try await executor.look(direction)
            } catch {
                log("look \(direction.keys): \(Self.describe(error))")
            }
        case .showColumn(let column):
            await workspace("show column \(column)") { try await self.executor.showColumn(column) }
        case .carryToColumn(let column):
            await workspace("carry to column \(column)") { try await self.executor.carryToColumn(column) }
        case .showBench:
            await workspace("show bench") { try await self.executor.showBench() }
        case .carryToBench:
            await workspace("carry to bench") { try await self.executor.carryToBench() }
        case .showPrevious:
            await workspace("show previous") { try await self.executor.showPrevious() }
        case .stepWorkspace(let step):
            await workspace("workspace step \(step)") { try await self.executor.stepWorkspace(step) }
        case .carryStepWorkspace(let step):
            await workspace("carry workspace step \(step)") { try await self.executor.carryStepWorkspace(step) }
        case .spread:
            log("spread: not wired to windows yet; nothing changed")
        case .abortCharge:
            log("abort: Option+0 charge aborted; nothing changed")
        }
    }

    /// One workspace key. The Executor logs each change, and why nothing changed when it
    /// refuses; only a failure is logged here.
    private func workspace(_ label: String, _ body: () async throws -> [Change]) async {
        await finishRun(reason: "workspace")
        do {
            _ = try await body()
        } catch {
            log("\(label): \(Self.describeWorkspace(error))")
        }
    }

    // MARK: Unfold

    private func unfold() async {
        do {
            let window: UnfoldRect
            let visible: UnfoldRect
            if running, let current = animator.currentRect, let known = visibleFrame {
                window = current
                visible = known
            } else {
                await finishRun(reason: "restart")
                let context = try await executor.beginFrameRun(label: "unfold")
                running = true
                window = UnfoldRect(context.bounds)
                visible = UnfoldRect(context.visibleFrame)
                visibleFrame = visible
            }
            animator.press(window: window, visibleFrame: visible)
            log("unfold: press, step \(animator.step)")
            scheduleTick()
        } catch {
            log("unfold: \(Self.describe(error))")
        }
    }

    private func tick() async {
        tickScheduled = false
        guard running else { return }
        guard let rect = animator.tick() else {
            await finishRun(reason: "timer expired")
            return
        }
        do {
            try await executor.stepFrameRun(to: ScreenRect(rect))
        } catch {
            log("unfold: \(Self.describe(error)); stopping")
            await finishRun(reason: "step failed")
            return
        }
        if animator.phase == .idle {
            await finishRun(reason: "timer expired")
        } else {
            scheduleTick()
        }
    }

    /// Closes the open run, if any, as one undoable change and resets the animator so
    /// the next press starts again at the first stop.
    private func finishRun(reason: String) async {
        guard running else { return }
        running = false
        visibleFrame = nil
        animator = UnfoldAnimator(config: config, clock: Self.unfoldClock(clock))
        await executor.endFrameRun()
        log("unfold: finished (\(reason))")
    }

    private func scheduleTick() {
        guard !tickScheduled else { return }
        tickScheduled = true
        let delay = animator.phase == .waiting ? Self.restingInterval : Self.easingInterval
        let sleep = self.sleep
        Task { [weak self] in
            await sleep(delay)
            self?.submit(.tick)
        }
    }

    // MARK: Helpers

    private struct ClockBridge: UnfoldClock {
        let clock: InputClock
        func now() -> Double { clock.now() }
    }

    private static func unfoldClock(_ clock: InputClock) -> any UnfoldClock {
        ClockBridge(clock: clock)
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case BackendError.notConnected:
            return "Accessibility access is missing; nothing moved"
        case ExecutorError.noFocusedWindow:
            return "no focused window; nothing moved"
        case ExecutorError.noVisibleFrame:
            return "no monitor holds the window; nothing moved"
        case BackendError.unknownWindow:
            return "the window is gone; nothing moved"
        default:
            return "failed: \(error)"
        }
    }

    /// A workspace key's failure in words. Workspace calls go to AeroSpace, not to
    /// Accessibility, so a missing connection is about the server.
    static func describeWorkspace(_ error: Error) -> String {
        switch error {
        case BackendError.notConnected:
            return "AeroSpace is not reachable (not running, disabled, or not the pinned version); nothing changed"
        case ExecutorError.noFocusedWindow:
            return "no focused window; nothing moved"
        case BackendError.unknownWindow:
            return "the window is gone; nothing moved"
        default:
            return "failed: \(error)"
        }
    }
}

private extension UnfoldRect {
    init(_ rect: ScreenRect) {
        self.init(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }
}

private extension ScreenRect {
    init(_ rect: UnfoldRect) {
        self.init(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }
}
