/// Workspaces a plan may name. Place 9 (the vault) has no case, so no plan can
/// name it: not by construction, not by decoding, not by fallback.
public enum Workspace: Int, CaseIterable, Sendable, Codable {
    case one = 1, two, three, four, five, six, seven, eight
}

/// Where a window belongs: one of the workspaces, or the bench (the undecided pile).
public enum Place: Equatable, Sendable {
    case workspace(Workspace)
    case bench
}

/// Why an agent placed a window where it did.
public enum Reason: Equatable, Sendable {
    case pinned
    case appRule
    case remembered
    case inferred(confidence: Double)
}

/// One window's target place and the reason for it.
public struct Assignment: Equatable, Sendable {
    public let windowID: Int
    public let place: Place
    public let reason: Reason

    public init(windowID: Int, place: Place, reason: Reason) {
        self.windowID = windowID
        self.place = place
        self.reason = reason
    }
}

public enum PlanError: Error, Equatable, Sendable {
    case duplicateWindow(Int)
    case unknownWindow(Int)
    case invalidConfidence(windowID: Int)
}

/// Typed data an agent emits. The Executor is the only consumer; it applies
/// a plan only after `validate(knownWindows:)` succeeds.
public struct Plan: Equatable, Sendable {
    public let assignments: [Assignment]

    /// Rejects a window that appears twice and an inferred confidence outside 0...1.
    public init(assignments: [Assignment]) throws {
        var seen = Set<Int>()
        for assignment in assignments {
            guard seen.insert(assignment.windowID).inserted else {
                throw PlanError.duplicateWindow(assignment.windowID)
            }
            guard Plan.hasValidReason(assignment) else {
                throw PlanError.invalidConfidence(windowID: assignment.windowID)
            }
        }
        self.assignments = assignments
    }

    /// Rejects any assignment naming a window the caller does not know about.
    public func validate(knownWindows: Set<Int>) throws {
        for assignment in assignments where !knownWindows.contains(assignment.windowID) {
            throw PlanError.unknownWindow(assignment.windowID)
        }
    }

    /// Returns `decoded` when it is present and names only known windows. Otherwise
    /// returns the rules + bench fallback. Callers decode with `JSONDecoder` and pass
    /// `try? decode(...)` here, so a malformed plan never reaches the Executor.
    public static func acceptingOrFallingBack(
        _ decoded: Plan?, knownWindows: [Int], rules: [Assignment]
    ) -> Plan {
        if let decoded, (try? decoded.validate(knownWindows: Set(knownWindows))) != nil {
            return decoded
        }
        return fallback(knownWindows: knownWindows, rules: rules)
    }

    /// Each known window takes its rule's assignment (first rule wins; rules for
    /// unknown windows are ignored). Every other known window goes to the bench with
    /// confidence 0, recording that no inference was made.
    public static func fallback(knownWindows: [Int], rules: [Assignment]) -> Plan {
        let known = Set(knownWindows)
        var ruled: [Int: Assignment] = [:]
        for rule in rules where known.contains(rule.windowID) && hasValidReason(rule) {
            if ruled[rule.windowID] == nil { ruled[rule.windowID] = rule }
        }
        let assignments = known.sorted().map { id in
            ruled[id]
                ?? Assignment(windowID: id, place: .bench, reason: .inferred(confidence: 0))
        }
        // Every window appears once and every reason is valid, so init cannot fail.
        return Plan(uncheckedAssignments: assignments)
    }

    /// The actions that move each window from its current place to its planned place,
    /// followed by requested frame, focus, or home actions. Every action must name a
    /// window in `model`.
    public func actions(from model: [Int: Place], requested: [Action] = []) throws -> [Action] {
        try validate(knownWindows: Set(model.keys))
        for action in requested {
            guard model[action.windowID] != nil else {
                throw PlanError.unknownWindow(action.windowID)
            }
        }
        let placeActions = assignments.compactMap { assignment -> Action? in
            guard let current = model[assignment.windowID], current != assignment.place else { return nil }
            return .place(windowID: assignment.windowID, from: current, to: assignment.place)
        }
        return placeActions + requested
    }

    private init(uncheckedAssignments assignments: [Assignment]) {
        self.assignments = assignments
    }

    private static func hasValidReason(_ assignment: Assignment) -> Bool {
        if case .inferred(let confidence) = assignment.reason {
            return (0...1).contains(confidence)
        }
        return true
    }
}

/// A screen rectangle in logical points, independent of the window backend.
public struct ActionRect: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
    fileprivate var logDescription: String { "(\(x), \(y), \(width), \(height))" }
}

/// A remembered window home: its place and frame.
public struct WindowHome: Equatable, Sendable {
    public let place: Place
    public let frame: ActionRect

    public init(place: Place, frame homeFrame: ActionRect) {
        self.place = place
        frame = homeFrame
    }
    fileprivate var logDescription: String { "\(place) \(frame.logDescription)" }
}

/// A reversible typed change applied by the Executor. A focus action with no prior
/// focused window inverts to a logged no-op because the backend cannot clear focus.
public enum Action: Equatable, Sendable {
    case place(windowID: Int, from: Place, to: Place)
    case frame(windowID: Int, from: ActionRect, to: ActionRect)
    case focus(from: Int?, to: Int)
    case restoreHome(windowID: Int, from: WindowHome, to: WindowHome)
    /// A user reshape step. The deltas are log-space and recorded for the log;
    /// `from` and `to` are what the inverse restores.
    case reshape(windowID: Int, aspectDelta: Double, areaDelta: Double, from: ActionRect, to: ActionRect)
    case noop(windowID: Int)

