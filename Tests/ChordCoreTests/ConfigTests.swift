import Testing
@testable import ChordCore

@Suite("Config")
struct ConfigTests {
    private func load(_ text: String) -> ConfigLoadResult {
        Config.load(text: text)
    }

    @Test("defaults match the documented values")
    func defaults() {
        let c = Config.defaults
        #expect(c.keys.left == .keyH)
        #expect(c.keys.down == .keyJ)
        #expect(c.keys.up == .keyK)
        #expect(c.keys.right == .keyL)
        #expect(c.keys.bench == .backquote)
        #expect(c.keys.redactedTier == .digit4)
        #expect(c.keys.vault == .digit9)
        #expect(c.timing.holdMs == 700)
        #expect(c.timing.tapMs == 250)
        #expect(c.timing.chordWindowMs == 35)
        #expect(c.timing.a5HoldMs == 200)
        #expect(c.timing.unfoldStepWindowMs == 1000)
        #expect(c.carry.ramp == CarryRamp(near: 10, middle: 20, far: 30))
        #expect(c.carry.edgeMagnetPx == 30)
        #expect(c.backend.aerospaceTag == "v0.21.3-Beta")
        #expect(c.standingWishes.isEmpty)
    }

    @Test("defaults round-trip through the canonical writer")
    func defaultsRoundTrip() {
        let result = load(Config.defaults.tomlText())
        #expect(result.diagnostics.isEmpty)
        #expect(result.config == Config.defaults)
    }

    @Test("empty file yields defaults with no diagnostics")
    func emptyFile() {
        let result = load("")
        #expect(result.diagnostics.isEmpty)
        #expect(result.config == Config.defaults)
    }

    @Test("partial file keeps defaults for absent keys")
    func partialFile() {
        let result = load("[timing]\nhold_ms = 900\n")
        #expect(result.diagnostics.isEmpty)
        #expect(result.config.timing.holdMs == 900)
        #expect(result.config.timing.tapMs == 250)
        #expect(result.config.keys == Config.defaults.keys)
    }

