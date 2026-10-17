import Testing
@testable import ChordCore

@Suite("reshapedFrame")
struct ReshapeTests {
    private let visible = ActionRect(x: 0, y: 0, width: 1000, height: 800)
    private let minimum = ActionSize(width: 160, height: 120)

    private func reshape(_ rect: ActionRect, aspect: Double = 0, area: Double = 0,
        within: ActionRect? = nil, minimum: ActionSize? = nil) -> ActionRect
    {
        reshapedFrame(rect, aspectDelta: aspect, areaDelta: area, within: within ?? visible,
            minimumSize: minimum ?? self.minimum)
    }

    @Test func areaStepScalesBothSidesAboutTheCenterAndRoundsToIntegers() {
        let out = reshape(ActionRect(x: 100, y: 100, width: 400, height: 300), area: 0.05)
        #expect(out == ActionRect(x: 95, y: 96, width: 410, height: 308))
    }

    @Test func aspectStepKeepsAreaAndMovesAspectInLogSpace() {
        let start = ActionRect(x: 100, y: 100, width: 400, height: 300)
        let out = reshape(start, aspect: 0.2)
        let aspect = naturalLog(out.width / out.height) - naturalLog(start.width / start.height)
        let area = naturalLog(out.width * out.height) - naturalLog(start.width * start.height)
        #expect(abs(aspect - 0.2) < 0.01)
        #expect(abs(area) < 0.01)
    }

    @Test func opposingStepsReturnToTheStartSize() {
        let start = ActionRect(x: 100, y: 100, width: 400, height: 300)
        let out = reshape(reshape(start, aspect: 0.05), aspect: -0.05)
        #expect(abs(out.width - start.width) <= 1 && abs(out.height - start.height) <= 1)
    }

    @Test func clampsToTheVisibleEdgeByShiftingTheFrameInside() {
        let out = reshape(ActionRect(x: 700, y: 0, width: 300, height: 200), area: 0.5)
        #expect(out == ActionRect(x: 615, y: 0, width: 385, height: 257))
    }

    @Test func clampsSizeToTheVisibleFrame() {
        let out = reshape(ActionRect(x: 0, y: 0, width: 800, height: 600), area: 1)
        #expect(out == ActionRect(x: 0, y: 0, width: 1000, height: 800))
    }

    @Test func clampsToTheAppMinimumSize() {
        let out = reshape(ActionRect(x: 100, y: 100, width: 200, height: 150), area: -1)
        #expect(out == ActionRect(x: 120, y: 115, width: 160, height: 120))
    }

    @Test func atTheMinimumASmallerStepChangesNothing() {
        let start = ActionRect(x: 120, y: 115, width: 160, height: 120)
        #expect(reshape(start, area: -0.05) == start)
    }

    @Test func visibleFrameWinsWhenTheMinimumDoesNotFit() {
        let small = ActionRect(x: 0, y: 0, width: 100, height: 100)
        let out = reshape(
            ActionRect(x: 0, y: 0, width: 80, height: 80), area: -1, within: small,
            minimum: ActionSize(width: 300, height: 300))
        #expect(out == small)
    }

    @Test func reshapeActionInvertsExactlyAndLogsDeltas() {
        let from = ActionRect(x: 0, y: 0, width: 400, height: 300)
        let to = ActionRect(x: 0, y: 0, width: 410, height: 308)
        let action = Action.reshape(windowID: 7, aspectDelta: 0, areaDelta: 0.05, from: from, to: to)
        #expect(action.inverse == .reshape(windowID: 7, aspectDelta: 0, areaDelta: -0.05, from: to, to: from))
        #expect(action.inverse.inverse == action)
        #expect(action.windowID == 7)
        #expect(action.logLine
            == "reshape window 7 (aspect 0.0, area 0.05): (0.0, 0.0, 400.0, 300.0) -> (0.0, 0.0, 410.0, 308.0)")
    }
}
