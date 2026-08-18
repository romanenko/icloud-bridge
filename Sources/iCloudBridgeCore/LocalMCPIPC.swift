import Foundation
import OSLog
import SwiftMCP

#if os(macOS)
import Darwin
#endif

/// The private per-user IPC endpoint used between the menu-bar owner and stdio shims.
public enum iCloudBridgeIPC {
    public static var socketPath: String {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("iCloud Bridge", isDirectory: true)
            .appendingPathComponent("mcp.sock")
            .path
    }
}

/// Serves MCP requests from the already-authorized menu-bar process.
///
/// macOS TCC attributes a directly spawned stdio child to its parent MCP client.
/// Keeping EventKit here means the MCP client only handles JSON-RPC and never
/// needs Calendar or Reminders permission itself.
public final class LocalMCPBroker: @unchecked Sendable {
    private let server: iCloudBridgeServer
    private let logger = Logger(subsystem: "com.icloudbridge.app", category: "mcp-ipc")
    private let queue = DispatchQueue(label: "com.icloudbridge.app.mcp-ipc")
    private var listenerFD: Int32 = -1
    private var listenerSource: DispatchSourceRead?

    public init(server: iCloudBridgeServer) {
        self.server = server
    }

    public func start() throws {
        guard listenerFD == -1 else { return }

        let directory = URL(fileURLWithPath: iCloudBridgeIPC.socketPath).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        _ = iCloudBridgeIPC.socketPath.withCString { unlink($0) }

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw posixError(operation: "create MCP socket") }

        do {
            try withUnixAddress(path: iCloudBridgeIPC.socketPath) { address, length in
                let result = withUnsafePointer(to: address) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        Darwin.bind(fd, $0, length)
                    }
                }
                guard result == 0 else { throw posixError(operation: "bind MCP socket") }
            }

            guard Darwin.listen(fd, 8) == 0 else {
                throw posixError(operation: "listen on MCP socket")
            }
            guard fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else {
                throw posixError(operation: "configure MCP socket")
            }
            guard chmod(iCloudBridgeIPC.socketPath, S_IRUSR | S_IWUSR) == 0 else {
                throw posixError(operation: "secure MCP socket")
            }
        } catch {
            Darwin.close(fd)
            _ = iCloudBridgeIPC.socketPath.withCString { unlink($0) }
            throw error
        }

        listenerFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptConnections()
        }
        source.setCancelHandler {
            Darwin.close(fd)
        }
        listenerSource = source
        source.resume()
        logger.notice("MCP broker listening on the private user socket")
    }

    public func stop() {
        listenerSource?.cancel()
        listenerSource = nil
        listenerFD = -1
        _ = iCloudBridgeIPC.socketPath.withCString { unlink($0) }
        logger.notice("MCP broker stopped")
    }

    private func acceptConnections() {
        guard listenerFD >= 0 else { return }

        while true {
            let clientFD = Darwin.accept(listenerFD, nil, nil)
            if clientFD >= 0 {
                // The listener is nonblocking for the accept loop; each client
                // connection is consumed by a blocking line reader instead.
                _ = fcntl(clientFD, F_SETFL, 0)
                serveConnection(clientFD)
                continue
            }

            if errno == EAGAIN || errno == EWOULDBLOCK {
                return
            }
            let message = String(cString: strerror(errno))
            logger.error("MCP socket accept failed: \(message, privacy: .public)")
            return
        }
    }

    private func serveConnection(_ clientFD: Int32) {
        let server = self.server
        let logger = self.logger
        Task.detached(priority: .userInitiated) {
            defer { Darwin.close(clientFD) }

            do {
                while let line = readSocketLine(clientFD) {
                    guard !line.isEmpty else { continue }
                    let messages = try JSONRPCMessage.decodeMessages(from: line)
                    let replies = await server.processBatch(messages)
                    for reply in replies {
                        var encoded = try reply.encoded()
                        encoded.append(10)
                        try writeSocketData(encoded, to: clientFD)
                    }
                }
            } catch {
                logger.error("MCP socket connection failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

/// Proxies MCP stdio to the menu-bar process without touching EventKit.
public enum LocalMCPProxy {
    public static func run() throws {
        let fd = try connectToBroker()
        defer { Darwin.close(fd) }

        while let line = readStandardInputLine() {
            guard !line.isEmpty else { continue }
            let messages = try JSONRPCMessage.decodeMessages(from: line)
            try writeSocketData(line + Data([10]), to: fd)

            let expectedReplies = messages.reduce(into: 0) { count, message in
                if case .request = message {
                    count += 1
                }
            }

            for _ in 0..<expectedReplies {
                guard let reply = readSocketLine(fd) else {
                    throw NSError(
                        domain: "iCloudBridge",
                        code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "iCloud Bridge closed the MCP connection."]
                    )
                }
                try writeStandardOutput(reply + Data([10]))
            }
        }
    }

    private static func connectToBroker() throws -> Int32 {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw posixError(operation: "create MCP client socket") }

        do {
            try withUnixAddress(path: iCloudBridgeIPC.socketPath) { address, length in
                let result = withUnsafePointer(to: address) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        Darwin.connect(fd, $0, length)
                    }
                }
                guard result == 0 else { throw posixError(operation: "connect to iCloud Bridge") }
            }
            return fd
        } catch {
            Darwin.close(fd)
            throw NSError(
                domain: "iCloudBridge",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey: "iCloud Bridge is not running. Launch the menu-bar app and grant Calendar or Reminders access first.",
                    NSUnderlyingErrorKey: error,
                ]
            )
        }
    }
}

private func withUnixAddress<T>(path: String, _ body: (inout sockaddr_un, socklen_t) throws -> T) throws -> T {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)

    let pathBytes = Array(path.utf8) + [0]
    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    guard pathBytes.count <= capacity else {
        throw NSError(domain: "iCloudBridge", code: 1, userInfo: [NSLocalizedDescriptionKey: "MCP socket path is too long."])
    }

    withUnsafeMutableBytes(of: &address.sun_path) { destination in
        destination.copyBytes(from: pathBytes)
    }

    let offset = MemoryLayout<sockaddr_un>.offset(of: \.sun_path) ?? 0
    return try body(&address, socklen_t(offset + pathBytes.count))
}

private func posixError(operation: String) -> NSError {
    NSError(
        domain: NSPOSIXErrorDomain,
        code: Int(errno),
        userInfo: [NSLocalizedDescriptionKey: "\(operation): \(String(cString: strerror(errno)))"]
    )
}

private func readSocketLine(_ fd: Int32) -> Data? {
    var data = Data()
    var byte: UInt8 = 0

    while true {
        let count = withUnsafeMutableBytes(of: &byte) { buffer in
            Darwin.read(fd, buffer.baseAddress, 1)
        }
        if count == 0 { return data.isEmpty ? nil : data }
        if count < 0 {
            return errno == EINTR ? readSocketLine(fd) : nil
        }
        if byte == 10 { return data }
        data.append(byte)
    }
}

private func writeSocketData(_ data: Data, to fd: Int32) throws {
    try data.withUnsafeBytes { buffer in
        guard var pointer = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
        var remaining = buffer.count

        while remaining > 0 {
            let written = Darwin.write(fd, pointer, remaining)
            if written < 0 {
                if errno == EINTR { continue }
                throw posixError(operation: "write MCP socket")
            }
            pointer = pointer.advanced(by: written)
            remaining -= written
        }
    }
}

private func readStandardInputLine() -> Data? {
    readSocketLine(STDIN_FILENO)
}

private func writeStandardOutput(_ data: Data) throws {
    try writeSocketData(data, to: STDOUT_FILENO)
}
