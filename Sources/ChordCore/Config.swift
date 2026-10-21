/// A physical key position, named by the W3C `KeyboardEvent.code` value
/// (`KeyH`, `Digit9`, `Backquote`). Bindings never use characters, so a
/// keyboard layout cannot move them.
public struct PhysicalKey: Hashable, Sendable {
  public let code: String

  /// Accepts only names in the closed set below; anything else is nil.
  public init?(code: String) {
    guard PhysicalKey.allCodes.contains(code) else { return nil }
    self.code = code
  }

  private init(trustedCode: String) {
    self.code = trustedCode
  }

  public static let keyH = PhysicalKey(trustedCode: "KeyH")
  public static let keyJ = PhysicalKey(trustedCode: "KeyJ")
  public static let keyK = PhysicalKey(trustedCode: "KeyK")
  public static let keyL = PhysicalKey(trustedCode: "KeyL")
  public static let backquote = PhysicalKey(trustedCode: "Backquote")
  public static let digit4 = PhysicalKey(trustedCode: "Digit4")
  public static let digit9 = PhysicalKey(trustedCode: "Digit9")

  private static let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map { "Key\($0)" }
  private static let digits = "0123456789".map { "Digit\($0)" }
  private static let punctuation = [
    "Backquote", "Minus", "Equal", "BracketLeft", "BracketRight", "Backslash",
    "Semicolon", "Quote", "Comma", "Period", "Slash", "Space",
  ]
  private static let allCodes: Set<String> = Set(letters + digits + punctuation)
}

/// Key bindings. Names match the `[keys]` table.
public struct KeyBindings: Equatable, Sendable {
  public let left: PhysicalKey
  public let down: PhysicalKey
  public let up: PhysicalKey
  public let right: PhysicalKey
  public let bench: PhysicalKey
  /// Place 4, the redacted tier.
  public let redactedTier: PhysicalKey
  /// Place 9, the vault. Users may bind it; agents never reach it.
  public let vault: PhysicalKey

  public static let defaults = KeyBindings(
    left: .keyH, down: .keyJ, up: .keyK, right: .keyL,
    bench: .backquote, redactedTier: .digit4, vault: .digit9)
}

/// Durations in milliseconds.
public struct Timing: Equatable, Sendable {
  public let holdMs: Int
  public let tapMs: Int
  public let chordWindowMs: Int
  public let a5HoldMs: Int
  /// Presses within this window step an Unfold up; after it expires the next press resets to A5.
  public let unfoldStepWindowMs: Int

  public static let defaults = Timing(
    holdMs: 700, tapMs: 250, chordWindowMs: 35, a5HoldMs: 200, unfoldStepWindowMs: 1000)
}

/// Carry step sizes in pixels for held-direction repeats.
public struct CarryRamp: Equatable, Sendable {
  public let near: Int
  public let middle: Int
  public let far: Int

  public static let defaults = CarryRamp(near: 10, middle: 20, far: 30)
}

public struct Carry: Equatable, Sendable {
  public let ramp: CarryRamp
  public let edgeMagnetPx: Int

  public static let defaults = Carry(ramp: .defaults, edgeMagnetPx: 30)
}

public struct Backend: Equatable, Sendable {
  /// The pinned AeroSpace release tag.
  public let aerospaceTag: String

  public static let defaults = Backend(aerospaceTag: "v0.21.3-Beta")
}

/// Update checks. Off by default. The menu's "Check for Updates…" item works regardless.
public struct Updates: Equatable, Sendable {
  /// Once-a-day background check against the GitHub Releases API.
  public let backgroundCheck: Bool

  public static let defaults = Updates(backgroundCheck: false)
}

/// Size a user may ask for ahead of time. Size stays the user's decision; a
/// standing wish is that decision recorded as a rule. These are the only
/// size-changing commands a config can name.
public enum WishSize: String, CaseIterable, Sendable {
  case fullscreen
  case zoom
}

/// `"App Name" = "fullscreen"` under `[standing_wishes]`.
public struct StandingWish: Equatable, Sendable {
  public let app: String
  public let size: WishSize
}

