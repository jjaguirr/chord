import Foundation
import Testing

@testable import ChordCore

private let plain = KeyModifiers()
private let shift = KeyModifiers(shift: true)
private let mod = KeyModifiers(mod: true)
private let testRect = PickerRect(x: 100, y: 100, width: 40, height: 40)
private let testEdges = KeyStateMachine.Edges(left: 0, right: 500, top: 0, bottom: 500)

@Test func modZeroTapHoldBoundaryAndEscape() {
  var machine = KeyStateMachine()
  #expect(
    machine.process(
      .down(.zero, repeat: false, modifiers: mod), at: 0, rect: testRect, edges: testEdges
    ).isEmpty)
  #expect(machine.advance(to: 0.699, rect: testRect, edges: testEdges).isEmpty)
  #expect(machine.advance(to: 0.7, rect: testRect, edges: testEdges) == [.spread])
  #expect(
    machine.process(
      .down(.zero, repeat: true, modifiers: plain), at: 0.71, rect: testRect, edges: testEdges
    ).isEmpty)
  #expect(
    machine.process(.up(.zero, modifiers: plain), at: 0.8, rect: testRect, edges: testEdges).isEmpty
  )
  var releaseOnly = KeyStateMachine()
  _ = releaseOnly.process(
    .down(.zero, repeat: false, modifiers: mod), at: 1, rect: testRect, edges: testEdges)
  #expect(
    releaseOnly.process(.up(.zero, modifiers: mod), at: 1.8, rect: testRect, edges: testEdges) == [
      .spread
    ])
  var tap = KeyStateMachine()
  _ = tap.process(
    .down(.zero, repeat: false, modifiers: mod), at: 1, rect: testRect, edges: testEdges)
  #expect(
    tap.process(.up(.zero, modifiers: mod), at: 1.249, rect: testRect, edges: testEdges) == [
      .unfold
    ])
  var abort = KeyStateMachine()
  _ = abort.process(
    .down(.zero, repeat: false, modifiers: mod), at: 2, rect: testRect, edges: testEdges)
  #expect(
    abort.process(
      .down(.escape, repeat: false, modifiers: plain), at: 2.1, rect: testRect, edges: testEdges)
      == [.abortCharge])
  #expect(abort.advance(to: 3, rect: testRect, edges: testEdges).isEmpty)
}

@Test func directionRepeatIsIgnoredAndRollDiffersFromChord() {
  var roll = KeyStateMachine()
  #expect(
    roll.process(
      .down(.h, repeat: false, modifiers: plain), at: 0, rect: testRect, edges: testEdges
    ).isEmpty)
  #expect(
    roll.process(
      .down(.h, repeat: true, modifiers: plain), at: 0.01, rect: testRect, edges: testEdges
    ).isEmpty)
  #expect(
    roll.process(.up(.h, modifiers: plain), at: 0.015, rect: testRect, edges: testEdges) == [
      .look(.h)
    ])
  #expect(
    roll.process(
      .down(.l, repeat: false, modifiers: plain), at: 0.02, rect: testRect, edges: testEdges
    ).isEmpty)
  #expect(
    roll.process(.up(.l, modifiers: plain), at: 0.03, rect: testRect, edges: testEdges) == [
      .look(.l)
    ])
  var chord = KeyStateMachine()
  _ = chord.process(
    .down(.h, repeat: false, modifiers: plain), at: 1, rect: testRect, edges: testEdges)
  #expect(
    chord.process(
      .down(.j, repeat: false, modifiers: plain), at: 1.02, rect: testRect, edges: testEdges)
      == [.look(PickDirection(x: -1, y: 1))])
}

@Test func oppositeDirectionChordsCancelWithoutLookIntents() {
  for (first, second) in [(ChordKey.h, ChordKey.l), (.k, .j)] {
    var machine = KeyStateMachine()
    #expect(
      machine.process(
        .down(first, repeat: false, modifiers: plain), at: 0, rect: testRect, edges: testEdges
      ).isEmpty)
    #expect(
      machine.process(
        .down(second, repeat: false, modifiers: plain), at: 0.02, rect: testRect, edges: testEdges
      ).isEmpty)
    #expect(
      machine.process(.up(first, modifiers: plain), at: 0.03, rect: testRect, edges: testEdges)
        .isEmpty)
    #expect(
      machine.process(.up(second, modifiers: plain), at: 0.04, rect: testRect, edges: testEdges)
        .isEmpty)
  }
}

