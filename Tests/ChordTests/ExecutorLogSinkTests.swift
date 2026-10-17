import ChordCore
import Foundation
import Testing
@testable import Chord

private final class LogSinkRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(line)
    }

    var lines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

@Suite("Executor log sink")
struct ExecutorLogSinkTests {
    @Test func sinkReceivesSuccessfulAndFailedEntriesAlongsideMemoryLog() async throws {
        let backend = FakeWorkspaceBackend(
            monitors: [],
            windows: [WindowSnapshot(
                id: WindowID(1), appName: "App", place: .workspace(.one), isFloating: true,
                bounds: ScreenRect(x: 0, y: 0, width: 333, height: 471))],
            focusedWindow: nil)
        let recorder = LogSinkRecorder()
        let executor = Executor(backend: backend, logSink: { recorder.append($0) })
        let successfulPlan = try Plan(assignments: [
            Assignment(windowID: 1, place: .workspace(.two), reason: .pinned),
        ])

        try await executor.apply(successfulPlan)
        try await executor.undo()
        await backend.queue([.proceed, .timeoutBeforeApply])
        await #expect(throws: BackendError.unknown(reason: "timed out before apply")) {
            try await executor.apply(successfulPlan)
        }

        let memoryLog = await executor.log
        #expect(recorder.lines == memoryLog)
        #expect(recorder.lines.contains { $0.hasPrefix("failed:") })
        #expect(recorder.lines.contains { $0.hasPrefix("undo:") })
    }
}
