import ChordCore
import Foundation
import Testing
@testable import Chord

private final class MotionClock: InputClock {
    var time = 0.0
    func now() -> Double { time }
}

private final class MotionLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(line)
    }

    func has(_ fragments: String...) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return storage.contains { line in fragments.allSatisfy { line.contains($0) } }
    }
}

@MainActor
@Suite("Window motion")
struct WindowMotionTests {
    private let visible = ScreenRect(x: 0, y: 25, width: 1440, height: 875)
    private let start = ScreenRect(x: 100, y: 100, width: 600, height: 400)

    private struct Rig {
        let backend: FakeWorkspaceBackend
        let executor: Executor
        let motion: WindowMotion
        let clock: MotionClock
        let log: MotionLog

        func bounds() async throws -> ScreenRect {
            let windows = try await backend.snapshot().windows
            return windows.first?.bounds ?? ScreenRect(x: 0, y: 0, width: 0, height: 0)
        }

        func press(at time: Double) async {
            clock.time = time
            await motion.handle(.intents([.unfold]))
        }

        func tick(at time: Double) async {
            clock.time = time
            await motion.handle(.tick)
        }
    }

    private func makeRig(supportsPlaces: Bool = false) -> Rig {
        let backend = FakeWorkspaceBackend(
            monitors: [MonitorSnapshot(id: MonitorID(1), bounds: visible, isPrimary: true)],
            windows: [WindowSnapshot(
                id: WindowID(1), appName: "App", place: .bench, isFloating: true, bounds: start)],
            focusedWindow: WindowID(1), supportsPlaces: supportsPlaces)
        let log = MotionLog()
        let executor = Executor(backend: backend, logSink: { log.append($0) })
        let clock = MotionClock()
        let motion = WindowMotion(
            executor: executor, clock: clock, sleep: { _ in }, log: { log.append($0) })
        return Rig(backend: backend, executor: executor, motion: motion, clock: clock, log: log)
    }

    // MARK: Unfold

    @Test func theFirstPressCentersTheWindowAtTheBabyA5Card() async throws {
        let rig = makeRig()
        await rig.press(at: 0)
        await rig.tick(at: 0.5)

        let frame = try await rig.bounds()
        #expect(frame.width == 333)
        #expect(frame.height == 471)
        #expect(abs((frame.x + frame.width / 2) - (visible.x + visible.width / 2)) <= 1)
        #expect(abs((frame.y + frame.height / 2) - (visible.y + visible.height / 2)) <= 1)
    }

    @Test func pressesInsideTheWindowStepThroughTheLandmarkRatios() async throws {
        let rig = makeRig()
        await rig.press(at: 0)
        await rig.tick(at: 0.5)
        await rig.press(at: 0.5)
        await rig.tick(at: 0.75)
        let square = try await rig.bounds()
        #expect(abs(square.width - square.height) <= 1)

        await rig.press(at: 0.75)
        await rig.tick(at: 1.0)
        let fourThirds = try await rig.bounds()
        #expect(abs(fourThirds.width / fourThirds.height - 4.0 / 3) < 0.01)
        #expect(fourThirds.width > square.width)
    }

    @Test func aSlowTickSkipsStraightToWhereTheClockSaysTheWindowShouldBe() async throws {
        let rig = makeRig()
        await rig.press(at: 0)
        await rig.tick(at: 0.5)  // no tick ran during the ease: the first frame is the end

        let frame = try await rig.bounds()
        #expect(frame.width == 333)
    }

    @Test func expiryClosesTheRunAsOneUndoAndTheNextPressRestartsAtA5() async throws {
        let rig = makeRig()
        await rig.press(at: 0)
        await rig.tick(at: 0.5)
        await rig.press(at: 0.5)
        await rig.tick(at: 0.75)
        await rig.tick(at: 2)  // past the 600 ms window: the run closes

        #expect(rig.log.has("unfold: finished"))
        try await rig.executor.undo()
        #expect(try await rig.bounds() == start)

        await rig.press(at: 3)
        await rig.tick(at: 3.5)
        let frame = try await rig.bounds()
        #expect(frame.width == 333)
        #expect(frame.height == 471)
    }

    @Test func unfoldWithoutAccessibilityLogsAndMovesNothing() async throws {
        let rig = makeRig()
        await rig.backend.queue([.disconnected])
        await rig.press(at: 0)

        #expect(rig.log.has("unfold: Accessibility access is missing"))
        try await rig.backend.reconnect()
        #expect(try await rig.bounds() == start)
    }

    // MARK: Reshape and carry

    @Test func aReshapeIntentChangesAspectAndAreaAroundTheCenter() async throws {
        let rig = makeRig()
        await rig.motion.handle(.intents([.reshape(aspectDelta: 0, areaDelta: 0.05)]))

        let frame = try await rig.bounds()
        #expect(frame.width * frame.height > start.width * start.height)
        #expect(abs(frame.width / frame.height - start.width / start.height) < 0.02)
    }

    @Test func aCarryIntentMovesTheWindowByTheMachinesDelta() async throws {
        let rig = makeRig()
        await rig.motion.handle(.intents([.carry(dx: 10, dy: 0)]))

        #expect(try await rig.bounds() == ScreenRect(x: 110, y: 100, width: 600, height: 400))
    }

    @Test func aCarryDuringUnfoldClosesTheRunFirst() async throws {
        let rig = makeRig()
        await rig.press(at: 0)
        await rig.tick(at: 0.5)
        await rig.motion.handle(.intents([.carry(dx: 10, dy: 0)]))

        #expect(rig.log.has("unfold: finished (carry)"))
        let frame = try await rig.bounds()
        #expect(frame.width == 333)
    }

