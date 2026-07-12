import AppKit
import SwiftUI
import SwiftData
import SwiftTerm

/// Live SSH PTY terminal powered by SwiftTerm + local ssh process (ControlMaster aware).
struct InteractiveSSHTerminalView: NSViewRepresentable {
    let server: SSHConnectionInfo
    var initialCommand: String?

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        view.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        context.coordinator.start(view: view, server: server, initialCommand: initialCommand)
        return view
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        func start(view: LocalProcessTerminalView, server: SSHConnectionInfo, initialCommand: String?) {
            var args: [String] = [
                "-tt",
                "-o", "ControlMaster=auto",
                "-o", "ControlPersist=30m",
                "-o", "ControlPath=/tmp/parevo-ssh-\(sanitize(server.username))-\(sanitize(server.host))-\(server.port)",
                "-o", "StrictHostKeyChecking=accept-new",
                "-o", "Compression=no",
                "-p", "\(server.port)"
            ]

            if server.authMethod == .sshKey, let key = server.privateKeyPath, !key.isEmpty {
                let expanded = (key as NSString).expandingTildeInPath
                args += ["-i", expanded, "-o", "IdentitiesOnly=yes", "-o", "BatchMode=yes"]
            }

            args.append("\(server.username)@\(server.host)")

            if let cmd = initialCommand?.trimmingCharacters(in: .whitespacesAndNewlines), !cmd.isEmpty {
                // Run command inside a login shell so follow modes keep the session open until exit.
                args.append("bash -lc \(shellQuote(cmd))")
            }

            view.startProcess(executable: "/usr/bin/ssh", args: args, environment: nil, execName: "ssh")
        }

        private func sanitize(_ value: String) -> String {
            value.replacingOccurrences(of: ":", with: "_").replacingOccurrences(of: "/", with: "_")
        }

        private func shellQuote(_ value: String) -> String {
            "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
    }
}

struct InteractiveShellSheet: View {
    @Environment(AppSession.self) private var session
    @Query private var servers: [Server]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let info = session.connectionInfo(from: servers) {
                    InteractiveSSHTerminalView(server: info, initialCommand: session.interactiveShellCommand)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView(
                        "No Active Server",
                        systemImage: "terminal",
                        description: Text("Select a host before opening the interactive shell.")
                    )
                }
            }
            .navigationTitle("Interactive Shell")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        session.interactiveShellCommand = nil
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 800, minHeight: 520)
    }
}
