/// A value in the TOML subset Chord reads: strings, integers, floats,
/// booleans, and single-line arrays of those.
public enum TOMLValue: Equatable, Sendable {
  case string(String)
  case integer(Int)
  case float(Double)
  case boolean(Bool)
  case array([TOMLValue])
}

/// One `key = value` line, with the 1-based line it appeared on.
public struct TOMLEntry: Equatable, Sendable {
  public let value: TOMLValue
  public let line: Int

  public init(value: TOMLValue, line: Int) {
    self.value = value
    self.line = line
  }
}

/// A `[name]` table, or the root table (name `""`, line 0) holding keys that
/// appear before any header.
public struct TOMLTable: Equatable, Sendable {
  public let name: String
  public let line: Int
  public let entries: [String: TOMLEntry]

  public init(name: String, line: Int, entries: [String: TOMLEntry]) {
    self.name = name
    self.line = line
    self.entries = entries
  }
}

/// A parsed document: the root table first, then each header in file order.
public struct TOMLDocument: Equatable, Sendable {
  public let tables: [TOMLTable]

  public init(tables: [TOMLTable]) {
    self.tables = tables
  }
}

/// A syntax or unsupported-construct error, pointing at the 1-based line.
public struct TOMLParseError: Error, Equatable, Sendable {
  public let line: Int
  public let message: String

  public init(line: Int, message: String) {
    self.line = line
    self.message = message
  }
}

/// Hand-written parser for the TOML subset Chord reads.
///
/// Accepted: `[table]` headers, bare or double-quoted keys, basic strings with
/// escapes `\" \\ \n \t \r`, decimal integers, floats, `true`/`false`,
/// single-line arrays of scalars (trailing comma allowed), and `#` comments.
/// Everything else (dotted keys, inline tables, arrays of tables, literal
/// strings, multi-line values, dates, hex/octal/binary, `inf`/`nan`, nested
/// arrays) is rejected with the line it appears on.
public enum TOMLParser {
  public static func parse(_ text: String) throws(TOMLParseError) -> TOMLDocument {
    var finished: [TOMLTable] = []
    var seenNames: Set<String> = [""]
    var current = TableBuilder(name: "", line: 0)

    // Only "\n" and "\r\n" separate lines. Character.isNewline also matches
    // U+2028 and friends, which may legally appear inside strings.
    let lines = text.split(
      omittingEmptySubsequences: false,
      whereSeparator: { $0 == "\n" || $0 == "\r\n" })

    for (index, lineText) in lines.enumerated() {
      let lineNumber = index + 1
      var scanner = LineScanner(lineText, line: lineNumber)
      scanner.skipSpaces()
      if scanner.atEnd || scanner.peek == "#" { continue }

      if scanner.peek == "[" {
        let name = try scanner.parseTableHeader()
        guard seenNames.insert(name).inserted else {
          throw TOMLParseError(line: lineNumber, message: "duplicate table [\(name)]")
        }
        finished.append(current.table)
        current = TableBuilder(name: name, line: lineNumber)
      } else {
        let (key, value) = try scanner.parseKeyValue()
        guard current.entries[key] == nil else {
          throw TOMLParseError(line: lineNumber, message: "duplicate key '\(key)'")
        }
        current.entries[key] = TOMLEntry(value: value, line: lineNumber)
      }
    }
    finished.append(current.table)
    return TOMLDocument(tables: finished)
  }
}

private struct TableBuilder {
  let name: String
  let line: Int
  var entries: [String: TOMLEntry] = [:]

  init(name: String, line: Int) {
    self.name = name
    self.line = line
  }

  var table: TOMLTable {
    TOMLTable(name: name, line: line, entries: entries)
  }
}

private func isDigit(_ c: Character) -> Bool {
  c >= "0" && c <= "9"
}

