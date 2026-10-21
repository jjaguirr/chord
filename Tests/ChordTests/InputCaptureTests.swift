import ChordCore
import Foundation
import Testing
@testable import Chord

private final class FakeClock: InputClock {
    var time = 0.0
    func now() -> Double { time }
}

private struct FakePermissions: InputPermissions {
    var accessibilityGranted = true
    var inputMonitoringGranted = true
}

private final class LineRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(line)
    }

    var lines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func has(_ fragments: String...) -> Bool {
        lines.contains { line in fragments.allSatisfy { line.contains($0) } }
    }
}

private final class FakeSource: HotkeySource {
    let path: CapturePath
    var isEnabled = true
    /// Carbon: label -> OSStatus to fail with. Tap: unused.
    var failures: [String: Int32] = [:]
    var failure: SourceFailure?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private weak var delegate: HotkeySourceDelegate?

    init(_ path: CapturePath) { self.path = path }

    func start(bindings: [HotkeyBinding], delegate: HotkeySourceDelegate) -> SourceStartReport {
        startCount += 1
        self.delegate = delegate
        var report = SourceStartReport()
        report.failure = failure
        guard path == .carbon, failure == nil else { return report }
        for binding in bindings {
            report.outcomes[binding] = failures[binding.label].map { .failed($0) } ?? .registered
        }
        return report
    }

    func stop() { stopCount += 1 }

    @discardableResult
    func send(
        _ code: String, shift: Bool = false, option: Bool = true, control: Bool = false,
        _ phase: KeyPhase = .down
    ) -> EventDecision {
        let event = RawKeyEvent(
            key: InputKey(code: code),
            modifiers: HeldModifiers(option: option, shift: shift, control: control),
            phase: phase)
        return delegate?.hotkeySource(path, didReceive: event) ?? .passThrough
    }

    func disable(_ cause: String) {
        delegate?.hotkeySource(path, wasDisabledBy: cause)
    }
}

private final class Harness {
    let clock = FakeClock()
    let carbon = FakeSource(.carbon)
    let tap = FakeSource(.tap)
    let log = LineRecorder()
    let capture: InputCapture
    private(set) var ticking: [Bool] = []

    init(
        config: Config = .defaults, permissions: FakePermissions = FakePermissions(),
        setUp: (FakeSource, FakeSource) -> Void = { _, _ in }
    ) {
        setUp(carbon, tap)
        let log = self.log
        capture = InputCapture(
            config: config, carbon: carbon, tap: tap, permissions: permissions, clock: clock,
            logSink: { log.append($0) })
        capture.tickRequest = { [unowned self] needed in ticking.append(needed) }
        capture.start()
    }

    func at(_ time: Double) { clock.time = time }

    func advance(to time: Double) {
        clock.time = time
        capture.tick()
    }
}

@Suite("Input capture")
struct InputCaptureTests {
    // MARK: Catalog

    @Test func catalogCoversTheSpecWithOptionOnly() {
        let catalog = HotkeyCatalog(keys: KeyBindings.defaults)
        let labels = Set(catalog.bindings.map(\.label))

        #expect(catalog.bindings.count == labels.count)
        #expect(catalog.bindings.allSatisfy { $0.label.hasPrefix("Option+") })
        #expect(!labels.contains { $0.localizedCaseInsensitiveContains("ctrl") })
        let expected = ["Option+0", "Option+R", "Option+W", "Option+Tab", "Option+`", "Option+Shift+`"]
            + "HJKL".flatMap { ["Option+\($0)", "Option+Shift+\($0)"] }
            + (1...9).flatMap { ["Option+\($0)", "Option+Shift+\($0)"] }
        #expect(labels == Set(expected))
        // 0, R and W are tap/hold and hold keys: no Shift variants.
        #expect(catalog.binding(for: .digit0, shift: true) == nil)
        #expect(catalog.binding(for: .keyR, shift: true) == nil)
        #expect(catalog.binding(for: .keyW, shift: true) == nil)
        #expect(catalog.binding(for: .keyW, shift: false)?.role == .workspaceLayer)
    }

    @Test func catalogFollowsConfiguredDirectionKeys() {
        let config = Config.load(text: "[keys]\nleft = \"KeyA\"\n").config
        let catalog = HotkeyCatalog(keys: config.keys)

        #expect(catalog.binding(for: InputKey(code: "KeyA"), shift: false)?.role == .direction(.h))
        #expect(catalog.binding(for: InputKey(code: "KeyH"), shift: false) == nil)
    }

