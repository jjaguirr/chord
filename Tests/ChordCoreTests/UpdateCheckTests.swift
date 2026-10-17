import Testing
@testable import ChordCore

@Suite("Release version parsing and comparison")
struct UpdateCheckTests {
    @Test("accepts plain and v-prefixed dotted numbers")
    func parsesReleaseVersions() {
        #expect(ReleaseVersion("0.2.0")?.components == [0, 2, 0])
        #expect(ReleaseVersion("v1.10.3")?.components == [1, 10, 3])
        #expect(ReleaseVersion("7")?.components == [7])
        #expect(ReleaseVersion("1.2.3.4")?.components == [1, 2, 3, 4])
    }

    @Test("rejects anything that is not a plain release version")
    func rejectsMalformedVersions() {
        for text in ["", "v", "1.", ".1", "1..2", "1.2.3.4.5", "1.2-beta", "1.2.3-rc1",
                     "v1.2+build", "-1.0", "+1.0", "1.a", "1 .0", " 1.0", "1.0\n",
                     "99999999999999999999999.0", "latest", "é1"]
        {
            #expect(ReleaseVersion(text) == nil, "\(text) should not parse")
        }
    }

    @Test("numeric, not lexical, ordering")
    func numericOrdering() {
        #expect(ReleaseVersion("0.10.0")! > ReleaseVersion("0.9.9")!)
        #expect(ReleaseVersion("1.0.0")! > ReleaseVersion("0.99.99")!)
        #expect(ReleaseVersion("0.2.0")! < ReleaseVersion("0.2.1")!)
    }

    @Test("missing trailing components equal zero")
    func trailingZeros() {
        #expect(ReleaseVersion("0.2")! == ReleaseVersion("0.2.0")!)
        #expect(!(ReleaseVersion("0.2")! < ReleaseVersion("v0.2.0")!))
        #expect(ReleaseVersion("0.2.0.1")! > ReleaseVersion("0.2")!)
    }

    @Test("a newer tag is available, an equal or older tag is up to date")
    func evaluate() {
        #expect(UpdateCheck.evaluate(current: "0.1.0", latestTag: "v0.2.0") == .available)
        #expect(UpdateCheck.evaluate(current: "0.1.0", latestTag: "v0.1.0") == .upToDate)
        #expect(UpdateCheck.evaluate(current: "0.2.0", latestTag: "v0.1.9") == .upToDate)
        #expect(UpdateCheck.evaluate(current: "0.9", latestTag: "v0.10") == .available)
    }

    @Test("an unparseable side is reported with its text, never guessed")
    func evaluateUnparseable() {
        #expect(UpdateCheck.evaluate(current: "dev", latestTag: "v0.2.0") == .unparseable("dev"))
        #expect(UpdateCheck.evaluate(current: "0.1.0", latestTag: "v0.2.0-beta")
            == .unparseable("v0.2.0-beta"))
    }
}
