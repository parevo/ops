import Foundation

public struct PortTunnel: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var serverID: UUID
    public var serverName: String
    public var localPort: Int
    public var remoteHost: String
    public var remotePort: Int
    public var label: String

    public init(
        id: UUID = UUID(),
        serverID: UUID,
        serverName: String,
        localPort: Int,
        remoteHost: String = "127.0.0.1",
        remotePort: Int,
        label: String = ""
    ) {
        self.id = id
        self.serverID = serverID
        self.serverName = serverName
        self.localPort = localPort
        self.remoteHost = remoteHost
        self.remotePort = remotePort
        self.label = label.isEmpty ? "\(localPort) → \(remoteHost):\(remotePort)" : label
    }
}

public protocol PortForwardServiceProtocol: Sendable {
    func startTunnel(_ tunnel: PortTunnel, on server: SSHConnectionInfo) async throws
    func stopTunnel(id: UUID) async
    func stopAll() async
}

public final class PortForwardService: PortForwardServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var processes: [UUID: Process] = [:]

    public init() {}

    public func startTunnel(_ tunnel: PortTunnel, on server: SSHConnectionInfo) async throws {
        // Ensure ControlMaster is up (handles password via ASKPASS).
        _ = try await DependencyContainer.shared.resolve(SSHServiceProtocol.self).connect(server: server)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
                    process.arguments = [
                        "-N",
                        "-L", "\(tunnel.localPort):\(tunnel.remoteHost):\(tunnel.remotePort)",
                        "-o", "ControlPath=\(server.controlSocketPath)",
                        "-o", "ControlMaster=auto",
                        "-o", "ControlPersist=30m",
                        "-o", "ExitOnForwardFailure=yes",
                        "-o", "BatchMode=yes",
                        "-p", "\(server.port)",
                        "\(server.username)@\(server.host)"
                    ]
                    let err = Pipe()
                    process.standardError = err
                    process.standardOutput = Pipe()
                    try process.run()

                    // Give ssh a moment to fail fast on bind errors.
                    Thread.sleep(forTimeInterval: 0.35)
                    if !process.isRunning {
                        let data = err.fileHandleForReading.readDataToEndOfFile()
                        let msg = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Tunnel failed"
                        continuation.resume(throwing: OpsError.sshConnectionFailed(msg.isEmpty ? "Tunnel failed" : msg))
                        return
                    }

                    self.lock.lock()
                    self.processes[tunnel.id] = process
                    self.lock.unlock()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func stopTunnel(id: UUID) async {
        lock.lock()
        let process = processes.removeValue(forKey: id)
        lock.unlock()
        process?.terminate()
    }

    public func stopAll() async {
        lock.lock()
        let all = Array(processes.values)
        processes.removeAll()
        lock.unlock()
        all.forEach { $0.terminate() }
    }
}
