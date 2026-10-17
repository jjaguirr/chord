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
private let count = UnfoldConfig().stepCount

private func target(_ step: Int, _ s: UnfoldRect = screen) -> UnfoldRect {
    let f = frame(Double(step) / Double(count - 1), screenW: s.width, screenH: s.height)
    return UnfoldRect(x: s.x + f.x, y: s.y + f.y, width: f.w, height: f.h)
}

private func make() -> (UnfoldAnimator, FakeClock) {
    let clock = FakeClock()
    return (UnfoldAnimator(clock: clock), clock)
}

private func expectRect(_ a: UnfoldRect, _ b: UnfoldRect, tol: Double = 1e-9) {
    expectRelativelyClose(a.x, b.x, relTol: tol)
    expectRelativelyClose(a.y, b.y, relTol: tol)
    expectRelativelyClose(a.width, b.width, relTol: tol)
    expectRelativelyClose(a.height, b.height, relTol: tol)
}

@Suite struct UnfoldAnimatorTests {
    @Test func idleTickDoesNothing() {
        var (a, _) = make()
        #expect(a.tick() == nil)
        #expect(a.phase == .idle)
    }

    @Test func firstPressShrinksFromWindowToCenteredA5() {
        var (a, clock) = make()
        #expect(a.press(window: start, visibleFrame: screen) == start)
        #expect(a.phase == .shrink)
        clock.time += 0.15
        let mid = a.tick()!
        // smootherstep(0.5) == 0.5
        expectRelativelyClose(mid.width, (start.width + target(0).width) / 2, relTol: 1e-12)
        clock.time += 0.15
        expectRect(a.tick()!, target(0))
        #expect(a.phase == .waiting)
        #expect(a.step == 0)
    }

    @Test func pressesInsideWindowStepUpThroughAllSizes() {
        var (a, clock) = make()
        a.press(window: start, visibleFrame: screen)
        var widths = [target(0).width]
        for k in 1..<count {
            clock.time += 0.4  // eased, timer still running
            a.press(window: start, visibleFrame: screen)
            #expect(a.step == k)
            #expect(a.phase == .step)
            clock.time += 0.15
            let r = a.tick()!
            expectRect(r, target(k))
            widths.append(r.width)
        }
        #expect(widths == widths.sorted())
        expectRelativelyClose(widths.last!, frame(1, screenW: 1920, screenH: 1055).w, relTol: 1e-12)
    }

    @Test func timerExpiryReturnsToIdleKeepingSizeThenPressResetsToA5() {
        var (a, clock) = make()
        a.press(window: start, visibleFrame: screen)
        clock.time += 0.4
        a.press(window: start, visibleFrame: screen)
        clock.time += 0.15
        _ = a.tick()
        #expect(a.step == 1)
        clock.time += UnfoldConfig.defaultStepWindow + 0.01
        let kept = a.tick()!
        #expect(a.phase == .idle)
        expectRect(kept, target(1))
        #expect(a.tick() == nil)
        // Window now sits at step 1; next press shrinks from there to A5.
        #expect(a.press(window: kept, visibleFrame: screen) == kept)
        #expect(a.step == 0)
        #expect(a.phase == .shrink)
        clock.time += 0.3
        expectRect(a.tick()!, target(0))
    }

    @Test func maxStepClampsAndStillRestartsTimer() {
        var (a, clock) = make()
        a.press(window: start, visibleFrame: screen)
        for _ in 0..<(count + 3) {
            clock.time += 0.4
            a.press(window: start, visibleFrame: screen)
        }
        #expect(a.step == count - 1)
        clock.time += 0.15
        expectRect(a.tick()!, target(count - 1))
        // Last press restarted the timer: still waiting well after the first window.
        clock.time += 0.4
        _ = a.tick()
        #expect(a.phase == .waiting)
        clock.time += 0.3
        _ = a.tick()
        #expect(a.phase == .idle)
    }

    @Test func pressMidEaseRetargetsFromInterpolatedRectNotWindow() {
        var (a, clock) = make()
        var win = FakeWindow(rect: start)
        win.apply(a.press(window: start, visibleFrame: screen))
        clock.time += 0.1
        win.apply(a.tick())
        clock.time += 0.05
        let bogus = UnfoldRect(x: 0, y: 0, width: 1, height: 1)
        let retarget = a.press(window: bogus, visibleFrame: screen)
        #expect(a.step == 1)
        #expect(retarget != win.rect)  // advanced past the last applied tick
        #expect(retarget.width > target(0).width && retarget.width < start.width)
        // One animation: a fresh step ease from there, done after stepDuration.
        clock.time += 0.14
        _ = a.tick()
        #expect(a.phase == .step)
        clock.time += 0.01
        expectRect(a.tick()!, target(1))
    }

    @Test func offsetVisibleFrameIsHonored() {
        let second = UnfoldRect(x: 1920, y: 0, width: 2560, height: 1415)
        var (a, clock) = make()
        a.press(window: start, visibleFrame: second)
        clock.time += 0.3
        expectRect(a.tick()!, target(0, second))
    }

    @Test func sameInputsGiveSameRects() {
        func run() -> [UnfoldRect] {
            var (a, clock) = make()
            var win = FakeWindow(rect: start)
            win.apply(a.press(window: start, visibleFrame: screen))
            for i in 0..<400 {
                clock.time += 0.0083
                if i % 37 == 0 { win.apply(a.press(window: win.rect, visibleFrame: screen)) }
                win.apply(a.tick())
            }
            return win.applied
        }
        #expect(run() == run())
    }
}
