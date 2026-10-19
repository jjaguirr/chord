import Testing
@testable import ChordCore

@Suite("Look")
struct LookTests {
    // Two 1000x800 monitors side by side; every number is a multiple of the Picker's
    // 8-point grid so snapping never decides a test.
    private let left = PickerMonitor(id: 1, bounds: PickerRect(x: 0, y: 0, width: 1000, height: 800), isPrimary: true)
    private let right = PickerMonitor(id: 2, bounds: PickerRect(x: 1000, y: 0, width: 1000, height: 800))

    private func window(
        _ id: Int, _ x: Double, _ y: Double, _ width: Double = 96, _ height: Double = 96,
        mru: Int = 0, coverage: Double = 0
    ) -> PickerWindow {
        PickerWindow(
            id: id, rect: PickerRect(x: x, y: y, width: width, height: height), layer: 1, mru: mru,
            coverage: coverage)
    }

    private func decide(
        _ origin: Int, _ direction: PickDirection, cameFrom: Int? = nil, _ windows: [PickerWindow],
        _ monitors: [PickerMonitor]
    ) -> LookDecision {
        Look.decide(from: origin, direction: direction, cameFrom: cameFrom, windows: windows, monitors: monitors)
    }

    // MARK: Same monitor

    @Test func aWindowOnTheSameMonitorBeatsANearerOneOnTheNextMonitor() {
        // 2 is 600 away on the same monitor; 3 sits just over the edge, 200 away.
        let windows = [window(1, 100, 352), window(2, 700, 352), window(3, 1000, 352)]
        let result = decide(1, .l, windows, [left, right])
        #expect(result.outcome == .picked(2, .sameMonitor))
        #expect(result.candidates == [2])
    }

    // MARK: Crossing

    @Test func atTheEdgeFocusCrossesToTheNearestWindowOnTheAdjacentMonitor() {
        let windows = [window(1, 800, 352), window(2, 1096, 352), window(3, 1600, 352)]
        let result = decide(1, .l, windows, [left, right])
        #expect(result.outcome == .picked(2, .adjacentMonitor))
        #expect(result.candidates == [2, 3])
    }

    @Test func crossingWorksInEveryDirection() {
        let above = PickerMonitor(id: 3, bounds: PickerRect(x: 0, y: -800, width: 1000, height: 800))
        let windows = [window(1, 500, 352), window(2, 1200, 352), window(3, 500, -400)]
        let monitors = [left, right, above]
        #expect(decide(1, .l, windows, monitors).outcome == .picked(2, .adjacentMonitor))
        #expect(decide(1, .k, windows, monitors).outcome == .picked(3, .adjacentMonitor))
        #expect(decide(2, .h, windows, monitors).outcome == .picked(1, .adjacentMonitor))
        #expect(decide(3, .j, windows, monitors).outcome == .picked(1, .adjacentMonitor))
    }

    @Test func aCrossingTieFallsToThePickersOrderAndCameFromOverridesIt() {
        // 2 and 3 are equally far above and below 1's center: same score bucket, same layer,
        // same mru, same offset across, so the lowest id wins, and cameFrom overrides that.
        let windows = [window(1, 800, 352), window(2, 1096, 200), window(3, 1096, 504)]
        #expect(decide(1, .l, windows, [left, right]).target == 2)
        #expect(decide(1, .l, cameFrom: 3, windows, [left, right]).target == 3)
    }

    @Test func mostRecentlyUsedWindowWinsATieOnTheAdjacentMonitor() {
        let windows = [window(1, 800, 352), window(2, 1096, 200), window(3, 1096, 504, mru: 5)]
        #expect(decide(1, .l, windows, [left, right]).target == 3)
    }

    @Test func aPressAndItsOppositeComeBackAcrossTheEdge() {
        let windows = [window(1, 800, 352), window(2, 1096, 352)]
        let there = decide(1, .l, windows, [left, right])
        #expect(there.target == 2)
        let back = decide(2, .h, cameFrom: 1, windows, [left, right])
        #expect(back.target == 1)
    }

    @Test func monitorsOfDifferentSizesAreNeighboursWhereTheirExtentsShareRows() {
        // The tall monitor's lower part has no row of the short one beside it, but the
        // monitors as a whole do, so Look still crosses.
        let tall = PickerMonitor(id: 2, bounds: PickerRect(x: 1000, y: 0, width: 1000, height: 1600), isPrimary: false)
        let windows = [window(1, 1200, 1200), window(2, 400, 352)]
        let result = decide(1, .h, windows, [left, tall])
        #expect(result.outcome == .picked(2, .adjacentMonitor))
    }

    @Test func aWindowIsOnTheMonitorHoldingItsCenter() {
        // 2 straddles the seam but its center is on the right monitor, so from 1 it is across.
        let windows = [window(1, 800, 352), window(2, 960, 352, 200, 96)]
        #expect(decide(1, .l, windows, [left, right]).outcome == .picked(2, .adjacentMonitor))
    }

    // MARK: Nothing