/// Something wrong with a config file. Each case carries the 1-based line.
public enum ConfigDiagnostic: Equatable, Sendable {
  case syntax(line: Int, message: String)
  case unknownTable(line: Int, table: String)
  case unknownKey(line: Int, key: String)
  case wrongType(line: Int, key: String, expected: String)
  case outOfRange(line: Int, key: String, min: Int, max: Int)
  case invalidValue(line: Int, key: String, reason: String)
  case duplicateBinding(line: Int, key: String, conflictsWith: String, code: String)

  public var line: Int {
    switch self {
    case .syntax(let line, _), .unknownTable(let line, _), .unknownKey(let line, _),
      .wrongType(let line, _, _), .outOfRange(let line, _, _, _),
      .invalidValue(let line, _, _), .duplicateBinding(let line, _, _, _):
      return line
    }
  }
}

public struct ConfigLoadResult: Equatable, Sendable {
  /// The parsed settings if `diagnostics` is empty, otherwise `Config.defaults`.
  public let config: Config
  /// Sorted by line.
  public let diagnostics: [ConfigDiagnostic]
}

/// User configuration. Parsing is all-or-nothing: any diagnostic yields
/// `Config.defaults`, so a file is never half-applied.
public struct Config: Equatable, Sendable {
  public let keys: KeyBindings
  public let timing: Timing
  public let carry: Carry
  public let backend: Backend
  public let updates: Updates
  /// The workspace grid: rows, their names, and what a step past the edge does.
  public let workspaces: WorkspaceLayout
  /// Sorted by app name.
  public let standingWishes: [StandingWish]

  public static let defaults = Config(
    keys: .defaults, timing: .defaults, carry: .defaults, backend: .defaults,
    updates: .defaults, workspaces: .defaults, standingWishes: [])

  /// Parses config text. Never traps on any input.
  public static func load(text: String) -> ConfigLoadResult {
    let document: TOMLDocument
    do {
      document = try TOMLParser.parse(text)
    } catch {
      return ConfigLoadResult(
        config: .defaults,
        diagnostics: [.syntax(line: error.line, message: error.message)])
    }

    var reader = ConfigReader()
    var keys = KeyBindings.defaults
    var timing = Timing.defaults
    var carry = Carry.defaults
    var backend = Backend.defaults
    var updates = Updates.defaults
    var workspaces = WorkspaceLayout.defaults
    var wishes: [StandingWish] = []

    for table in document.tables {
      switch table.name {
      case "":
        reader.reportUnknownKeys(in: table, known: [])
      case "keys":
        reader.reportUnknownKeys(in: table, known: KeyBindings.names)
        keys = reader.readKeys(table)
      case "timing":
        reader.reportUnknownKeys(
          in: table,
          known: [
            "hold_ms", "tap_ms", "chord_window_ms", "a5_hold_ms",
            "unfold_step_window_ms",
          ])
        timing = reader.readTiming(table)
      case "carry":
        reader.reportUnknownKeys(in: table, known: ["ramp_px", "edge_magnet_px"])
        carry = reader.readCarry(table)
      case "backend":
        reader.reportUnknownKeys(in: table, known: ["aerospace_tag"])
        backend = reader.readBackend(table)
      case "updates":
        reader.reportUnknownKeys(in: table, known: ["background_check"])
        updates = reader.readUpdates(table)
      case "workspaces":
        reader.reportUnknownKeys(in: table, known: ["rows", "row_names", "wrap"])
        workspaces = reader.readWorkspaces(table)
      case "standing_wishes":
        wishes = reader.readStandingWishes(table)
      default:
        reader.diagnostics.append(.unknownTable(line: table.line, table: table.name))
      }
    }

    let diagnostics = reader.diagnostics.sorted { $0.line < $1.line }
    guard diagnostics.isEmpty else {
      return ConfigLoadResult(config: .defaults, diagnostics: diagnostics)
    }
    let config = Config(
      keys: keys, timing: timing, carry: carry, backend: backend, updates: updates,
      workspaces: workspaces, standingWishes: wishes.sorted { $0.app < $1.app })
    return ConfigLoadResult(config: config, diagnostics: [])
  }

