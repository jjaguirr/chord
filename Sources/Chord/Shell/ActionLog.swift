import ChordCore
import Foundation

/// Append-only shell log at ~/Library/Logs/Chord/chord.log. Every shell action writes one line.
/// The file rotates at `LogPolicy.maxBytes` to chord.1.log, chord.2.log, and so on, keeping
/// `LogPolicy.archiveCount` rotated generations.
struct ActionLog {
    let directory: URL

    static var live: ActionLog {
        ActionLog(directory: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Chord", isDirectory: true))
    }

    var fileURL: URL {
        directory.appendingPathComponent("chord.log")
    }

    func write(_ message: String) {
        let clippedMessage = LogPolicy.clipped(message)
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(clippedMessage)\n"
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            rotateIfNeeded(incomingBytes: line.utf8.count)
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } catch {
            NSLog("Chord: log write failed: %@", error.localizedDescription)
        }
    }

    private func archiveURL(_ generation: Int) -> URL {
        directory.appendingPathComponent("chord.\(generation).log")
    }

    private func rotateIfNeeded(incomingBytes: Int) {
        let manager = FileManager.default
        let currentBytes = (try? manager.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
        guard LogPolicy.shouldRotate(currentBytes: currentBytes, incomingBytes: incomingBytes) else { return }
        try? manager.removeItem(at: archiveURL(LogPolicy.archiveCount))
        for generation in stride(from: LogPolicy.archiveCount - 1, through: 1, by: -1)
        where manager.fileExists(atPath: archiveURL(generation).path) {
            try? manager.moveItem(at: archiveURL(generation), to: archiveURL(generation + 1))
        }
        try? manager.moveItem(at: fileURL, to: archiveURL(1))
    }
}