    @Test func carryWithoutAccessibilityLogsAndMovesNothing() async throws {
        let rig = makeRig()
        await rig.backend.queue([.disconnected])
        await rig.motion.handle(.intents([.carry(dx: 10, dy: 0)]))

        #expect(rig.log.has("carry: Accessibility access is missing"))
        try await rig.backend.reconnect()
        #expect(try await rig.bounds() == start)
    }

    @Test func lookSpreadAndAbortAreLoggedAndChangeNothing() async throws {
        let rig = makeRig()
        await rig.motion.handle(.intents([.look(PickDirection(x: 1, y: 0)), .spread, .abortCharge]))

        #expect(rig.log.has("look: moving focus is not wired"))
        #expect(rig.log.has("spread: not wired"))
        #expect(try await rig.bounds() == start)
    }

    // MARK: Places

    private func placeBinding(_ digit: Int, shift: Bool = true) throws -> HotkeyBinding {
        let catalog = HotkeyCatalog(keys: KeyBindings.defaults)
        return try #require(catalog.binding(for: InputKey(code: "Digit\(digit)"), shift: shift))
    }

    @Test func placingOnABackendWithoutPlacesIsLoggedAndTheWindowStays() async throws {
        let rig = makeRig(supportsPlaces: false)
        await rig.motion.handle(.place(try placeBinding(3)))

        #expect(rig.log.has("place:", "no places"))
        #expect(try await rig.backend.snapshot().windows.first?.place == .bench)
    }

    @Test func placingOnABackendWithPlacesMovesTheFocusedWindow() async throws {
        let rig = makeRig(supportsPlaces: true)
        await rig.motion.handle(.place(try placeBinding(3)))

        #expect(try await rig.backend.snapshot().windows.first?.place == .workspace(.three))
    }

    @Test func aPlaceKeyThatNamesNoWorkspaceLeavesTheWindowAlone() async throws {
        let rig = makeRig(supportsPlaces: true)
        await rig.motion.handle(.place(try placeBinding(9)))

        #expect(rig.log.has("names no place a window can be sent to"))
        #expect(try await rig.backend.snapshot().windows.first?.place == .bench)
    }

    @Test func optionDigitWithoutShiftIsNotWired() async throws {
        let rig = makeRig(supportsPlaces: true)
        await rig.motion.handle(.place(try placeBinding(3, shift: false)))

        #expect(rig.log.has("not wired"))
        #expect(try await rig.backend.snapshot().windows.first?.place == .bench)
    }
}

@Suite("Screen geometry")
struct ScreenGeometryTests {
    @Test func cocoaRectsFlipAboutThePrimaryDisplayHeight() {
        // A 1440x875 visible frame under a 25 pt menu bar on a 900 pt display.
        let rect = ScreenGeometry.topLeftRect(
            fromCocoa: CGRect(x: 0, y: 0, width: 1440, height: 875), primaryHeight: 900)
        #expect(rect == ScreenRect(x: 0, y: 25, width: 1440, height: 875))
    }

    @Test func aMonitorAboveThePrimaryHasNegativeY() {
        let rect = ScreenGeometry.topLeftRect(
            fromCocoa: CGRect(x: 0, y: 900, width: 1920, height: 1080), primaryHeight: 900)
        #expect(rect == ScreenRect(x: 0, y: -1080, width: 1920, height: 1080))
    }

    @Test func theMonitorHoldingTheWindowCenterWins() {
        let primary = MonitorSnapshot(
            id: MonitorID(1), bounds: ScreenRect(x: 0, y: 25, width: 1440, height: 875), isPrimary: true)
        let right = MonitorSnapshot(
            id: MonitorID(2), bounds: ScreenRect(x: 1440, y: 0, width: 1920, height: 1080), isPrimary: false)
        let window = ScreenRect(x: 1500, y: 100, width: 400, height: 300)

        #expect(ScreenGeometry.visibleFrame(holding: window, monitors: [primary, right]) == right.bounds)
    }

    @Test func aWindowOnNoMonitorFallsBackToThePrimary() {
        let primary = MonitorSnapshot(
            id: MonitorID(1), bounds: ScreenRect(x: 0, y: 25, width: 1440, height: 875), isPrimary: true)
        let other = MonitorSnapshot(
            id: MonitorID(2), bounds: ScreenRect(x: 1440, y: 0, width: 1920, height: 1080), isPrimary: false)
        let window = ScreenRect(x: -5000, y: -5000, width: 400, height: 300)

        #expect(ScreenGeometry.visibleFrame(holding: window, monitors: [other, primary]) == primary.bounds)
        #expect(ScreenGeometry.visibleFrame(holding: window, monitors: []) == nil)
    }
}

@MainActor
@Suite("Focused geometry")
struct FocusedGeometryTests {
    private final class Clock: InputClock {
        var time = 0.0
        func now() -> Double { time }
    }

    private let monitor = MonitorSnapshot(
        id: MonitorID(1), bounds: ScreenRect(x: 0, y: 25, width: 1440, height: 875), isPrimary: true)

    @Test func edgesAreTheVisibleFrameOfTheMonitorHoldingTheWindow() {
        let monitors = [monitor]
        let provider = FocusedGeometry(
            clock: Clock(),
            readFrame: { ScreenRect(x: 100, y: 200, width: 333, height: 471) },
            readMonitors: { monitors })

        let geometry = provider.current()

        #expect(geometry.rect == PickerRect(x: 100, y: 200, width: 333, height: 471))
        #expect(geometry.edges == KeyStateMachine.Edges(left: 0, right: 1440, top: 25, bottom: 900))
    }

    @Test func nothingFocusedAnswersTheStandIn() {
        let monitors = [monitor]
        let provider = FocusedGeometry(clock: Clock(), readFrame: { nil }, readMonitors: { monitors })

        #expect(provider.current() == .standIn)
    }
}
