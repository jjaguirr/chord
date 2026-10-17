import ChordCore
import Foundation

/// Reads `~/Library/Application Support/Chord/config.toml` once at launch. A missing file is
/// normal and yields defaults; a file with any problem also yields defaults, as `Config.load` does.
enum ConfigFile {
    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Chord/config.toml")
    }

    static func load() -> Config {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .defaults }
        let text: String
        do {
            text = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            ActionLog.write("config: read failed: \(error.localizedDescription); using defaults")
            return .defaults
        }
        let result = Config.load(text: text)
        if let first = result.diagnostics.first {
            ActionLog.write(
                "config: \(result.diagnostics.count) problem(s), first at line \(first.line); using defaults")
        } else {
            ActionLog.write("config: loaded")
        }
        return result.config
    }
}
