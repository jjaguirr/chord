import Testing
@testable import ChordCore

@Suite("Picker properties")
struct PickerTests {
    private func grid() -> [PickerWindow] {
        [
            PickerWindow(id: 0, rect: PickerRect(x: 0, y: 0, width: 100, height: 100), layer: 0, mru: 0, coverage: 0),
            PickerWindow(id: 1, rect: PickerRect(x: 160, y: 0, width: 100, height: 100), layer: 0, mru: 1, coverage: 0),
            PickerWindow(id: 2, rect: PickerRect(x: 0, y: 160, width: 100, height: 100), layer: 1, mru: 2, coverage: 0),
            PickerWindow(id: 3, rect: PickerRect(x: 160, y: 160, width: 100, height: 100), layer: 0, mru: 3, coverage: 0),
        ]
    }

    @Test func orderIndependenceAcrossHundredShuffles() {
        let windows = grid()
        let expected = Picker.pick(from: 0, direction: .l, windows: windows)
        var rng = SplitMix64(state: 31)
        for _ in 0..<100 {
            let shuffled = windows.shuffled(using: &rng)
            #expect(Picker.pick(from: 0, direction: .l, windows: shuffled) == expected)
        }
    }

    @Test func jitterIndependenceWithinThreePixels() {
        let base = grid()
        var rng = SplitMix64(state: 32)
        let expected = Picker.pick(from: 0, direction: .l, windows: base)
        for _ in 0..<100 {
            let jittered = base.map { w in
                PickerWindow(id: w.id,
                    rect: PickerRect(x: w.rect.x + (rng.unit() * 6 - 3), y: w.rect.y + (rng.unit() * 6 - 3), width: w.rect.width, height: w.rect.height),
                    layer: w.layer, mru: w.mru, coverage: w.coverage)
            }
            #expect(Picker.pick(from: 0, direction: .l, windows: jittered) == expected)
        }
    }

