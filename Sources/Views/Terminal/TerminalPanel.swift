import SwiftUI
import SwiftData

struct TerminalPanel: View {
    @Environment(AppSession.self) private var session
    @Query private var servers: [Server]
    @State private var input = ""
    @State private var history: [String] = []
    @State private var cwd = "~"
    @FocusState private var focused: Bool
    @State private var nextHint: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(session.server(from: servers)?.name ?? "No server", systemImage: "terminal")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(cwd).font(.caption.monospaced()).foregroundStyle(BrandColor.textSecondary)
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

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(history.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(BrandColor.consoleText)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(idx)
                        }
                    }
                    .padding(BrandSpacing.medium)
                }
                .background(BrandColor.consoleBackground)
                .onChange(of: history.count) { _, _ in
                    if let last = history.indices.last { proxy.scrollTo(last, anchor: .bottom) }
                }
            }

            if let nextHint {
                HStack {
                    Image(systemName: "arrow.turn.down.right")
                    Text("Next step usually: \(nextHint)")
                        .font(.caption)
                    Spacer()
                    Button("Insert") { input = nextHint ?? input }
                        .buttonStyle(.borderless)
                }
                .padding(.horizontal, BrandSpacing.medium)
                .padding(.vertical, 6)
                .background(BrandColor.surface)
            }

            HStack(spacing: BrandSpacing.small) {
                Text("$").font(.body.monospaced().weight(.semibold)).foregroundStyle(BrandColor.success)
                TextField("Command", text: $input)
                    .textFieldStyle(.plain)
                    .font(.body.monospaced())
                    .focused($focused)
                    .onSubmit { Task { await run() } }
            }
            .padding(BrandSpacing.medium)
            .background(BrandColor.surface)
        }
        .onAppear { focused = true }
        .requiresServer(session.connectionInfo(from: servers) != nil)
    }

    @MainActor
    private func run() async {
        let cmd = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }
        guard let info = session.connectionInfo(from: servers) else {
            history.append("error: no active server")
            return
        }
        history.append("$ \(cmd)")
        input = ""
        do {
            let res = try await DependencyContainer.shared.resolve(SSHServiceProtocol.self).executeCommand(cmd, on: info)
            history.append(res.output.isEmpty ? "(exit \(res.exitCode))" : res.output)
            try? await DependencyContainer.shared.resolve(MemoryServiceProtocol.self).recordCommand(
                command: cmd,
                directory: cwd,
                exitCode: res.exitCode,
                isSuccess: res.exitCode == 0,
                serverId: session.activeServerID,
                projectId: nil
            )
            nextHint = try? await DependencyContainer.shared.resolve(MemoryServiceProtocol.self)
                .getPatternNextStep(currentCommand: cmd, serverId: session.activeServerID, projectId: nil)
        } catch {
            history.append(error.localizedDescription)
        }
    }
}

/// Full-page terminal (sidebar destination) reuses the panel chrome.
struct TerminalView: View {
    var body: some View {
        TerminalPanel()
    }
}