    // MARK: Intent translation

    @Test func directionTapLooksOnRelease() {
        let h = Harness()
        h.at(0)
        h.carbon.send("KeyH")
        h.at(0.05)
        h.carbon.send("KeyH", .up)

        #expect(h.log.has("down Option+H", "path=carbon", "intent=none"))
        #expect(h.log.has("up Option+H", "path=carbon", "role=direction", "intent=look(x: -1, y: 0)"))
    }

    @Test func nearSimultaneousDirectionsCombineIntoADiagonal() {
        let h = Harness()
        h.at(0)
        h.carbon.send("KeyH")
        h.at(0.01)
        h.carbon.send("KeyJ")

        #expect(h.log.has("down Option+J", "intent=look(x: -1, y: 1)"))
    }

    @Test func shiftDirectionCarriesImmediately() {
        let h = Harness()
        h.carbon.send("KeyL", shift: true)

        #expect(h.log.has("down Option+Shift+L", "intent=carry(dx: 10.0, dy: 0.0)"))
    }

    @Test func reshapeNeedsRHeldThenDirection() {
        let h = Harness()
        h.carbon.send("KeyR")
        h.carbon.send("KeyL")

        #expect(h.log.has("down Option+L", "intent=reshape(aspect: 0.05, area: 0.0)"))
    }

    // MARK: Workspace layer (Option+W)

