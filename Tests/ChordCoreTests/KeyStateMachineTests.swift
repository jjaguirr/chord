import Foundation
import Testing
@testable import ChordCore

private let plain = KeyModifiers()
private let shift = KeyModifiers(shift: true)
private let control = KeyModifiers(control: true)
private let mod = KeyModifiers(mod: true)
private let testRect = PickerRect(x: 100, y: 100, width: 40, height: 40)
private let testEdges = KeyStateMachine.Edges(left: 0, right: 500, top: 0, bottom: 500)

@Test func modZeroTapHoldBoundaryAndEscape() {
    var machine = KeyStateMachine()
    #expect(machine.process(.down(.zero, repeat: false, modifiers: mod), at: 0, rect: testRect, edges: testEdges).isEmpty)
    #expect(machine.advance(to: 0.699, rect: testRect, edges: testEdges).isEmpty)
    #expect(machine.advance(to: 0.7, rect: testRect, edges: testEdges) == [.spread])
    #expect(machine.process(.down(.zero, repeat: true, modifiers: plain), at: 0.71, rect: testRect, edges: testEdges).isEmpty)
    #expect(machine.process(.up(.zero, modifiers: plain), at: 0.8, rect: testRect, edges: testEdges).isEmpty)
    var releaseOnly = KeyStateMachine()
    _ = releaseOnly.process(.down(.zero, repeat: false, modifiers: mod), at: 1, rect: testRect, edges: testEdges)
    #expect(releaseOnly.process(.up(.zero, modifiers: mod), at: 1.8, rect: testRect, edges: testEdges) == [.spread])
    var tap = KeyStateMachine()
    _ = tap.process(.down(.zero, repeat: false, modifiers: mod), at: 1, rect: testRect, edges: testEdges)
    #expect(tap.process(.up(.zero, modifiers: mod), at: 1.249, rect: testRect, edges: testEdges) == [.unfold])
    var abort = KeyStateMachine()
    _ = abort.process(.down(.zero, repeat: false, modifiers: mod), at: 2, rect: testRect, edges: testEdges)
    #expect(abort.process(.down(.escape, repeat: false, modifiers: plain), at: 2.1, rect: testRect, edges: testEdges) == [.abortCharge])
    #expect(abort.advance(to: 3, rect: testRect, edges: testEdges).isEmpty)
}

@Test func directionRepeatIsIgnoredAndRollDiffersFromChord() {
    var roll = KeyStateMachine()
    #expect(roll.process(.down(.h, repeat: false, modifiers: plain), at: 0, rect: testRect, edges: testEdges).isEmpty)
    #expect(roll.process(.down(.h, repeat: true, modifiers: plain), at: 0.01, rect: testRect, edges: testEdges).isEmpty)
    #expect(roll.process(.up(.h, modifiers: plain), at: 0.015, rect: testRect, edges: testEdges) == [.look(.h)])
    #expect(roll.process(.down(.l, repeat: false, modifiers: plain), at: 0.02, rect: testRect, edges: testEdges).isEmpty)
    #expect(roll.process(.up(.l, modifiers: plain), at: 0.03, rect: testRect, edges: testEdges) == [.look(.l)])
    var chord = KeyStateMachine()
    _ = chord.process(.down(.h, repeat: false, modifiers: plain), at: 1, rect: testRect, edges: testEdges)
    #expect(chord.process(.down(.j, repeat: false, modifiers: plain), at: 1.02, rect: testRect, edges: testEdges)
        == [.look(PickDirection(x: -1, y: 1))])
}

@Test func oppositeDirectionChordsCancelWithoutLookIntents() {
    for (first, second) in [(ChordKey.h, ChordKey.l), (.k, .j)] {
        var machine = KeyStateMachine()
        #expect(machine.process(.down(first, repeat: false, modifiers: plain), at: 0, rect: testRect, edges: testEdges).isEmpty)
        #expect(machine.process(.down(second, repeat: false, modifiers: plain), at: 0.02, rect: testRect, edges: testEdges).isEmpty)
        #expect(machine.process(.up(first, modifiers: plain), at: 0.03, rect: testRect, edges: testEdges).isEmpty)
        #expect(machine.process(.up(second, modifiers: plain), at: 0.04, rect: testRect, edges: testEdges).isEmpty)
    }
}

@Test func delayedDirectionsAndRestingFingerDoNotInventChords() {
    var machine = KeyStateMachine()
    _ = machine.process(.down(.h, repeat: false, modifiers: plain), at: 0, rect: testRect, edges: testEdges)
    #expect(machine.advance(to: 0.036, rect: testRect, edges: testEdges) == [.look(.h)])
    _ = machine.process(.down(.l, repeat: false, modifiers: plain), at: 1, rect: testRect, edges: testEdges)
    _ = machine.process(.up(.l, modifiers: plain), at: 1.01, rect: testRect, edges: testEdges)
    #expect(machine.process(.down(.j, repeat: false, modifiers: plain), at: 1.02, rect: testRect, edges: testEdges).isEmpty)
    #expect(machine.process(.up(.j, modifiers: plain), at: 1.03, rect: testRect, edges: testEdges) == [.look(.j)])
}

@Test func carryEmissionsSnapAndTrackHeldDiagonalDirections() {
    var snapped = KeyStateMachine()
    let nearRight = PickerRect(x: 475, y: 100, width: 20, height: 20)
    #expect(snapped.process(.down(.l, repeat: false, modifiers: shift), at: 0, rect: nearRight, edges: testEdges) == [.carry(dx: 5, dy: 0)])
    #expect(snapped.advance(to: 0.1, rect: nearRight, edges: testEdges) == [.carry(dx: 5, dy: 0)])

    var diagonal = KeyStateMachine()
    #expect(diagonal.process(.down(.h, repeat: false, modifiers: shift), at: 0, rect: testRect, edges: testEdges) == [.carry(dx: -10, dy: 0)])
    #expect(diagonal.process(.down(.j, repeat: false, modifiers: shift), at: 0.01, rect: testRect, edges: testEdges) == [.carry(dx: -10, dy: 10)])
    #expect(diagonal.advance(to: 0.11, rect: testRect, edges: testEdges) == [.carry(dx: -20, dy: 20)])
    _ = diagonal.process(.up(.h, modifiers: shift), at: 0.12, rect: testRect, edges: testEdges)
    #expect(diagonal.advance(to: 0.21, rect: testRect, edges: testEdges) == [.carry(dx: 0, dy: 30)])
    _ = diagonal.process(.up(.j, modifiers: shift), at: 0.22, rect: testRect, edges: testEdges)
    #expect(diagonal.advance(to: 0.32, rect: testRect, edges: testEdges).isEmpty)
}

@Test func reshapeUsesLogSpaceAndControlKeyMapping() {
    let machine = KeyStateMachine()
    let aspect = machine.reshapeDeltas(for: .l)
    let area = machine.reshapeDeltas(for: .j)
    for (width, height) in [(100.0, 80.0), (1000.0, 800.0)] {
        let newAspect = log(width / height) + aspect.aspect
        let newArea = log(width * height) + area.area
        let newWidth = exp((newArea + newAspect) / 2)
        let newHeight = exp((newArea - newAspect) / 2)
        #expect(abs(log(newWidth / newHeight) - newAspect) < 1e-12)
        #expect(abs(log(newWidth * newHeight) - newArea) < 1e-12)
    }
    var controlled = KeyStateMachine()
    #expect(controlled.process(.down(.h, repeat: false, modifiers: control), at: 0, rect: testRect, edges: testEdges)
        == [.reshape(aspectDelta: -0.05, areaDelta: 0)])
}