  /// Canonical TOML text. `Config.load(text: config.tomlText())` returns `config`.
  public func tomlText() -> String {
    var lines: [String] = [
      "[keys]",
      "left = \(tomlQuoted(keys.left.code))",
      "down = \(tomlQuoted(keys.down.code))",
      "up = \(tomlQuoted(keys.up.code))",
      "right = \(tomlQuoted(keys.right.code))",
      "bench = \(tomlQuoted(keys.bench.code))",
      "redacted_tier = \(tomlQuoted(keys.redactedTier.code))",
      "vault = \(tomlQuoted(keys.vault.code))",
      "",
      "[timing]",
      "hold_ms = \(timing.holdMs)",
      "tap_ms = \(timing.tapMs)",
      "chord_window_ms = \(timing.chordWindowMs)",
      "a5_hold_ms = \(timing.a5HoldMs)",
      "unfold_step_window_ms = \(timing.unfoldStepWindowMs)",
      "",
      "[carry]",
      "ramp_px = [\(carry.ramp.near), \(carry.ramp.middle), \(carry.ramp.far)]",
      "edge_magnet_px = \(carry.edgeMagnetPx)",
      "",
      "[backend]",
      "aerospace_tag = \(tomlQuoted(backend.aerospaceTag))",
      "",
      "[updates]",
      "background_check = \(updates.backgroundCheck)",
      "",
      "[workspaces]",
      "rows = \(workspaces.rows)",
    ]
    if !workspaces.rowNames.isEmpty {
      lines.append("row_names = [\(workspaces.rowNames.map(tomlQuoted).joined(separator: ", "))]")
    }
    lines += [
      "wrap = \(workspaces.wrap)",
      "",
      "[standing_wishes]",
    ]
    for wish in standingWishes {
      lines.append("\(tomlQuoted(wish.app)) = \(tomlQuoted(wish.size.rawValue))")
    }
    return lines.joined(separator: "\n") + "\n"
  }
}

private func tomlQuoted(_ text: String) -> String {
  var out = "\""
  for c in text {
    switch c {
    case "\"": out += "\\\""
    case "\\": out += "\\\\"
    case "\n": out += "\\n"
    case "\t": out += "\\t"
    case "\r": out += "\\r"
    default: out.append(c)
    }
  }
  return out + "\""
}

extension KeyBindings {
  static let names = ["left", "down", "up", "right", "bench", "redacted_tier", "vault"]
}

/// Reads typed values from a parsed table, recording a diagnostic for each
/// bad value and substituting the default so reading can continue.
private struct ConfigReader {
  var diagnostics: [ConfigDiagnostic] = []

  static let msRange = 1...5000
  static let pxRange = 1...500
  static let edgeRange = 0...500

  mutating func reportUnknownKeys(in table: TOMLTable, known: [String]) {
    let knownSet = Set(known)
    for (key, entry) in table.entries.sorted(by: { $0.value.line < $1.value.line })
    where !knownSet.contains(key) {
      diagnostics.append(.unknownKey(line: entry.line, key: qualified(table, key)))
    }
  }

  private func qualified(_ table: TOMLTable, _ key: String) -> String {
    table.name == "standing_wishes" ? "\(table.name).\(key)" : key
  }

  private mutating func string(_ entry: TOMLEntry, key: String) -> String? {
    if case .string(let value) = entry.value { return value }
    diagnostics.append(.wrongType(line: entry.line, key: key, expected: "string"))
    return nil
  }

  private mutating func integer(_ entry: TOMLEntry, key: String, range: ClosedRange<Int>) -> Int? {
    guard case .integer(let value) = entry.value else {
      diagnostics.append(.wrongType(line: entry.line, key: key, expected: "integer"))
      return nil
    }
    guard range.contains(value) else {
      diagnostics.append(
        .outOfRange(
          line: entry.line, key: key, min: range.lowerBound, max: range.upperBound))
      return nil
    }
    return value
  }

  private mutating func physicalKey(_ entry: TOMLEntry, key: String) -> PhysicalKey? {
    guard let code = string(entry, key: key) else { return nil }
    guard let physical = PhysicalKey(code: code) else {
      diagnostics.append(
        .invalidValue(
          line: entry.line, key: key, reason: "'\(code)' is not a physical key name"))
      return nil
    }
    return physical
  }

