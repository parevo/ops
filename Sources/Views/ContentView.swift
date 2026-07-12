import SwiftUI
import SwiftData

public struct ContentView: View {
    @State private var selectedItem: SidebarItem? = .dashboard
    @Query private var servers: [Server]
    @Environment(AppSession.self) private var session
    @Environment(AlertMonitor.self) private var alertMonitor

    public var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                List(selection: $selectedItem) {
                    Section("Overview") {
                        link(.dashboard)
                        link(.metrics)
                    }
                    Section("Infrastructure") {
                        link(.servers)
                        link(.projects)
                        link(.services)
                        link(.cronJobs)
                    }
                    Section("Docker") {
                        link(.containers)
                        link(.images)
                        link(.volumes)
                        link(.networks)
                        link(.compose)
                    }
                    Section("Ops") {
                        link(.files)
                        link(.logs)
                        link(.deployments)
                        link(.terminal)
                    }
                    Section("Tools") {
                        link(.memory)
                        link(.settings)
                    }
                }
                .listStyle(.sidebar)
                .safeAreaInset(edge: .bottom) { footer }
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
                .navigationTitle("Parevo Ops")
            } detail: {
                NavigationStack {
                    detail(for: selectedItem)
                        .navigationTitle(selectedItem?.rawValue ?? "Parevo Ops")
                        .toolbar {
                            ToolbarItemGroup(placement: .primaryAction) {
                                if !alertMonitor.activeAlerts.isEmpty {
                                    Label("\(alertMonitor.activeAlerts.count)", systemImage: "bell.badge.fill")
                                        .foregroundStyle(BrandColor.danger)
                                        .help(alertMonitor.activeAlerts.map(\.kind.title).joined(separator: ", "))
                                }
                                serverMenu
                                Button {
                                    session.terminalVisible.toggle()
                                } label: {
                                    Label("Terminal", systemImage: "terminal")
                                }
                                .keyboardShortcut("`", modifiers: [.control])
                            }
                        }
                }
            }

            if session.terminalVisible && selectedItem != .terminal {
                Divider()
                TerminalPanel()
                    .frame(height: max(session.terminalHeight, 280))
            }
        }
        .onAppear {
            if session.activeServerID == nil {
                session.select(servers.first)
            }
            alertMonitor.start(session: session) { servers }
        }
        .onChange(of: servers) { _, newServers in
            if let id = session.activeServerID,
               !newServers.contains(where: { $0.id == id }) {
                session.select(newServers.first)
            } else if session.activeServerID == nil {
                session.select(newServers.first)
            }
        }
    }

    private func link(_ item: SidebarItem) -> some View {
        NavigationLink(value: item) {
            Label(item.rawValue, systemImage: item.systemImage)
        }
        .tag(item)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.tiny) {
            Divider()
            HStack(spacing: BrandSpacing.small) {
                Image(systemName: session.activeServerID != nil ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(session.activeServerID != nil ? BrandColor.success : BrandColor.warning)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.server(from: servers)?.name ?? "No Host Selected")
                        .font(.subheadline.weight(.medium))
                    if let server = session.server(from: servers) {
                        Text("\(server.username)@\(server.host)")
                            .font(.caption2)
                            .foregroundStyle(BrandColor.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, BrandSpacing.medium)
            .padding(.vertical, BrandSpacing.small)
        }
        .background(.bar)
    }

    private var serverMenu: some View {
        Menu {
            if servers.isEmpty {
                Text("No servers yet")
            } else {
                ForEach(servers) { server in
                    Button {
                        session.select(server)
                    } label: {
                        if session.activeServerID == server.id {
                            Label(server.name, systemImage: "checkmark")
                        } else {
                            Text(server.name)
                        }
                    }
                }
            }
            Divider()
            Button("Manage Servers…") { selectedItem = .servers }
        } label: {
            Label(session.server(from: servers)?.name ?? "Select Server", systemImage: "server.rack")
        }
    }

    @ViewBuilder
    private func detail(for item: SidebarItem?) -> some View {
        switch item {
        case .dashboard: DashboardView()
        case .servers: ServersView()
        case .projects: ProjectsView()
        case .containers: ContainersView()
        case .images: ImagesView()
        case .volumes: VolumesView()
        case .networks: NetworksView()
        case .compose: ComposeView()
        case .services: ServicesView()
        case .cronJobs: CronJobsView()
        case .files: FilesView()
        case .logs: LogsView()
        case .metrics: MetricsView()
        case .deployments: DeploymentsView()
        case .terminal: TerminalView()
        case .memory: MemoryView()
        case .settings: SettingsView()
        case nil:
            ContentUnavailableView("Select a Module", systemImage: "sidebar.left")
        }
    }
}
