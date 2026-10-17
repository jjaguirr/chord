import ChordCore
import Foundation
import Testing
@testable import Chord

@Suite("ActionLog")
struct ActionLogTests {
    @Test func clipsMessagesAndKeepsActiveFileUnderTheCap() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = ActionLog(directory: directory)

        log.write(String(repeating: "x", count: LogPolicy.maxBytes * 2))

        let bytes = try Data(contentsOf: log.fileURL)
        #expect(bytes.count <= LogPolicy.maxBytes)
        #expect(String(decoding: bytes, as: UTF8.self).contains(String(repeating: "x", count: LogPolicy.maxLineBytes)))
    }

    @Test func rotatesAnInjectedDirectoryBeforeAnAppendWouldExceedTheCap() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let log = ActionLog(directory: directory)
        try Data(repeating: 0x61, count: LogPolicy.maxBytes).write(to: log.fileURL)

        log.write("next")

        let activeBytes = try Data(contentsOf: log.fileURL).count
        let archiveBytes = try Data(contentsOf: directory.appendingPathComponent("chord.1.log")).count
        #expect(activeBytes <= LogPolicy.maxBytes)
        #expect(archiveBytes == LogPolicy.maxBytes)
    }
}
