import ChordCore
import Foundation

/// Screen geometry handed to the `KeyStateMachine` for carry edge-magnets. Until the
/// Executor slice supplies the focused window, carry intents are computed against a
/// stand-in rectangle.
struct InputGeometry: Equatable {
    var rect: PickerRect
    var edges: KeyStateMachine.Edges

    /// A 333x471 window centered on a 1440x900 screen.
    static let standIn = centered(on: CGRect(x: 0, y: 0, width: 1440, height: 900))

    /// The 333x471 stand-in window centered on `screen`, with the screen's edges.
    static func centered(on screen: CGRect) -> InputGeometry {
        InputGeometry(
            rect: PickerRect(x: screen.midX - 166.5, y: screen.midY - 235.5, width: 333, height: 471),
            edges: KeyStateMachine.Edges(
                left: screen.minX, right: screen.maxX, top: screen.minY, bottom: screen.maxY))
    }
}

/// Takes events from the Carbon and event-tap sources, decides which path owns each
/// hotkey, feeds the `KeyStateMachine`, and logs every event with the path that caught it.
/// It makes no window call: intents are logged, not executed.
///
/// Ownership: a hotkey Carbon registered is owned by Carbon; one it refused is owned by
/// the tap. The tap also watches Carbon-owned keys without consuming them. If the tap
/// sees a press Carbon does not deliver within `carbonGrace`, the capture logs a
/// DIAGNOSTIC line and counts it; ownership never changes and the tap keeps passing
/// those events through.
///
/// Main thread only: both sources deliver on the main run loop.
final class InputCapture: HotkeySourceDelegate {
    /// How long Carbon has to deliver a press the tap already saw.
    static let carbonGrace = 0.1

    private struct Held {
        let binding: HotkeyBinding
        let path: CapturePath
    }

    private struct TapPress {
        let binding: HotkeyBinding
        let downAt: Double
    }

    private let catalog: HotkeyCatalog
    private let carbon: HotkeySource
    private let tap: HotkeySource
    private let permissions: InputPermissions
    private let clock: InputClock
    private let geometry: () -> InputGeometry
    private let sink: (@Sendable (String) -> Void)?
    private let machineConfiguration: KeyStateMachine.Configuration

    private var machine: KeyStateMachine
    private var running = false
    private var tapRunning = false
    private var registrations: [HotkeyBinding: BindingOutcome] = [:]
    private var owners: [HotkeyBinding: CapturePath] = [:]
    private var startProblems: [InputProblem] = []
    private var runtimeProblems: [InputProblem] = []
    private var held: [InputKey: Held] = [:]
    private var unconfirmed: [InputKey: TapPress] = [:]
    private var recentCarbonDowns: [InputKey: Double] = [:]
    private var tickRequested = false
    private(set) var counters = InputCounters()

    /// Called when the capture starts or stops needing `tick()` (a key is down or a tap press
    /// awaits Carbon's confirmation). The app runs a timer only while this is true.
    var tickRequest: ((Bool) -> Void)?

    init(
        config: Config,
        carbon: HotkeySource,
        tap: HotkeySource,
        permissions: InputPermissions,
        clock: InputClock,
        geometry: @escaping () -> InputGeometry = { .standIn },
        logSink: (@Sendable (String) -> Void)? = nil
    ) {
        catalog = HotkeyCatalog(keys: config.keys)
        machineConfiguration = Self.machineConfiguration(config)
        machine = KeyStateMachine(configuration: machineConfiguration)
        self.carbon = carbon
        self.tap = tap
        self.permissions = permissions
        self.clock = clock
        self.geometry = geometry
        sink = logSink
    }

    static func machineConfiguration(_ config: Config) -> KeyStateMachine.Configuration {
        KeyStateMachine.Configuration(
            holdThreshold: Double(config.timing.holdMs) / 1000,
            chordWindow: Double(config.timing.chordWindowMs) / 1000,
            repeatStages: [config.carry.ramp.near, config.carry.ramp.middle, config.carry.ramp.far].map(Double.init),
            magnetDistance: Double(config.carry.edgeMagnetPx))
    }

    var isRunning: Bool { running }

