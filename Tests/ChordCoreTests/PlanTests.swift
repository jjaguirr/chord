import Foundation
import Testing
@testable import ChordCore

@Suite("Plan types")
struct PlanTests {
    private func decode(_ json: String) throws -> Plan {
        try JSONDecoder().decode(Plan.self, from: Data(json.utf8))
    }

    private func plan(_ assignments: Assignment...) throws -> Plan {
        try Plan(assignments: assignments)
    }

    @Test func unknownWindowIsRejected() throws {
        let p = try plan(Assignment(windowID: 2, place: .bench, reason: .pinned))
        #expect(throws: PlanError.unknownWindow(2)) {
            try p.validate(knownWindows: [1])
        }
    }

    @Test func duplicateWindowIsRejectedAtConstruction() {
        #expect(throws: PlanError.duplicateWindow(1)) {
            try Plan(assignments: [
                Assignment(windowID: 1, place: .bench, reason: .pinned),
                Assignment(windowID: 1, place: .workspace(.two), reason: .appRule),
            ])
        }
    }

    @Test func duplicateWindowIsRejectedWhenDecoded() {
        let json = """
            {"assignments":[
              {"window":1,"place":"bench","reason":"pinned"},
              {"window":1,"place":3,"reason":"remembered"}]}
            """
        #expect(throws: (any Error).self) { try decode(json) }
    }

    @Test func malformedDecodeFallsBackToRulesAndBench() throws {
        let rules = [Assignment(windowID: 2, place: .workspace(.three), reason: .pinned)]
        let decodedOrNil = try? decode("{\"assignments\": [oops")
        let result = Plan.acceptingOrFallingBack(
            decodedOrNil, knownWindows: [3, 1, 2], rules: rules)
        #expect(
            result.assignments == [
                Assignment(windowID: 1, place: .bench, reason: .inferred(confidence: 0)),
                Assignment(windowID: 2, place: .workspace(.three), reason: .pinned),
                Assignment(windowID: 3, place: .bench, reason: .inferred(confidence: 0)),
            ])
    }

    @Test func decodedPlanNamingUnknownWindowFallsBack() throws {
        let decoded = try decode(
            #"{"assignments":[{"window":9,"place":2,"reason":"appRule"}]}"#)
        let result = Plan.acceptingOrFallingBack(decoded, knownWindows: [1], rules: [])
        #expect(result == Plan.fallback(knownWindows: [1], rules: []))
    }

    @Test func validDecodedPlanIsAccepted() throws {
        let decoded = try decode(
            #"{"assignments":[{"window":1,"place":4,"reason":{"inferred":0.75}}]}"#)
        let result = Plan.acceptingOrFallingBack(decoded, knownWindows: [1], rules: [])
        #expect(
            result.assignments == [
                Assignment(windowID: 1, place: .workspace(.four), reason: .inferred(confidence: 0.75))
            ])
    }

    @Test func planNamingWorkspaceNineCannotBeDecoded() {
        let numeric = #"{"assignments":[{"window":1,"place":9,"reason":"pinned"}]}"#
        let named = #"{"assignments":[{"window":1,"place":"vault","reason":"pinned"}]}"#
        #expect(throws: (any Error).self) { try decode(numeric) }
        #expect(throws: (any Error).self) { try decode(named) }
        #expect(Workspace(rawValue: 9) == nil)
    }

    @Test func unknownKeysAreRejected() {
        let topLevel = #"{"assignments":[],"extra":1}"#
        let inner = #"{"assignments":[{"window":1,"place":"bench","reason":"pinned","x":true}]}"#
        #expect(throws: (any Error).self) { try decode(topLevel) }
        #expect(throws: (any Error).self) { try decode(inner) }
    }

    @Test func confidenceOutsideUnitIntervalIsRejected() {
        let high = #"{"assignments":[{"window":1,"place":"bench","reason":{"inferred":1.5}}]}"#
        #expect(throws: (any Error).self) { try decode(high) }
        #expect(throws: PlanError.invalidConfidence(windowID: 1)) {
            try Plan(assignments: [
                Assignment(windowID: 1, place: .bench, reason: .inferred(confidence: -0.1))
            ])
        }
    }

    @Test func encodeThenDecodeRoundTrips() throws {
        let original = try plan(
            Assignment(windowID: 1, place: .bench, reason: .remembered),
            Assignment(windowID: 2, place: .workspace(.eight), reason: .inferred(confidence: 0.5)),
            Assignment(windowID: 3, place: .workspace(.one), reason: .appRule),
        )
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(Plan.self, from: data) == original)
    }

    @Test func actionsSkipWindowsAlreadyInPlace() throws {
        let p = try plan(
            Assignment(windowID: 1, place: .workspace(.two), reason: .pinned),
            Assignment(windowID: 2, place: .bench, reason: .pinned),
        )
        let actions = try p.actions(from: [1: .workspace(.two), 2: .workspace(.five)])
        #expect(actions == [.place(windowID: 2, from: .workspace(.five), to: .bench)])
    }

    @Test func actionsRejectUnknownWindow() throws {
        let p = try plan(Assignment(windowID: 7, place: .bench, reason: .pinned))
        #expect(throws: PlanError.unknownWindow(7)) {
            try p.actions(from: [1: .bench])
        }
    }

    @Test func everyActionInverseRestoresModel() throws {
        let before: [Int: Place] = [1: .bench, 2: .workspace(.four), 3: .workspace(.one)]
        let p = try plan(
            Assignment(windowID: 1, place: .workspace(.six), reason: .pinned),
            Assignment(windowID: 2, place: .bench, reason: .remembered),
            Assignment(windowID: 3, place: .workspace(.one), reason: .appRule),
        )
        let actions = try p.actions(from: before)
        #expect(actions.count == 2)

        var model = before
        for action in actions { #expect(action.apply(to: &model)) }
        #expect(model != before)

        for action in actions.reversed() { #expect(action.inverse.apply(to: &model)) }
        #expect(model == before)
    }

    @Test func staleActionDoesNotChangeModel() {
        let action = Action.place(windowID: 1, from: .bench, to: .workspace(.two))
        var model: [Int: Place] = [1: .workspace(.three)]

        #expect(!action.apply(to: &model))
        #expect(model == [1: .workspace(.three)])
        #expect(!action.inverse.apply(to: &model))
        #expect(model == [1: .workspace(.three)])
    }

    @Test func inverseOfInverseIsOriginal() {
        let action = Action.place(windowID: 4, from: .bench, to: .workspace(.seven))
        #expect(action.inverse.inverse == action)
    }

    @Test func planWhitelistsFrameFocusAndRestoreHomeActions() throws {
        let frame = ActionRect(x: 0, y: 0, width: 333, height: 471)
        let larger = ActionRect(x: 10, y: 20, width: 500, height: 300)
        let home = WindowHome(place: .bench, frame: frame)
        let target = WindowHome(place: .workspace(.two), frame: larger)
        let requests: [Action] = [
            .frame(windowID: 1, from: frame, to: larger),
            .focus(from: 2, to: 1),
            .restoreHome(windowID: 1, from: home, to: target),
        ]
        let actions = try Plan(assignments: []).actions(from: [1: .bench, 2: .workspace(.two)], requested: requests)

        #expect(actions == requests)
        #expect(actions.allSatisfy { $0.inverse.inverse == $0 })
        #expect(actions[0].logLine == "frame window 1: (0.0, 0.0, 333.0, 471.0) -> (10.0, 20.0, 500.0, 300.0)")
        #expect(actions[1].logLine == "focus window 1 (was 2)")
        #expect(actions[2].logLine.hasPrefix("restore home for window 1:"))
    }
}