  private mutating func binding(
    _ table: TOMLTable, _ name: String, default fallback: PhysicalKey
  ) -> PhysicalKey {
    guard let entry = table.entries[name] else { return fallback }
    return physicalKey(entry, key: qualified(table, name)) ?? fallback
  }

  private mutating func integer(
    _ table: TOMLTable, _ name: String, range: ClosedRange<Int>, default fallback: Int
  ) -> Int {
    guard let entry = table.entries[name] else { return fallback }
    return integer(entry, key: qualified(table, name), range: range) ?? fallback
  }

  mutating func readKeys(_ table: TOMLTable) -> KeyBindings {
    let d = KeyBindings.defaults
    let keys = KeyBindings(
      left: binding(table, "left", default: d.left),
      down: binding(table, "down", default: d.down),
      up: binding(table, "up", default: d.up),
      right: binding(table, "right", default: d.right),
      bench: binding(table, "bench", default: d.bench),
      redactedTier: binding(table, "redacted_tier", default: d.redactedTier),
      vault: binding(table, "vault", default: d.vault))

    let ordered: [(name: String, key: PhysicalKey)] = [
      ("left", keys.left), ("down", keys.down), ("up", keys.up), ("right", keys.right),
      ("bench", keys.bench), ("redacted_tier", keys.redactedTier), ("vault", keys.vault),
    ]
    // Defaults are distinct, so a conflict always involves a key the file set.
    // Report on the explicit entry; prefer the later one when both are set.
    for i in ordered.indices {
      for j in ordered.indices where j > i && ordered[i].key == ordered[j].key {
        let second = ordered[j].name
        let first = ordered[i].name
        let explicit = table.entries[second] != nil ? second : first
        let other = explicit == second ? first : second
        guard let entry = table.entries[explicit] else { continue }
        diagnostics.append(
          .duplicateBinding(
            line: entry.line, key: qualified(table, explicit),
            conflictsWith: other, code: ordered[i].key.code))
      }
    }
    return keys
  }

  mutating func readTiming(_ table: TOMLTable) -> Timing {
    let d = Timing.defaults
    return Timing(
      holdMs: integer(table, "hold_ms", range: Self.msRange, default: d.holdMs),
      tapMs: integer(table, "tap_ms", range: Self.msRange, default: d.tapMs),
      chordWindowMs: integer(
        table, "chord_window_ms", range: Self.msRange, default: d.chordWindowMs),
      a5HoldMs: integer(table, "a5_hold_ms", range: Self.msRange, default: d.a5HoldMs),
      unfoldStepWindowMs: integer(
        table, "unfold_step_window_ms", range: Self.msRange, default: d.unfoldStepWindowMs))
  }

  mutating func readCarry(_ table: TOMLTable) -> Carry {
    let d = Carry.defaults
    let edge = integer(table, "edge_magnet_px", range: Self.edgeRange, default: d.edgeMagnetPx)
    return Carry(ramp: readRamp(table, default: d.ramp), edgeMagnetPx: edge)
  }

  private mutating func readRamp(_ table: TOMLTable, default fallback: CarryRamp) -> CarryRamp {
    guard let entry = table.entries["ramp_px"] else { return fallback }
    let key = qualified(table, "ramp_px")
    guard case .array(let items) = entry.value else {
      diagnostics.append(.wrongType(line: entry.line, key: key, expected: "array of 3 integers"))
      return fallback
    }
    guard items.count == 3 else {
      diagnostics.append(
        .invalidValue(
          line: entry.line, key: key, reason: "expected exactly 3 steps, found \(items.count)"))
      return fallback
    }
    let before = diagnostics.count
    let steps = items.map { item in
      integer(TOMLEntry(value: item, line: entry.line), key: key, range: Self.pxRange) ?? 0
    }
    guard diagnostics.count == before else { return fallback }
    return CarryRamp(near: steps[0], middle: steps[1], far: steps[2])
  }

