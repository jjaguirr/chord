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

    @Test func reachabilityOfEveryEligibleNeighbor() {
        for direction in [PickDirection.h, .j, .k, .l] {
            let windows = grid()
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
        let windows = grid()
        let chord = Picker.pick(from: 0, direction: PickDirection(x: 1, y: -1), windows: windows)
        let right = Picker.pick(from: 0, direction: .l, windows: windows)
        let sequence = right.flatMap { Picker.pick(from: $0, direction: .k, windows: windows) }
        #expect(chord == sequence)
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
}
