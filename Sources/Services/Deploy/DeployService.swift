import Foundation

public final class DeployService: DeployServiceProtocol {
    public init() {}

    private var ssh: SSHServiceProtocol {
        DependencyContainer.shared.resolve(SSHServiceProtocol.self)
    }

    public func deploy(directory: String, on server: SSHConnectionInfo) async throws -> String {
        let dir = shellQuote(directory)
        let cmd = """
        set -e
        cd \(dir)
        if [ -d .git ]; then git pull --ff-only; fi
        if [ -f docker-compose.yml ] || [ -f compose.yml ]; then
          docker compose pull
          docker compose up -d
        fi
        echo DEPLOY_OK
        """
        let res = try await ssh.executeCommand(cmd, on: server)
        guard res.exitCode == 0 else {
            throw OpsError.sshCommandFailed(exitCode: res.exitCode, output: res.output)
        }
        return res.output
    }

    public func rollbackHint(directory: String, on server: SSHConnectionInfo) async throws -> String {
        let res = try await ssh.executeCommand(
            "cd \(shellQuote(directory)) && git log --oneline -n 5 2>/dev/null || echo 'No git history'",
            on: server
        )
        guard res.exitCode == 0 else {
            throw OpsError.sshCommandFailed(exitCode: res.exitCode, output: res.output)
        }
        return res.output
    }

    public func recentEvents(directory: String, on server: SSHConnectionInfo) async throws -> [DeploymentEvent] {
        let res = try await ssh.executeCommand(
            """
            cd \(shellQuote(directory)) 2>/dev/null || exit 0
            git log --pretty=format:'%H|%s|%ct' -n 20 2>/dev/null || true
            """,
            on: server
        )
        guard res.exitCode == 0 else { return [] }
        return res.output.components(separatedBy: .newlines).compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3, let epoch = Double(parts[2]) else { return nil }
            return DeploymentEvent(
                title: String(parts[1]),
                detail: String(parts[0].prefix(12)),
                timestamp: Date(timeIntervalSince1970: epoch),
                kind: "git"
            )
        }
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
