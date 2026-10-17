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
private let count = unfoldLandmarkRatios.count + 1

private func target(_ step: Int, _ s: UnfoldRect = screen) -> UnfoldRect {
    let t = unfoldStopTimes(screenW: s.width, screenH: s.height)[step]
    let f = frame(t, screenW: s.width, screenH: s.height)
    return UnfoldRect(x: s.x + f.x, y: s.y + f.y, width: f.w, height: f.h)
}

private func make() -> (UnfoldAnimator, FakeClock) {
    let clock = FakeClock()
    return (UnfoldAnimator(clock: clock), clock)
}

private func ratio(_ r: UnfoldRect) -> Double { r.width / r.height }

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

    @Test func eachPressLandsOnLandmarkRatioOnCommonScreens() {
        let expected = [1.0 / 2.0.squareRoot()] + unfoldLandmarkRatios
        for (w, h) in [(1280.0, 720.0), (1440.0, 900.0), (2560.0, 1440.0)] {
            let vis = UnfoldRect(x: 0, y: 0, width: w, height: h)
            var (a, clock) = make()
            a.press(window: start, visibleFrame: vis)
            clock.time += 0.3
            expectRelativelyClose(ratio(a.tick()!), expected[0], relTol: 1e-9)
            for k in 1..<expected.count {
                clock.time += 0.2
                a.press(window: start, visibleFrame: vis)
                clock.time += 0.15
                let r = a.tick()!
                expectRelativelyClose(ratio(r), expected[k], relTol: 1e-6, "\(w)x\(h) step \(k)")
                #expect(r.x >= -1e-9 && r.y >= -1e-9 && r.x + r.width <= w + 1e-9 && r.y + r.height <= h + 1e-9)
            }
            // Clamp at 16:9.
            clock.time += 0.2
            a.press(window: start, visibleFrame: vis)
            clock.time += 0.15
            expectRelativelyClose(ratio(a.tick()!), 16.0 / 9, relTol: 1e-9)
            #expect(a.step == expected.count - 1)
        }
    }

    @Test func stopTimesAreStrictlyIncreasingAndMatchCharterReference() {
        let t = unfoldStopTimes(screenW: 1920, screenH: 1080)
        #expect(t.count == 6 && t.first == 0 && t.last == 1)
        #expect(t == t.sorted() && Set(t).count == 6)
        // Charter cross-check: square 0.6504, 4:3 0.7551, 3:2 0.8053, golden 0.8465.
        for (got, want) in zip(t[1...4], [0.6504, 0.7551, 0.8053, 0.8465]) {
            #expect(abs(got - want) < 5e-4)
        }
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
