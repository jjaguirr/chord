import ChordCore
import Darwin
import Foundation

/// Carries one command to the AeroSpace server and returns its answer.
protocol AeroSpaceTransport: Sendable {
    func send(_ command: AeroSpaceCommand) async throws -> AeroSpaceAnswer
    /// Drops the connection so the next `send` opens a fresh one. Idempotent.
    func reset() async
}

/// A persistent connection to AeroSpace's Unix socket. It connects lazily, handshakes
/// once per connection, and drops the connection after any failure so the byte stream
/// is never left half-read. Reads cost tens of milliseconds server-side (spike 6b):
/// command speed, never per frame.
///
/// Exchanges are serialized. Blocking socket calls run off the cooperative pool, and
/// every call is bounded by `timeout`.
final class AeroSpaceSocket: AeroSpaceTransport, @unchecked Sendable {
    private let path: String
    private let timeout: TimeInterval
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "chord.aerospace-socket")
    private var descriptor: Int32?

    init(path: String = AeroSpaceWire.defaultSocketPath(), timeout: TimeInterval = 2) {
        self.path = path
        self.timeout = timeout
    }

    deinit {
        if let descriptor { Darwin.close(descriptor) }
    }

    func send(_ command: AeroSpaceCommand) async throws -> AeroSpaceAnswer {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try self.exchange(command) })
            }
        }
    }

    func reset() async {
        close()
    }

    /// The blocking exchange; `send` runs it off the cooperative pool and the doctor
    /// calls it directly with a short timeout.
    func exchange(_ command: AeroSpaceCommand) throws -> AeroSpaceAnswer {
        lock.lock()
        defer { lock.unlock() }
        let fd = try connectedDescriptor()
        do {
            let request = try AeroSpaceWire.frame(command)
            try writeAll(fd, request)
            let prefix = try readExactly(fd, 4)
            guard let count = AeroSpaceWire.integer(from: prefix), count <= AeroSpaceWire.maxMessageBytes else {
                throw AeroSpaceTransportError.noReply("answer length is not valid")
            }
            let body = try readExactly(fd, Int(count))
            return try AeroSpaceWire.decodeAnswer(body)
        } catch {
            closeLocked()
            if let transport = error as? AeroSpaceTransportError { throw transport }
            throw AeroSpaceTransportError.noReply("answer could not be read: \(error.localizedDescription)")
        }
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        closeLocked()
    }

    // MARK: Connection

    private func closeLocked() {
        if let descriptor { Darwin.close(descriptor) }
        descriptor = nil
    }

    private func connectedDescriptor() throws -> Int32 {
        if let descriptor { return descriptor }
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AeroSpaceTransportError.cannotConnect(Self.describe(errno)) }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        var limit = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - timeout.rounded(.down)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &limit, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &limit, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else {
            Darwin.close(fd)
            throw AeroSpaceTransportError.cannotConnect("socket path is too long")
        }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
                _ = path.withCString { strncpy(destination, $0, capacity - 1) }
            }
        }
        let status = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard status == 0 else {
            let reason = Self.describe(errno)
            Darwin.close(fd)
            throw AeroSpaceTransportError.cannotConnect(reason)
        }

        do {
            try writeAll(fd, AeroSpaceWire.integerBytes(AeroSpaceWire.protocolVersion))
            let reply = try readExactly(fd, 4)
            guard AeroSpaceWire.integer(from: reply) == AeroSpaceWire.protocolVersion else {
                throw AeroSpaceTransportError.protocolMismatch
            }
        } catch let error as AeroSpaceTransportError {
            Darwin.close(fd)
            if error == .protocolMismatch { throw error }
            // Nothing was sent beyond the handshake, so no command can have applied.
            throw AeroSpaceTransportError.cannotConnect("handshake failed")
        }
        descriptor = fd
        return fd
    }

    // MARK: Bytes

    private func writeAll(_ fd: Int32, _ data: Data) throws {
        var offset = 0
        try data.withUnsafeBytes { buffer in
            while offset < buffer.count {
                let written = Darwin.write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw AeroSpaceTransportError.noReply("write failed: \(Self.describe(errno))")
                }
                offset += written
            }
        }
    }

    private func readExactly(_ fd: Int32, _ count: Int) throws -> Data {
        var data = Data(count: count)
        var offset = 0
        try data.withUnsafeMutableBytes { buffer in
            while offset < count {
                let received = Darwin.read(fd, buffer.baseAddress! + offset, count - offset)
                if received == 0 { throw AeroSpaceTransportError.noReply("connection closed") }
                if received < 0 {
                    if errno == EINTR { continue }
                    let timedOut = errno == EAGAIN || errno == EWOULDBLOCK
                    throw AeroSpaceTransportError.noReply(timedOut ? "timed out" : "read failed: \(Self.describe(errno))")
                }
                offset += received
            }
        }
        return data
    }

    private static func describe(_ code: Int32) -> String {
        String(cString: strerror(code))
    }
}
