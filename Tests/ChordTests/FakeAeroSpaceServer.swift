import ChordCore
import Foundation
@testable import Chord

/// An in-memory stand-in for a pinned AeroSpace server, speaking `AeroSpaceCommand`
/// instead of bytes. It records every command it was sent, so tests can prove what
/// was and was not asked of the server. Faults are consumed one per command.
actor FakeAeroSpaceServer: AeroSpaceTransport {
    enum Fault: Equatable, Sendable {
        /// No connection; nothing reaches the server.
        case cannotConnect
        /// The handshake is refused; nothing reaches the server.
        case protocolMismatch
        /// The command is lost before the server runs it.
        case noReplyBeforeApply
        /// The server runs the command but the answer never arrives.
        case noReplyAfterApply
        /// The server answers with this error and does not run the command.
        case failure(String)
        /// The command succeeds normally but uses up this queue slot, to aim a later fault.
        case proceed
    }

    struct Window: Equatable, Sendable {
        var workspace: String
        var layout: String
        var app: String
    }

    static let pinnedVersion = "0.21.3-Beta 0123abcdef"

    private(set) var windows: [Int: Window]
    private var order: [Int]
    private(set) var focusedWorkspace: String
    private(set) var focusedWindow: Int?
    private(set) var sent: [AeroSpaceCommand] = []
    private(set) var resets = 0
    var version = FakeAeroSpaceServer.pinnedVersion
    var enabled = true
    private var faults: [Fault] = []
    private var rawWindowLines: [String]?

    init(windows: [(id: Int, workspace: String, app: String)], focusedWorkspace: String, focusedWindow: Int? = nil) {
        self.windows = Dictionary(
            uniqueKeysWithValues: windows.map { ($0.id, Window(workspace: $0.workspace, layout: "floating", app: $0.app)) })
        self.order = windows.map(\.id)
        self.focusedWorkspace = focusedWorkspace
        self.focusedWindow = focusedWindow
    }

    func queue(_ faults: [Fault]) { self.faults.append(contentsOf: faults) }
    func setEnabled(_ enabled: Bool) { self.enabled = enabled }
    func setVersion(_ version: String) { self.version = version }
    /// Makes `list-windows --all` answer these lines verbatim.
    func overrideWindowLines(_ lines: [String]?) { rawWindowLines = lines }
    func workspace(of id: Int) -> String? { windows[id]?.workspace }

    /// Commands that change anything, in order.
    var changes: [AeroSpaceCommand] {
        sent.filter {
            switch $0 {
            case .showWorkspace, .moveWindow: return true
            case .listAllWindows, .focusedWindowID, .focusedWorkspace: return false
            }
        }
    }

    func reset() async { resets += 1 }

    func send(_ command: AeroSpaceCommand) async throws -> AeroSpaceAnswer {
        let fault = faults.isEmpty ? nil : faults.removeFirst()
        switch fault {
        case .cannotConnect: throw AeroSpaceTransportError.cannotConnect("connection refused")
        case .protocolMismatch: throw AeroSpaceTransportError.protocolMismatch
        case .noReplyBeforeApply:
            sent.append(command)
            throw AeroSpaceTransportError.noReply("timed out")
        case .failure(let message):
            sent.append(command)
            return answer(exit: 2, stderr: message)
        case .noReplyAfterApply, .proceed, nil:
            break
        }
        sent.append(command)
        guard enabled else {
            return answer(exit: 2, stderr: "AeroSpace server is disabled and doesn't accept commands. You can use 'aerospace enable on' to enable the server")
        }
        let result = run(command)
        if fault == .noReplyAfterApply { throw AeroSpaceTransportError.noReply("connection closed") }
        return result
    }

    private func run(_ command: AeroSpaceCommand) -> AeroSpaceAnswer {
        switch command {
        case .listAllWindows:
            if let rawWindowLines { return answer(stdout: rawWindowLines.joined(separator: "\n")) }
            let lines = order.compactMap { id in
                windows[id].map { "\(id)\t\($0.workspace)\t\($0.layout)\t\($0.app)" }
            }
            return answer(stdout: lines.joined(separator: "\n"))
        case .focusedWindowID:
            guard let focusedWindow else { return answer(exit: 1, stderr: "Can't find focused window") }
            return answer(stdout: String(focusedWindow))
        case .focusedWorkspace:
            return answer(stdout: focusedWorkspace)
        case .showWorkspace(let name):
            focusedWorkspace = name
            return answer()
        case .moveWindow(let id, let name):
            guard windows[id.rawValue] != nil else { return answer(exit: 2, stderr: "Can't find window with ID \(id.rawValue)") }
            windows[id.rawValue]?.workspace = name
            return answer()
        }
    }

    private func answer(exit: Int32 = 0, stdout: String = "", stderr: String = "") -> AeroSpaceAnswer {
        AeroSpaceAnswer(exitCode: exit, stdout: stdout, stderr: stderr, serverVersionAndHash: version)
    }
}
