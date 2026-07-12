import Foundation

public final class DeployService: DeployServiceProtocol {
    public init() {}

    private var ssh: SSHServiceProtocol {
        DependencyContainer.shared.resolve(SSHServiceProtocol.self)
    }

    public func deploy(directory: String, on server: SSHConnectionInfo) async throws -> String {
        let steps = try await deployPipeline(directory: directory, on: server)
        return steps.map { "[\($0.isSuccess ? "OK" : "FAIL")] \($0.title)\n\($0.detail)" }.joined(separator: "\n\n")
    }

    public func deployPipeline(directory: String, on server: SSHConnectionInfo) async throws -> [DeployStep] {
        let dir = shellQuote(directory)
        var steps: [DeployStep] = []

        func run(_ title: String, _ command: String) async throws {
            let res = try await ssh.executeCommand(command, on: server)
            let ok = res.exitCode == 0
            steps.append(DeployStep(title: title, detail: res.output.trimmingCharacters(in: .whitespacesAndNewlines), isSuccess: ok))
            if !ok {
                throw OpsError.sshCommandFailed(exitCode: res.exitCode, output: res.output)
            }
        }

        try await run("Git pull", """
            set -e
            cd \(dir)
            if [ -d .git ]; then git pull --ff-only; else echo 'No git repo'; fi
            """)

        try await run("Compose pull", """
            set -e
            cd \(dir)
            if [ -f docker-compose.yml ] || [ -f compose.yml ]; then docker compose pull; else echo 'No compose file'; fi
            """)

        try await run("Compose up", """
            set -e
            cd \(dir)
            if [ -f docker-compose.yml ] || [ -f compose.yml ]; then docker compose up -d; else echo 'No compose file'; fi
            """)

        try await run("Health snapshot", """
            set -e
            cd \(dir)
            docker compose ps 2>/dev/null || docker ps --format 'table {{.Names}}\t{{.Status}}' | head -20
            """)

        return steps
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
