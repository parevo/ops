import SwiftUI
import SwiftData

struct TerminalPanel: View {
    @Environment(AppSession.self) private var session
    @Query private var servers: [Server]
    @State private var term = TerminalSession()
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: BrandSpacing.small) {
                Label(session.server(from: servers)?.name ?? "No server", systemImage: "terminal")
                    .font(.caption.weight(.semibold))
                if term.isRunning {
                    ProgressView().controlSize(.small)
                    Text("live").font(.caption2).foregroundStyle(BrandColor.success)
                }
                Spacer()
                Text(term.statusLine)
                    .font(.caption2.monospaced())
                    .foregroundStyle(BrandColor.textSecondary)
                Button("Clear") { term.clear() }
                    .buttonStyle(.borderless)
                if term.isRunning {
                    Button("Stop") { term.stop() }
                        .buttonStyle(.bordered)
                        .tint(BrandColor.danger)
                        .keyboardShortcut(.cancelAction)
                }
                Button {
                    session.terminalVisible = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(BrandColor.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, BrandSpacing.medium)
            .padding(.vertical, BrandSpacing.small)
            .background(.bar)

            TerminalConsoleView(text: $term.buffer, isDark: colorScheme == .dark)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let hint = term.nextHint, !term.isRunning {
                HStack {
                    Image(systemName: "arrow.turn.down.right")
                    Text("Next: \(hint)").font(.caption).lineLimit(1)
                    Spacer()
                    Button("Insert") { term.input = hint }
                        .buttonStyle(.borderless)
                }
                .padding(.horizontal, BrandSpacing.medium)
                .padding(.vertical, 6)
                .background(BrandColor.surface)
            }

            HStack(spacing: BrandSpacing.small) {
                Text("$")
                    .font(.body.monospaced().weight(.semibold))
                    .foregroundStyle(BrandColor.success)
                TextField("Command — docker logs -f streams live · Esc stops", text: $term.input)
                    .textFieldStyle(.plain)
                    .font(.body.monospaced())
                    .focused($focused)
                    .disabled(session.connectionInfo(from: servers) == nil)
                    .onSubmit { submit() }
                if term.isRunning {
                    Button("Stop", action: term.stop)
                        .keyboardShortcut("c", modifiers: .control)
                }
            }
            .padding(BrandSpacing.medium)
            .background(BrandColor.surface)
        }
        .onAppear {
            focused = true
            warmSSH()
        }
        .onChange(of: session.activeServerID) { _, _ in
            warmSSH()
        }
        .requiresServer(session.connectionInfo(from: servers) != nil)
    }

    private func submit() {
        guard let info = session.connectionInfo(from: servers) else {
            term.buffer += "error: no active server\n"
            return
        }
        term.run(on: info, serverId: session.activeServerID)
        focused = true
    }

    private func warmSSH() {
        guard let info = session.connectionInfo(from: servers) else { return }
        Task {
            _ = try? await DependencyContainer.shared.resolve(SSHServiceProtocol.self).connect(server: info)
        }
    }
}

struct TerminalView: View {
    var body: some View {
        TerminalPanel()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
