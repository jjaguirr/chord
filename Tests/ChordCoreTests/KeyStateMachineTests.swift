import Testing
@testable import ChordCore

private let plain = KeyModifiers()
private let shift = KeyModifiers(shift: true)
private let control = KeyModifiers(control: true)

private let mod = KeyModifiers(mod: true)
@Test func modZeroTapHoldBoundaryAndEscape() {
    var machine = KeyStateMachine()
    #expect(machine.process(.down(.zero, repeat: false, modifiers: mod), at: 0).isEmpty)
    #expect(machine.advance(to: 0.699).isEmpty)
    #expect(machine.advance(to: 0.7) == [.spread])
    #expect(machine.process(.down(.zero, repeat: true, modifiers: plain), at: 0.71).isEmpty)
    #expect(machine.process(.up(.zero, modifiers: plain), at: 0.8).isEmpty)
    var tap = KeyStateMachine()
    _ = tap.process(.down(.zero, repeat: false, modifiers: mod), at: 1)
    #expect(tap.process(.up(.zero, modifiers: mod), at: 1.249) == [.unfold])
    var abort = KeyStateMachine()
    _ = abort.process(.down(.zero, repeat: false, modifiers: mod), at: 2)
    #expect(abort.process(.down(.escape, repeat: false, modifiers: plain), at: 2.1) == [.abortCharge])
    #expect(abort.advance(to: 3).isEmpty)
}

@Test func directionRepeatIsIgnoredAndRollDiffersFromChord() {
    var roll = KeyStateMachine()
    #expect(roll.process(.down(.h, repeat: false, modifiers: plain), at: 0).isEmpty)
    #expect(roll.process(.down(.h, repeat: true, modifiers: plain), at: 0.01).isEmpty)
    #expect(roll.process(.up(.h, modifiers: plain), at: 0.015) == [.look(.h)])
    #expect(roll.process(.down(.l, repeat: false, modifiers: plain), at: 0.02).isEmpty)
    #expect(roll.process(.up(.l, modifiers: plain), at: 0.03) == [.look(.l)])
    var chord = KeyStateMachine()
    _ = chord.process(.down(.h, repeat: false, modifiers: plain), at: 1)
    #expect(chord.process(.down(.j, repeat: false, modifiers: plain), at: 1.02)
        == [.look(PickDirection(x: -1, y: 1))])
}

@Test func delayedDirectionsAndRestingFingerDoNotInventChords() {
    var machine = KeyStateMachine()
    _ = machine.process(.down(.h, repeat: false, modifiers: plain), at: 0)
    #expect(machine.advance(to: 0.036) == [.look(.h)])
    _ = machine.process(.down(.l, repeat: false, modifiers: plain), at: 1)
    _ = machine.process(.up(.l, modifiers: plain), at: 1.01)
    #expect(machine.process(.down(.j, repeat: false, modifiers: plain), at: 1.02).isEmpty)
    #expect(machine.process(.up(.j, modifiers: plain), at: 1.03) == [.look(.j)])
}

@Test func carryRampDiagonalAndIndependentEdgeMagnets() {
    var machine = KeyStateMachine()
    #expect(machine.process(.down(.l, repeat: false, modifiers: shift), at: 0) == [.carry(dx: 10, dy: 0)])
    #expect(machine.advance(to: 0.1) == [.carry(dx: 20, dy: 0)])
    #expect(machine.advance(to: 0.2) == [.carry(dx: 30, dy: 0)])
    _ = machine.process(.up(.l, modifiers: shift), at: 0.21)
    let diagonal = machine.carry(vector: PickDirection(x: 1, y: -1), ticks: 1,
        rect: PickerRect(x: 475, y: 5, width: 20, height: 20),
        edges: KeyStateMachine.Edges(left: 0, right: 500, top: 0, bottom: 500))
    #expect(diagonal.dx == 5)
    #expect(diagonal.dy == -5)
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
    #expect(controlled.process(.down(.h, repeat: false, modifiers: control), at: 0)
        == [.reshape(aspectDelta: -0.05, areaDelta: 0)])
}