    @Test func reversibilityOnGeneratedSeparatedPairs() {
        var rng = SplitMix64(state: 33)
        for id in 0..<100 {
            let x = Double((id + 1) * 160)
            let windows = [
                PickerWindow(id: id, rect: PickerRect(x: 0, y: 0, width: 100, height: 100), layer: 0, mru: 0, coverage: 0),
                PickerWindow(id: id + 1000, rect: PickerRect(x: x, y: rng.unit() * 3, width: 100, height: 100), layer: 0, mru: 1, coverage: 0)
            ]
            if let target = Picker.pick(from: id, direction: .l, windows: windows) {
                #expect(Picker.pick(from: target, direction: .h, windows: windows) == id)
            }
        }
    }
    @Test func approvedThreeWindowTiePrefersCameFrom() {
        let windows = [
            PickerWindow(id: 1, rect: PickerRect(x: 0, y: 0, width: 100, height: 100), layer: 0, mru: 0, coverage: 0),
            PickerWindow(id: 2, rect: PickerRect(x: 120, y: 0, width: 100, height: 100), layer: 0, mru: 1, coverage: 0),
            PickerWindow(id: 0, rect: PickerRect(x: 0, y: 0, width: 100, height: 100), layer: 0, mru: 10, coverage: 0),
        ]
        #expect(Picker.pick(from: 1, direction: .l, windows: windows) == 2)
        #expect(Picker.pick(from: 2, direction: .h, windows: windows) == 0)
        #expect(Picker.pick(from: 2, direction: .h, cameFrom: 1,
                            windows: windows, screenBounds: testScreenBounds) == 1)
    }

    @Test func mruPrecedesPerpendicularOffsetWithinScoreBucket() {
        let windows = [
            PickerWindow(id: 0, rect: PickerRect(x: 0, y: 0, width: 100, height: 100), layer: 0, mru: 0, coverage: 0),
            PickerWindow(id: 1, rect: PickerRect(x: 120, y: 0, width: 100, height: 100), layer: 0, mru: 1, coverage: 0),
            PickerWindow(id: 2, rect: PickerRect(x: 120, y: 16, width: 100, height: 100), layer: 0, mru: 2, coverage: 0),
        ]
        #expect(Picker.pick(from: 0, direction: .l, windows: windows) == 2)
    }
    @Test func reachabilityOfEveryEligibleNeighbor() {
        let windows = grid() + [
            PickerWindow(id: 4, rect: PickerRect(x: -160, y: 0, width: 100, height: 100), layer: 0, mru: 4, coverage: 0),
            PickerWindow(id: 5, rect: PickerRect(x: 0, y: -160, width: 100, height: 100), layer: 0, mru: 5, coverage: 0),
        ]
        for direction in [PickDirection.h, .j, .k, .l] {
            let chosen = Picker.pick(from: 0, direction: direction, windows: windows)
            #expect(chosen != nil && chosen != 0)
        }
    }

    @Test func totalityWithDenseOverlappingLayouts() {
        for count in 1...100 {
            let windows = (0..<count).map { id in
                PickerWindow(id: id, rect: PickerRect(x: Double(id % 5), y: Double(id % 7), width: 100, height: 100),
                             layer: id % 2, mru: id, coverage: id % 11 == 0 ? 0.9 : 0)
            }
            for d in [PickDirection.h, .j, .k, .l] {
                let result = Picker.pick(from: 0, direction: d, windows: windows)
                #expect(result != 0)
            }
        }
    }

    @Test func chordEqualsSequenceOnPlainGrid() {
        let windows = [
            PickerWindow(id: 0, rect: PickerRect(x: 0, y: 0, width: 100, height: 100), layer: 0, mru: 0, coverage: 0),
            PickerWindow(id: 1, rect: PickerRect(x: -160, y: 0, width: 100, height: 100), layer: 0, mru: 1, coverage: 0),
            PickerWindow(id: 2, rect: PickerRect(x: -160, y: -160, width: 100, height: 100), layer: 0, mru: 2, coverage: 0),
        ]
        let chord = Picker.pick(from: 0, direction: PickDirection(x: -1, y: -1), windows: windows)
        let left = Picker.pick(from: 0, direction: .h, windows: windows)
        let sequence = left.flatMap { Picker.pick(from: $0, direction: .k, windows: windows) }
        #expect(chord == 2)
        #expect(sequence == 2)
        #expect(chord == sequence)
    }

    @Test func beamUsesRectangleIntersectionOnBothAxes() {
        let windows = [
            PickerWindow(id: 0, rect: PickerRect(x: 0, y: 0, width: 100, height: 100), layer: 0, mru: 0, coverage: 0),
            PickerWindow(id: 1, rect: PickerRect(x: 120, y: 30, width: 100, height: 100), layer: 0, mru: 0, coverage: 0),
            PickerWindow(id: 2, rect: PickerRect(x: 136, y: -5, width: 100, height: 100), layer: 0, mru: 10, coverage: 0),
        ]
        #expect(Picker.pick(from: 0, direction: .l, windows: windows) == 1)
        let vertical = windows.map { window in
            PickerWindow(id: window.id,
                         rect: PickerRect(x: window.rect.y, y: window.rect.x,
                                          width: window.rect.height, height: window.rect.width),
                         layer: window.layer, mru: window.mru, coverage: window.coverage)
        }
        #expect(Picker.pick(from: 0, direction: .j, windows: vertical) == 1)
    }

    @Test func zFallbackUsesSnappedRectangles() {
        let windows = [
            PickerWindow(id: 0, rect: PickerRect(x: 0, y: 0, width: 100, height: 100), layer: 0, mru: 0, coverage: 0),
            PickerWindow(id: 1, rect: PickerRect(x: 95.1, y: 10, width: 100, height: 100), layer: 1, mru: 1, coverage: 0),
            PickerWindow(id: 2, rect: PickerRect(x: 95.4, y: 10, width: 100, height: 100), layer: 1, mru: 2, coverage: 0),
        ]
        #expect(Picker.pick(from: 0, direction: .k, windows: windows) == 2)
    }

    @Test func zFallbackTiesAreOrderIndependent() {
        let origin = PickerWindow(id: 0, rect: PickerRect(x: 0, y: 0, width: 100, height: 100),
                                  layer: 0, mru: 0, coverage: 0)
        let floats = [
            PickerWindow(id: 2, rect: PickerRect(x: 0, y: 0, width: 100, height: 100),
                         layer: 1, mru: 1, coverage: 0),
            PickerWindow(id: 1, rect: PickerRect(x: 0, y: 0, width: 100, height: 100),
                         layer: 1, mru: 1, coverage: 0),
        ]
        for windows in [[origin] + floats, [origin] + Array(floats.reversed())] {
            #expect(Picker.pick(from: 0, direction: .k, windows: windows) == 1)
        }

        let tiles = [
            PickerWindow(id: 4, rect: PickerRect(x: 0, y: 0, width: 100, height: 100),
                         layer: 0, mru: 1, coverage: 0),
            PickerWindow(id: 3, rect: PickerRect(x: 0, y: 0, width: 100, height: 100),
                         layer: 0, mru: 1, coverage: 0),
        ]
        let floatingOrigin = PickerWindow(id: 0, rect: PickerRect(x: 0, y: 0, width: 100, height: 100),
                                          layer: 1, mru: 0, coverage: 0)
        for windows in [[floatingOrigin] + tiles, [floatingOrigin] + Array(tiles.reversed())] {
            #expect(Picker.pick(from: 0, direction: .j, windows: windows) == 3)
        }
    }

    @Test func zeroVectorCancelDoesNotChangeFocus() {
        #expect(Picker.pick(from: 0, direction: PickDirection(x: 0, y: 0), windows: grid()) == nil)
        #expect(Picker.pick(from: 0, direction: PickDirection(x: 0, y: 0), windows: grid()) == nil)
    }

    @Test func beamPrefersStraightOverNearerDiagonalCone() {
        let windows = [
            PickerWindow(id: 0, rect: PickerRect(x: 0, y: 0, width: 100, height: 100), layer: 0, mru: 0, coverage: 0),
            PickerWindow(id: 1, rect: PickerRect(x: 120, y: 120, width: 100, height: 100), layer: 0, mru: 1, coverage: 0),
            PickerWindow(id: 2, rect: PickerRect(x: 200, y: 0, width: 100, height: 100), layer: 0, mru: 0, coverage: 0),
        ]
        #expect(Picker.pick(from: 0, direction: .l, windows: windows) == 2)
    }

    @Test func coneSelectsDirectionalCandidateOutsideBeam() {
        let windows = [
            PickerWindow(id: 0, rect: PickerRect(x: 0, y: 0, width: 100, height: 100), layer: 0, mru: 0, coverage: 0),
            PickerWindow(id: 1, rect: PickerRect(x: 160, y: 120, width: 100, height: 100), layer: 0, mru: 0, coverage: 0),
        ]
        #expect(Picker.pick(from: 0, direction: .l, windows: windows) == 1)
    }

    @Test func sameLayerWinsWithinScoreBucketAndCoveredCandidatesAreSkipped() {
        let windows = [
            PickerWindow(id: 0, rect: PickerRect(x: 0, y: 0, width: 100, height: 100), layer: 0, mru: 0, coverage: 0),
            PickerWindow(id: 1, rect: PickerRect(x: 120, y: 0, width: 100, height: 100), layer: 1, mru: 20, coverage: 0),
            PickerWindow(id: 2, rect: PickerRect(x: 128, y: 0, width: 100, height: 100), layer: 0, mru: 0, coverage: 0),
            PickerWindow(id: 3, rect: PickerRect(x: 112, y: 0, width: 100, height: 100), layer: 0, mru: 100, coverage: 0.8),
        ]
        #expect(Picker.pick(from: 0, direction: .l, windows: windows) == 2)
    }
    @Test func reciprocityDoesNotOverrideUnequalDistanceWithinBucket() {
        let windows = [
            PickerWindow(id: 1, rect: PickerRect(x: 0, y: 0, width: 100, height: 100), layer: 0, mru: 1, coverage: 0),
            PickerWindow(id: 2, rect: PickerRect(x: 120, y: 0, width: 100, height: 100), layer: 0, mru: 0, coverage: 0),
            PickerWindow(id: 0, rect: PickerRect(x: -8, y: 0, width: 100, height: 100), layer: 0, mru: 20, coverage: 0),
            PickerWindow(id: 3, rect: PickerRect(x: 120, y: 500, width: 100, height: 100), layer: 0, mru: 0, coverage: 0),
        ]
        #expect(Picker.pick(from: 2, direction: .h, cameFrom: 1,
                            windows: windows, screenBounds: testScreenBounds) == 0)
    }



    @Test func diagonalTieUsesScreenCornerDistance() {
        let windows = [
            PickerWindow(id: 0, rect: PickerRect(x: 0, y: 0, width: 100, height: 100), layer: 0, mru: 0, coverage: 0),
            PickerWindow(id: 1, rect: PickerRect(x: 120, y: 120, width: 100, height: 100), layer: 0, mru: 0, coverage: 0),
            PickerWindow(id: 2, rect: PickerRect(x: 128, y: 112, width: 100, height: 100), layer: 0, mru: 0, coverage: 0),
        ]
        #expect(Picker.pick(from: 0, direction: PickDirection(x: 1, y: 1),
                            windows: windows,
                            screenBounds: PickerRect(x: 0, y: 0, width: 300, height: 300)) == 1)
    }
}
private let testScreenBounds = PickerRect(x: -10_000, y: -10_000, width: 20_000, height: 20_000)

private extension Picker {
    static func pick(from originID: Int, direction: PickDirection,
                     windows: [PickerWindow]) -> Int? {
        pick(from: originID, direction: direction, windows: windows, screenBounds: testScreenBounds)
    }
}
