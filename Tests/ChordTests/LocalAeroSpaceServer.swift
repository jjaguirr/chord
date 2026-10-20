import Darwin
import Foundation
@testable import Chord

/// A throwaway server on a Unix socket in /tmp, speaking AeroSpace v0.21.3-Beta's wire
/// format (4-byte little-endian handshake, then length-prefixed JSON) or, on request,
/// a deliberately wrong one. It never touches the real AeroSpace socket.
final class LocalAeroSpaceServer: @unchecked Sendable {
    enum Behavior: Sendable {
        /// Handshake, then answer every request with `answer(args)`.
        case pinned
        /// Handshake, then read one request and close without answering.
        case dropsAfterRequest
        /// Handshake, then read one request and never answer.
        case silentAfterRequest
        /// Pre-0.21 style: no handshake, unframed JSON answer to whatever arrives.
        case legacy
        /// Handshake, then an answer whose length prefix is absurd.
        case hugeLengthPrefix
    }

    let path: String
    private var listener: Int32 = -1
    private let lock = NSLock()
    private var connectionCount = 0
    private var received: [[String: Any]] = []
    private let behavior: @Sendable (Int) -> Behavior
    private let answer: @Sendable ([String]) -> (exit: Int, stdout: String, stderr: String)
    private let version: String

    init(
        version: String = "0.21.3-Beta 0123abcdef",
        behavior: @escaping @Sendable (Int) -> Behavior = { _ in .pinned },
        answer: @escaping @Sendable ([String]) -> (exit: Int, stdout: String, stderr: String) = { _ in (0, "", "") }
    ) throws {
        self.version = version
        self.behavior = behavior
        self.answer = answer
        self.path = "/tmp/chord-test-\(UUID().uuidString.prefix(8)).sock"
        try listen()
        Thread.detachNewThread { [self] in acceptLoop() }
    }

    var connections: Int { lock.withLock { connectionCount } }
    var requests: [[String: Any]] { lock.withLock { received } }

    /// Stops accepting. The socket file stays unless `removeFile`, which leaves the stale
    /// file a crashed AeroSpace would.
    func stop(removeFile: Bool = true) {
        if listener >= 0 { Darwin.close(listener) }
        listener = -1
        if removeFile { unlink(path) }
    }

    deinit { stop() }

    private func listen() throws {
        listener = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0 else { throw POSIXError(.EIO) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
                _ = path.withCString { strncpy(destination, $0, capacity - 1) }
            }
        }
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, Darwin.listen(listener, 4) == 0 else { throw POSIXError(.EADDRINUSE) }
    }

    private func acceptLoop() {
        while true {
            let current = listener
            guard current >= 0 else { return }
            let client = accept(current, nil, nil)
            if client < 0 { return }
            let index = lock.withLock { () -> Int in
                connectionCount += 1
                return connectionCount
            }
            serve(client, behavior(index))
            Darwin.close(client)
        }
    }

    private func serve(_ client: Int32, _ behavior: Behavior) {
        switch behavior {
        case .legacy:
            _ = readSome(client)
            writeAll(client, Data(#"{"exitCode":2,"stdout":"","stderr":"Can't parse request","serverVersionAndHash":"0.20.3-Beta x"}"#.utf8))
            return
        default:
            break
        }
        guard let hello = readExactly(client, 4), AeroSpaceWire.integer(from: hello) == 1 else { return }
        writeAll(client, AeroSpaceWire.integerBytes(1))
        while let prefix = readExactly(client, 4), let count = AeroSpaceWire.integer(from: prefix),
            let body = readExactly(client, Int(count))
        {
            let request = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
            lock.withLock { received.append(request) }
            switch behavior {
            case .dropsAfterRequest:
                return
            case .silentAfterRequest:
                Thread.sleep(forTimeInterval: 2)
                return
            case .hugeLengthPrefix:
                writeAll(client, AeroSpaceWire.integerBytes(UInt32.max))
                return
            case .pinned, .legacy:
                let outcome = answer(request["args"] as? [String] ?? [])
                let json = try? JSONSerialization.data(withJSONObject: [
                    "exitCode": outcome.exit, "stdout": outcome.stdout, "stderr": outcome.stderr,
                    "serverVersionAndHash": version,
                ])
                let payload = json ?? Data()
                writeAll(client, AeroSpaceWire.integerBytes(UInt32(payload.count)) + payload)
            }
        }
    }

    private func readSome(_ fd: Int32) -> Data? {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let count = Darwin.read(fd, &buffer, buffer.count)
        return count > 0 ? Data(buffer[0..<count]) : nil
    }

    private func readExactly(_ fd: Int32, _ count: Int) -> Data? {
        var data = Data()
        while data.count < count {
            var buffer = [UInt8](repeating: 0, count: count - data.count)
            let got = Darwin.read(fd, &buffer, buffer.count)
            if got <= 0 { return nil }
            data.append(contentsOf: buffer[0..<got])
        }
        return data
    }

    private func writeAll(_ fd: Int32, _ data: Data) {
        var offset = 0
        let bytes = [UInt8](data)
        while offset < bytes.count {
            let written = bytes.withUnsafeBufferPointer {
                Darwin.write(fd, $0.baseAddress! + offset, bytes.count - offset)
            }
            if written <= 0 { return }
            offset += written
        }
    }
}
