import SwiftUI
import SwiftData
import Charts

// MARK: - Docker modules

struct ContainersView: View {
    @Environment(AppSession.self) private var session
    @Query private var servers: [Server]
    @State private var containers: [ContainerInfo] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var selected: ContainerInfo?

    var body: some View {
        Group {
            if let errorMessage { Text(errorMessage).foregroundStyle(BrandColor.danger).padding() }
            Table(containers, selection: Binding(
                get: { selected.map { Set([$0.id]) } ?? [] },
                set: { ids in selected = containers.first { ids.contains($0.id) } }
            )) {
                TableColumn("State") { StatusBadge(title: $0.state.uppercased(), tone: $0.isRunning ? .success : .danger) }.width(90)
                TableColumn("Name", value: \.name)
                TableColumn("Image", value: \.image)
                TableColumn("Ports") { Text($0.ports.isEmpty ? "—" : $0.ports).font(.caption.monospaced()) }
                TableColumn("Actions") { c in
                    HStack {
                        Button { selected = c } label: { Image(systemName: "ellipsis.circle") }.help("Quick Actions")
                        if c.isRunning {
                            Button { Task { await act(.stop, c.id) } } label: { Image(systemName: "stop.fill") }
                        } else {
                            Button { Task { await act(.start, c.id) } } label: { Image(systemName: "play.fill") }
                        }
                        Button { Task { await act(.restart, c.id) } } label: { Image(systemName: "arrow.clockwise") }
                        Button(role: .destructive) { Task { await act(.delete, c.id) } } label: { Image(systemName: "trash") }
                    }
                    .buttonStyle(.borderless)
                }.width(130)
            }
            .contextMenu(forSelectionType: ContainerInfo.ID.self) { ids in
                if let id = ids.first, let c = containers.first(where: { $0.id == id }) {
                    Button("Quick Actions…") { selected = c }
                    Button("Shell") {
                        session.openInteractiveShell(command: "docker exec -it \(String(c.id.prefix(12))) sh")
                    }
                    Button("Follow Logs") {
                        session.openInteractiveShell(command: "docker logs -f --tail 100 \(String(c.id.prefix(12)))")
                    }
                    Divider()
                    Button("Restart") { Task { await act(.restart, c.id) } }
                    Button("Delete", role: .destructive) { Task { await act(.delete, c.id) } }
                }
            } primaryAction: { ids in
                if let id = ids.first {
                    selected = containers.first(where: { $0.id == id })
                }
            }
        }
        .overlay { if isLoading { ProgressView() } }
        .requiresServer(session.connectionInfo(from: servers) != nil)
        .toolbar {
            ToolbarItem {
                Button { Task { await load() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            }
        }
        .sheet(item: $selected) { container in
            ContainerQuickActionsSheet(container: container)
                .onDisappear { Task { await load() } }
        }
        .task(id: session.activeServerID) { await load() }
    }

    private enum Action { case start, stop, restart, delete }

    @MainActor
    private func load() async {
        guard let info = session.connectionInfo(from: servers) else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            containers = try await DependencyContainer.shared.resolve(DockerServiceProtocol.self).fetchContainers(for: info)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            containers = []
        }
    }

    private func act(_ action: Action, _ id: String) async {
        guard let info = session.connectionInfo(from: servers) else { return }
        let docker = DependencyContainer.shared.resolve(DockerServiceProtocol.self)
        do {
            switch action {
            case .start: try await docker.startContainer(id: id, on: info)
            case .stop: try await docker.stopContainer(id: id, on: info)
            case .restart: try await docker.restartContainer(id: id, on: info)
            case .delete: try await docker.deleteContainer(id: id, on: info)
            }
            await load()
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }
}

struct ImagesView: View {
    @Environment(AppSession.self) private var session
    @Query private var servers: [Server]
    @State private var items: [DockerImageInfo] = []
    @State private var errorMessage: String?

    var body: some View {
        Table(items) {
            TableColumn("Repository") { Text($0.displayName) }
            TableColumn("ID") { Text($0.id).font(.caption.monospaced()) }.width(100)
            TableColumn("Size", value: \.size).width(100)
        }
        .overlay { if let errorMessage { Text(errorMessage).foregroundStyle(BrandColor.danger) } }
        .requiresServer(session.connectionInfo(from: servers) != nil)
        .task(id: session.activeServerID) {
            guard let info = session.connectionInfo(from: servers) else { return }
            do { items = try await DependencyContainer.shared.resolve(DockerServiceProtocol.self).fetchImages(for: info); errorMessage = nil }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

struct VolumesView: View {
    @Environment(AppSession.self) private var session
    @Query private var servers: [Server]
    @State private var items: [DockerVolumeInfo] = []
    @State private var errorMessage: String?

    var body: some View {
        Table(items) {
            TableColumn("Name", value: \.name)
            TableColumn("Driver", value: \.driver).width(100)
            TableColumn("Mountpoint") { Text($0.mountpoint).font(.caption.monospaced()) }
        }
        .overlay { if let errorMessage { Text(errorMessage).foregroundStyle(BrandColor.danger) } }
        .requiresServer(session.connectionInfo(from: servers) != nil)
        .task(id: session.activeServerID) {
            guard let info = session.connectionInfo(from: servers) else { return }
            do { items = try await DependencyContainer.shared.resolve(DockerServiceProtocol.self).fetchVolumes(for: info); errorMessage = nil }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

struct NetworksView: View {
    @Environment(AppSession.self) private var session
    @Query private var servers: [Server]
    @State private var items: [DockerNetworkInfo] = []
    @State private var errorMessage: String?

    var body: some View {
        Table(items) {
            TableColumn("Name", value: \.name)
            TableColumn("Driver", value: \.driver).width(100)
            TableColumn("Scope", value: \.scope).width(80)
            TableColumn("ID") { Text($0.id).font(.caption.monospaced()) }.width(100)
        }
        .overlay { if let errorMessage { Text(errorMessage).foregroundStyle(BrandColor.danger) } }
        .requiresServer(session.connectionInfo(from: servers) != nil)
        .task(id: session.activeServerID) {
            guard let info = session.connectionInfo(from: servers) else { return }
            do { items = try await DependencyContainer.shared.resolve(DockerServiceProtocol.self).fetchNetworks(for: info); errorMessage = nil }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

struct ComposeView: View {
    @Environment(AppSession.self) private var session
    @Query private var servers: [Server]
    @State private var items: [ComposeProjectInfo] = []
    @State private var errorMessage: String?

    var body: some View {
        Table(items) {
            TableColumn("Name", value: \.name)
            TableColumn("Status", value: \.status)
            TableColumn("Config", value: \.configFiles)
            TableColumn("Actions") { item in
                HStack {
                    Button("Up") { Task { await up(item.name) } }
                    Button("Down", role: .destructive) { Task { await down(item.name) } }
                }
                .buttonStyle(.borderless)
            }.width(120)
        }
        .overlay { if let errorMessage { Text(errorMessage).foregroundStyle(BrandColor.danger) } }
        .requiresServer(session.connectionInfo(from: servers) != nil)
        .toolbar { ToolbarItem { Button("Refresh") { Task { await load() } } } }
        .task(id: session.activeServerID) { await load() }
    }

    @MainActor
    private func load() async {
        guard let info = session.connectionInfo(from: servers) else { return }
        do { items = try await DependencyContainer.shared.resolve(DockerServiceProtocol.self).fetchComposeProjects(for: info); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }

    private func up(_ name: String) async {
        guard let info = session.connectionInfo(from: servers) else { return }
        do { try await DependencyContainer.shared.resolve(DockerServiceProtocol.self).composeUp(project: name, on: info); await load() }
        catch { await MainActor.run { errorMessage = error.localizedDescription } }
    }

    private func down(_ name: String) async {
        guard let info = session.connectionInfo(from: servers) else { return }
        do { try await DependencyContainer.shared.resolve(DockerServiceProtocol.self).composeDown(project: name, on: info); await load() }
        catch { await MainActor.run { errorMessage = error.localizedDescription } }
    }
}

// MARK: - Services / Cron / Files / Logs / Metrics / Deploy / Memory / Settings

struct ServicesView: View {
    @Environment(AppSession.self) private var session
    @Query private var servers: [Server]
    @State private var items: [SystemdServiceInfo] = []
    @State private var errorMessage: String?

    var body: some View {
        Table(items) {
            TableColumn("Unit", value: \.unit)
            TableColumn("Load", value: \.load).width(70)
            TableColumn("Active") { StatusBadge(title: $0.active, tone: $0.isRunning ? .success : .neutral) }.width(90)
            TableColumn("Sub", value: \.sub).width(90)
            TableColumn("Description", value: \.description)
            TableColumn("Actions") { s in
                HStack {
                    Button { Task { await run(.restart, s.unit) } } label: { Image(systemName: "arrow.clockwise") }
                    Button { Task { await run(.stop, s.unit) } } label: { Image(systemName: "stop.fill") }
                    Button { Task { await run(.start, s.unit) } } label: { Image(systemName: "play.fill") }
                }.buttonStyle(.borderless)
            }.width(100)
        }
        .overlay { if let errorMessage { Text(errorMessage).foregroundStyle(BrandColor.danger) } }
        .requiresServer(session.connectionInfo(from: servers) != nil)
        .task(id: session.activeServerID) {
            guard let info = session.connectionInfo(from: servers) else { return }
            do { items = try await DependencyContainer.shared.resolve(SystemdServiceProtocol.self).fetchServices(for: info); errorMessage = nil }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private enum Act { case restart, stop, start }
    private func run(_ act: Act, _ unit: String) async {
        guard let info = session.connectionInfo(from: servers) else { return }
        let svc = DependencyContainer.shared.resolve(SystemdServiceProtocol.self)
        do {
            switch act {
            case .restart: try await svc.restart(unit: unit, on: info)
            case .stop: try await svc.stop(unit: unit, on: info)
            case .start: try await svc.start(unit: unit, on: info)
            }
            items = try await svc.fetchServices(for: info)
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }
}

struct CronJobsView: View {
    @Environment(AppSession.self) private var session
    @Query private var servers: [Server]
    @State private var jobs: [CronJobInfo] = []
    @State private var errorMessage: String?

    var body: some View {
        Table(jobs) {
            TableColumn("Command") { Text($0.command).font(.body.monospaced()) }
            TableColumn("Schedule", value: \.schedule)
            TableColumn("Source") { StatusBadge(title: $0.source, tone: .neutral) }.width(120)
            TableColumn("Run") { job in
                Button("Run Now") {
                    Task {
                        guard let info = session.connectionInfo(from: servers) else { return }
                        do { try await DependencyContainer.shared.resolve(CronServiceProtocol.self).runCronJob(id: job.id, on: info) }
                        catch { await MainActor.run { errorMessage = error.localizedDescription } }
                    }
                }
            }.width(90)
        }
        .overlay { if let errorMessage { Text(errorMessage).foregroundStyle(BrandColor.danger) } }
        .requiresServer(session.connectionInfo(from: servers) != nil)
        .task(id: session.activeServerID) {
            guard let info = session.connectionInfo(from: servers) else { return }
            do { jobs = try await DependencyContainer.shared.resolve(CronServiceProtocol.self).fetchCronJobs(for: info); errorMessage = nil }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

struct FilesView: View {
    @Environment(AppSession.self) private var session
    @Query private var servers: [Server]
    @State private var files: [FileInfo] = []
    @State private var currentPath = "/"
    @State private var preview = ""
    @State private var errorMessage: String?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Button("Up") { goUp() }.disabled(currentPath == "/")
                    TextField("Path", text: $currentPath).textFieldStyle(.roundedBorder).font(.body.monospaced()).onSubmit { Task { await load() } }
                    Button("Go") { Task { await load() } }
                }
                .padding(BrandSpacing.medium)
                Divider()
                List(files) { file in
                    HStack {
                        Image(systemName: file.isDirectory ? "folder.fill" : "doc")
                            .foregroundStyle(file.isDirectory ? BrandColor.accent : BrandColor.textSecondary)
                        Text(file.name)
                        Spacer()
                        Text(file.permissions).font(.caption.monospaced()).foregroundStyle(BrandColor.textSecondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if file.isDirectory {
                            currentPath = file.path
                            Task { await load() }
                        } else {
                            Task { await open(file.path) }
                        }
                    }
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            Task {
                                guard let info = session.connectionInfo(from: servers) else { return }
                                try? await DependencyContainer.shared.resolve(FileServiceProtocol.self).deletePath(file.path, on: info)
                                await load()
                            }
                        }
                    }
                }
            }
            TextEditor(text: .constant(preview))
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 280)
        }
        .overlay(alignment: .top) {
            if let errorMessage { Text(errorMessage).foregroundStyle(BrandColor.danger).padding(8) }
        }
        .requiresServer(session.connectionInfo(from: servers) != nil)
        .task(id: session.activeServerID) { await load() }
    }

    @MainActor
    private func load() async {
        guard let info = session.connectionInfo(from: servers) else { return }
        do {
            files = try await DependencyContainer.shared.resolve(FileServiceProtocol.self).listFiles(path: currentPath, on: info)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func open(_ path: String) async {
        guard let info = session.connectionInfo(from: servers) else { return }
        do { preview = try await DependencyContainer.shared.resolve(FileServiceProtocol.self).readFile(path: path, on: info) }
        catch { errorMessage = error.localizedDescription }
    }

    private func goUp() {
        guard currentPath != "/" else { return }
        let parts = currentPath.split(separator: "/")
        currentPath = parts.count <= 1 ? "/" : "/" + parts.dropLast().joined(separator: "/")
        Task { await load() }
    }
}

struct LogsView: View {
    @Environment(AppSession.self) private var session
    @Query private var servers: [Server]
    @State private var source = "journal"
    @State private var lines: [String] = []
    @State private var filter = ""
    @State private var errorMessage: String?
    @State private var streaming = false

    var filtered: [String] {
        filter.isEmpty ? lines : lines.filter { $0.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Source", selection: $source) {
                    Text("Journal").tag("journal")
                    Text("Nginx").tag("unit:nginx")
                    Text("Docker daemon").tag("unit:docker")
                }
                .frame(maxWidth: 220)
                TextField("Filter", text: $filter).textFieldStyle(.roundedBorder)
                Button("Reload") { Task { await load() } }
                Button(streaming ? "Streaming…" : "Stream") { startStream() }.disabled(streaming)
            }
            .padding(BrandSpacing.medium)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(filtered.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(BrandColor.consoleText)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(idx)
                        }
                    }
                    .padding(BrandSpacing.medium)
                }
                .background(BrandColor.consoleBackground)
                .onChange(of: filtered.count) { _, _ in
                    if let last = filtered.indices.last { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(BrandColor.danger).padding(8) }
        }
        .requiresServer(session.connectionInfo(from: servers) != nil)
        .task(id: "\(session.activeServerID?.uuidString ?? "")-\(source)") { await load() }
    }

    @MainActor
    private func load() async {
        guard let info = session.connectionInfo(from: servers) else { return }
        do {
            lines = try await DependencyContainer.shared.resolve(LogServiceProtocol.self).fetchStaticLogs(source: source, on: info)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startStream() {
        guard let info = session.connectionInfo(from: servers) else { return }
        streaming = true
        Task {
            do {
                for try await line in DependencyContainer.shared.resolve(LogServiceProtocol.self).streamLogs(source: source, on: info) {
                    await MainActor.run {
                        lines.append(line)
                        if lines.count > 500 { lines.removeFirst(lines.count - 500) }
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    streaming = false
                }
            }
        }
    }
}

struct DeploymentsView: View {
    @Environment(AppSession.self) private var session
    @Query private var servers: [Server]
    @Query private var projects: [Project]
    @State private var selectedProjectID: UUID?
    @State private var events: [DeploymentEvent] = []
    @State private var log = ""
    @State private var errorMessage: String?

    private var selectedProject: Project? {
        projects.first { $0.id == selectedProjectID }
    }

    var body: some View {
        HSplitView {
            List(selection: $selectedProjectID) {
                ForEach(projects) { project in
                    Text(project.name).tag(project.id as UUID?)
                }
            }
            .frame(minWidth: 200)
            VStack(alignment: .leading, spacing: BrandSpacing.medium) {
                if let project = selectedProject {
                    HStack {
                        Button("Deploy Now") { Task { await deploy(project) } }.buttonStyle(.borderedProminent)
                        Button("Refresh Timeline") { Task { await loadEvents(project) } }
                    }
                    if let errorMessage { Text(errorMessage).foregroundStyle(BrandColor.danger) }
                    if !log.isEmpty {
                        Text(log).font(.caption.monospaced()).textSelection(.enabled)
                    }
                    List(events) { event in
                        VStack(alignment: .leading) {
                            Text(event.title).font(.headline)
                            Text(event.detail).font(.caption.monospaced()).foregroundStyle(BrandColor.textSecondary)
                            Text(event.timestamp.formatted()).font(.caption2).foregroundStyle(BrandColor.textMuted)
                        }
                    }
                } else {
                    ContentUnavailableView("Select a Project", systemImage: "arrow.up.circle")
                }
            }
            .padding()
        }
        .requiresServer(session.connectionInfo(from: servers) != nil)
        .onChange(of: selectedProjectID) { _, id in
            if let project = projects.first(where: { $0.id == id }) {
                Task { await loadEvents(project) }
            }
        }
    }

    @MainActor
    private func deploy(_ project: Project) async {
        guard let info = session.connectionInfo(from: servers) else { return }
        do {
            log = try await DependencyContainer.shared.resolve(DeployServiceProtocol.self).deploy(directory: project.directoryPath, on: info)
            await loadEvents(project)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadEvents(_ project: Project) async {
        guard let info = session.connectionInfo(from: servers) else { return }
        do {
            events = try await DependencyContainer.shared.resolve(DeployServiceProtocol.self).recentEvents(directory: project.directoryPath, on: info)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct MemoryView: View {
    @Environment(AppSession.self) private var session
    @Query private var servers: [Server]
    @State private var query = ""
    @State private var suggestions: [String] = []
    @State private var nextStep: String?

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.large) {
            TextField("Partial command", text: $query, prompt: Text("dock, git, systemctl…"))
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .onChange(of: query) { _, value in Task { await load(value) } }
            GroupBox("Suggestions") {
                if suggestions.isEmpty {
                    Text("No history matches yet. Commands you run are learned locally in SQLite.")
                        .foregroundStyle(BrandColor.textMuted)
                } else {
                    ForEach(suggestions, id: \.self) { s in
                        Label(s, systemImage: "sparkles").font(.body.monospaced())
                    }
                }
            }
            if let nextStep {
                GroupBox("Pattern Next Step") {
                    Text(nextStep).font(.body.monospaced())
                }
            }
            Spacer()
        }
        .padding(BrandSpacing.large)
    }

    @MainActor
    private func load(_ value: String) async {
        let memory = DependencyContainer.shared.resolve(MemoryServiceProtocol.self)
        let serverId = session.activeServerID
        suggestions = (try? await memory.getSmartSuggestions(input: value, serverId: serverId, projectId: nil)) ?? []
        nextStep = try? await memory.getPatternNextStep(currentCommand: value, serverId: serverId, projectId: nil)
    }
}

struct SettingsView: View {
    @AppStorage("parevo.autoRefresh") private var autoRefresh = true
    @AppStorage("parevo.refreshInterval") private var refreshInterval = 15.0
    @Environment(AlertMonitor.self) private var alerts

    var body: some View {
        Form {
            Section("General") {
                Toggle("Auto-refresh metrics", isOn: $autoRefresh)
                if autoRefresh {
                    LabeledContent("Interval") {
                        HStack {
                            Slider(value: $refreshInterval, in: 5...60, step: 5)
                            Text("\(Int(refreshInterval))s").monospacedDigit().frame(width: 36, alignment: .trailing)
                        }
                    }
                }
            }
            Section("Alerts & Notifications") {
                Toggle("Enable alert monitor", isOn: Binding(
                    get: { alerts.isEnabled },
                    set: { alerts.isEnabled = $0 }
                ))
                LabeledContent("CPU ≥") {
                    Slider(value: Binding(
                        get: { alerts.thresholds.cpu },
                        set: { alerts.thresholds.cpu = $0 }
                    ), in: 50...99, step: 1)
                    Text("\(Int(alerts.thresholds.cpu))%").monospacedDigit().frame(width: 40)
                }
                LabeledContent("RAM ≥") {
                    Slider(value: Binding(
                        get: { alerts.thresholds.ram },
                        set: { alerts.thresholds.ram = $0 }
                    ), in: 50...99, step: 1)
                    Text("\(Int(alerts.thresholds.ram))%").monospacedDigit().frame(width: 40)
                }
                LabeledContent("Disk ≥") {
                    Slider(value: Binding(
                        get: { alerts.thresholds.disk },
                        set: { alerts.thresholds.disk = $0 }
                    ), in: 50...99, step: 1)
                    Text("\(Int(alerts.thresholds.disk))%").monospacedDigit().frame(width: 40)
                }
                Text("macOS notifications fire on threshold breach (5 min cooldown per type).")
                    .foregroundStyle(BrandColor.textSecondary)
            }
            Section("Security") {
                Text("SSH passwords are stored in the macOS Keychain. Private keys stay as local file paths you select.")
                    .foregroundStyle(BrandColor.textSecondary)
            }
            Section("About") {
                HStack(spacing: BrandSpacing.medium) {
                    Image("BrandLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ops").font(.headline)
                        Text("Native DevOps workspace for macOS")
                            .font(.caption)
                            .foregroundStyle(BrandColor.textSecondary)
                        Text("by Parevo Co.")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(BrandColor.textMuted)
                    }
                }
                LabeledContent("Version", value: "1.0")
                LabeledContent("Developer", value: "Parevo Co.")
            }
        }
        .formStyle(.grouped)
        .padding(BrandSpacing.large)
        .frame(maxWidth: 640, alignment: .leading)
    }
}
