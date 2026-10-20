import AppKit
import ChordCore

/// Gathers the facts shown in the diagnostics bundle. Reads only: it changes no
/// window, no config, and no Chord state.
@MainActor
enum DiagnosticsCollector {
    static var crashReportsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
    }

    /// Chord's crash reports, newest first, at most `LogPolicy.crashReportCount`.
    static func recentCrashReports(in directory: URL = crashReportsDirectory) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let chordNames = Set(DiagnosticsReport.chordCrashReports(urls.map(\.lastPathComponent)))
        return urls
            .filter { chordNames.contains($0.lastPathComponent) }
            .sorted { modificationDate($0) > modificationDate($1) }
            .prefix(LogPolicy.crashReportCount)
            .map { $0 }
    }

    static func render(
        config: Config,
        logFileURL: URL = ActionLog.live.fileURL,
        crashReportsDirectory: URL = crashReportsDirectory,
        aerospaceHealth: (String) -> AeroSpaceHealth = { AeroSpaceDoctor.check(pinnedTag: $0) }
    ) -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "unknown (not packaged)"
        let log = (try? String(contentsOf: logFileURL, encoding: .utf8)) ?? ""
        return DiagnosticsReport.render(
            chordVersion: version,
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            aerospaceVersion: "\(config.backend.aerospaceTag) (pinned)",
            aerospaceHealth: aerospaceHealth(config.backend.aerospaceTag).report,
            accessibilityGranted: AccessibilityPermission.isGranted,
            config: config,
            crashReports: recentCrashReports(in: crashReportsDirectory).map(\.lastPathComponent),
            logLines: DiagnosticsReport.lastLines(of: log, limit: LogPolicy.diagnosticsLineCount))
    }

    private static func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}

