import Testing
@testable import ChordCore

@Suite("Diagnostics")
struct DiagnosticsTests {
    @Test("place 4 titles are redacted")
    func placeFourRedacted() {
        let shown = LogRedaction.loggedTitle("Quarterly plan", appName: "Notes", place: .workspace(.four))
        #expect(shown == LogRedaction.redacted)
    }

    @Test("titles in other places pass through")
    func otherPlacesVisible() {
        #expect(LogRedaction.loggedTitle("Inbox", appName: "Mail", place: .workspace(.one)) == "Inbox")
        #expect(LogRedaction.loggedTitle("Inbox", appName: "Mail", place: .bench) == "Inbox")
    }

    @Test("a window in no representable place is redacted, failing closed")
    func unplacedRedacted() {
        #expect(LogRedaction.loggedTitle("Secret", appName: "Mail", place: nil) == LogRedaction.redacted)
    }

    @Test("password managers are redacted in every place")
    func passwordManagersRedacted() {
        for place in [Place.workspace(.one), .bench, .workspace(.four)] {
            #expect(LogRedaction.loggedTitle("Vault item", appName: "1Password", place: place) == LogRedaction.redacted)
            #expect(LogRedaction.loggedTitle("Vault item", appName: "Bitwarden", place: place) == LogRedaction.redacted)
        }
    }

    @Test("password manager match ignores case and a version suffix")
    func passwordManagerMatching() {
        #expect(LogRedaction.isPasswordManager(appName: "1PASSWORD 8"))
        #expect(LogRedaction.isPasswordManager(appName: "Keychain Access"))
        #expect(!LogRedaction.isPasswordManager(appName: "Notes"))
        #expect(!LogRedaction.isPasswordManager(appName: "Bit"))
    }

    @Test("a log line at the cap is kept, one byte over rotates")
    func rotationBoundary() {
        #expect(!LogPolicy.shouldRotate(currentBytes: LogPolicy.maxBytes - 10, incomingBytes: 10))
        #expect(LogPolicy.shouldRotate(currentBytes: LogPolicy.maxBytes - 10, incomingBytes: 11))
    }

    @Test("an empty file never rotates, so one oversized line is still written")
    func emptyFileDoesNotRotate() {
        #expect(!LogPolicy.shouldRotate(currentBytes: 0, incomingBytes: LogPolicy.maxBytes * 2))
    }

    @Test("last lines are the tail, without the empty entry after a final newline")
    func lastLinesTail() {
        #expect(DiagnosticsReport.lastLines(of: "a\nb\nc\n", limit: 2) == ["b", "c"])
        #expect(DiagnosticsReport.lastLines(of: "a\nb", limit: 5) == ["a", "b"])
        #expect(DiagnosticsReport.lastLines(of: "", limit: 5) == [])
        #expect(DiagnosticsReport.lastLines(of: "a\nb\n", limit: 0) == [])
    }

    @Test("only Chord crash reports are listed, in the order given")
    func crashReportFilter() {
        let names = ["Chrome-2026-10-01.ips", "Chord-2026-10-02.ips", "Chord_2026-10-03.crash", "Chord-notes.txt", "Chordial-1.ips"]
        #expect(DiagnosticsReport.chordCrashReports(names) == ["Chord-2026-10-02.ips", "Chord_2026-10-03.crash"])
    }

    @Test("config summary shows flags and counts, never personal values")
    func configSummaryHidesValues() {
        let wish = StandingWish(app: "Private Journal", size: .fullscreen)
        let config = Config(
            keys: .defaults, timing: .defaults, carry: .defaults, backend: .defaults,
            standingWishes: [wish])
        let lines = DiagnosticsReport.configLines(config).joined(separator: "\n")
        #expect(!lines.contains("Private Journal"))
        #expect(lines.contains("standing wishes: 1"))
        #expect(lines.contains("keys: defaults"))
    }

    @Test("rendered report carries no standing-wish names and no window titles")
    func renderedReportPrivacy() {
        let config = Config(
            keys: .defaults, timing: .defaults, carry: .defaults, backend: .defaults,
            standingWishes: [StandingWish(app: "Private Journal", size: .zoom)])
        let text = DiagnosticsReport.render(
            chordVersion: "0.1.0", macOSVersion: "27.0", aerospaceVersion: "v0.21.3-Beta",
            aerospaceHealth: "not connected", accessibilityGranted: true, config: config,
            crashReports: ["Chord-2026-10-02.ips"], logLines: ["launch: accessibility granted"])
        #expect(!text.contains("Private Journal"))
        #expect(text.contains("launch: accessibility granted"))
        #expect(text.contains("Chord-2026-10-02.ips"))
    }
}
