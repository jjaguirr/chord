import ChordCore
import Foundation

struct RegistrationFailure: Equatable, Sendable {
    let label: String
    let status: Int32
}

/// A failed precondition or runtime fault, each with the one-line cause the captain reads.
enum InputProblem: Equatable, Sendable {
    case accessibilityMissing
    case inputMonitoringMissing
    case tapCreateFailed
    case tapDisabledBySystem(String)
    case carbonHandlerFailed(Int32)
    /// `tapFallback` is true when the event tap took the failed keys over.
    case registrationFailed([RegistrationFailure], tapFallback: Bool)
    /// Carbon accepted the registrations but never delivered a press the tap saw.
    case carbonSilent(first: String, moved: Int)

    var cause: String {
        switch self {
        case .accessibilityMissing:
            "Accessibility not granted: event tap fallback is off. Grant Chord in System Settings > Privacy & Security > Accessibility."
        case .inputMonitoringMissing:
            "Input Monitoring not granted: event tap fallback is off. Grant Chord in System Settings > Privacy & Security > Input Monitoring."
        case .tapCreateFailed:
            "Event tap could not be created although Accessibility and Input Monitoring read as granted: a grant made while Chord ran may need a relaunch."
        case .tapDisabledBySystem(let reason):
            "Event tap was disabled by the system (\(reason))."
        case .carbonHandlerFailed(let status):
            "Carbon hotkey handler could not be installed (\(InputStatus.describe(status))): no Carbon hotkeys are active."
        case .registrationFailed(let failures, let tapFallback):
            Self.registrationCause(failures, tapFallback: tapFallback)
        case .carbonSilent(let first, let moved):
            "Carbon registered \(first) but never delivered it while the event tap saw it: \(moved) hotkeys moved to the event tap."
        }
    }

    private static func registrationCause(_ failures: [RegistrationFailure], tapFallback: Bool) -> String {
        let shown = failures.prefix(3).map { "\($0.label) (\(InputStatus.describe($0.status)))" }
        let extra = failures.count > shown.count ? ", and \(failures.count - shown.count) more" : ""
        let outcome = tapFallback ? "the event tap took them over" : "they are dead until a capture path exists"
        let conflict = failures.contains { $0.status == InputStatus.hotKeyExists }
            ? " -9878 means another app (AeroSpace alt-key bindings, for one) or Chord already holds the key;" : ""
        return "Carbon could not register \(failures.count) hotkeys: \(shown.joined(separator: ", "))\(extra);\(conflict) \(outcome)."
    }
}

enum TapStatus: Equatable, Sendable {
    case off
    case enabled
    case disabled
}

struct InputCounters: Equatable, Sendable {
    var carbonEvents = 0
    var tapEvents = 0
    var consumed = 0
    var passedThrough = 0
    var autorepeats = 0
    var intents = 0
    /// Tap saw a Carbon-owned press and Carbon delivered it too.
    var carbonConfirmed = 0
    /// Tap saw a Carbon-owned press and Carbon never did.
    var carbonSilent = 0
    var ignoredDuplicates = 0
    var missedKeyUps = 0
    var tapDisabledEvents = 0
}

struct HotkeyStatus: Equatable, Sendable {
    let label: String
    let role: String
    let outcome: BindingOutcome?
    let owner: CapturePath?
}

/// A snapshot for the menu, the log, and Copy Diagnostics. Plain data: rendering is pure.
struct InputStatus: Equatable, Sendable {
    var running: Bool
    var accessibilityGranted: Bool
    var inputMonitoringGranted: Bool
    var tap: TapStatus
    var hotkeys: [HotkeyStatus]
    var counters: InputCounters
    var problems: [InputProblem]

    var carbonRegistered: Int { hotkeys.filter { $0.outcome == .registered }.count }
    var carbonOwned: Int { hotkeys.filter { $0.owner == .carbon }.count }
    var tapOwned: Int { hotkeys.filter { $0.owner == .tap }.count }
    var unowned: Int { hotkeys.filter { $0.owner == nil }.count }

    /// The one line shown in the menu: the first problem's cause, or the healthy summary.
    var headline: String {
        if !running { return "Input capture is stopped." }
        if let first = problems.first {
            let more = problems.count > 1 ? " (+\(problems.count - 1) more)" : ""
            return first.cause + more
        }
        return "All \(hotkeys.count) hotkeys captured (carbon \(carbonOwned), tap \(tapOwned))."
    }

    var countersLine: String {
        let c = counters
        return "events: carbon \(c.carbonEvents), tap \(c.tapEvents); consumed \(c.consumed), "
            + "passed \(c.passedThrough); intents \(c.intents); repeats \(c.autorepeats); "
            + "carbon confirmed \(c.carbonConfirmed), carbon silent \(c.carbonSilent); "
            + "duplicates \(c.ignoredDuplicates); missed key-ups \(c.missedKeyUps); "
            + "tap disabled \(c.tapDisabledEvents)"
    }

    var tapLine: String {
        switch tap {
        case .off: "off"
        case .enabled: "enabled"
        case .disabled: "disabled"
        }
    }

    var summaryLines: [String] {
        [
            "Accessibility: \(accessibilityGranted ? "granted" : "not granted")",
            "Input Monitoring: \(inputMonitoringGranted ? "granted" : "not granted")",
            "Event tap: \(tapLine)",
            "Carbon: \(carbonRegistered) of \(hotkeys.count) hotkeys registered",
            "Owners: carbon \(carbonOwned), tap \(tapOwned), none \(unowned)",
            "Counters: \(countersLine)",
        ]
    }

    func hotkeyLine(_ hotkey: HotkeyStatus) -> String {
        let carbon: String
        switch hotkey.outcome {
        case .registered: carbon = "registered"
        case .failed(let status): carbon = "FAILED \(Self.describe(status))"
        case nil: carbon = "not attempted"
        }
        return "\(hotkey.label) [\(hotkey.role)]: carbon \(carbon); caught by \(hotkey.owner?.rawValue ?? "nothing")"
    }

    /// Text for Copy Diagnostics.
    func render() -> String {
        var lines = ["Input capture: \(headline)"]
        lines += summaryLines.map { "  \($0)" }
        if !problems.isEmpty {
            lines.append("Problems:")
            lines += problems.map { "  - \($0.cause)" }
        }
        lines.append("Hotkeys:")
        lines += hotkeys.map { "  \(hotkeyLine($0))" }
        return lines.joined(separator: "\n")
    }

    /// Status plus the most recent input lines from the action log, for Copy Input Diagnostics.
    func render(logText: String) -> String {
        let recent = logText.split(separator: "\n").filter { $0.contains(" input: ") }
            .suffix(LogPolicy.diagnosticsLineCount)
        return render() + "\n\nRecent input log (\(recent.count) lines):\n" + recent.joined(separator: "\n")
    }

    static let hotKeyExists: Int32 = -9878

    /// Carbon `RegisterEventHotKey` statuses worth naming; everything else prints raw.
    static func describe(_ status: Int32) -> String {
        switch status {
        case hotKeyExists: "OSStatus -9878 eventHotKeyExistsErr"
        case -9879: "OSStatus -9879 eventHotKeyInvalidErr"
        default: "OSStatus \(status)"
        }
    }
}