    /// Self-check, then take the hotkeys. Every failed precondition is logged with its cause.
    /// Never prompts: the tap is created only when both permissions already read as granted.
    func start() {
        guard !running else { return }
        running = true
        machine = KeyStateMachine(configuration: machineConfiguration)
        registrations = [:]
        owners = [:]
        startProblems = []
        runtimeProblems = []
        held = [:]
        unconfirmed = [:]
        recentCarbonDowns = [:]

        let accessibility = permissions.accessibilityGranted
        let inputMonitoring = permissions.inputMonitoringGranted
        log("input: self-check accessibility=\(accessibility ? "granted" : "missing") "
            + "inputMonitoring=\(inputMonitoring ? "granted" : "missing")")

        let carbonReport = carbon.start(bindings: catalog.bindings, delegate: self)
        registrations = carbonReport.outcomes
        if case .handlerInstall(let status)? = carbonReport.failure {
            startProblems.append(.carbonHandlerFailed(status))
        }
        var failures: [RegistrationFailure] = []
        for binding in catalog.bindings {
            if case .failed(let status)? = registrations[binding] {
                failures.append(RegistrationFailure(label: binding.label, status: status))
            }
        }

        if !accessibility { startProblems.append(.accessibilityMissing) }
        if !inputMonitoring { startProblems.append(.inputMonitoringMissing) }
        tapRunning = false
        if accessibility && inputMonitoring {
            if tap.start(bindings: catalog.bindings, delegate: self).failure == nil {
                tapRunning = true
            } else {
                startProblems.append(.tapCreateFailed)
            }
        }

        for binding in catalog.bindings {
            if registrations[binding] == .registered {
                owners[binding] = .carbon
            } else if tapRunning {
                owners[binding] = .tap
            }
        }
        if !failures.isEmpty {
            startProblems.insert(.registrationFailed(failures, tapFallback: tapRunning), at: 0)
        }

        for failure in failures {
            log("input: carbon register FAILED \(failure.label): \(InputStatus.describe(failure.status))")
        }
        for problem in startProblems { log("input: PROBLEM \(problem.cause)") }
        let unowned = catalog.bindings.count - owners.count
        log("input: ready carbon=\(owners.values.filter { $0 == .carbon }.count) "
            + "tap=\(owners.values.filter { $0 == .tap }.count) none=\(unowned) "
            + "hold=\(Int((machineConfiguration.holdThreshold * 1000).rounded()))ms")
    }

    /// Releases every hotkey and tap. Inverse of `start()`.
    func stop() {
        guard running else { return }
        carbon.stop()
        tap.stop()
        running = false
        tapRunning = false
        held = [:]
        unconfirmed = [:]
        recentCarbonDowns = [:]
        machine = KeyStateMachine(configuration: machineConfiguration)
        updateTickRequest()
        log("input: stopped; hotkeys released")
    }

    func restart(reason: String) {
        stop()
        log("input: restarting: \(reason)")
        start()
    }

    var needsTick: Bool { !held.isEmpty || !unconfirmed.isEmpty }

    /// Advances hold and repeat timers, and reports presses Carbon never delivered. Call from a timer while
    /// `tickRequest` last reported true.
    func tick() {
        guard running else { return }
        let now = clock.now()
        reportSilentCarbon(now: now)
        let screen = geometry()
        let intents = machine.advance(to: now, rect: screen.rect, edges: screen.edges)
        if !intents.isEmpty {
            counters.intents += intents.count
            log("input: timer intent=\(Self.describe(intents))")
        }
        updateTickRequest()
    }

    func status() -> InputStatus {
        var problems = startProblems + runtimeProblems
        var tapStatus = TapStatus.off
        if tapRunning {
            let isTapDisabled: (InputProblem) -> Bool = {
                if case .tapDisabledBySystem = $0 { return true }
                return false
            }
            if tap.isEnabled {
                tapStatus = .enabled
                problems.removeAll(where: isTapDisabled)
            } else {
                tapStatus = .disabled
                if !problems.contains(where: isTapDisabled) {
                    problems.append(.tapDisabledBySystem("it reports disabled right now"))
                }
            }
        }
        return InputStatus(
            running: running,
            accessibilityGranted: permissions.accessibilityGranted,
            inputMonitoringGranted: permissions.inputMonitoringGranted,
            tap: tapStatus,
            hotkeys: catalog.bindings.map {
                HotkeyStatus(label: $0.label, role: $0.role.name, outcome: registrations[$0], owner: owners[$0])
            },
            counters: counters,
            problems: running ? problems : [])
    }

    // MARK: HotkeySourceDelegate

    func hotkeySource(_ path: CapturePath, didReceive event: RawKeyEvent) -> EventDecision {
        guard running else { return .passThrough }
        let now = clock.now()

        // Escape is watched, never consumed: it only matters while Option+0 is charging.
        if event.key == .escape { return observeEscape(event, path: path, at: now) }

        // A key this path consumed on press keeps being routed to it until released,
        // even if the modifiers changed in between.
        if event.phase != .down, let current = held[event.key], current.path == path {
            return accept(current.binding, event.phase, path: path, at: now)
        }
        guard event.modifiers.isChordFamily,
            let binding = catalog.binding(for: event.key, shift: event.modifiers.shift)
        else { return .passThrough }

        guard owners[binding] == path else {
            if path == .tap {
                observeCarbonOwnedKey(binding, event.phase, at: now)
            } else {
                counters.ignoredDuplicates += 1
            }
            return .passThrough
        }
        return accept(binding, event.phase, path: path, at: now)
    }

    func hotkeySource(_ path: CapturePath, wasDisabledBy cause: String) {
        guard running else { return }
        counters.tapDisabledEvents += 1
        let problem = InputProblem.tapDisabledBySystem(cause)
        if !runtimeProblems.contains(problem) { runtimeProblems.append(problem) }
        log("input: PROBLEM \(problem.cause) Re-enabling it.")
    }