@Test func delayedDirectionsAndRestingFingerDoNotInventChords() {
  var machine = KeyStateMachine()
  _ = machine.process(
    .down(.h, repeat: false, modifiers: plain), at: 0, rect: testRect, edges: testEdges)
  #expect(machine.advance(to: 0.036, rect: testRect, edges: testEdges) == [.look(.h)])
  _ = machine.process(
    .down(.l, repeat: false, modifiers: plain), at: 1, rect: testRect, edges: testEdges)
  _ = machine.process(.up(.l, modifiers: plain), at: 1.01, rect: testRect, edges: testEdges)
  #expect(
    machine.process(
      .down(.j, repeat: false, modifiers: plain), at: 1.02, rect: testRect, edges: testEdges
    ).isEmpty)
  #expect(
    machine.process(.up(.j, modifiers: plain), at: 1.03, rect: testRect, edges: testEdges) == [
      .look(.j)
    ])
}

@Test func carryEmissionsSnapAndTrackHeldDiagonalDirections() {
  var snapped = KeyStateMachine()
  let nearRight = PickerRect(x: 475, y: 100, width: 20, height: 20)
  #expect(
    snapped.process(
      .down(.l, repeat: false, modifiers: shift), at: 0, rect: nearRight, edges: testEdges) == [
        .carry(dx: 5, dy: 0)
      ])
  #expect(snapped.advance(to: 0.1, rect: nearRight, edges: testEdges) == [.carry(dx: 5, dy: 0)])

  var diagonal = KeyStateMachine()
  #expect(
    diagonal.process(
      .down(.h, repeat: false, modifiers: shift), at: 0, rect: testRect, edges: testEdges) == [
        .carry(dx: -10, dy: 0)
      ])
  #expect(
    diagonal.process(
      .down(.j, repeat: false, modifiers: shift), at: 0.01, rect: testRect, edges: testEdges) == [
        .carry(dx: -10, dy: 10)
      ])
  #expect(diagonal.advance(to: 0.11, rect: testRect, edges: testEdges) == [.carry(dx: -20, dy: 20)])
  _ = diagonal.process(.up(.h, modifiers: shift), at: 0.12, rect: testRect, edges: testEdges)
  #expect(diagonal.advance(to: 0.21, rect: testRect, edges: testEdges) == [.carry(dx: 0, dy: 30)])
  _ = diagonal.process(.up(.j, modifiers: shift), at: 0.22, rect: testRect, edges: testEdges)
  #expect(diagonal.advance(to: 0.32, rect: testRect, edges: testEdges).isEmpty)
}

@Test func opposingCarryDirectionsCancelUntilOneKeyIsReleased() {
  var machine = KeyStateMachine()
  #expect(
    machine.process(
      .down(.h, repeat: false, modifiers: shift), at: 0, rect: testRect, edges: testEdges)
      == [.carry(dx: -10, dy: 0)])
  #expect(
    machine.process(
      .down(.l, repeat: false, modifiers: shift), at: 0.01, rect: testRect, edges: testEdges
    ).isEmpty)
  #expect(machine.advance(to: 0.11, rect: testRect, edges: testEdges).isEmpty)
  _ = machine.process(.up(.h, modifiers: shift), at: 0.12, rect: testRect, edges: testEdges)
  #expect(machine.advance(to: 0.21, rect: testRect, edges: testEdges) == [.carry(dx: 30, dy: 0)])
  _ = machine.process(.up(.l, modifiers: shift), at: 0.22, rect: testRect, edges: testEdges)
  #expect(machine.advance(to: 0.32, rect: testRect, edges: testEdges).isEmpty)
}

@Test func reshapeUsesLogSpaceAndOptionRMapping() {
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
  var reshaping = KeyStateMachine()
  #expect(
    reshaping.process(.down(.r, repeat: false, modifiers: mod), at: 0, rect: testRect, edges: testEdges)
      .isEmpty)
  for (key, aspectDelta, areaDelta) in [
    (ChordKey.h, -0.05, 0.0), (.l, 0.05, 0), (.j, 0, 0.05), (.k, 0, -0.05),
  ] {
    #expect(
      reshaping.process(.down(key, repeat: false, modifiers: mod), at: 0.1, rect: testRect, edges: testEdges)
        == [.reshape(aspectDelta: aspectDelta, areaDelta: areaDelta)])
    _ = reshaping.process(.up(key, modifiers: mod), at: 0.2, rect: testRect, edges: testEdges)
  }
}

