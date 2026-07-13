import SwiftUI
import SwiftData

@MainActor
struct ContainerQuickActionsSheet: View {
    let container: ContainerInfo
    @Environment(AppSession.self) private var session
    @Query private var servers: [Server]
    @Environment(\.dismiss) private var dismiss

    @State private var summary = ContainerInspectSummary()
    @State private var isLoadingInspect = false
    @State private var errorMessage: String?
    @State private var tab: Tab = .actions
    @State private var forwardLocalPort = ""
    @State private var tunnelMessage: String?

    private enum Tab: String, CaseIterable, Identifiable {
        case actions = "Actions"
        case inspect = "Inspect"
        case logs = "Logs"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding()

                switch tab {
                case .actions: actionsPane
                case .inspect: inspectPane
                case .logs: logsPane
                }
            }
            .navigationTitle(container.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .frame(minWidth: 720, minHeight: 520)
        .task(id: tab) {
            if tab == .inspect { await loadInspect() }
        }
    }

    private var actionsPane: some View {
        Form {
            Section("Container · \(session.server(from: servers)?.name ?? "host")") {
                LabeledContent("Name", value: container.name)
                LabeledContent("Image", value: container.image)
                LabeledContent("State") {
                    StatusBadge(title: container.state.uppercased(), tone: container.isRunning ? .success : .danger)
                }
                LabeledContent("Ports", value: container.ports.isEmpty ? "—" : container.ports)
                LabeledContent("ID") {
                    Text(String(container.id.prefix(12))).font(.body.monospaced())
                }
            }
            Section("Quick Actions") {
                Button("Open Shell (docker exec)") {
                    let short = String(container.id.prefix(12))
                    session.openInteractiveShell(command: "docker exec -it \(short) sh")
                    dismiss()
                }
                Button("Follow Logs") {
                    let short = String(container.id.prefix(12))
                    session.openInteractiveShell(command: "docker logs -f --tail 100 \(short)")
                    dismiss()
                }
                Button("Restart") { Task { await mutate(.restart); dismiss() } }
                if container.isRunning {
                    Button("Stop", role: .destructive) { Task { await mutate(.stop); dismiss() } }
                } else {
                    Button("Start") { Task { await mutate(.start); dismiss() } }
                }
                Button("Delete", role: .destructive) { Task { await mutate(.delete); dismiss() } }
            }
            Section("Port Forward") {
                TextField("Local port", text: $forwardLocalPort)
                    .textFieldStyle(.roundedBorder)
                Button("Start Tunnel") { Task { await startTunnel() } }
                    .disabled(Int(forwardLocalPort) == nil)
                if let tunnelMessage {
                    Text(tunnelMessage).font(.caption).foregroundStyle(BrandColor.textSecondary)
                }
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(BrandColor.danger) }
            }
        }
        .formStyle(.grouped)
    }

    private var inspectPane: some View {
        Group {
            if isLoadingInspect {
                ProgressView("Inspecting…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section("Runtime") {
                        LabeledContent("Image", value: summary.image.isEmpty ? "—" : summary.image)
                        LabeledContent("Cmd", value: summary.cmd.isEmpty ? "—" : summary.cmd)
                        LabeledContent("Network", value: summary.networkMode.isEmpty ? "—" : summary.networkMode)
                        LabeledContent("Restart", value: summary.restartPolicy.isEmpty ? "—" : summary.restartPolicy)
                        LabeledContent("Memory", value: summary.memoryLimit)
                        LabeledContent("CPU shares", value: summary.cpuShares)
                    }
                    if !summary.ports.isEmpty {
                        Section("Ports") {
                            ForEach(summary.ports, id: \.self) { Text($0).font(.caption.monospaced()) }
                        }
                    }
                    if !summary.mounts.isEmpty {
                        Section("Mounts") {
                            ForEach(summary.mounts, id: \.self) { Text($0).font(.caption.monospaced()) }
                        }
                    }
                    if !summary.env.isEmpty {
                        Section("Env (\(summary.env.count))") {
                            ForEach(summary.env.prefix(80), id: \.self) { Text($0).font(.caption.monospaced()) }
                        }
                    }
                    Section("Raw JSON") {
                        Text(summary.rawJSON)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private var logsPane: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.medium) {
            Text("Opens a live follow session on the active host.")
                .foregroundStyle(BrandColor.textSecondary)
            Button("Stream docker logs -f") {
                let short = String(container.id.prefix(12))
                session.openInteractiveShell(command: "docker logs -f --tail 200 \(short)")
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private enum Mut { case start, stop, restart, delete }

    private func mutate(_ action: Mut) async {
        guard let info = session.connectionInfo(from: servers) else { return }
        let docker = DependencyContainer.shared.resolve(DockerServiceProtocol.self)
        do {
            switch action {
            case .start: try await docker.startContainer(id: container.id, on: info)
            case .stop: try await docker.stopContainer(id: container.id, on: info)
            case .restart: try await docker.restartContainer(id: container.id, on: info)
            case .delete: try await docker.deleteContainer(id: container.id, on: info)
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    @MainActor
    private func loadInspect() async {
        guard let info = session.connectionInfo(from: servers) else { return }
        isLoadingInspect = true
        defer { isLoadingInspect = false }
        do {
            summary = try await DependencyContainer.shared.resolve(DockerServiceProtocol.self)
                .inspectContainerSummary(id: container.id, on: info)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func startTunnel() async {
        guard let info = session.connectionInfo(from: servers),
              let server = session.server(from: servers),
              let local = Int(forwardLocalPort) else { return }

        // Prefer first published host port from container.ports like "8080->80/tcp"
        let remotePort: Int = {
            let parts = container.ports.split(separator: ",").first.map(String.init) ?? ""
            if let arrow = parts.split(separator: "->").first, let p = Int(arrow.trimmingCharacters(in: .whitespaces)) {
                return p
            }
            return local
        }()

        let tunnel = PortTunnel(
            serverID: server.id,
            serverName: server.name,
            localPort: local,
            remoteHost: "127.0.0.1",
            remotePort: remotePort,
            label: "\(container.name):\(remotePort)"
        )
        do {
            try await DependencyContainer.shared.resolve(PortForwardServiceProtocol.self)
                .startTunnel(tunnel, on: info)
            session.addTunnel(tunnel)
            tunnelMessage = "Listening on localhost:\(local) → \(remotePort)"
        } catch {
            tunnelMessage = error.localizedDescription
        }
    }
}
