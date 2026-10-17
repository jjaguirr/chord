import Testing
@testable import ChordCore

@Suite("Config [updates]")
struct UpdateConfigTests {
    @Test("background check is off by default")
    func defaultOff() {
        #expect(Config.defaults.updates.backgroundCheck == false)
        #expect(Config.load(text: "").config.updates.backgroundCheck == false)
    }

    @Test("background_check = true enables it and survives the writer")
    func enabledRoundTrip() {
        let result = Config.load(text: "[updates]\nbackground_check = true\n")
        #expect(result.diagnostics.isEmpty)
        #expect(result.config.updates.backgroundCheck == true)
        #expect(Config.load(text: result.config.tomlText()).config == result.config)
    }

    @Test("a non-boolean background_check is a wrong-type diagnostic, not coerced")
    func wrongType() {
        let result = Config.load(text: "[updates]\nbackground_check = \"yes\"\n")
        #expect(result.config == Config.defaults)
        #expect(result.diagnostics == [
            .wrongType(line: 2, key: "background_check", expected: "boolean"),
        ])
    }

    @Test("unknown key in [updates] is reported")
    func unknownKey() {
        let result = Config.load(text: "[updates]\ncheck_now = true\n")
        #expect(result.config == Config.defaults)
        #expect(result.diagnostics == [.unknownKey(line: 2, key: "check_now")])
    }
}
