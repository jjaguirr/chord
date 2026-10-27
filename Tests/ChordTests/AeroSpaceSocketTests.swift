import ChordCore
import Foundation
import Testing
@testable import Chord

@Suite("AeroSpace socket and doctor (local test server)")
struct AeroSpaceSocketTests {
    private let pin = "v0.21.3-Beta"

    // MARK: Wire format

    @Test func integersAreFourBytesLittleEndian() {
        #expect(Array(AeroSpaceWire.integerBytes(1)) == [1, 0, 0, 0])
        #expect(Array(AeroSpaceWire.integerBytes(0x0102_0304)) == [4, 3, 2, 1])
        #expect(AeroSpaceWire.integer(from: Data([4, 3, 2, 1])) == 0x0102_0304)
        #expect(AeroSpaceWire.integer(from: Data([1, 0, 0])) == nil)
    }

    @Test func aRequestIsLengthPrefixedJSONWithExplicitNulls() throws {
        let framed = try AeroSpaceWire.frame(.showWorkspace("r2-5"))

        let length = try #require(AeroSpaceWire.integer(from: framed.prefix(4)))
        #expect(Int(length) == framed.count - 4)
        let object = try #require(try JSONSerialization.jsonObject(with: framed.dropFirst(4)) as? [String: Any])
        #expect(object["args"] as? [String] == ["workspace", "r2-5"])
        #expect(object["stdin"] as? String == "")
        // Missing keys make the server append a warning to stderr; both must be present as null.
        #expect(object.keys.contains("windowId") && object["windowId"] is NSNull)
        #expect(object.keys.contains("workspace") && object["workspace"] is NSNull)
    }

    @Test func theSocketPathIsPerUser() {
        #expect(AeroSpaceWire.defaultSocketPath(user: "ada") == "/tmp/bobko.aerospace-ada.sock")
    }

    // MARK: Transport

    @Test func oneConnectionHandshakesOnceAndServesManyRequests() async throws {
        let server = try LocalAeroSpaceServer(answer: { args in (0, args.joined(separator: " "), "") })
        defer { server.stop() }
        let socket = AeroSpaceSocket(path: server.path, timeout: 2)

        let first = try await socket.send(.focusedWorkspace)
        let second = try await socket.send(.showWorkspace("r1-2"))

        #expect(first.stdout == "list-workspaces --focused --format %{workspace}")
        #expect(second.stdout == "workspace r1-2")
        #expect(first.serverVersionAndHash == "0.21.3-Beta 0123abcdef")
        #expect(server.connections == 1)
        #expect(server.requests.count == 2)
    }

    @Test func theServerSeesExplicitNullsOnTheWire() async throws {
        let server = try LocalAeroSpaceServer()
        defer { server.stop() }

        _ = try await AeroSpaceSocket(path: server.path, timeout: 2).send(.focusedWindowID)

        let request = try #require(server.requests.first)
        #expect(request["windowId"] is NSNull)
        #expect(request["workspace"] is NSNull)
    }

