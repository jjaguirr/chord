import ChordCore
import Foundation

/// Checks whether the AeroSpace server is there, enabled, and the pinned version, and
/// reports the next step. Read-only: it sends one list query and nothing else. Chord
/// never starts, enables, or disables AeroSpace; a missing or disabled server is shown
/// to the user, who decides.
enum AeroSpaceDoctor {
    /// Blocking, bounded by `timeout`, safe from any thread. Never prompts.
    static func check(
        pinnedTag: String,
        socketPath: String = AeroSpaceWire.defaultSocketPath(),
        timeout: TimeInterval = 1
    ) -> AeroSpaceHealth {
        AeroSpaceHealth(probe: probe(socketPath: socketPath, timeout: timeout), pinnedTag: pinnedTag)
    }

    static func probe(socketPath: String, timeout: TimeInterval) -> AeroSpaceProbe {
        guard FileManager.default.fileExists(atPath: socketPath) else { return .socketMissing }
        let socket = AeroSpaceSocket(path: socketPath, timeout: timeout)
        defer { socket.close() }
        do {
            let answer = try socket.exchange(.focusedWorkspace)
            if answer.isServerDisabled { return .serverDisabled(serverVersion: answer.serverVersionAndHash) }
            if answer.exitCode != 0 {
                let line = answer.stderr.split(separator: "\n").first.map(String.init) ?? "exit code \(answer.exitCode)"
                return .rejected(serverVersion: answer.serverVersionAndHash, message: LogPolicy.clipped(line))
            }
            return .answered(serverVersion: answer.serverVersionAndHash)
        } catch AeroSpaceTransportError.cannotConnect(let reason) {
            return .refused(reason)
        } catch AeroSpaceTransportError.protocolMismatch {
            return .protocolMismatch
        } catch AeroSpaceTransportError.noReply(let reason) {
            return .unreachable(reason)
        } catch {
            return .unreachable(error.localizedDescription)
        }
    }
}
