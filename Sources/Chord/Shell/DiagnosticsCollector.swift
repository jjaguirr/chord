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
        logFileURL: URL = ActionLog.live.fileURL,
        crashReportsDirectory: URL = crashReportsDirectory
    ) -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "unknown (not packaged)"
        let log = (try? String(contentsOf: logFileURL, encoding: .utf8)) ?? ""
        return DiagnosticsReport.render(
            chordVersion: version,
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            aerospaceVersion: "\(Config.defaults.backend.aerospaceTag) (pinned)",
            aerospaceHealth: "not connected; no substrate is wired in this build",
            accessibilityGranted: AccessibilityPermission.isGranted,
            config: Config.defaults,
            crashReports: recentCrashReports(in: crashReportsDirectory).map(\.lastPathComponent),
            logLines: DiagnosticsReport.lastLines(of: log, limit: LogPolicy.diagnosticsLineCount))
    }

    private static func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}