    @Test func aServerWithoutTheHandshakeIsAProtocolMismatchAndSendsNothing() async throws {
        let server = try LocalAeroSpaceServer(behavior: { _ in .legacy })
        defer { server.stop() }

        await #expect(throws: AeroSpaceTransportError.protocolMismatch) {
            try await AeroSpaceSocket(path: server.path, timeout: 2).send(.focusedWorkspace)
        }
        #expect(server.requests.isEmpty)
    }

    @Test func noListenerIsCannotConnect() async throws {
        let socket = AeroSpaceSocket(path: "/tmp/chord-test-absent-\(UUID().uuidString.prefix(8)).sock", timeout: 1)

        let error = await #expect(throws: AeroSpaceTransportError.self) { try await socket.send(.focusedWorkspace) }
        guard case .cannotConnect = error else {
            Issue.record("expected cannotConnect, got \(String(describing: error))")
            return
        }
    }

    @Test func aRequestThatGetsNoAnswerIsNoReplyAndTheNextSendReconnects() async throws {
        let server = try LocalAeroSpaceServer(behavior: { $0 == 1 ? .dropsAfterRequest : .pinned })
        defer { server.stop() }
        let socket = AeroSpaceSocket(path: server.path, timeout: 2)

        let error = await #expect(throws: AeroSpaceTransportError.self) { try await socket.send(.focusedWorkspace) }
        guard case .noReply = error else {
            Issue.record("expected noReply, got \(String(describing: error))")
            return
        }

        _ = try await socket.send(.focusedWorkspace)
        #expect(server.connections == 2)
    }

    @Test func aSilentServerTimesOutAsNoReply() async throws {
        let server = try LocalAeroSpaceServer(behavior: { _ in .silentAfterRequest })
        defer { server.stop() }
        let socket = AeroSpaceSocket(path: server.path, timeout: 0.3)

        let error = await #expect(throws: AeroSpaceTransportError.self) { try await socket.send(.focusedWorkspace) }
        #expect(error == .noReply("timed out"))
    }

    @Test func anAbsurdLengthPrefixIsNoReplyNotAHugeAllocation() async throws {
        let server = try LocalAeroSpaceServer(behavior: { _ in .hugeLengthPrefix })
        defer { server.stop() }

        let error = await #expect(throws: AeroSpaceTransportError.self) {
            try await AeroSpaceSocket(path: server.path, timeout: 2).send(.focusedWorkspace)
        }
        guard case .noReply = error else {
            Issue.record("expected noReply, got \(String(describing: error))")
            return
        }
    }

    /// Regression: tests run in parallel and every server owns an accept thread, a listener
    /// descriptor and a socket file. A stopped server's accept thread must never accept
    /// from, or answer for, a later server, however descriptor numbers get reused. Each
    /// server here answers with its own name, so a crossed connection shows as a wrong answer.
    @Test func everyServerAnswersOnlyItsOwnConnectionsWhileOthersStartAndStop() async throws {
        try await withThrowingTaskGroup(of: String?.self) { group in
            for worker in 0..<16 {
                group.addTask {
                    for round in 0..<40 {
                        let name = "w\(worker)r\(round)"
                        let server = try LocalAeroSpaceServer(answer: { _ in (0, name, "") })
                        // Half the servers stop before anything connects, half after one request.
                        if round % 2 == 0 {
                            let socket = AeroSpaceSocket(path: server.path, timeout: 5)
                            let answer = try await socket.send(.focusedWorkspace)
                            await socket.reset()
                            if answer.stdout != name { return "\(name) was answered with \(answer.stdout)" }
                        }
                        server.stop()
                    }
                    return nil
                }
            }
            for try await failure in group {
                #expect(failure == nil)
            }
        }
    }

    // MARK: Backend over the real transport

    @Test func theAdapterMovesAWindowOverTheRealTransport() async throws {
        let server = try LocalAeroSpaceServer(answer: { args in
            switch args.first {
            case "list-windows" where args.contains("--all"):
                return (0, "10\tr1-1\tfloating\tTerminal", "")
            default:
                return (0, "", "")
            }
        })
        defer { server.stop() }
        let backend = AeroSpaceBackend(
            transport: AeroSpaceSocket(path: server.path, timeout: 2), pinnedTag: pin, monitors: { [] }, frames: { _ in [:] })

        let left = try await backend.moveWindow(WindowID(10), to: GridCell(row: 2, column: 5)!)

        #expect(left == .cell(GridCell.first))
        let sent = server.requests.compactMap { $0["args"] as? [String] }
        #expect(sent.last == ["move-node-to-workspace", "--window-id", "10", "r2-5"])
        #expect(server.connections == 1)
    }

    @Test func aCarryRunsThroughTheExecutorAndTheSplitBackendOverTheRealTransport() async throws {
        let server = try LocalAeroSpaceServer(answer: { args in
            switch args.first {
            case "list-windows" where args.contains("--all"): return (0, "10\tr1-1\tfloating\tTerminal", "")
            case "list-windows": return (0, "10", "")
            case "list-workspaces": return (0, "r1-1", "")
            default: return (0, "", "")
            }
        })
        defer { server.stop() }
        let workspaces = AeroSpaceBackend(
            transport: AeroSpaceSocket(path: server.path, timeout: 2), pinnedTag: pin, monitors: { [] }, frames: { _ in [:] })
        let frames = FakeWorkspaceBackend(monitors: [], windows: [], focusedWindow: nil)
        let executor = Executor(backend: SplitBackend(frames: frames, workspaces: workspaces))

        let applied = try await executor.carryToColumn(5)

        let cell = GridCell(row: 1, column: 5)!
        #expect(applied == [
            .move(windowID: 10, from: .cell(GridCell.first), to: .cell(cell)),
            .show(from: .cell(GridCell.first), to: .cell(cell)),
        ])
        let sent = server.requests.compactMap { $0["args"] as? [String] }
        let changes = sent.filter { $0.first == "move-node-to-workspace" || $0.first == "workspace" }
        #expect(changes == [["move-node-to-workspace", "--window-id", "10", "r1-5"], ["workspace", "r1-5"]])
        #expect(!sent.contains { $0.first == "enable" || $0.first == "disable" })
    }

    // MARK: Doctor

    private func health(_ path: String, timeout: TimeInterval = 1) -> AeroSpaceHealth {
        AeroSpaceDoctor.check(pinnedTag: pin, socketPath: path, timeout: timeout)
    }

    @Test func doctorReportsAMissingSocketAsNotRunning() {
        let result = health("/tmp/chord-test-missing-\(UUID().uuidString.prefix(8)).sock")
        #expect(result.status == .notRunning)
        #expect(result.nextStep?.contains("Install AeroSpace \(pin)") == true)
    }

    @Test func doctorReportsAStaleSocketFileAsNotRunning() throws {
        let server = try LocalAeroSpaceServer()
        server.stop(removeFile: false)
        defer { unlink(server.path) }

        #expect(health(server.path).status == .notRunning)
    }

    @Test func doctorReportsADisabledServerWithTheCommandAndSendsOnlyOneReadOnlyQuery() throws {
        let server = try LocalAeroSpaceServer(answer: { _ in
            (2, "", "AeroSpace server is disabled and doesn't accept commands. You can use 'aerospace enable on' to enable the server")
        })
        defer { server.stop() }

        let result = health(server.path)

        #expect(result.status == .disabled)
        #expect(result.nextStep?.contains("aerospace enable on") == true)
        let sent = server.requests.compactMap { $0["args"] as? [String] }
        #expect(sent == [["list-workspaces", "--focused", "--format", "%{workspace}"]])
    }

    @Test func doctorReportsAnOlderServerAsAProtocolMismatch() throws {
        let server = try LocalAeroSpaceServer(behavior: { _ in .legacy })
        defer { server.stop() }

        #expect(health(server.path).status == .protocolMismatch)
    }

    @Test func doctorReportsAWrongVersionBeforeAnythingElse() throws {
        let server = try LocalAeroSpaceServer(version: "0.21.0-Beta abc")
        defer { server.stop() }

        #expect(health(server.path).status == .wrongVersion(found: "0.21.0-Beta abc"))
    }

    @Test func doctorReportsAHealthyPinnedServerAsReady() throws {
        let server = try LocalAeroSpaceServer(answer: { _ in (0, "r1-1", "") })
        defer { server.stop() }

        let result = health(server.path)

        #expect(result.isReady)
        #expect(result.nextStep == nil)
    }

    @Test func doctorReportsAServerThatNeverAnswersAsUnreachableWithinItsTimeout() throws {
        let server = try LocalAeroSpaceServer(behavior: { _ in .silentAfterRequest })
        defer { server.stop() }

        let started = Date()
        let result = health(server.path, timeout: 0.3)

        #expect(result.status == .unreachable("timed out"))
        #expect(Date().timeIntervalSince(started) < 1.5)
    }
}
