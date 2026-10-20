import ChordCore
import Foundation
import Testing
@testable import Chord

@Suite("DiagnosticsCollector")
struct DiagnosticsCollectorTests {
    @MainActor
    @Test func includesActiveConfigWithoutExposingValuesAndCrashPointers() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let logs = root.appendingPathComponent("logs", isDirectory: true)
        let crashes = root.appendingPathComponent("crashes", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: crashes, withIntermediateDirectories: true)
        let log = ActionLog(directory: logs)
        log.write("executor: moved window 1")
        FileManager.default.createFile(atPath: crashes.appendingPathComponent("Chord-2026-10-16.ips").path, contents: Data())
        FileManager.default.createFile(atPath: crashes.appendingPathComponent("Other-2026-10-16.ips").path, contents: Data())
        let config = Config.load(text: """
        [backend]
        aerospace_tag = "custom-private-tag"

        [timing]
        hold_ms = 777
        """).config

        let report = DiagnosticsCollector.render(
            config: config, logFileURL: log.fileURL, crashReportsDirectory: crashes,
            aerospaceHealth: AeroSpaceHealth(probe: .socketMissing, pinnedTag: config.backend.aerospaceTag))

        #expect(report.contains("timing: customized"))
        #expect(report.contains("AeroSpace pin: custom-private-tag"))
        #expect(report.contains("executor: moved window 1"))
        #expect(report.contains("Chord-2026-10-16.ips"))
        #expect(!report.contains("Other-2026-10-16.ips"))
        #expect(report.contains("AeroSpace custom-private-tag (pinned): not running"))
        #expect(report.contains("Next step: Install AeroSpace custom-private-tag"))
    }
}