    // MARK: Routing

    private func accept(
        _ binding: HotkeyBinding, _ phase: KeyPhase, path: CapturePath, at time: Double
    ) -> EventDecision {
        if path == .tap { counters.tapEvents += 1 } else { counters.carbonEvents += 1 }
        let decision: EventDecision = path == .tap ? .consume : .passThrough
        if decision == .consume { counters.consumed += 1 }
        let key = binding.key

        switch phase {
        case .autorepeat:
            counters.autorepeats += 1
        case .down:
            if path == .carbon {
                recentCarbonDowns[key] = time
                if unconfirmed.removeValue(forKey: key) != nil { counters.carbonConfirmed += 1 }
            }
            if let stale = held[key] {
                counters.missedKeyUps += 1
                log("input: missed key-up for \(stale.binding.label); releasing it first")
                deliver(binding: stale.binding, phase: .up, path: stale.path, at: time, note: "synthesized")
            }
            held[key] = Held(binding: binding, path: path)
            deliver(binding: binding, phase: .down, path: path, at: time, note: nil)
        case .up:
            guard held.removeValue(forKey: key) != nil else { break }
            deliver(binding: binding, phase: .up, path: path, at: time, note: nil)
        }
        updateTickRequest()
        return decision
    }

    private func observeEscape(_ event: RawKeyEvent, path: CapturePath, at time: Double) -> EventDecision {
        guard path == .tap, event.phase != .autorepeat else { return .passThrough }
        let screen = geometry()
        let modifiers = KeyModifiers(shift: event.modifiers.shift, mod: event.modifiers.option)
        let input: KeyInput = event.phase == .down
            ? .down(.escape, repeat: false, modifiers: modifiers) : .up(.escape, modifiers: modifiers)
        let intents = machine.process(input, at: time, rect: screen.rect, edges: screen.edges)
        if !intents.isEmpty {
            counters.tapEvents += 1
            counters.intents += intents.count
            log("input: \(event.phase == .down ? "down" : "up") Esc path=tap role=abort intent=\(Self.describe(intents))")
        }
        return .passThrough
    }

    /// Tap saw a key Carbon owns. Pass it through (Carbon takes it if it works) and note the
    /// press so a Carbon that never delivers it is reported by `tick()`.
    private func observeCarbonOwnedKey(_ binding: HotkeyBinding, _ phase: KeyPhase, at time: Double) {
        let key = binding.key
        if phase == .down {
            if let at = recentCarbonDowns[key], time - at <= Self.carbonGrace {
                counters.carbonConfirmed += 1
            } else if unconfirmed[key] == nil {
                unconfirmed[key] = TapPress(binding: binding, downAt: time)
            }
        }
        counters.passedThrough += 1
        updateTickRequest()
    }

    private func reportSilentCarbon(now: Double) {
        let overdue = unconfirmed.values
            .filter { now - $0.downAt >= Self.carbonGrace }
            .sorted { $0.downAt < $1.downAt }
        for press in overdue {
            unconfirmed[press.binding.key] = nil
            counters.carbonSilent += 1
            log("input: DIAGNOSTIC Carbon registered \(press.binding.label) but did not deliver the press the tap saw; ownership unchanged")
        }
    }

    private func deliver(
        binding: HotkeyBinding, phase: KeyPhase, path: CapturePath, at time: Double, note: String?
    ) {
        var intents: [KeyIntent] = []
        if let chordKey = binding.role.chordKey {
            let modifiers = KeyModifiers(shift: binding.shift, mod: true)
            let input: KeyInput = phase == .down
                ? .down(chordKey, repeat: false, modifiers: modifiers) : .up(chordKey, modifiers: modifiers)
            let screen = geometry()
            intents = machine.process(input, at: time, rect: screen.rect, edges: screen.edges)
        }
        counters.intents += intents.count
        log("input: \(phase == .down ? "down" : "up") \(binding.label) path=\(path.rawValue) "
            + "role=\(binding.role.name) intent=\(Self.describe(intents))\(note.map { " (\($0))" } ?? "")")
    }

    private func updateTickRequest() {
        let needed = running && needsTick
        guard needed != tickRequested else { return }
        tickRequested = needed
        tickRequest?(needed)
    }

    private func log(_ message: String) {
        sink?(LogPolicy.clipped(message))
    }

    // MARK: Description

    static func describe(_ intents: [KeyIntent]) -> String {
        intents.isEmpty ? "none" : intents.map(describe).joined(separator: ", ")
    }

    static func describe(_ intent: KeyIntent) -> String {
        switch intent {
        case .look(let direction): "look(x: \(direction.x), y: \(direction.y))"
        case .carry(let dx, let dy): "carry(dx: \(dx), dy: \(dy))"
        case .reshape(let aspect, let area): "reshape(aspect: \(aspect), area: \(area))"
        case .unfold: "unfold"
        case .spread: "spread"
        case .abortCharge: "abortCharge"
        }
    }
}
