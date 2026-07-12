import Foundation
import SwiftUI
import SwiftData

@Observable
@MainActor
final class TerminalSession {
    var buffer = "Parevo Ops terminal — live SSH stream ready.\n"
    var input = ""
    var isRunning = false
    var cwd = "~"
    var nextHint: String?
    var statusLine = "idle"

    private var runTask: Task<Void, Never>?
    private let maxChars = 400_000

    func stop() {
        runTask?.cancel()
        runTask = nil
        isRunning = false
        statusLine = "stopped"
        append("\n^C\n")
    }

    func clear() {
        buffer = ""
    }

    func run(on info: SSHConnectionInfo, serverId: UUID?) {
        let cmd = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }
        if isRunning { stop() }

        input = ""
        append("$ \(cmd)\n")
        isRunning = true
        statusLine = "running…"

        let ssh = DependencyContainer.shared.resolve(SSHServiceProtocol.self)
        let memory = DependencyContainer.shared.resolve(MemoryServiceProtocol.self)

        runTask = Task { [weak self] in
            guard let self else { return }
            var exitCode = 0
            let started = Date()
            do {
                for try await event in ssh.streamCommand(cmd, on: info) {
                    if Task.isCancelled { break }
                    switch event {
                    case .chunk(let text):
                        self.append(text)
                    case .exit(let code):
                        exitCode = code
                    }
                }
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                if !Task.isCancelled {
                    if exitCode != 0 {
                        self.append("\n[exit \(exitCode)]\n")
                    }
                    self.statusLine = "done · \(ms)ms · exit \(exitCode)"
                }
                try? await memory.recordCommand(
                    command: cmd,
                    directory: self.cwd,
                    exitCode: exitCode,
                    isSuccess: exitCode == 0,
                    serverId: serverId,
                    projectId: nil
                )
                self.nextHint = try? await memory.getPatternNextStep(
                    currentCommand: cmd,
                    serverId: serverId,
                    projectId: nil
                )
            } catch is CancellationError {
                self.statusLine = "cancelled"
            } catch {
                self.append("\n\(error.localizedDescription)\n")
                self.statusLine = "error"
            }
            self.isRunning = false
            self.runTask = nil
        }
    }

    private func append(_ text: String) {
        buffer += text
        if buffer.count > maxChars {
            buffer.removeFirst(buffer.count - maxChars)
        }
    }
}
