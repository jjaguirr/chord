import Testing
@testable import ChordCore

@Suite("TOML subset parser")
struct TOMLParserTests {
    private func parseError(_ text: String) -> TOMLParseError? {
        do {
            _ = try TOMLParser.parse(text)
            return nil
        } catch {
            return error
        }
    }

    @Test("empty file yields only the root table with no entries")
    func emptyFile() throws {
        let document = try TOMLParser.parse("")
        #expect(document.tables.count == 1)
        #expect(document.tables[0].name == "")
        #expect(document.tables[0].entries.isEmpty)
    }

    @Test("comments and blank lines are ignored")
    func commentsAndBlanks() throws {
        let document = try TOMLParser.parse("# top\n\n  # indented\nkey = 1 # trailing\n")
        #expect(document.tables[0].entries["key"]?.value == .integer(1))
        #expect(document.tables[0].entries["key"]?.line == 4)
    }

    @Test("scalar values parse to their types")
    func scalars() throws {
        let text = """
        s = "hi"
        i = -42
        f = 1.5
        e = 1e3
        t = true
        n = false
        """
        let entries = try TOMLParser.parse(text).tables[0].entries
        #expect(entries["s"]?.value == .string("hi"))
        #expect(entries["i"]?.value == .integer(-42))
        #expect(entries["f"]?.value == .float(1.5))
        #expect(entries["e"]?.value == .float(1000))
        #expect(entries["t"]?.value == .boolean(true))
        #expect(entries["n"]?.value == .boolean(false))
    }

    @Test("floats reject leading-zero integer parts")
    func leadingZeroFloats() {
        #expect(parseError("x = 01.2\n")?.line == 1)
        #expect(parseError("x = -01e2\n")?.line == 1)
        #expect(parseError("x = [0.2, 01.2]\n")?.line == 1)
    }

    @Test("string escapes decode")
    func stringEscapes() throws {
        let entries = try TOMLParser.parse(#"s = "a\"b\\c\nd\te\rf""#).tables[0].entries
        #expect(entries["s"]?.value == .string("a\"b\\c\nd\te\rf"))
    }

    @Test("basic strings reject unescaped control characters")
    func unescapedControlCharacters() {
        #expect(parseError("x = \"a\tb\"\n")?.line == 1)
        #expect(parseError("x = \"a\u{0001}b\"\n")?.line == 1)
        #expect(parseError("\"a\u{0085}b\" = 1\n")?.line == 1)
    }

    @Test("single-line arrays of scalars, trailing comma allowed")
    func arrays() throws {
        let entries = try TOMLParser.parse(#"a = [10, 20, 30,]"#).tables[0].entries
        #expect(entries["a"]?.value == .array([.integer(10), .integer(20), .integer(30)]))
        let empty = try TOMLParser.parse("a = []").tables[0].entries
        #expect(empty["a"]?.value == .array([]))
    }

    @Test("tables are kept in file order with their header line")
    func tables() throws {
        let document = try TOMLParser.parse("[keys]\nleft = \"KeyH\"\n\n[timing]\nhold_ms = 700\n")
        #expect(document.tables.map(\.name) == ["", "keys", "timing"])
        #expect(document.tables[1].line == 1)
        #expect(document.tables[2].line == 4)
        #expect(document.tables[2].entries["hold_ms"]?.line == 5)
    }

    @Test("quoted keys are accepted, including app names with spaces")
    func quotedKeys() throws {
        let document = try TOMLParser.parse("[standing_wishes]\n\"Google Chrome\" = \"zoom\"\n")
        #expect(document.tables[1].entries["Google Chrome"]?.value == .string("zoom"))
    }

    @Test("CRLF line endings parse with the same line numbers")
    func crlf() throws {
        let document = try TOMLParser.parse("[a]\r\nx = 1\r\ny = 2\r\n")
        #expect(document.tables[1].entries["y"]?.line == 3)
    }

    @Test("duplicate table is an error on the second header")
    func duplicateTable() {
        let error = parseError("[a]\nx = 1\n[a]\n")
        #expect(error?.line == 3)
    }

    @Test("duplicate key is an error on the second assignment")
    func duplicateKey() {
        let error = parseError("[a]\nx = 1\nx = 2\n")
        #expect(error?.line == 3)
    }

    @Test("missing equals sign reports its line")
    func missingEquals() {
        #expect(parseError("[a]\n\nkey 1\n")?.line == 3)
    }

    @Test("unterminated string reports its line")
    func unterminatedString() {
        #expect(parseError("x = 1\ny = \"open\n")?.line == 2)
    }

    @Test("unterminated table header reports its line")
    func unterminatedHeader() {
        #expect(parseError("x = 1\n[keys\n")?.line == 2)
    }

    @Test("unsupported escape reports its line")
    func badEscape() {
        #expect(parseError("x = 1\ns = \"a\\qb\"\n")?.line == 2)
    }

    @Test("literal strings are rejected with a hint")
    func literalString() {
        let error = parseError("s = 'x'\n")
        #expect(error?.line == 1)
        #expect(error?.message.contains("double quotes") == true)
    }

    @Test("inline tables are rejected")
    func inlineTable() {
        #expect(parseError("t = { a = 1 }\n")?.line == 1)
    }

    @Test("arrays of tables are rejected")
    func arrayOfTables() {
        #expect(parseError("x = 1\n[[servers]]\n")?.line == 2)
    }

    @Test("dotted keys are rejected")
    func dottedKey() {
        #expect(parseError("a.b = 1\n")?.line == 1)
    }

    @Test("dotted table names are rejected")
    func dottedTable() {
        #expect(parseError("[a.b]\n")?.line == 1)
    }

    @Test("multi-line array is rejected at the opening line")
    func multiLineArray() {
        #expect(parseError("a = [\n  1,\n  2,\n]\n")?.line == 1)
    }

    @Test("nested arrays are rejected")
    func nestedArray() {
        #expect(parseError("a = [[1], [2]]\n")?.line == 1)
    }

    @Test("unsupported value reports its line")
    func unsupportedValue() {
        #expect(parseError("a = 1979-05-27\n")?.line == 1)
        #expect(parseError("a = 0xFF\n")?.line == 1)
        #expect(parseError("a = inf\n")?.line == 1)
    }

    @Test("out-of-range integer is an error, not a wrap")
    func integerOverflow() {
        #expect(parseError("a = 99999999999999999999999\n")?.line == 1)
    }

    @Test("trailing garbage after a value is an error")
    func trailingGarbage() {
        #expect(parseError("a = 1 2\n")?.line == 1)
    }
}
