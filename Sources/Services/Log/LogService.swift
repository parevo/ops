import Foundation

public final class LogService: LogServiceProtocol {
    public init() {}

    private var ssh: SSHServiceProtocol {
        DependencyContainer.shared.resolve(SSHServiceProtocol.self)
    }

    public func fetchStaticLogs(source: String, on server: SSHConnectionInfo) async throws -> [String] {
        let cmd: String
        if source.hasPrefix("container:") {
            let id = source.replacingOccurrences(of: "container:", with: "")
            cmd = "docker logs --tail 200 \(shellQuote(id)) 2>&1"
        } else if source.hasPrefix("unit:") {
            let unit = source.replacingOccurrences(of: "unit:", with: "")
            cmd = "journalctl -n 200 -u \(shellQuote(unit)) --no-pager 2>&1"
        } else {
            cmd = "journalctl -n 200 --no-pager 2>&1"
        }
        let res = try await ssh.executeCommand(cmd, on: server)
        guard res.exitCode == 0 || !res.output.isEmpty else {
            throw OpsError.sshCommandFailed(exitCode: res.exitCode, output: res.output)
        }
        return res.output.components(separatedBy: .newlines).filter { !$0.isEmpty }
    }

    public func streamLogs(source: String, on server: SSHConnectionInfo) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    _ = try await ssh.connect(server: server)
                    let cmd: String
                    if source.hasPrefix("container:") {
                        let id = source.replacingOccurrences(of: "container:", with: "")
                        cmd = "docker logs -f --tail 50 \(shellQuote(id)) 2>&1"
                    } else if source.hasPrefix("unit:") {
                        let unit = source.replacingOccurrences(of: "unit:", with: "")
                        cmd = "journalctl -f -u \(shellQuote(unit)) -n 20 --no-pager 2>&1"
                    } else {
                        cmd = "journalctl -f -n 20 --no-pager 2>&1"
                    }

                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
                    let safeHost = server.host.replacingOccurrences(of: ":", with: "_")
                    let socketPath = "/tmp/parevo-ssh-\(server.username)-\(safeHost)-\(server.port)"
                    var args = [
                        "-o", "ControlPath=\(socketPath)",
                        "-p", "\(server.port)",
                        "\(server.username)@\(server.host)",
                        cmd
                    ]
                    if server.authMethod == .sshKey, let key = server.privateKeyPath, !key.isEmpty {
                        args.insert(contentsOf: ["-i", (key as NSString).expandingTildeInPath], at: 0)
                    }
                    process.arguments = args
                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = pipe

                    continuation.onTermination = { _ in
                        if process.isRunning { process.terminate() }
                    }

                    try process.run()
                    let handle = pipe.fileHandleForReading
                    while process.isRunning {
                        try Task.checkCancellation()
                        if let chunk = try handle.read(upToCount: 2048), !chunk.isEmpty,
                           let text = String(data: chunk, encoding: .utf8) {
                            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                                let value = String(line).trimmingCharacters(in: .newlines)
                                if !value.isEmpty { continuation.yield(value) }
                            }
                        } else {
                            try await Task.sleep(nanoseconds: 80_000_000)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
