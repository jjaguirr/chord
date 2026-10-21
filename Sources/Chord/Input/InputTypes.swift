import ChordCore

/// Which source delivered an event.
enum CapturePath: String, Sendable, CaseIterable {
    case carbon
    case tap
}

/// A physical key position by its W3C `KeyboardEvent.code` name (`KeyH`, `Digit0`, `Tab`).
/// Never a character, so a keyboard layout cannot move a binding.
struct InputKey: Hashable, Sendable {
    let code: String

    init(code: String) {
        self.code = code
    }

    init(_ physical: PhysicalKey) {
        self.code = physical.code
    }

    static let tab = InputKey(code: "Tab")
    static let escape = InputKey(code: "Escape")
    static let keyR = InputKey(code: "KeyR")
    static let keyW = InputKey(code: "KeyW")
    static let digit0 = InputKey(code: "Digit0")

    /// Short human label for logs and the menu: `H`, `0`, `` ` ``, `Tab`.
    var label: String {
        if code.hasPrefix("Key"), code.count == 4 { return String(code.dropFirst(3)) }
        if code.hasPrefix("Digit"), code.count == 6 { return String(code.dropFirst(5)) }
        switch code {
        case "Backquote": return "`"
        case "Escape": return "Esc"
        default: return code
        }
    }
}

/// Modifier flags as seen on one key event. Ctrl is read only to reject: Chord never uses it.
struct HeldModifiers: Equatable, Sendable {
    var option = false
    var shift = false
    var control = false
    var command = false

    init(option: Bool = false, shift: Bool = false, control: Bool = false, command: Bool = false) {
        self.option = option
        self.shift = shift
        self.control = control
        self.command = command
    }

    /// True when Option is down and Ctrl/Cmd are not: the only modifier family Chord binds.
    var isChordFamily: Bool { option && !control && !command }
}

enum KeyPhase: Equatable, Sendable {
    case down
    case up
    case autorepeat
}

/// One key event as a source saw it, before Chord decides whether it is a hotkey.
struct RawKeyEvent: Equatable, Sendable {
    var key: InputKey
    var modifiers: HeldModifiers
    var phase: KeyPhase
}

/// What a source should do with the event it just delivered. Carbon ignores this: a
/// registered hotkey is already consumed by the system.
enum EventDecision: Equatable, Sendable {
    case consume
    case passThrough
}

/// What a bound key means. Place, bench and Tab keys have no `KeyStateMachine` input: a
/// press is one workspace intent, made by `InputCapture`. The workspace layer key (W) is
/// held like the reshape key: the state machine turns hjkl into workspace steps while it is down.
enum HotkeyRole: Hashable, Sendable {
    case place
    case direction(ChordKey)
    case reshape
    case workspaceLayer
    case unfold
    case bench
    case cycle

    /// The state-machine key this role feeds, if any.
    var chordKey: ChordKey? {
        switch self {
        case .direction(let key): key
        case .reshape: .r
        case .workspaceLayer: .w
        case .unfold: .zero
        case .place, .bench, .cycle: nil
        }
    }

    var name: String {
        switch self {
        case .place: "place"
        case .direction: "direction"
        case .reshape: "reshape"
        case .workspaceLayer: "workspace layer"
        case .unfold: "unfold/spread"
        case .bench: "bench"
        case .cycle: "cycle"
        }
    }
}

/// One global hotkey: Option (always) plus optionally Shift, on one physical key.
struct HotkeyBinding: Hashable, Sendable {
    let key: InputKey
    let shift: Bool
    let role: HotkeyRole

    /// `Option+H`, `Option+Shift+3`.
    var label: String {
        "Option+\(shift ? "Shift+" : "")\(key.label)"
    }

    /// Identity for matching: role is derived from key and shift, never part of the lookup.
    struct Identity: Hashable, Sendable {
        let key: InputKey
        let shift: Bool
    }

    var identity: Identity { Identity(key: key, shift: shift) }
}

/// Outcome of asking one source to take one hotkey.
enum BindingOutcome: Equatable, Sendable {
    case registered
    /// `RegisterEventHotKey` failed; the payload is the raw OSStatus.
    case failed(Int32)
}

/// Why a whole source could not start.
enum SourceFailure: Equatable, Sendable {
    case handlerInstall(Int32)
    case tapCreateFailed
}

struct SourceStartReport: Equatable, Sendable {
    var outcomes: [HotkeyBinding: BindingOutcome] = [:]
    var failure: SourceFailure?
}
