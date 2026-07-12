import SwiftUI
import SwiftData

struct ContainerQuickActionsSheet: View {
    let container: ContainerInfo
    @Environment(AppSession.self) private var session
    @Query private var servers: [Server]
    @Environment(\.dismiss) private var dismiss

    @State private var inspectJSON = ""
    @State private var isLoadingInspect = false
    @State private var errorMessage: String?
    @State private var tab: Tab = .actions

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
                case .actions:
                    actionsPane
                case .inspect:
                    inspectPane
                case .logs:
                    logsPane
                }
            }
            .navigationTitle(container.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .task(id: tab) {
            if tab == .inspect { await loadInspect() }
        }
    }

    private var actionsPane: some View {
        Form {
            Section("Container") {
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
                Button("Restart") {
                    Task { await mutate(.restart); dismiss() }
                }
                if container.isRunning {
                    Button("Stop", role: .destructive) {
                        Task { await mutate(.stop); dismiss() }
                    }
                } else {
                    Button("Start") {
                        Task { await mutate(.start); dismiss() }
                    }
                }
                Button("Delete", role: .destructive) {
                    Task { await mutate(.delete); dismiss() }
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
                ProgressView("Inspecting…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Text(inspectJSON.isEmpty ? "No data" : inspectJSON)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .background(BrandColor.consoleBackground)
            }
        }
    }

    private var logsPane: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.medium) {
            Text("Opens a live follow session in the interactive shell.")
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
            inspectJSON = try await DependencyContainer.shared.resolve(DockerServiceProtocol.self)
                .inspectContainer(id: container.id, on: info)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