    public var windowID: Int {
        switch self {
        case .place(let id, _, _), .frame(let id, _, _), .restoreHome(let id, _, _), .noop(let id),
            .reshape(let id, _, _, _, _): return id
        case .focus(_, let id): return id
        }
    }

    public var inverse: Action {
        switch self {
        case .place(let id, let from, let to): return .place(windowID: id, from: to, to: from)
        case .frame(let id, let from, let to): return .frame(windowID: id, from: to, to: from)
        // Without a prior focused window, inverse is an explicit no-op; the backend cannot clear focus.
        case .focus(let from, let to): return from.map { .focus(from: to, to: $0) } ?? .noop(windowID: to)
        case .restoreHome(let id, let from, let to): return .restoreHome(windowID: id, from: to, to: from)
        case .reshape(let id, let aspect, let area, let from, let to):
            return .reshape(windowID: id, aspectDelta: 0 - aspect, areaDelta: 0 - area, from: to, to: from)
        case .noop: return self
        }
    }

    public var logLine: String {
        switch self {
        case .place(let id, let from, let to): return "place window \(id): \(from) -> \(to)"
        case .frame(let id, let from, let to):
            return "frame window \(id): \(from.logDescription) -> \(to.logDescription)"
        case .focus(let from, let to): return "focus window \(to) (was \(from.map(String.init) ?? "none"))"
        case .restoreHome(let id, _, let to):
            return "restore home for window \(id): \(to.logDescription)"
        case .reshape(let id, let aspect, let area, let from, let to):
            return "reshape window \(id) (aspect \(aspect), area \(area)): \(from.logDescription) -> \(to.logDescription)"
        case .noop: return "nothing to restore"
        }
    }

    /// Updates the place model when this action is a place transition.
    @discardableResult
    public func apply(to model: inout [Int: Place]) -> Bool {
        guard case .place(let id, let from, let to) = self, model[id] == from else { return false }
        model[id] = to
        return true
    }
}


// MARK: - Strict Codable

/// Coding key that accepts any name, so unknown keys can be detected and rejected.
private struct AnyKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private func requireOnlyKeys(_ decoder: any Decoder, allowed: Set<String>) throws {
    let keys = try decoder.container(keyedBy: AnyKey.self).allKeys.map(\.stringValue)
    if let unknown = keys.first(where: { !allowed.contains($0) }) {
        throw DecodingError.dataCorrupted(
            .init(codingPath: decoder.codingPath, debugDescription: "unknown key \(unknown)"))
    }
}

extension Place: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let name = try? container.decode(String.self) {
            guard name == "bench" else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "unknown place \(name)")
            }
            self = .bench
        } else {
            self = .workspace(try container.decode(Workspace.self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bench: try container.encode("bench")
        case .workspace(let workspace): try container.encode(workspace)
        }
    }
}

extension Reason: Codable {
    private enum InferredKey: String, CodingKey { case inferred }

    public init(from decoder: any Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
            let name = try? container.decode(String.self)
        {
            switch name {
            case "pinned": self = .pinned
            case "appRule": self = .appRule
            case "remembered": self = .remembered
            default:
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "unknown reason \(name)")
            }
            return
        }
        try requireOnlyKeys(decoder, allowed: ["inferred"])
        let container = try decoder.container(keyedBy: InferredKey.self)
        self = .inferred(confidence: try container.decode(Double.self, forKey: .inferred))
    }

    private func encodeName(_ name: String, to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(name)
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .pinned:
            try encodeName("pinned", to: encoder)
        case .appRule:
            try encodeName("appRule", to: encoder)
        case .remembered:
            try encodeName("remembered", to: encoder)
        case .inferred(let confidence):
            var container = encoder.container(keyedBy: InferredKey.self)
            try container.encode(confidence, forKey: .inferred)
        }
    }
}

extension Assignment: Codable {
    private enum Key: String, CodingKey { case window, place, reason }

    public init(from decoder: any Decoder) throws {
        try requireOnlyKeys(decoder, allowed: ["window", "place", "reason"])
        let container = try decoder.container(keyedBy: Key.self)
        self.init(
            windowID: try container.decode(Int.self, forKey: .window),
            place: try container.decode(Place.self, forKey: .place),
            reason: try container.decode(Reason.self, forKey: .reason))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(windowID, forKey: .window)
        try container.encode(place, forKey: .place)
        try container.encode(reason, forKey: .reason)
    }
}

extension Plan: Codable {
    private enum Key: String, CodingKey { case assignments }

    public init(from decoder: any Decoder) throws {
        try requireOnlyKeys(decoder, allowed: ["assignments"])
        let container = try decoder.container(keyedBy: Key.self)
        try self.init(assignments: container.decode([Assignment].self, forKey: .assignments))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(assignments, forKey: .assignments)
    }
}

// MARK: - Redacted tier (workspace 4)

/// A title an agent may see for a workspace-4 window. It stores nothing, so the
/// raw title cannot leak through it.
public struct RedactedTitle: Equatable, Sendable {
    public init() {}
    public var display: String { "[redacted]" }
}

/// Agent-facing view of a workspace-4 window: app name and redacted title only.
public struct RedactedTierWindow: Equatable, Sendable {
    public let windowID: Int
    public let appName: String
    public let title: RedactedTitle

    public init(windowID: Int, appName: String) {
        self.windowID = windowID
        self.appName = appName
        self.title = RedactedTitle()
    }
}
