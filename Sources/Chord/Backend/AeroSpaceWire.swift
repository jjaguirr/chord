import ChordCore
import Foundation

/// The only commands Chord ever sends to AeroSpace. A closed set, so no code path can
/// send `enable` or any other command that changes machine-level behavior: Chord never
/// enables or disables the server.
enum AeroSpaceCommand: Equatable, Sendable {
    /// Every window on every workspace: id, workspace, layout, app name; tab separated,
    /// one window per line, app name last because it is free text.
    case listAllWindows
    /// The id of the focused window. An error answer means no window has focus.
    case focusedWindowID
    /// The name of the focused workspace.
    case focusedWorkspace
    /// Focuses the named workspace, creating it if it does not exist.
    case showWorkspace(String)
    /// Moves one window, named by id, to the named workspace.
    case moveWindow(WindowID, toWorkspace: String)

    /// The argument vector as the `aerospace` CLI would send it.
    var args: [String] {
        switch self {
        case .listAllWindows:
            return ["list-windows", "--all", "--format", "%{window-id}%{tab}%{workspace}%{tab}%{window-layout}%{tab}%{app-name}"]
        case .focusedWindowID:
            return ["list-windows", "--focused", "--format", "%{window-id}"]
        case .focusedWorkspace:
            return ["list-workspaces", "--focused", "--format", "%{workspace}"]
        case .showWorkspace(let name):
            return ["workspace", name]
        case .moveWindow(let id, let name):
            return ["move-node-to-workspace", "--window-id", String(id.rawValue), name]
        }
    }
}

/// A server's answer to one command.
struct AeroSpaceAnswer: Equatable, Sendable, Decodable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    /// `<version> <git hash>`, for example `0.21.3-Beta <hash>`.
    let serverVersionAndHash: String

    /// The server's own refusal text while disabled; it answers every command but
    /// `enable` this way.
    var isServerDisabled: Bool {
        exitCode != 0 && stderr.contains("server is disabled and doesn't accept commands")
    }
}

/// Why a command did not get an answer.
enum AeroSpaceTransportError: Error, Equatable, Sendable {
    /// No connection was made, or the handshake failed before any command was sent.
    case cannotConnect(String)
    /// The server answered the handshake with another protocol version, or with
    /// something that is not a handshake. Nothing was sent.
    case protocolMismatch
    /// The command may have reached the server, but no complete answer came back.
    case noReply(String)
}

/// The wire format of AeroSpace v0.21.3-Beta, read from that tag's
/// `Sources/Common/util/NWConnectionEx.swift`, `Sources/Common/model/clientServer.swift`,
/// and `Sources/AppBundle/server.swift`:
///
/// - Socket `/tmp/bobko.aerospace-<user>.sock`, a stream Unix socket.
/// - Handshake: the client sends `SOCKET_PROTOCOL_VERSION` (1) as a 4-byte little-endian
///   integer; the server answers with its own the same way.
/// - Then one connection serves many requests. Each message, in both directions, is a
///   4-byte little-endian byte count followed by that many bytes of JSON.
/// - Request: `{"args":[...],"stdin":"","windowId":null,"workspace":null}`. `windowId`
///   and `workspace` must be present (explicit `null`); the server adds a warning to
///   `stderr` when either is missing.
/// - Answer: `{"exitCode","stdout","stderr","serverVersionAndHash"}`.
///
/// Releases before 0.21 (the installed 0.20.3 among them) have neither handshake nor
/// length prefix. A handshake sent to one is answered with unframed JSON, which this
/// side reports as `protocolMismatch`.
enum AeroSpaceWire {
    static let protocolVersion: UInt32 = 1
    /// Largest answer accepted; a larger length prefix is a corrupt stream.
    static let maxMessageBytes = 16 * 1024 * 1024

    static func defaultSocketPath(user: String = NSUserName()) -> String {
        "/tmp/bobko.aerospace-\(user).sock"
    }

    static func integerBytes(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    static func integer(from bytes: Data) -> UInt32? {
        guard bytes.count == 4 else { return nil }
        let raw = bytes.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        return UInt32(littleEndian: raw)
    }

    /// The length-prefixed request for `command`.
    static func frame(_ command: AeroSpaceCommand) throws -> Data {
        let object: [String: Any] = [
            "args": command.args, "stdin": "", "windowId": NSNull(), "workspace": NSNull(),
        ]
        let json = try JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
        return integerBytes(UInt32(json.count)) + json
    }

    static func decodeAnswer(_ json: Data) throws -> AeroSpaceAnswer {
        try JSONDecoder().decode(AeroSpaceAnswer.self, from: json)
    }
}