@Test func reshapeNeedsOptionAndRHeldAndStopsWhenRIsReleased() {
  var noR = KeyStateMachine()
  _ = noR.process(.down(.h, repeat: false, modifiers: mod), at: 0, rect: testRect, edges: testEdges)
  #expect(noR.advance(to: 1, rect: testRect, edges: testEdges) == [.look(.h)])

  var noOption = KeyStateMachine()
  _ = noOption.process(.down(.r, repeat: false, modifiers: plain), at: 0, rect: testRect, edges: testEdges)
  #expect(
    !noOption.process(.down(.h, repeat: false, modifiers: plain), at: 0.1, rect: testRect, edges: testEdges)
      .contains { if case .reshape = $0 { true } else { false } })

  var released = KeyStateMachine()
  _ = released.process(.down(.r, repeat: false, modifiers: mod), at: 0, rect: testRect, edges: testEdges)
  #expect(
    released.process(.down(.l, repeat: false, modifiers: mod), at: 0.1, rect: testRect, edges: testEdges)
      == [.reshape(aspectDelta: 0.05, areaDelta: 0)])
  _ = released.process(.up(.l, modifiers: mod), at: 0.2, rect: testRect, edges: testEdges)
  _ = released.process(.up(.r, modifiers: mod), at: 0.3, rect: testRect, edges: testEdges)
  _ = released.process(.down(.l, repeat: false, modifiers: mod), at: 0.4, rect: testRect, edges: testEdges)
  #expect(
    released.process(.up(.l, modifiers: mod), at: 0.45, rect: testRect, edges: testEdges) == [.look(.l)])
}

@Test func plainLookIsUnaffectedByReshapeMode() {
  var machine = KeyStateMachine()
  _ = machine.process(.down(.h, repeat: false, modifiers: plain), at: 0, rect: testRect, edges: testEdges)
  #expect(
    machine.process(.up(.h, modifiers: plain), at: 0.05, rect: testRect, edges: testEdges) == [.look(.h)])
}

@Test func aFreshCarryPressAtAnEdgeCrossesButHeldRepeatsDoNot() {
  var machine = KeyStateMachine()
  let flushRight = PickerRect(x: 460, y: 100, width: 40, height: 40)
  #expect(
    machine.process(.down(.l, repeat: false, modifiers: shift), at: 0, rect: flushRight, edges: testEdges)
      == [.carryAcross(PickDirection(x: 1, y: 0), dx: 0, dy: 0)])
  #expect(machine.advance(to: 0.1, rect: flushRight, edges: testEdges) == [.carry(dx: 0, dy: 0)])

  // Not yet flush (outside the magnet's reach too): an ordinary carry.
  var inside = KeyStateMachine()
  #expect(
    inside.process(.down(.l, repeat: false, modifiers: shift), at: 0, rect: testRect, edges: testEdges)
      == [.carry(dx: 10, dy: 0)])
}

@Test func aDiagonalPressFlushOnOneAxisCarriesTheOrdinaryStepAsTheFallback() {
  var machine = KeyStateMachine()
  let flushRight = PickerRect(x: 460, y: 100, width: 40, height: 40)
  _ = machine.process(.down(.l, repeat: false, modifiers: shift), at: 0, rect: testRect, edges: testEdges)
  let intents = machine.process(
    .down(.j, repeat: false, modifiers: shift), at: 0.01, rect: flushRight, edges: testEdges)
  #expect(intents == [.carryAcross(PickDirection(x: 1, y: 0), dx: 0, dy: 10)])
}

// MARK: Option+W workspace layer

private func tapKey(
  _ machine: inout KeyStateMachine, _ key: ChordKey, _ modifiers: KeyModifiers, at time: Double
) -> [KeyIntent] {
  let down = machine.process(
    .down(key, repeat: false, modifiers: modifiers), at: time, rect: testRect, edges: testEdges)
  let up = machine.process(.up(key, modifiers: modifiers), at: time + 0.01, rect: testRect, edges: testEdges)
  return down + up
}

private func holdWorkspaceLayer(_ machine: inout KeyStateMachine, at time: Double = 0) {
  #expect(
    machine.process(.down(.w, repeat: false, modifiers: mod), at: time, rect: testRect, edges: testEdges)
      .isEmpty)
}

@Test func whileWIsHeldHjklStepTheGridAndShiftCarriesTheWindowAlong() {
  var machine = KeyStateMachine()
  holdWorkspaceLayer(&machine)
  // h/l are columns, k/j are rows: j is the next row (down), k the previous (up).
  for (key, step) in [
    (ChordKey.h, GridStep.left), (.l, .right), (.j, .down), (.k, .up),
  ] {
    #expect(tapKey(&machine, key, mod, at: 0.1) == [.stepWorkspace(step)])
    #expect(
      tapKey(&machine, key, KeyModifiers(shift: true, mod: true), at: 0.2) == [.carryStepWorkspace(step)])
  }
  // Nothing in the layer is a Look or a carry step, and nothing waits to flush later.
  #expect(machine.advance(to: 5, rect: testRect, edges: testEdges).isEmpty)
}

