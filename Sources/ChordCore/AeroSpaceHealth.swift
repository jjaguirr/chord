/// What one read-only probe of the AeroSpace socket observed. The shell produces it;
/// `AeroSpaceHealth` turns it into a verdict and a next step. Pure data.
public enum AeroSpaceProbe: Equatable, Sendable {
    /// The socket file does not exist: AeroSpace is not installed or not running.
    case socketMissing
    /// The socket file exists but nothing accepted the connection (a stale file).
    case refused(String)
    /// Connected, but the server did not answer the version handshake as the pinned
    /// protocol does (older releases answer unframed JSON).
    case protocolMismatch
    /// Connected and handshaken, but no usable answer arrived.
    case unreachable(String)
    /// The server answered that it is disabled and ignores commands.
    case serverDisabled(serverVersion: String)
    /// The server ran the read-only query.
    case answered(serverVersion: String)
    /// The server answered the query with an error.
    case rejected(serverVersion: String, message: String)
}

/// Compares a server's self-reported version with the pinned release tag.
public enum AeroSpaceVersion {
    /// The version number from a server's `<version> <hash>` string.
    public static func number(of serverVersionAndHash: String) -> String {
        String(serverVersionAndHash.split(separator: " ").first ?? "")
    }

    /// True when the server runs exactly the pinned release. A tag is `v0.21.3-Beta`;
    /// the server reports `0.21.3-Beta <hash>`.
    public static func matches(pinnedTag: String, serverVersionAndHash: String) -> Bool {
        let pinned = pinnedTag.hasPrefix("v") ? String(pinnedTag.dropFirst()) : pinnedTag
        return !pinned.isEmpty && number(of: serverVersionAndHash) == pinned
    }
}

/// The doctor's verdict on the AeroSpace server. Chord never enables, disables, or
/// starts AeroSpace; every unhealthy verdict carries the step the user takes.
public struct AeroSpaceHealth: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case ready(serverVersion: String)
        case notRunning
        case disabled
        case wrongVersion(found: String)
        case protocolMismatch
        case unreachable(String)
        case rejected(String)
    }

    public let status: Status
    public let pinnedTag: String

    public init(status: Status, pinnedTag: String) {
        self.status = status
        self.pinnedTag = pinnedTag
    }

    /// The verdict for `probe` against `pinnedTag`. A wrong version is reported before
    /// a disabled server, because installing the pinned release comes first.
    public init(probe: AeroSpaceProbe, pinnedTag: String) {
        self.pinnedTag = pinnedTag
        switch probe {
        case .socketMissing, .refused:
            status = .notRunning
        case .protocolMismatch:
            status = .protocolMismatch
        case .unreachable(let reason):
            status = .unreachable(reason)
        case .serverDisabled(let version):
            status = Self.versionStatus(version, pinnedTag) ?? .disabled
        case .answered(let version):
            status = Self.versionStatus(version, pinnedTag) ?? .ready(serverVersion: version)
        case .rejected(let version, let message):
            status = Self.versionStatus(version, pinnedTag) ?? .rejected(message)
        }
    }

    public var isReady: Bool {
        if case .ready = status { return true }
        return false
    }

    /// One line for the diagnostics bundle.
    public var summary: String {
        switch status {
        case .ready(let version): return "ready (server \(AeroSpaceVersion.number(of: version)))"
        case .notRunning: return "not running: no server answers on its socket"
        case .disabled: return "server is disabled and ignores commands"
        case .wrongVersion(let found):
            return "server is \(AeroSpaceVersion.number(of: found)), not the pinned \(pinnedTag)"
        case .protocolMismatch: return "server speaks a different protocol than the pinned \(pinnedTag)"
        case .unreachable(let reason): return "server did not answer: \(reason)"
        case .rejected(let message): return "server rejected a read-only query: \(message)"
        }
    }

    /// What the user does next. Nil when nothing is needed. Chord shows these steps and
    /// never runs them: turning AeroSpace on or off changes machine-level behavior.
    public var nextStep: String? {
        switch status {
        case .ready:
            return nil
        case .notRunning:
            return "Install AeroSpace \(pinnedTag) and open AeroSpace.app. Chord never starts it."
        case .disabled:
            return "AeroSpace is running with its server turned off. Chord never turns it on. "
                + "When you want Chord to use AeroSpace, run `aerospace enable on` yourself."
        case .wrongVersion:
            return "Install AeroSpace \(pinnedTag) (or set [backend] aerospace_tag to the release you tested) "
                + "and restart AeroSpace.app."
        case .protocolMismatch:
            return "Install AeroSpace \(pinnedTag) and restart AeroSpace.app; "
                + "releases before 0.21 use a different socket protocol."
        case .unreachable:
            return "Restart AeroSpace.app, then check again."
        case .rejected:
            return "Run `aerospace list-workspaces --focused` in a terminal to see the server's error."
        }
    }

    /// `summary` followed by the next step, as one block for the diagnostics bundle.
    public var report: String {
        guard let nextStep else { return summary }
        return "\(summary). Next step: \(nextStep)"
    }

    private static func versionStatus(_ serverVersion: String, _ pinnedTag: String) -> Status? {
        AeroSpaceVersion.matches(pinnedTag: pinnedTag, serverVersionAndHash: serverVersion)
            ? nil : .wrongVersion(found: serverVersion)
    }
}
