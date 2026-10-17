import Testing
@testable import ChordCore

private final class FakeClock: UnfoldClock {
    var time = 100.0
    func now() -> Double { time }
}

/// Stand-in for the Executor frame action: records every applied rect.
private struct FakeWindow {
    var rect: UnfoldRect
    var applied: [UnfoldRect] = []
    mutating func apply(_ r: UnfoldRect?) {
        guard let r else { return }
        rect = r
        applied.append(r)
    }
}

private let screen = UnfoldRect(x: 0, y: 25, width: 1920, height: 1055)
private let start = UnfoldRect(x: 300, y: 200, width: 800, height: 600)

private func target(_ t: Double, _ s: UnfoldRect = screen) -> UnfoldRect {
    let f = frame(t, screenW: s.width, screenH: s.height)
    return UnfoldRect(x: s.x + f.x, y: s.y + f.y, width: f.w, height: f.h)
}

private func make(_ config: UnfoldConfig = UnfoldConfig()) -> (UnfoldAnimator, FakeClock, FakeWindow) {
    let clock = FakeClock()
    return (UnfoldAnimator(config: config, clock: clock), clock, FakeWindow(rect: start))
}

@Suite struct UnfoldAnimatorTests {
    @Test func idleTickDoesNothing() {
        var (a, _, _) = make()
        #expect(a.tick() == nil)
        #expect(a.phase == .idle)
    }

    @Test func shrinkRunsFromCurrentRectToFrameZero() {
        var (a, clock, win) = make()
        win.apply(a.press(window: start, visibleFrame: screen))
        #expect(a.phase == .shrink)
        #expect(win.rect == start)
        clock.time += 0.15
        let mid = a.tick()
        #expect(a.phase == .shrink)
        // smootherstep(0.5) == 0.5
        expectRelativelyClose(mid!.width, (start.width + target(0).width) / 2, relTol: 1e-12)
        clock.time += 0.15
        let end = a.tick()
        #expect(a.phase == .grow)
        expectRelativelyClose(end!.width, target(0).width, relTol: 1e-12)
        expectRelativelyClose(end!.x, target(0).x, relTol: 1e-12)
        expectRelativelyClose(end!.y, target(0).y, relTol: 1e-12)
    }

    @Test func holdPausesAtS1ThenGrowFinishesAtS2() {
        var (a, clock, _) = make()
        a.press(window: start, visibleFrame: screen)
        let knotTime = 0.3 + 2.4 * Unfold.knot
        clock.time += knotTime + 0.001
        let held1 = a.tick()!
        clock.time += 0.19
        let held2 = a.tick()!
        #expect(held1 == held2)
        expectRelativelyClose(held1.width, Unfold.largeStop.w, relTol: 1e-9)
        clock.time += 0.02
        #expect(a.tick()! != held2)
        #expect(a.phase == .grow)
        clock.time += 10
        let last = a.tick()!
        #expect(a.phase == .idle)
        #expect(last == target(1))
        #expect(a.tick() == nil)
    }

    @Test func holdSkippedWhenS1LargerThanS2() {
        let small = UnfoldRect(x: 0, y: 0, width: 400, height: 300)
        var (a, clock, _) = make()
        a.press(window: start, visibleFrame: small)
        clock.time += 0.3 + 2.4 * Unfold.knot + 0.1
        let r1 = a.tick()!
        clock.time += 0.1
        #expect(a.tick()! != r1)
        // Total run is 2.7 s without the hold.
        clock.time = 100 + 2.71
        _ = a.tick()
        #expect(a.phase == .idle)
    }

    @Test func runLengthIncludesHoldWhenItApplies() {
        var (a, clock, _) = make()
        a.press(window: start, visibleFrame: screen)
        clock.time += 2.7 + 0.19
        _ = a.tick()
        #expect(a.phase == .grow)
        clock.time += 0.02
        _ = a.tick()
        #expect(a.phase == .idle)
    }

    @Test func pressMidShrinkRestartsFromHeldRectNotWindow() {
        var (a, clock, win) = make()
        win.apply(a.press(window: start, visibleFrame: screen))
        clock.time += 0.1
        win.apply(a.tick())
        clock.time += 0.05
        let expected = a.press(window: UnfoldRect(x: 0, y: 0, width: 1, height: 1), visibleFrame: screen)
        #expect(a.phase == .shrink)
        #expect(expected != win.rect)  // advanced past last applied tick
        #expect(expected.width > target(0).width && expected.width < start.width)
        // Restart begins a fresh 0.3 s shrink: not done at 0.29, done at 0.3.
        clock.time += 0.29
        _ = a.tick()
        #expect(a.phase == .shrink)
        clock.time += 0.01
        _ = a.tick()
        #expect(a.phase == .grow)
    }

    @Test func pressMidGrowRestartsShrinkFromGrowRect() {
        var (a, clock, _) = make()
        a.press(window: start, visibleFrame: screen)
        clock.time += 1.5
        let grown = a.tick()!
        #expect(a.phase == .grow)
        let restart = a.press(window: start, visibleFrame: screen)
        #expect(restart == grown)
        #expect(a.phase == .shrink)
        clock.time += 0.31
        let end = a.tick()!
        #expect(a.phase == .grow)
        expectRelativelyClose(end.width, target(0).width, relTol: 1e-3)
    }

    @Test func pressAfterFinishStartsFreshFromWindowRect() {
        var (a, clock, _) = make()
        a.press(window: start, visibleFrame: screen)
        clock.time += 5
        _ = a.tick()
        #expect(a.phase == .idle)
        let moved = UnfoldRect(x: 10, y: 40, width: 500, height: 500)
        clock.time += 30
        #expect(a.press(window: moved, visibleFrame: screen) == moved)
        #expect(a.phase == .shrink)
    }

    @Test func lateTickSkipsFramesToTimelinePosition() {
        var (a, clock, _) = make()
        a.press(window: start, visibleFrame: screen)
        clock.time += 0.3 + 1.5
        let late = a.tick()!
        #expect(a.phase == .grow)
        expectRelativelyClose(late.width, target(1.3 / 2.4).width, relTol: 1e-12)
    }

    @Test func offsetVisibleFrameIsHonored() {
        let second = UnfoldRect(x: 1920, y: 0, width: 2560, height: 1415)
        var (a, clock, _) = make()
        a.press(window: start, visibleFrame: second)
        clock.time += 10
        #expect(a.tick()! == target(1, second))
    }

    @Test func sameInputsGiveSameRects() {
        func run() -> [UnfoldRect] {
            var (a, clock, win) = make()
            win.apply(a.press(window: start, visibleFrame: screen))
            for i in 0..<400 {
                clock.time += 0.0083
                if i == 50 { win.apply(a.press(window: start, visibleFrame: screen)) }
                win.apply(a.tick())
            }
            return win.applied
        }
        #expect(run() == run())
    }
}
