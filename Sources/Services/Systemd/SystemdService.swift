import Foundation

public final class SystemdService: SystemdServiceProtocol {
    public init() {}

    private var ssh: SSHServiceProtocol {
        DependencyContainer.shared.resolve(SSHServiceProtocol.self)
    }

    public func fetchServices(for server: SSHConnectionInfo) async throws -> [SystemdServiceInfo] {
        let res = try await ssh.executeCommand(
            "systemctl list-units --type=service --all --no-pager --plain --no-legend",
            on: server
        )
        guard res.exitCode == 0 else {
            throw OpsError.sshCommandFailed(exitCode: res.exitCode, output: res.output)
        }
        return res.output.components(separatedBy: .newlines).compactMap { line in
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 5 else { return nil }
            let unit = String(parts[0])
            let load = String(parts[1])
            let active = String(parts[2])
            let sub = String(parts[3])
            let description = parts.dropFirst(4).joined(separator: " ")
            return SystemdServiceInfo(unit: unit, load: load, active: active, sub: sub, description: description)
        }
    }

    public func restart(unit: String, on server: SSHConnectionInfo) async throws {
        try await run("systemctl restart \(shellQuote(unit))", on: server)
    }

    public func stop(unit: String, on server: SSHConnectionInfo) async throws {
        try await run("systemctl stop \(shellQuote(unit))", on: server)
    }

    public func start(unit: String, on server: SSHConnectionInfo) async throws {
        try await run("systemctl start \(shellQuote(unit))", on: server)
    }

    public func enable(unit: String, on server: SSHConnectionInfo) async throws {
        try await run("systemctl enable \(shellQuote(unit))", on: server)
    }

    public func disable(unit: String, on server: SSHConnectionInfo) async throws {
        try await run("systemctl disable \(shellQuote(unit))", on: server)
    }

    private func run(_ cmd: String, on server: SSHConnectionInfo) async throws {
        let res = try await ssh.executeCommand(cmd, on: server)
        guard res.exitCode == 0 else {
            throw OpsError.sshCommandFailed(exitCode: res.exitCode, output: res.output)
        }
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
