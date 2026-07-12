import Foundation

public final class SSHService: SSHServiceProtocol, @unchecked Sendable {
    private let fileManager = FileManager.default
    private let lock = NSLock()
    private var activeSessions: Set<String> = []

    public init() {}

    private func controlPath(for server: SSHConnectionInfo) -> String {
        let safeHost = server.host.replacingOccurrences(of: ":", with: "_")
        let safeUser = server.username.replacingOccurrences(of: "/", with: "_")
        return "/tmp/parevo-ssh-\(safeUser)-\(safeHost)-\(server.port)"
    }

    private func isCached(_ socketPath: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeSessions.contains(socketPath) && fileManager.fileExists(atPath: socketPath)
    }

    private func cache(_ socketPath: String) {
        lock.lock()
        defer { lock.unlock() }
        activeSessions.insert(socketPath)
    }

    private func uncache(_ socketPath: String) {
        lock.lock()
        defer { lock.unlock() }
        activeSessions.remove(socketPath)
    }

    private func expandPath(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    private func makeAskPass(password: String) throws -> URL {
        let dir = fileManager.temporaryDirectory
        let script = dir.appendingPathComponent("parevo-askpass-\(UUID().uuidString).sh")
        let escaped = password
            .replacingOccurrences(of: "'", with: "'\\''")
        let content = "#!/bin/sh\necho '\(escaped)'\n"
        try content.write(to: script, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        return script
    }

    private func baseArguments(for server: SSHConnectionInfo, socketPath: String) -> [String] {
        var args = [
            "-o", "ControlPath=\(socketPath)",
            "-o", "ConnectTimeout=10",
            "-o", "ServerAliveInterval=30",
            "-o", "ServerAliveCountMax=3",
            "-o", "StrictHostKeyChecking=accept-new",
            "-p", "\(server.port)"
        ]
        if server.authMethod == .sshKey, let keyPath = server.privateKeyPath, !keyPath.isEmpty {
            args += ["-i", expandPath(keyPath), "-o", "IdentitiesOnly=yes"]
        }
        return args
    }

    public func connect(server: SSHConnectionInfo) async throws -> Bool {
        let socketPath = controlPath(for: server)
        if isCached(socketPath) { return true }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.openMaster(server: server, socketPath: socketPath)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        return true
    }

    private func openMaster(server: SSHConnectionInfo, socketPath: String) throws {
        if fileManager.fileExists(atPath: socketPath) {
            cache(socketPath)
            return
        }

        var askPassURL: URL?
        defer {
            if let askPassURL {
                try? fileManager.removeItem(at: askPassURL)
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        var args = baseArguments(for: server, socketPath: socketPath)
        args += [
            "-o", "ControlMaster=yes",
            "-o", "ControlPersist=10m",
            "-N", "-f",
            "\(server.username)@\(server.host)"
        ]

        var environment = Foundation.ProcessInfo.processInfo.environment
        if server.authMethod == .password {
            guard let password = server.passwordPlain, !password.isEmpty else {
                throw OpsError.sshConnectionFailed("Password is missing in Keychain.")
            }
            let script = try makeAskPass(password: password)
            askPassURL = script
            environment["SSH_ASKPASS"] = script.path
            environment["SSH_ASKPASS_REQUIRE"] = "force"
            environment["DISPLAY"] = "none"
            process.environment = environment
        }

        process.arguments = args
        let err = Pipe()
        process.standardOutput = Pipe()
        process.standardError = err

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0, fileManager.fileExists(atPath: socketPath) {
            cache(socketPath)
            return
        }

        let errData = err.fileHandleForReading.readDataToEndOfFile()
        let message = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
        throw OpsError.sshConnectionFailed(message.isEmpty ? "exit \(process.terminationStatus)" : message)
    }

    public func executeCommand(_ command: String, on server: SSHConnectionInfo) async throws -> (output: String, exitCode: Int) {
        _ = try await connect(server: server)
        let socketPath = controlPath(for: server)

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try self.runCommand(command, server: server, socketPath: socketPath)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runCommand(_ command: String, server: SSHConnectionInfo, socketPath: String) throws -> (output: String, exitCode: Int) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        var args = baseArguments(for: server, socketPath: socketPath)
        args += ["\(server.username)@\(server.host)", command]
        process.arguments = args

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(data: outData, encoding: .utf8) ?? ""
        let errorText = String(data: errData, encoding: .utf8) ?? ""
        let exitCode = Int(process.terminationStatus)
        let combined = errorText.isEmpty ? output : (output.isEmpty ? errorText : output + "\n" + errorText)
        return (combined, exitCode)
    }

    public func disconnect(server: SSHConnectionInfo) async {
        let socketPath = controlPath(for: server)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = ["-O", "exit", "-S", socketPath, "\(server.username)@\(server.host)"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
        uncache(socketPath)
        try? fileManager.removeItem(atPath: socketPath)
    }
}