private func isBareKeyCharacter(_ c: Character) -> Bool {
  isDigit(c) || (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || c == "_" || c == "-"
}

private func skipDigits(_ s: inout Substring) {
  while let c = s.first, isDigit(c) { s.removeFirst() }
}

/// Decimal integer: optional sign, then `0` or a nonzero-led digit run.
private func isDecimalInteger(_ s: String) -> Bool {
  var rest = Substring(s)
  if rest.first == "+" || rest.first == "-" { rest.removeFirst() }
  guard let first = rest.first, isDigit(first) else { return false }
  if first == "0" { return rest.count == 1 }
  skipDigits(&rest)
  return rest.isEmpty
}

/// Decimal float: integer part, then an optional fraction and optional
/// exponent, with at least one of the two present.
private func isDecimalFloat(_ s: String) -> Bool {
  var rest = Substring(s)
  if rest.first == "+" || rest.first == "-" { rest.removeFirst() }
  guard let first = rest.first, isDigit(first) else { return false }
  if first == "0" {
    rest.removeFirst()
    if let next = rest.first, isDigit(next) { return false }
  } else {
    skipDigits(&rest)
  }

  var hasFraction = false
  var hasExponent = false
  if rest.first == "." {
    rest.removeFirst()
    guard let d = rest.first, isDigit(d) else { return false }
    skipDigits(&rest)
    hasFraction = true
  }
  if rest.first == "e" || rest.first == "E" {
    rest.removeFirst()
    if rest.first == "+" || rest.first == "-" { rest.removeFirst() }
    guard let d = rest.first, isDigit(d) else { return false }
    skipDigits(&rest)
    hasExponent = true
  }
  return rest.isEmpty && (hasFraction || hasExponent)
}
private func isControlScalar(_ value: UInt32) -> Bool {
  (0x00...0x1F).contains(value) || (0x7F...0x9F).contains(value)
}

private struct LineScanner {
  private let chars: [Character]
  private var pos = 0
  private let line: Int

  init(_ text: Substring, line: Int) {
    self.chars = Array(text)
    self.line = line
  }

  var atEnd: Bool { pos >= chars.count }

  var peek: Character? { pos < chars.count ? chars[pos] : nil }

  private var lookahead: Character? { pos + 1 < chars.count ? chars[pos + 1] : nil }

  private func fail(_ message: String) -> TOMLParseError {
    TOMLParseError(line: line, message: message)
  }

  mutating func skipSpaces() {
    while let c = peek, c == " " || c == "\t" { pos += 1 }
  }

  /// Requires nothing but spaces or a comment to remain on the line.
  private mutating func expectLineEnd() throws(TOMLParseError) {
    skipSpaces()
    if atEnd || peek == "#" { return }
    throw fail("unexpected characters after value")
  }

  /// Parses `[name]` and returns the name. Positioned on the opening `[`.
  mutating func parseTableHeader() throws(TOMLParseError) -> String {
    if lookahead == "[" {
      throw fail("arrays of tables ([[name]]) are not supported")
    }
    pos += 1
    skipSpaces()
    let name = try parseKey()
    skipSpaces()
    if peek == "." { throw fail("dotted table names are not supported") }
    guard peek == "]" else { throw fail("expected ']' to close table header") }
    pos += 1
    try expectLineEnd()
    return name
  }

  mutating func parseKeyValue() throws(TOMLParseError) -> (String, TOMLValue) {
    let key = try parseKey()
    skipSpaces()
    if peek == "." { throw fail("dotted keys are not supported") }
    guard peek == "=" else { throw fail("expected '=' after key '\(key)'") }
    pos += 1
    skipSpaces()
    let value = try parseValue(allowArray: true)
    try expectLineEnd()
    return (key, value)
  }

  private mutating func parseKey() throws(TOMLParseError) -> String {
    if peek == "\"" { return try parseBasicString() }
    var key = ""
    while let c = peek, isBareKeyCharacter(c) {
      key.append(c)
      pos += 1
    }
    if key.isEmpty {
      if peek == "'" { throw fail("literal keys are not supported; use double quotes") }
      throw fail("expected a key")
    }
    return key
  }

  private mutating func parseValue(allowArray: Bool) throws(TOMLParseError) -> TOMLValue {
    guard let c = peek else { throw fail("expected a value") }
    switch c {
    case "\"":
      return .string(try parseBasicString())
    case "'":
      throw fail("literal strings are not supported; use double quotes")
    case "{":
      throw fail("inline tables are not supported")
    case "[":
      guard allowArray else { throw fail("nested arrays are not supported") }
      return .array(try parseArray())
    default:
      return try parseBareValue(takeToken())
    }
  }

  /// Positioned on `[`. Single-line only; a trailing comma is allowed.
  private mutating func parseArray() throws(TOMLParseError) -> [TOMLValue] {
    pos += 1
    var items: [TOMLValue] = []
    while true {
      skipSpaces()
      if atEnd || peek == "#" {
        throw fail("unterminated array; multi-line arrays are not supported")
      }
      if peek == "]" {
        pos += 1
        return items
      }
      items.append(try parseValue(allowArray: false))
      skipSpaces()
      if atEnd || peek == "#" {
        throw fail("unterminated array; multi-line arrays are not supported")
      }
      if peek == "," {
        pos += 1
      } else if peek == "]" {
        pos += 1
        return items
      } else {
        throw fail("expected ',' or ']' in array")
      }
    }
  }

  /// Consumes a run of characters up to whitespace, a delimiter, or a comment.
  private mutating func takeToken() -> String {
    var token = ""
    while let c = peek, !(c == " " || c == "\t" || c == "," || c == "]" || c == "#") {
      token.append(c)
      pos += 1
    }
    return token
  }

  private func parseBareValue(_ token: String) throws(TOMLParseError) -> TOMLValue {
    if token.isEmpty { throw fail("expected a value") }
    if token == "true" { return .boolean(true) }
    if token == "false" { return .boolean(false) }
    if isDecimalInteger(token) {
      guard let value = Int(token) else { throw fail("integer '\(token)' is out of range") }
      return .integer(value)
    }
    if isDecimalFloat(token) {
      guard let value = Double(token), value.isFinite else {
        throw fail("float '\(token)' is out of range")
      }
      return .float(value)
    }
    throw fail("unsupported value '\(token)'")
  }

  /// Positioned on the opening quote. Supports `\" \\ \n \t \r` only.
  private mutating func parseBasicString() throws(TOMLParseError) -> String {
    pos += 1
    var out = ""
    while true {
      guard let c = peek else { throw fail("unterminated string") }
      pos += 1
      if c == "\"" { return out }
      guard c == "\\" else {
        guard !c.unicodeScalars.contains(where: { isControlScalar($0.value) }) else {
          throw fail("unescaped control character in string")
        }
        out.append(c)
        continue
      }
      guard let escape = peek else { throw fail("unterminated string") }
      pos += 1
      switch escape {
      case "\"": out.append("\"")
      case "\\": out.append("\\")
      case "n": out.append("\n")
      case "t": out.append("\t")
      case "r": out.append("\r")
      default: throw fail("unsupported escape '\\\(escape)'")
      }
    }
  }
}