  mutating func readBackend(_ table: TOMLTable) -> Backend {
    guard let entry = table.entries["aerospace_tag"] else { return .defaults }
    let key = qualified(table, "aerospace_tag")
    guard let tag = string(entry, key: key) else { return .defaults }
    guard !tag.isEmpty, !tag.contains(where: { $0 == " " || $0 == "\t" }) else {
      diagnostics.append(
        .invalidValue(
          line: entry.line, key: key, reason: "must be non-empty with no spaces"))
      return .defaults
    }
    return Backend(aerospaceTag: tag)
  }

  mutating func readUpdates(_ table: TOMLTable) -> Updates {
    guard let entry = table.entries["background_check"] else { return .defaults }
    let key = qualified(table, "background_check")
    guard case .boolean(let value) = entry.value else {
      diagnostics.append(.wrongType(line: entry.line, key: key, expected: "boolean"))
      return .defaults
    }
    return Updates(backgroundCheck: value)
  }

  mutating func readWorkspaces(_ table: TOMLTable) -> WorkspaceLayout {
    let d = WorkspaceLayout.defaults
    let before = diagnostics.count
    var wrap = d.wrap
    if let entry = table.entries["wrap"] {
      if case .boolean(let value) = entry.value {
        wrap = value
      } else {
        diagnostics.append(.wrongType(line: entry.line, key: "wrap", expected: "boolean"))
      }
    }
    let names = readRowNames(table)
    // Names given alone set the row count; given with `rows` they must agree with it.
    let rows: Int
    if let entry = table.entries["rows"] {
      rows = integer(entry, key: "rows", range: 1...WorkspaceLayout.maxRows) ?? d.rows
      if let names, diagnostics.count == before, names.count != rows {
        diagnostics.append(
          .invalidValue(
            line: table.entries["row_names"]?.line ?? entry.line, key: "row_names",
            reason: "rows is \(rows) but \(names.count) names are given"))
      }
    } else {
      rows = names?.count ?? d.rows
    }
    guard diagnostics.count == before else { return d }
    return WorkspaceLayout(rows: rows, rowNames: names ?? [], wrap: wrap)
  }

  /// `row_names = ["work", "home"]`: one non-empty string per row, at most `maxRows`.
  private mutating func readRowNames(_ table: TOMLTable) -> [String]? {
    guard let entry = table.entries["row_names"] else { return nil }
    guard case .array(let items) = entry.value else {
      diagnostics.append(.wrongType(line: entry.line, key: "row_names", expected: "array of strings"))
      return nil
    }
    guard (1...WorkspaceLayout.maxRows).contains(items.count) else {
      diagnostics.append(
        .invalidValue(
          line: entry.line, key: "row_names",
          reason: "expected 1 to \(WorkspaceLayout.maxRows) names, found \(items.count)"))
      return nil
    }
    var names: [String] = []
    for item in items {
      guard case .string(let name) = item else {
        diagnostics.append(.wrongType(line: entry.line, key: "row_names", expected: "array of strings"))
        return nil
      }
      guard !name.allSatisfy({ $0 == " " || $0 == "\t" }) else {
        diagnostics.append(
          .invalidValue(line: entry.line, key: "row_names", reason: "a row name is empty"))
        return nil
      }
      names.append(name)
    }
    return names
  }

  mutating func readStandingWishes(_ table: TOMLTable) -> [StandingWish] {
    var wishes: [StandingWish] = []
    for (app, entry) in table.entries.sorted(by: { $0.value.line < $1.value.line }) {
      let key = "standing_wishes.\"\(app)\""
      guard let raw = string(entry, key: key) else { continue }
      guard let size = WishSize(rawValue: raw) else {
        diagnostics.append(
          .invalidValue(
            line: entry.line, key: key,
            reason:
              "'\(raw)' is not a standing wish size; expected one of \(WishSize.allCases.map(\.rawValue).joined(separator: ", "))"
          ))
        continue
      }
      guard !app.isEmpty else {
        diagnostics.append(.invalidValue(line: entry.line, key: key, reason: "app name is empty"))
        continue
      }
      wishes.append(StandingWish(app: app, size: size))
    }
    return wishes
  }
}