@Test func releasingWEndsTheLayerAndHjklLookAgain() {
  var machine = KeyStateMachine()
  holdWorkspaceLayer(&machine)
  #expect(tapKey(&machine, .l, mod, at: 0.1) == [.stepWorkspace(.right)])
  #expect(machine.process(.up(.w, modifiers: mod), at: 0.2, rect: testRect, edges: testEdges).isEmpty)

  _ = machine.process(.down(.l, repeat: false, modifiers: mod), at: 0.3, rect: testRect, edges: testEdges)
  #expect(machine.process(.up(.l, modifiers: mod), at: 0.32, rect: testRect, edges: testEdges) == [.look(.l)])
}

@Test func theLayerNeedsOptionWhenWIsPressed() {
  var machine = KeyStateMachine()
  _ = machine.process(.down(.w, repeat: false, modifiers: plain), at: 0, rect: testRect, edges: testEdges)
  _ = machine.process(.down(.l, repeat: false, modifiers: mod), at: 0.1, rect: testRect, edges: testEdges)
  #expect(machine.process(.up(.l, modifiers: mod), at: 0.12, rect: testRect, edges: testEdges) == [.look(.l)])
}

@Test func keyRepeatNeitherReArmsTheLayerNorRepeatsAStep() {
  var machine = KeyStateMachine()
  holdWorkspaceLayer(&machine)
  // A held W auto-repeats; a held l does too. Neither does anything.
  #expect(
    machine.process(.down(.w, repeat: true, modifiers: mod), at: 0.5, rect: testRect, edges: testEdges)
      .isEmpty)
  #expect(
    machine.process(.down(.l, repeat: false, modifiers: mod), at: 0.6, rect: testRect, edges: testEdges)
      == [.stepWorkspace(.right)])
  for time in [0.7, 0.8, 0.9] {
    #expect(
      machine.process(.down(.l, repeat: true, modifiers: mod), at: time, rect: testRect, edges: testEdges)
        .isEmpty)
  }
  #expect(machine.advance(to: 3, rect: testRect, edges: testEdges).isEmpty)
  _ = machine.process(.up(.l, modifiers: mod), at: 3.1, rect: testRect, edges: testEdges)
  // The layer is still armed after the repeats: a second press steps again.
  #expect(tapKey(&machine, .l, mod, at: 3.2) == [.stepWorkspace(.right)])
}

@Test func escapeCancelsTheLayerUntilWIsReleased() {
  var machine = KeyStateMachine()
  holdWorkspaceLayer(&machine)
  #expect(tapKey(&machine, .j, mod, at: 0.1) == [.stepWorkspace(.down)])
  #expect(tapKey(&machine, .escape, plain, at: 0.2).isEmpty)

  // Cancelled: neither a step, nor a Look or a carry, nor a delayed flush of one.
  #expect(tapKey(&machine, .j, mod, at: 0.3).isEmpty)
  #expect(tapKey(&machine, .j, KeyModifiers(shift: true, mod: true), at: 0.4).isEmpty)
  #expect(machine.advance(to: 5, rect: testRect, edges: testEdges).isEmpty)

  // Releasing W and pressing it again starts a new layer.
  _ = machine.process(.up(.w, modifiers: mod), at: 6, rect: testRect, edges: testEdges)
  holdWorkspaceLayer(&machine, at: 6.1)
  #expect(tapKey(&machine, .j, mod, at: 6.2) == [.stepWorkspace(.down)])
}

@Test func escapeOutsideTheLayerChangesNothingAboutIt() {
  var machine = KeyStateMachine()
  #expect(tapKey(&machine, .escape, plain, at: 0).isEmpty)
  holdWorkspaceLayer(&machine, at: 0.1)
  #expect(tapKey(&machine, .k, mod, at: 0.2) == [.stepWorkspace(.up)])
}

@Test func theLayerStepsOnlyWhileOptionIsHeld() {
  var machine = KeyStateMachine()
  holdWorkspaceLayer(&machine)
  // Option released but W still down: a bare l is an ordinary press, not a workspace step.
  _ = machine.process(.down(.l, repeat: false, modifiers: plain), at: 0.1, rect: testRect, edges: testEdges)
  #expect(machine.process(.up(.l, modifiers: plain), at: 0.12, rect: testRect, edges: testEdges) == [.look(.l)])
}

@Test func theWorkspaceLayerWinsOverAHeldReshapeLayer() {
  var machine = KeyStateMachine()
  _ = machine.process(.down(.r, repeat: false, modifiers: mod), at: 0, rect: testRect, edges: testEdges)
  holdWorkspaceLayer(&machine, at: 0.1)
  #expect(tapKey(&machine, .l, mod, at: 0.2) == [.stepWorkspace(.right)])
  _ = machine.process(.up(.w, modifiers: mod), at: 0.3, rect: testRect, edges: testEdges)
  #expect(tapKey(&machine, .l, mod, at: 0.4) == [.reshape(aspectDelta: 0.05, areaDelta: 0)])
}
