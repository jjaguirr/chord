/// Pure policy for the local action log and the diagnostics bundle. No I/O: the
/// shell owns files, the pasteboard, and the menu.
public enum LogPolicy {
    /// Size at which the active log file rotates.
    public static let maxBytes = 1_048_576
    /// Maximum UTF-8 bytes retained from one log message.
    public static let maxLineBytes = 4096
    /// Rotated generations kept beside the active file, so disk use is bounded by
    /// `maxBytes * (archiveCount + 1)`.
    public static let archiveCount = 2
    /// Log lines included in the diagnostics bundle.
    public static let diagnosticsLineCount = 50
    /// Crash reports listed in the diagnostics bundle and the menu.
    public static let crashReportCount = 5

    public static func clipped(_ message: String) -> String {
        var scalars = String.UnicodeScalarView()
        var byteCount = 0
        for scalar in message.unicodeScalars {
            let scalarBytes = scalar.utf8.count
            guard byteCount + scalarBytes <= maxLineBytes else { break }
            scalars.append(scalar)
            byteCount += scalarBytes
        }
        return String(scalars)
    }

    /// Whether appending `incomingBytes` to a file of `currentBytes` must rotate it
    /// first.
    public static func shouldRotate(currentBytes: Int, incomingBytes: Int) -> Bool {
        currentBytes > 0 && currentBytes + incomingBytes > maxBytes
    }
}

/// Redaction for anything a log or diagnostics bundle may show about a window.
public enum LogRedaction {
    public static let redacted = "[redacted]"

    /// Password managers, matched case-insensitively against the start of the app name.
    public static let passwordManagers = [
        "1password", "bitwarden", "dashlane", "keepassxc", "lastpass", "enpass", "proton pass", "keychain access",
    ]

    public static func isPasswordManager(appName: String) -> Bool {
        let name = appName.lowercased()
        return passwordManagers.contains { name.hasPrefix($0) }
    }

    /// The title that may be written to a log for a window. Place 4 and password
    /// managers never show a title. `nil` means the window is in no representable
    /// place (the vault has no `Place` case); it fails closed and is redacted too.
    public static func loggedTitle(_ title: String, appName: String, place: Place?) -> String {
        guard let place else { return redacted }
        if place == .workspace(.four) || isPasswordManager(appName: appName) { return redacted }
        return title
    }
}

/// Assembles the text copied by "Copy Diagnostics". The shell supplies the facts
/// it can observe; this type decides what is shown and how.
public enum DiagnosticsReport {
    /// Config as counts and "defaults"/"customized" flags. Standing-wish app names
    /// and key codes are personal values, so they are never rendered.
    public static func configLines(_ config: Config) -> [String] {
        [
            "AeroSpace pin: \(config.backend.aerospaceTag)",
            "keys: \(config.keys == .defaults ? "defaults" : "customized")",
            "timing: \(config.timing == .defaults ? "defaults" : "customized")",
            "carry: \(config.carry == .defaults ? "defaults" : "customized")",
            "workspaces: \(config.workspaces == .defaults ? "defaults" : "customized")",
            "standing wishes: \(config.standingWishes.count)",
        ]
    }

    /// The last `limit` lines of log text, without the empty line after a final newline.
    public static func lastLines(of text: String, limit: Int) -> [String] {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.last == "" { lines.removeLast() }
        return Array(lines.suffix(max(0, limit)))
    }

    /// Crash report file names belonging to Chord, in the order given. Chord's
    /// reports are named after its process: `Chord-<stamp>.ips` or `Chord_<stamp>.crash`.
    public static func chordCrashReports(_ fileNames: [String]) -> [String] {
        fileNames.filter { name in
            (name.hasPrefix("Chord-") || name.hasPrefix("Chord_"))
                && (name.hasSuffix(".ips") || name.hasSuffix(".crash"))
        }
    }

    public static func render(
        chordVersion: String,
        macOSVersion: String,
        aerospaceVersion: String,
        aerospaceHealth: String,
        accessibilityGranted: Bool,
        config: Config,
        crashReports: [String],
        logLines: [String]
    ) -> String {
        var lines = [
            "Chord \(chordVersion)",
            "macOS \(macOSVersion)",
            "AeroSpace \(aerospaceVersion): \(aerospaceHealth)",
            "Accessibility: \(accessibilityGranted ? "granted" : "missing")",
            "Config:",
        ]
        lines += configLines(config).map { "  " + $0 }
        lines.append("Recent crash reports:")
        lines += crashReports.isEmpty ? ["  none"] : crashReports.map { "  " + $0 }
        lines.append("Last \(logLines.count) log lines:")
        lines += logLines.map { "  " + $0 }
        return lines.joined(separator: "\n") + "\n"
    }
}
