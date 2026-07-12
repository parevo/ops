import Foundation

public final class SSHService: SSHServiceProtocol, @unchecked Sendable {
    private let fileManager = FileManager.default
    private let lock = NSLock()
    private var activeSessions: Set<String> = []
    private var runningProcesses: [UUID: Process] = [:]

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
        let escaped = password.replacingOccurrences(of: "'", with: "'\\''")
        try "#!/bin/sh\necho '\(escaped)'\n".write(to: script, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        return script
    }

    private func baseArguments(for server: SSHConnectionInfo, socketPath: String) -> [String] {
        var args = [
            "-o", "ControlPath=\(socketPath)",
            "-o", "ControlMaster=auto",
            "-o", "ControlPersist=30m",
            "-o", "ConnectTimeout=8",
            "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=2",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "Compression=no",
            "-o", "IPQoS=throughput",
            "-p", "\(server.port)"
        ]
        if server.authMethod == .sshKey, let keyPath = server.privateKeyPath, !keyPath.isEmpty {
            args += [
                "-i", expandPath(keyPath),
                "-o", "IdentitiesOnly=yes",
                "-o", "BatchMode=yes",
                "-o", "PreferredAuthentications=publickey"
            ]
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
            if let askPassURL { try? fileManager.removeItem(at: askPassURL) }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        var args = baseArguments(for: server, socketPath: socketPath)
        args += [
            "-o", "ControlMaster=yes",
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

    /// Non-TTY, clean stdout — used for Docker API / JSON / parsing commands.
    public func executeCommand(_ command: String, on server: SSHConnectionInfo) async throws -> (output: String, exitCode: Int) {
        _ = try await connect(server: server)
        let socketPath = controlPath(for: server)

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
                    var args = self.baseArguments(for: server, socketPath: socketPath)
                    // Explicitly NO tty — prevents \r and prompt pollution in JSON.
                    args += [
                        "-o", "RequestTTY=no",
                        "\(server.username)@\(server.host)",
                        command
                    ]
                    process.arguments = args

                    let out = Pipe()
                    let err = Pipe()
                    process.standardOutput = out
                    process.standardError = err
                    try process.run()
                    process.waitUntilExit()

                    let outText = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    let errText = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    let code = Int(process.terminationStatus)
                    let cleanedOut = outText.replacingOccurrences(of: "\r", with: "")
                    let cleanedErr = errText.replacingOccurrences(of: "\r", with: "")
                    let combined = cleanedErr.isEmpty
                        ? cleanedOut
                        : (cleanedOut.isEmpty ? cleanedErr : cleanedOut + "\n" + cleanedErr)
                    continuation.resume(returning: (combined, code))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Live stream with TTY — for `docker logs -f`, shells, etc.
    public func streamCommand(_ command: String, on server: SSHConnectionInfo) -> AsyncThrowingStream<SSHStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let jobID = UUID()
            let processBox = ProcessBox()

            let work = Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else {
                    continuation.finish(throwing: OpsError.sshConnectionFailed("SSH service deallocated"))
                    return
                }

                do {
                    _ = try await self.connect(server: server)
                    let socketPath = self.controlPath(for: server)

                    let wrapped = """
                    export TERM=xterm-256color; \
                    if command -v stdbuf >/dev/null 2>&1; then \
                      stdbuf -oL -eL bash -lc \(self.shellSingleQuote(command)); \
                    else \
                      bash -lc \(self.shellSingleQuote(command)); \
                    fi
                    """

                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
                    var args = self.baseArguments(for: server, socketPath: socketPath)
                    args += ["-tt", "\(server.username)@\(server.host)", wrapped]
                    process.arguments = args

                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = pipe

                    processBox.process = process
                    self.lock.lock()
                    self.runningProcesses[jobID] = process
                    self.lock.unlock()

                    let handle = pipe.fileHandleForReading
                    handle.readabilityHandler = { fileHandle in
                        let data = fileHandle.availableData
                        guard !data.isEmpty else { return }
                        if let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
                            let cleaned = text
                                .replacingOccurrences(of: "\r\n", with: "\n")
                                .replacingOccurrences(of: "\r", with: "\n")
                            if !cleaned.isEmpty {
                                continuation.yield(.chunk(cleaned))
                            }
                        }
                    }

                    let exitCode: Int32 = try await withTaskCancellationHandler {
                        try await withCheckedThrowingContinuation { (resume: CheckedContinuation<Int32, Error>) in
                            var resumed = false
                            let gate = NSLock()
                            func finish(_ code: Int32) {
                                gate.lock(); defer { gate.unlock() }
                                guard !resumed else { return }
                                resumed = true
                                resume.resume(returning: code)
                            }
                            func fail(_ error: Error) {
                                gate.lock(); defer { gate.unlock() }
                                guard !resumed else { return }
                                resumed = true
                                resume.resume(throwing: error)
                            }

                            process.terminationHandler = { finished in
                                finish(finished.terminationStatus)
                            }

                            do {
                                try process.run()
                            } catch {
                                fail(error)
                            }
                        }
                    } onCancel: {
                        Self.forceStop(process)
                    }

                    handle.readabilityHandler = nil

                    if let leftover = try? handle.readToEnd(), !leftover.isEmpty,
                       let text = String(data: leftover, encoding: .utf8) {
                        let cleaned = text
                            .replacingOccurrences(of: "\r\n", with: "\n")
                            .replacingOccurrences(of: "\r", with: "\n")
                        if !cleaned.isEmpty {
                            continuation.yield(.chunk(cleaned))
                        }
                    }

                    if !Task.isCancelled {
                        continuation.yield(.exit(code: Int(exitCode)))
                    }
                    continuation.finish()
                } catch {
                    if let process = processBox.process {
                        Self.forceStop(process)
                    }
                    continuation.finish(throwing: error)
                }

                self.lock.lock()
                self.runningProcesses.removeValue(forKey: jobID)
                self.lock.unlock()
                processBox.process = nil
            }

            continuation.onTermination = { @Sendable _ in
                work.cancel()
                if let process = processBox.process {
                    Self.forceStop(process)
                }
            }
        }
    }

    private static func forceStop(_ process: Process) {
        guard process.isRunning else { return }
        process.interrupt()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.35) {
            if process.isRunning {
                process.terminate()
            }
        }
    }

    private final class ProcessBox: @unchecked Sendable {
        var process: Process?
    }

    private func shellSingleQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public func disconnect(server: SSHConnectionInfo) async {
        let socketPath = controlPath(for: server)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = ["-O", "exit", "-S", socketPath, "\(server.username)@\(server.host)"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {}
        uncache(socketPath)
        try? fileManager.removeItem(atPath: socketPath)
    }
}