    @Test func noMonitorInTheDirectionPicksNothingEvenWithWindowsElsewhere() {
        let windows = [window(1, 800, 352), window(2, 1096, 352)]
        // 1 is on the left monitor; nothing is left of it and no monitor is either.
        let result = decide(1, .h, windows, [left, right])
        #expect(result.outcome == .nothing(.noMonitorInDirection))
        #expect(result.target == nil)
        #expect(decide(1, .j, windows, [left, right]).outcome == .nothing(.noMonitorInDirection))
        #expect(decide(1, .k, windows, [left, right]).outcome == .nothing(.noMonitorInDirection))
    }

    @Test func aMonitorTouchingOnlyAtACornerIsNotAdjacent() {
        let diagonal = PickerMonitor(id: 2, bounds: PickerRect(x: 1000, y: 800, width: 1000, height: 800))
        let windows = [window(1, 800, 352), window(2, 1200, 1200)]
        #expect(decide(1, .l, windows, [left, diagonal]).outcome == .nothing(.noMonitorInDirection))
        #expect(decide(1, .j, windows, [left, diagonal]).outcome == .nothing(.noMonitorInDirection))
    }

    @Test func anEmptyNeighbourMonitorPicksNothing() {
        let result = decide(1, .l, [window(1, 800, 352), window(2, 100, 352)], [left, right])
        #expect(result.outcome == .nothing(.neighbourMonitorEmpty))
    }

    @Test func aNeighbourWhoseWindowsAreAllCoveredPicksNothing() {
        let windows = [window(1, 800, 352), window(2, 1096, 352, coverage: 0.9)]
        let result = decide(1, .l, windows, [left, right])
        #expect(result.outcome == .nothing(.neighbourHasNoTarget))
        #expect(result.candidates == [2])
    }

    @Test func aLoneWindowAMissingOriginAndNoDirectionPickNothing() {
        #expect(decide(1, .l, [window(1, 0, 0)], [left, right]).outcome == .nothing(.noOtherWindow))
        #expect(decide(9, .l, [window(1, 0, 0)], [left, right]).outcome == .nothing(.originNotVisible))
        let windows = [window(1, 0, 0), window(2, 200, 0)]
        #expect(decide(1, PickDirection(x: 0, y: 0), windows, [left, right]).outcome == .nothing(.noDirection))
    }

    // MARK: No monitors, chords, keys

    @Test func withoutMonitorsEveryWindowIsOnePool() {
        let windows = [window(1, 0, 352), window(2, 400, 352)]
        #expect(decide(1, .l, windows, []).target == 2)
        #expect(decide(1, .h, windows, []).outcome == .nothing(.noMonitorInDirection))
    }

    @Test func aChordLooksDiagonallyAcrossAnEdge() {
        let above = PickerMonitor(id: 3, bounds: PickerRect(x: 0, y: -800, width: 1000, height: 800))
        let windows = [window(1, 800, 352), window(2, 1096, 352), window(3, 700, -400)]
        // Up-right: the right monitor shares rows and the upper one shares columns, so the
        // Picker ranks both monitors' windows together; 2 is far nearer along the diagonal.
        let result = decide(1, PickDirection(x: 1, y: -1), windows, [left, right, above])
        #expect(result.outcome == .picked(2, .adjacentMonitor))
        #expect(result.candidates == [2, 3])
    }

    @Test func directionKeysNameTheHjklPresses() {
        #expect(PickDirection.h.keys == "h")
        #expect(PickDirection.l.keys == "l")
        #expect(PickDirection.k.keys == "k")
        #expect(PickDirection.j.keys == "j")
        #expect(PickDirection(x: -1, y: 1).keys == "h+j")
        #expect(PickDirection(x: 1, y: -1).keys == "l+k")
    }

    // MARK: Properties

    @Test func aPickIsNeverTheOriginAndStaysOnTheMonitorsItClaims() {
        let monitors = [left, right]
        var rng = SplitMix64(state: 64)
        for _ in 0..<200 {
            let count = 2 + Int(rng.unit() * 8)
            let windows = (0..<count).map { id in
                window(
                    id, (rng.unit() * 1900 / 8).rounded() * 8, (rng.unit() * 700 / 8).rounded() * 8,
                    96, 96, mru: Int(rng.unit() * 4))
            }
            for direction in [PickDirection.h, .j, .k, .l] {
                let result = decide(0, direction, windows, monitors)
                guard let target = result.target else { continue }
                #expect(target != 0)
                let originMonitor = windows[0].rect.x + 48 < 1000 ? 0 : 1
                let targetWindow = windows.first { $0.id == target }
                let targetMonitor = (targetWindow?.rect.x ?? 0) + 48 < 1000 ? 0 : 1
                if case .picked(_, .sameMonitor) = result.outcome { #expect(targetMonitor == originMonitor) }
                if case .picked(_, .adjacentMonitor) = result.outcome { #expect(targetMonitor != originMonitor) }
                #expect(result.candidates.contains(target))
            }
        }
    }

    @Test func orderOfWindowsNeverChangesTheDecision() {
        var rng = SplitMix64(state: 65)
        let windows = [
            window(1, 800, 352), window(2, 1096, 200), window(3, 1096, 504),
            window(4, 400, 352), window(5, 1500, 352, mru: 2),
        ]
        for direction in [PickDirection.h, .j, .k, .l] {
            let expected = decide(1, direction, windows, [left, right]).outcome
            for _ in 0..<50 {
                #expect(decide(1, direction, windows.shuffled(using: &rng), [right, left]).outcome == expected)
            }
        }
    }
}