    @Test func holdingWThenHjklStepsTheGridAndShiftCarriesTheWindowAlong() {
        let h = Harness()
        let received = HandlerBox()
        h.capture.intentHandler = { received.intents.append(contentsOf: $0) }

        h.carbon.send("KeyW")
        for key in ["KeyH", "KeyJ", "KeyK", "KeyL"] {
            h.carbon.send(key)
            h.carbon.send(key, .up)
            h.carbon.send(key, shift: true)
            h.carbon.send(key, shift: true, .up)
        }
        h.carbon.send("KeyW", .up)

        #expect(received.intents == [
            .stepWorkspace(.left), .carryStepWorkspace(.left),
            .stepWorkspace(.down), .carryStepWorkspace(.down),
            .stepWorkspace(.up), .carryStepWorkspace(.up),
            .stepWorkspace(.right), .carryStepWorkspace(.right),
        ])
        #expect(h.log.has("down Option+W", "role=workspace layer", "intent=none"))
        #expect(h.log.has("down Option+J", "role=direction", "intent=stepWorkspace(down)"))
        #expect(h.log.has("down Option+Shift+K", "intent=carryStepWorkspace(up)"))
    }

    @Test func releasingWEndsTheLayerSoHjklLookAgain() {
        let h = Harness()
        let received = HandlerBox()
        h.capture.intentHandler = { received.intents.append(contentsOf: $0) }

        h.carbon.send("KeyW")
        h.carbon.send("KeyL")
        h.carbon.send("KeyL", .up)
        h.carbon.send("KeyW", .up)
        h.carbon.send("KeyL")
        h.carbon.send("KeyL", .up)

        #expect(received.intents == [.stepWorkspace(.right), .look(PickDirection(x: 1, y: 0))])
    }

    @Test func aHeldHjklKeyDoesNotRepeatAStepAndNoTimerIsNeeded() {
        let h = Harness()
        let received = HandlerBox()
        h.capture.intentHandler = { received.intents.append(contentsOf: $0) }

        h.carbon.send("KeyW")
        h.carbon.send("KeyL")
        h.carbon.send("KeyL", .autorepeat)
        h.carbon.send("KeyL", .autorepeat)
        h.advance(to: 2)
        h.carbon.send("KeyL", .up)

        #expect(received.intents == [.stepWorkspace(.right)])
    }

    @Test func escapeCancelsTheLayerButIsNeverConsumed() {
        let h = Harness()
        let received = HandlerBox()
        h.capture.intentHandler = { received.intents.append(contentsOf: $0) }

        h.carbon.send("KeyW")
        h.carbon.send("KeyJ")
        h.carbon.send("KeyJ", .up)
        #expect(h.tap.send("Escape", option: false) == .passThrough)
        h.tap.send("Escape", option: false, .up)
        h.carbon.send("KeyJ")
        h.carbon.send("KeyJ", .up)
        h.advance(to: 2)

        #expect(received.intents == [.stepWorkspace(.down)])
    }

    @Test func theTapPathTakesOptionWWhenCarbonRefusesItAndConsumesIt() {
        let h = Harness { carbon, _ in carbon.failures["Option+W"] = -9878 }
        let received = HandlerBox()
        h.capture.intentHandler = { received.intents.append(contentsOf: $0) }

        #expect(h.tap.send("KeyW") == .consume)
        #expect(h.tap.send("KeyJ") == .passThrough)
        h.carbon.send("KeyJ")

        #expect(received.intents == [.stepWorkspace(.down)])
    }

    @Test func controlWIsNeverTheWorkspaceLayer() {
        let h = Harness()
        let received = HandlerBox()
        h.capture.intentHandler = { received.intents.append(contentsOf: $0) }

        #expect(h.tap.send("KeyW", control: true) == .passThrough)
        h.carbon.send("KeyL")
        h.carbon.send("KeyL", .up)

        #expect(received.intents == [.look(PickDirection(x: 1, y: 0))])
    }

    // MARK: Workspace keys

    @Test func optionDigitShowsThatColumnAndShiftCarriesToIt() {
        let h = Harness()
        let received = HandlerBox()
        h.capture.intentHandler = { received.intents.append(contentsOf: $0) }

        for column in 1...9 {
            h.carbon.send("Digit\(column)")
            h.carbon.send("Digit\(column)", .up)
            h.carbon.send("Digit\(column)", shift: true)
            h.carbon.send("Digit\(column)", shift: true, .up)
        }

        #expect(received.intents == (1...9).flatMap { [KeyIntent.showColumn($0), .carryToColumn($0)] })
        #expect(h.log.has("down Option+3", "path=carbon", "role=place", "intent=showColumn(3)"))
        #expect(h.log.has("down Option+Shift+3", "role=place", "intent=carryToColumn(3)"))
    }

    @Test func benchKeyShowsTheBenchAndShiftCarriesToIt() {
        let h = Harness()
        let received = HandlerBox()
        h.capture.intentHandler = { received.intents.append(contentsOf: $0) }

        h.carbon.send("Backquote")
        h.carbon.send("Backquote", .up)
        h.carbon.send("Backquote", shift: true)

        #expect(received.intents == [.showBench, .carryToBench])
    }

    @Test func optionTabShowsThePreviousWorkspaceAndShiftTabIsNotCaptured() {
        let h = Harness()
        let received = HandlerBox()
        h.capture.intentHandler = { received.intents.append(contentsOf: $0) }

        h.carbon.send("Tab")
        let shifted = h.carbon.send("Tab", shift: true)

        #expect(received.intents == [.showPrevious])
        #expect(shifted == .passThrough)
    }

    @Test func aHeldWorkspaceKeyDoesNotRepeatAndReleaseIsSilent() {
        let h = Harness()
        let received = HandlerBox()
        h.capture.intentHandler = { received.intents.append(contentsOf: $0) }

        h.carbon.send("Digit5")
        h.carbon.send("Digit5", .autorepeat)
        h.carbon.send("Digit5", .autorepeat)
        h.carbon.send("Digit5", .up)

        #expect(received.intents == [.showColumn(5)])
    }

    @Test func theTapPathConsumesTheDigitBeforeItBecomesACharacter() {
        let h = Harness { carbon, _ in carbon.failures["Option+3"] = -9878 }
        let received = HandlerBox()
        h.capture.intentHandler = { received.intents.append(contentsOf: $0) }

        #expect(h.tap.send("Digit3") == .consume)

        #expect(received.intents == [.showColumn(3)])
        #expect(h.log.has("down Option+3", "path=tap", "intent=showColumn(3)"))
    }

    @Test func controlDigitIsNeverAWorkspaceKey() {
        let h = Harness()
        let received = HandlerBox()
        h.capture.intentHandler = { received.intents.append(contentsOf: $0) }

        #expect(h.carbon.send("Digit3", control: true) == .passThrough)
        #expect(h.tap.send("Digit3", control: true) == .passThrough)

        #expect(received.intents.isEmpty)
    }

    @Test func aReboundVaultKeyIsStillTheLastColumnAndAReboundTierKeyColumnFour() {
        let config = Config.load(text: "[keys]\nvault = \"KeyV\"\nredacted_tier = \"KeyT\"\n").config
        let catalog = HotkeyCatalog(keys: config.keys)

        #expect(catalog.column(for: InputKey(code: "KeyV")) == GridCell.columnCount)
        #expect(catalog.column(for: InputKey(code: "KeyT")) == Workspace.four.rawValue)
        #expect(catalog.column(for: InputKey(code: "Digit9")) == GridCell.columnCount)
        #expect(catalog.column(for: InputKey(code: "KeyH")) == nil)
    }

    // MARK: Hold timing

    @Test func optionZeroTapUnfolds() {
        let h = Harness()
        h.at(0)
        h.carbon.send("Digit0")
        h.at(0.1)
        h.carbon.send("Digit0", .up)

        #expect(h.log.has("up Option+0", "intent=unfold"))
    }

    @Test func optionZeroHoldSpreadsAtTheConfiguredThresholdOnTheTimer() {
        let h = Harness()
        h.at(0)
        h.carbon.send("Digit0")
        h.advance(to: 0.69)
        #expect(!h.log.has("intent=spread"))
        h.advance(to: 0.7)
        #expect(h.log.has("timer intent=spread"))
        h.at(1.0)
        h.carbon.send("Digit0", .up)

        #expect(!h.log.has("intent=unfold"))
        #expect(h.ticking == [true, false])
    }

    @Test func holdThresholdComesFromConfig() {
        let config = Config.load(text: "[timing]\nhold_ms = 300\n").config
        let h = Harness(config: config)
        h.at(0)
        h.carbon.send("Digit0")
        h.advance(to: 0.299)
        #expect(!h.log.has("intent=spread"))
        h.advance(to: 0.3)

        #expect(h.log.has("timer intent=spread"))
        #expect(h.log.has("hold=300ms"))
    }

    @Test func escapeAbortsAChargeButIsNeverConsumed() {
        let h = Harness()
        #expect(h.tap.send("Escape", option: false) == .passThrough)
        h.tap.send("Escape", option: false, .up)
        #expect(!h.log.has("Esc"))

        h.carbon.send("Digit0")
        let decision = h.tap.send("Escape", option: false)

        #expect(decision == .passThrough)
        #expect(h.log.has("down Esc", "path=tap", "intent=abortCharge"))
        h.tap.send("Escape", option: false, .up)
        h.carbon.send("Digit0", .up)
        #expect(!h.log.has("intent=unfold"))
    }

    // MARK: Failures carry causes

    @Test func registrationConflictIsReportedWithStatusAndTheTapTakesOver() {
        let h = Harness { carbon, _ in carbon.failures["Option+H"] = -9878 }
        let status = h.capture.status()

        let cause = status.problems.first?.cause ?? ""
        #expect(cause.contains("Option+H"))
        #expect(cause.contains("-9878"))
        #expect(cause.contains("AeroSpace"))
        #expect(h.log.has("carbon register FAILED Option+H", "-9878"))
        #expect(h.log.has("PROBLEM", "Option+H"))
        #expect(status.hotkeys.first { $0.label == "Option+H" }?.owner == .tap)
        #expect(status.hotkeys.first { $0.label == "Option+J" }?.owner == .carbon)
        #expect(status.headline.contains("-9878"))

        #expect(h.tap.send("KeyH") == .consume)
        #expect(h.log.has("down Option+H", "path=tap"))
        #expect(h.tap.send("KeyH", option: true, .up) == .consume)
    }

    @Test func tapKeepsConsumingAReleaseAfterOptionLetGo() {
        let h = Harness { carbon, _ in carbon.failures["Option+H"] = -9878 }
        h.tap.send("KeyH")

        #expect(h.tap.send("KeyH", option: false, .up) == .consume)
        #expect(h.log.has("up Option+H", "path=tap"))
    }

    @Test func missingAccessibilityNeverStartsTheTapAndSaysWhy() {
        let h = Harness(permissions: FakePermissions(accessibilityGranted: false)) { carbon, _ in
            carbon.failures["Option+H"] = -9878
        }
        let status = h.capture.status()

        #expect(h.tap.startCount == 0)
        #expect(status.tap == .off)
        #expect(status.problems.contains(.accessibilityMissing))
        #expect(h.log.has("PROBLEM", "Accessibility not granted"))
        #expect(h.log.has("accessibility=missing", "inputMonitoring=granted"))
        // Carbon refused Option+H and no tap exists: that key has no capture path.
        #expect(status.unowned == 1)
        #expect(status.problems.first?.cause.contains("dead") == true)
    }

    @Test func missingInputMonitoringNeverStartsTheTapAndSaysWhy() {
        let h = Harness(permissions: FakePermissions(inputMonitoringGranted: false))
        let status = h.capture.status()

        #expect(h.tap.startCount == 0)
        #expect(status.problems == [.inputMonitoringMissing])
        #expect(status.headline.contains("Input Monitoring"))
        #expect(h.log.has("PROBLEM", "Input Monitoring not granted"))
    }

    @Test func tapCreateFailureIsReported() {
        let h = Harness { _, tap in tap.failure = .tapCreateFailed }

        #expect(h.capture.status().problems == [.tapCreateFailed])
        #expect(h.capture.status().tap == .off)
    }

    @Test func carbonHandlerFailureMovesEverythingToTheTap() {
        let h = Harness { carbon, _ in carbon.failure = .handlerInstall(-50) }
        let status = h.capture.status()

        #expect(status.problems == [.carbonHandlerFailed(-50)])
        #expect(status.tapOwned == status.hotkeys.count)
        #expect(h.log.has("PROBLEM", "-50"))
    }

    @Test func systemDisablingTheTapIsReportedAndClearsOnceEnabled() {
        let h = Harness()
        h.tap.disable("timeout: callback ran too long")
        h.tap.isEnabled = false
        let disabled = h.capture.status()
        #expect(disabled.tap == .disabled)
        #expect(disabled.counters.tapDisabledEvents == 1)
        #expect(disabled.problems.contains(.tapDisabledBySystem("timeout: callback ran too long")))
        #expect(h.log.has("PROBLEM", "disabled by the system", "timeout"))

        h.tap.isEnabled = true
        let recovered = h.capture.status()
        #expect(recovered.tap == .enabled)
        #expect(recovered.problems.isEmpty)
        #expect(recovered.counters.tapDisabledEvents == 1)
    }

    @Test func healthyStartupSummarizesEveryKey() {
        let h = Harness()
        let status = h.capture.status()

        #expect(status.problems.isEmpty)
        #expect(status.tap == .enabled)
        #expect(status.headline == "All 32 hotkeys captured (carbon 32, tap 0).")
        #expect(h.log.has("self-check accessibility=granted inputMonitoring=granted"))
        #expect(h.log.has("ready carbon=32 tap=0 none=0"))
    }

    // MARK: Tap routing

    @Test func tapIgnoresEverythingThatIsNotAnOptionHotkey() {
        let h = Harness { carbon, _ in carbon.failure = .handlerInstall(-50) }

        #expect(h.tap.send("KeyH", option: false) == .passThrough)
        #expect(h.tap.send("KeyH", control: true) == .passThrough)
        #expect(h.tap.send("KeyQ") == .passThrough)
        #expect(h.tap.send("Digit0", shift: true) == .passThrough)
        #expect(h.capture.counters.tapEvents == 0)
        #expect(!h.log.has("down "))
    }

    // MARK: Carbon cross-check

    @Test func carbonThatNeverFiresIsReportedWithoutChangingOwnership() {
        let h = Harness()
        h.at(0)
        #expect(h.tap.send("Digit1") == .passThrough)
        h.advance(to: 0.05)
        #expect(h.capture.counters.carbonSilent == 0)
        #expect(!h.log.has("DIAGNOSTIC"))
        h.advance(to: 0.1)

        let status = h.capture.status()
        #expect(status.counters.carbonSilent == 1)
        #expect(h.log.has("DIAGNOSTIC", "Option+1", "did not deliver", "ownership unchanged"))
        #expect(status.problems.isEmpty)
        #expect(status.hotkeys.first { $0.label == "Option+1" }?.owner == .carbon)
        #expect(status.hotkeys.first { $0.label == "Option+2" }?.owner == .carbon)
        #expect(h.tap.send("Digit1") == .passThrough)
        #expect(h.tap.send("Digit2") == .passThrough)
        #expect(status.counters.consumed == 0)
        #expect(!h.log.has("down Option+1"))
    }

    @Test func eachSilentPressIsReportedOnce() {
        let h = Harness()
        h.at(0)
        h.tap.send("Digit1")
        h.advance(to: 0.1)
        h.advance(to: 0.2)
        #expect(h.capture.counters.carbonSilent == 1)
        #expect(!h.capture.needsTick)
        h.at(0.3)
        h.tap.send("Digit1")
        h.advance(to: 0.4)
        #expect(h.capture.counters.carbonSilent == 2)
    }

    @Test func carbonThatDeliversIsNotReported() {
        let h = Harness()
        h.at(0)
        h.tap.send("Digit1")
        h.at(0.01)
        h.carbon.send("Digit1")
        h.advance(to: 0.5)

        let status = h.capture.status()
        #expect(status.problems.isEmpty)
        #expect(status.counters.carbonSilent == 0)
        #expect(status.counters.carbonConfirmed == 1)
        #expect(!h.log.has("DIAGNOSTIC"))
        #expect(status.hotkeys.first { $0.label == "Option+1" }?.owner == .carbon)
        #expect(h.log.lines.filter { $0.contains("down Option+1") }.count == 1)
    }

    @Test func carbonFiringBeforeTheTapSawItIsNotAFalseAlarm() {
        let h = Harness()
        h.at(0)
        h.carbon.send("Digit1")
        h.at(0.005)
        h.tap.send("Digit1")
        h.advance(to: 0.5)

        #expect(h.capture.status().problems.isEmpty)
    }

    // MARK: Robustness

    @Test func aSecondPressWithoutARelease_recoversFromAMissedKeyUp() {
        let h = Harness()
        h.carbon.send("Digit3")
        h.carbon.send("Digit3")

        #expect(h.capture.counters.missedKeyUps == 1)
        #expect(h.log.has("missed key-up for Option+3"))
        #expect(h.log.has("up Option+3", "synthesized"))
    }

    @Test func stopReleasesHotkeysAndStartRetakesThem() {
        let h = Harness()
        h.capture.stop()
        #expect(h.carbon.stopCount == 1)
        #expect(h.tap.stopCount == 1)
        #expect(h.carbon.send("KeyH") == .passThrough)
        #expect(!h.log.has("down Option+H"))
        #expect(h.log.has("stopped"))

        h.capture.start()
        h.carbon.send("KeyH")
        #expect(h.carbon.startCount == 2)
        #expect(h.log.has("down Option+H"))
    }

    @Test func logLinesAreCappedAtThePolicyLimit() {
        let h = Harness()
        h.capture.restart(reason: String(repeating: "x", count: 10_000))

        let longest = h.log.lines.map(\.utf8.count).max() ?? 0
        #expect(longest <= LogPolicy.maxLineBytes)
        #expect(h.log.has("restarting: xxx"))
    }

    // MARK: Handlers

    @Test func intentHandlerReceivesWhatTheMachineProducesAfterTheLogLine() {
        let h = Harness()
        let received = HandlerBox()
        h.capture.intentHandler = { received.intents.append(contentsOf: $0) }
        h.at(0)
        h.carbon.send("Digit0")
        h.at(0.1)
        h.carbon.send("Digit0", .up)
        h.carbon.send("KeyL", shift: true)

        #expect(received.intents == [.unfold, .carry(dx: 10, dy: 0)])
    }

    @Test func timerIntentsReachTheHandler() {
        let h = Harness()
        let received = HandlerBox()
        h.capture.intentHandler = { received.intents.append(contentsOf: $0) }
        h.at(0)
        h.carbon.send("Digit0")
        h.advance(to: 0.7)

        #expect(received.intents == [.spread])
    }

    // MARK: Status text

    @Test func renderNamesEveryKeyItsStatusAndTheCounters() {
        let h = Harness { carbon, _ in carbon.failures["Option+H"] = -9878 }
        h.tap.send("KeyH")
        h.carbon.send("KeyJ")
        let text = h.capture.status().render(logText: """
        2026-10-17T00:00:00Z executor: moved window 1
        2026-10-17T00:00:01Z input: down Option+H path=tap
        """)

        #expect(text.contains("Option+H [direction]: carbon FAILED OSStatus -9878 eventHotKeyExistsErr; caught by tap"))
        #expect(text.contains("Option+J [direction]: carbon registered; caught by carbon"))
        #expect(text.contains("events: carbon 1, tap 1"))
        #expect(text.contains("Accessibility: granted"))
        #expect(text.contains("input: down Option+H path=tap"))
        #expect(!text.contains("executor: moved window 1"))
    }
}

private final class HandlerBox {
    var intents: [KeyIntent] = []
}
