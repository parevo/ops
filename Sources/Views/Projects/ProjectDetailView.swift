import SwiftUI
import SwiftData

struct ProjectDetailView: View {
    let project: Project
    @Environment(AppSession.self) private var session
    @Query private var servers: [Server]
    @Environment(\.dismiss) private var dismiss

    @State private var containers: [ContainerInfo] = []
    @State private var events: [DeploymentEvent] = []
    @State private var compose: [ComposeProjectInfo] = []
    @State private var deployLog = ""
    @State private var errorMessage: String?
    @State private var isBusy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.xLarge) {
                header

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(BrandColor.danger)
                }

                HStack(spacing: BrandSpacing.medium) {
                    Button {
                        Task { await deploy() }
                    } label: {
                        Label("Deploy", systemImage: "arrow.up.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy)

                    Button {
                        session.openInteractiveShell(command: "cd \(project.directoryPath) && pwd && ls")
                    } label: {
                        Label("Shell in Dir", systemImage: "terminal")
                    }

                    Button {
                        Task { await refresh() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }

                if !deployLog.isEmpty {
                    GroupBox("Deploy Output") {
                        Text(deployLog)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                GroupBox("Services / Containers") {
                    if containers.isEmpty {
                        Text("No matching containers for this project yet.")
                            .foregroundStyle(BrandColor.textMuted)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(containers) { c in
                            HStack {
                                StatusBadge(title: c.state.uppercased(), tone: c.isRunning ? .success : .danger)
                                VStack(alignment: .leading) {
                                    Text(c.name).font(.headline)
                                    Text(c.image).font(.caption).foregroundStyle(BrandColor.textSecondary)
                                }
                                Spacer()
                                Text(c.ports).font(.caption.monospaced()).foregroundStyle(BrandColor.textMuted)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                GroupBox("Compose") {
                    if compose.isEmpty {
                        Text("No compose projects detected.")
                            .foregroundStyle(BrandColor.textMuted)
                    } else {
                        ForEach(compose) { item in
                            HStack {
                                Text(item.name).font(.headline)
                                Spacer()
                                Text(item.status).font(.caption).foregroundStyle(BrandColor.textSecondary)
                                Button("Up") { Task { await composeUp(item.name) } }
                                Button("Down", role: .destructive) { Task { await composeDown(item.name) } }
                            }
                        }
                    }
                }

                GroupBox("Timeline") {
                    if events.isEmpty {
                        Text("No git timeline yet.")
                            .foregroundStyle(BrandColor.textMuted)
                    } else {
                        ForEach(events) { event in
                            HStack(alignment: .top) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 6))
                                    .foregroundStyle(BrandColor.accent)
                                    .padding(.top, 6)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.title).font(.headline)
                                    Text(event.detail).font(.caption.monospaced()).foregroundStyle(BrandColor.textSecondary)
                                    Text(event.timestamp.formatted()).font(.caption2).foregroundStyle(BrandColor.textMuted)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .padding(BrandSpacing.large)
        }
        .navigationTitle(project.name)
        .task { await refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.small) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name).font(.title2.weight(.semibold))
                    Text(project.projectDescription)
                        .foregroundStyle(BrandColor.textSecondary)
                    Text(project.directoryPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(BrandColor.textMuted)
                }
                Spacer()
            }
            if !project.tags.isEmpty {
                HStack {
                    ForEach(project.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(BrandColor.accent.opacity(0.12), in: Capsule())
                    }
                }
            }
        }
    }

    @MainActor
    private func refresh() async {
        guard let info = session.connectionInfo(from: servers) else {
            errorMessage = OpsError.noActiveServer.localizedDescription
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let all = try await DependencyContainer.shared.resolve(DockerServiceProtocol.self).fetchContainers(for: info)
            let needle = project.name.lowercased()
            let pathNeedle = project.directoryPath.split(separator: "/").last.map(String.init)?.lowercased() ?? needle
            containers = all.filter {
                $0.name.lowercased().contains(needle)
                    || $0.name.lowercased().contains(pathNeedle)
                    || $0.image.lowercased().contains(needle)
            }
            compose = try await DependencyContainer.shared.resolve(DockerServiceProtocol.self).fetchComposeProjects(for: info)
            events = try await DependencyContainer.shared.resolve(DeployServiceProtocol.self)
                .recentEvents(directory: project.directoryPath, on: info)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func deploy() async {
        guard let info = session.connectionInfo(from: servers) else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            deployLog = try await DependencyContainer.shared.resolve(DeployServiceProtocol.self)
                .deploy(directory: project.directoryPath, on: info)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func composeUp(_ name: String) async {
        guard let info = session.connectionInfo(from: servers) else { return }
        do {
            try await DependencyContainer.shared.resolve(DockerServiceProtocol.self).composeUp(project: name, on: info)
            await refresh()
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private func composeDown(_ name: String) async {
        guard let info = session.connectionInfo(from: servers) else { return }
        do {
            try await DependencyContainer.shared.resolve(DockerServiceProtocol.self).composeDown(project: name, on: info)
            await refresh()
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }
}
