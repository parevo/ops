import SwiftUI
import SwiftData

public struct ContentView: View {
    @Query private var servers: [Server]
    @Environment(AppSession.self) private var session
    @Environment(AlertMonitor.self) private var alertMonitor

    public var body: some View {
        @Bindable var session = session

        ZStack {
            VStack(spacing: 0) {
                NavigationSplitView {
                    List(selection: $session.selectedSidebar) {
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
                        Section("Workspace") {
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
                    .navigationTitle("Ops")
                } detail: {
                    NavigationStack {
                        detail(for: session.selectedSidebar)
                            .navigationTitle(session.selectedSidebar?.rawValue ?? "Ops")
                            .toolbar {
                                ToolbarItemGroup(placement: .primaryAction) {
                                    Button {
                                        session.showCommandPalette = true
                                    } label: {
                                        Label("Command Palette", systemImage: "magnifyingglass")
                                    }
                                    .keyboardShortcut("k", modifiers: [.command])

                                    if !alertMonitor.activeAlerts.isEmpty {
                                        Label("\(alertMonitor.activeAlerts.count)", systemImage: "bell.badge.fill")
                                            .foregroundStyle(BrandColor.danger)
                                            .help(alertMonitor.activeAlerts.map(\.kind.title).joined(separator: ", "))
                                    }

                                    serverMenu

                                    Button {
                                        session.openInteractiveShell()
                                    } label: {
                                        Label("Shell", systemImage: "terminal.fill")
                                    }

                                    Button {
                                        session.terminalVisible.toggle()
                                    } label: {
                                        Label("Panel", systemImage: "rectangle.bottomthird.inset.filled")
                                    }
                                    .keyboardShortcut("`", modifiers: [.control])
                                }
                            }
                    }
                }

                if session.terminalVisible && session.selectedSidebar != .terminal {
                    Divider()
                    TerminalPanel()
                        .frame(height: max(session.terminalHeight, 280))
                }
            }

            if session.showCommandPalette {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .onTapGesture { session.showCommandPalette = false }
                CommandPaletteView(isPresented: $session.showCommandPalette)
            }
        }
        .sheet(isPresented: $session.showInteractiveShell) {
            InteractiveShellSheet()
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
                    } else {
                        Text("by Parevo Co.")
                            .font(.caption2)
                            .foregroundStyle(BrandColor.textMuted)
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
            Button("Manage Servers…") { session.selectedSidebar = .servers }
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