    @Test("a valid file round-trips through the writer")
    func customRoundTrip() {
        let text = """
        [keys]
        left = "KeyA"
        vault = "Digit8"
        [timing]
        unfold_step_window_ms = 450
        [carry]
        ramp_px = [5, 15, 60]
        [standing_wishes]
        "Safari" = "fullscreen"
        "Terminal" = "zoom"
        """
        let result = load(text)
        #expect(result.diagnostics.isEmpty)
        #expect(result.config.keys.left.code == "KeyA")
        #expect(result.config.keys.vault.code == "Digit8")
        #expect(result.config.timing.unfoldStepWindowMs == 450)
        #expect(result.config.carry.ramp == CarryRamp(near: 5, middle: 15, far: 60))
        #expect(result.config.standingWishes == [
            StandingWish(app: "Safari", size: .fullscreen),
            StandingWish(app: "Terminal", size: .zoom),
        ])
        #expect(load(result.config.tomlText()).config == result.config)
    }

    @Test("CRLF file loads the same as LF")
    func crlfLoads() {
        let result = load("[timing]\r\nhold_ms = 900\r\n")
        #expect(result.diagnostics.isEmpty)
        #expect(result.config.timing.holdMs == 900)
    }

    @Test("syntax error returns defaults with a line-numbered diagnostic")
    func syntaxError() {
        let result = load("[timing]\nhold_ms = 900\nbroken line\n")
        #expect(result.config == Config.defaults)
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics.first?.line == 3)
    }

    @Test("unknown key is reported and the whole file falls back to defaults")
    func unknownKey() {
        let result = load("[timing]\nhold_ms = 900\nbogus = 1\n")
        #expect(result.config == Config.defaults)
        #expect(result.diagnostics == [.unknownKey(line: 3, key: "bogus")])
    }

    @Test("unknown table is reported, including any agent permission table")
    func unknownTable() {
        let result = load("[agents]\nvault = true\n")
        #expect(result.config == Config.defaults)
        #expect(result.diagnostics.first == .unknownTable(line: 1, table: "agents"))
    }

    @Test("zero and over-max milliseconds are out of range")
    func msOutOfRange() {
        let low = load("[timing]\nhold_ms = 0\n")
        #expect(low.diagnostics == [.outOfRange(line: 2, key: "hold_ms", min: 1, max: 5000)])
        #expect(low.config == Config.defaults)
        let high = load("[timing]\nhold_ms = 5001\n")
        #expect(high.diagnostics == [.outOfRange(line: 2, key: "hold_ms", min: 1, max: 5000)])
    }

    @Test("unfold step window out of range is reported")
    func unfoldWindowOutOfRange() {
        let result = load("[timing]\nunfold_step_window_ms = 0\n")
        #expect(result.diagnostics == [.outOfRange(line: 2, key: "unfold_step_window_ms", min: 1, max: 5000)])
        #expect(result.config == Config.defaults)
    }

    @Test("unfold_steps is not a config key; the ratio progression is fixed")
    func unfoldStepsRemoved() {
        let result = load("[timing]\nunfold_steps = 6\n")
        #expect(result.diagnostics == [.unknownKey(line: 2, key: "unfold_steps")])
        #expect(result.config == Config.defaults)
    }

    @Test("wrong type is reported, not coerced")
    func wrongType() {
        let result = load("[timing]\nhold_ms = \"700\"\n")
        #expect(result.diagnostics == [.wrongType(line: 2, key: "hold_ms", expected: "integer")])
        #expect(result.config == Config.defaults)
    }

    @Test("ramp with wrong step count is invalid")
    func rampCount() {
        let result = load("[carry]\nramp_px = [10, 20]\n")
        #expect(result.diagnostics.first?.line == 2)
        #expect(result.config == Config.defaults)
    }

    @Test("ramp step out of range is reported")
    func rampStepOutOfRange() {
        let result = load("[carry]\nramp_px = [10, 0, 30]\n")
        #expect(result.diagnostics == [.outOfRange(line: 2, key: "ramp_px", min: 1, max: 500)])
    }

    @Test("edge magnet of 0 is allowed; negative is not")
    func edgeMagnet() {
        #expect(load("[carry]\nedge_magnet_px = 0\n").diagnostics.isEmpty)
        let negative = load("[carry]\nedge_magnet_px = -1\n")
        #expect(negative.diagnostics == [.outOfRange(line: 2, key: "edge_magnet_px", min: 0, max: 500)])
    }

    @Test("unknown physical key name is invalid")
    func invalidKeyName() {
        let result = load("[keys]\nleft = \"KeyHH\"\n")
        #expect(result.diagnostics.first?.line == 2)
        #expect(result.config == Config.defaults)
    }

    @Test("two actions bound to one key is a duplicate-binding diagnostic")
    func duplicateBinding() {
        let result = load("[keys]\nleft = \"KeyJ\"\n")
        #expect(result.diagnostics == [
            .duplicateBinding(line: 2, key: "left", conflictsWith: "down", code: "KeyJ"),
        ])
        #expect(result.config == Config.defaults)
    }

    @Test("vault key can be rebound; agents have no vault setting to reach")
    func vaultIsOnlyAUserBinding() {
        let result = load("[keys]\nvault = \"Digit8\"\n")
        #expect(result.diagnostics.isEmpty)
        #expect(result.config.keys.vault.code == "Digit8")
    }

    @Test("standing wish with a size outside fullscreen and zoom is invalid")
    func standingWishBadSize() {
        let result = load("[standing_wishes]\n\"Safari\" = \"huge\"\n")
        #expect(result.diagnostics.first?.line == 2)
        #expect(result.config == Config.defaults)
    }

    @Test("standing wish with a non-string size is a wrong-type diagnostic")
    func standingWishWrongType() {
        let result = load("[standing_wishes]\n\"Safari\" = 1\n")
        #expect(result.diagnostics == [
            .wrongType(line: 2, key: "standing_wishes.\"Safari\"", expected: "string"),
        ])
    }

    @Test("standing wishes load sorted by app name")
    func standingWishesSorted() {
        let result = load("[standing_wishes]\n\"Zed\" = \"zoom\"\n\"Arc\" = \"fullscreen\"\n")
        #expect(result.config.standingWishes.map(\.app) == ["Arc", "Zed"])
    }

    @Test("backend tag must be non-empty with no spaces")
    func backendTag() {
        #expect(load("[backend]\naerospace_tag = \"\"\n").diagnostics.first?.line == 2)
        #expect(load("[backend]\naerospace_tag = \"v 1\"\n").diagnostics.first?.line == 2)
    }

    @Test("diagnostics are sorted by line")
    func sortedDiagnostics() {
        let result = load("[timing]\nhold_ms = 0\nunfold_step_window_ms = 0\n")
        #expect(result.diagnostics.map(\.line) == [2, 3])
    }

    @Test("physical key names are a closed set")
    func physicalKeyClosedSet() {
        #expect(PhysicalKey(code: "KeyA") != nil)
        #expect(PhysicalKey(code: "Digit0") != nil)
        #expect(PhysicalKey(code: "Space") != nil)
        #expect(PhysicalKey(code: "keyA") == nil)
        #expect(PhysicalKey(code: "a") == nil)
        #expect(PhysicalKey(code: "") == nil)
    }

    @Test("workspaces default to three unnamed rows that clamp at the edge")
    func workspaceDefaults() {
        let w = Config.defaults.workspaces
        #expect(w.rows == 3)
        #expect(w.rowNames.isEmpty)
        #expect(w.wrap == false)
    }

    @Test("workspace rows, names and wrap load and round-trip")
    func workspacesLoad() {
        let result = load("[workspaces]\nrows = 2\nrow_names = [\"work\", \"home \\\"b\\\"\"]\nwrap = true\n")
        #expect(result.diagnostics.isEmpty)
        #expect(result.config.workspaces == WorkspaceLayout(rows: 2, rowNames: ["work", "home \"b\""], wrap: true))
        #expect(load(result.config.tomlText()).config == result.config)
    }

    @Test("names alone set the row count; rows alone leave rows unnamed")
    func workspaceNamesImplyRows() {
        let named = load("[workspaces]\nrow_names = [\"a\", \"b\", \"c\", \"d\"]\n")
        #expect(named.diagnostics.isEmpty)
        #expect(named.config.workspaces.rows == 4)
        let counted = load("[workspaces]\nrows = 5\n")
        #expect(counted.config.workspaces == WorkspaceLayout(rows: 5))
    }

    @Test("bad workspace values are diagnostics and the file falls back to defaults")
    func workspacesRejectBadValues() {
        let cases: [(String, ConfigDiagnostic)] = [
            ("rows = 0", .outOfRange(line: 2, key: "rows", min: 1, max: 9)),
            ("rows = 10", .outOfRange(line: 2, key: "rows", min: 1, max: 9)),
            ("rows = \"3\"", .wrongType(line: 2, key: "rows", expected: "integer")),
            ("wrap = 1", .wrongType(line: 2, key: "wrap", expected: "boolean")),
            ("row_names = \"work\"", .wrongType(line: 2, key: "row_names", expected: "array of strings")),
            ("row_names = [1, 2]", .wrongType(line: 2, key: "row_names", expected: "array of strings")),
            ("row_names = []", .invalidValue(line: 2, key: "row_names", reason: "expected 1 to 9 names, found 0")),
            ("row_names = [\"a\", \" \"]", .invalidValue(line: 2, key: "row_names", reason: "a row name is empty")),
            ("bogus = 1", .unknownKey(line: 2, key: "bogus")),
        ]
        for (line, diagnostic) in cases {
            let result = load("[workspaces]\n\(line)\n")
            #expect(result.diagnostics == [diagnostic], "\(line)")
            #expect(result.config == Config.defaults)
        }
    }

    @Test("a name count that disagrees with rows is a diagnostic on the names")
    func workspaceNamesMustMatchRows() {
        let result = load("[workspaces]\nrows = 3\nrow_names = [\"a\", \"b\"]\n")
        #expect(result.diagnostics == [
            .invalidValue(line: 3, key: "row_names", reason: "rows is 3 but 2 names are given")
        ])
    }

    @Test("a layout keeps names only when there is one per row")
    func layoutNormalizes() {
        #expect(WorkspaceLayout(rows: 3, rowNames: ["a"]).rowNames.isEmpty)
        #expect(WorkspaceLayout(rows: 0).rows == 1)
        #expect(WorkspaceLayout(rows: 99).rows == WorkspaceLayout.maxRows)
        let named = WorkspaceLayout(rows: 2, rowNames: ["work", "home"])
        #expect(named.name(ofRow: 2) == "home")
        #expect(named.name(ofRow: 3) == nil)
        #expect(WorkspaceLayout.defaults.name(ofRow: 1) == nil)
    }
}
