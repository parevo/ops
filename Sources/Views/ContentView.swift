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
                            alertsLink
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
                            link(.tunnels)
                        }
                        Section("Tools") {
                            link(.memory)
                            link(.settings)
                        }
                    }
                    .listStyle(.sidebar)
                    .safeAreaInset(edge: .bottom) { SidebarServerSwitcher() }
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

                                    Button {
                                        session.navigate(to: .alerts)
                                        alertMonitor.markAllRead()
                                    } label: {
                                        Label(
                                            alertMonitor.activeAlerts.isEmpty
                                                ? "Alerts"
                                                : "\(alertMonitor.activeAlerts.count)",
                                            systemImage: alertMonitor.activeAlerts.isEmpty
                                                ? "bell"
                                                : "bell.badge.fill"
                                        )
                                    }
                                    .foregroundStyle(alertMonitor.activeAlerts.isEmpty ? BrandColor.textSecondary : BrandColor.danger)
                                    .help(alertMonitor.activeAlerts.isEmpty
                                          ? "Alert Center"
                                          : alertMonitor.activeAlerts.map(\.kind.title).joined(separator: ", "))

                                    serverMenu

                                    Button {
                                        session.openInteractiveShell()
                                    } label: {
                                        Label("Shell", systemImage: "terminal.fill")
                                    }
                                    .keyboardShortcut("t", modifiers: [.command, .shift])

                                    Button {
                                        if session.terminalVisible {
                                            session.terminalVisible = false
                                        } else {
                                            session.ensureTerminalTab()
                                            session.terminalVisible = true
                                        }
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
        .alert("Shell", isPresented: Binding(
            get: { session.lastErrorMessage != nil },
            set: { if !$0 { session.lastErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { session.lastErrorMessage = nil }
        } message: {
            Text(session.lastErrorMessage ?? "")
        }
    }

    private func link(_ item: SidebarItem) -> some View {
        NavigationLink(value: item) {
            Label(item.rawValue, systemImage: item.systemImage)
        }
        .tag(item)
    }

    private var alertsLink: some View {
        NavigationLink(value: SidebarItem.alerts) {
            HStack {
                Label("Alerts", systemImage: SidebarItem.alerts.systemImage)
                Spacer()
                if alertMonitor.unreadCount > 0 {
                    Text("\(alertMonitor.unreadCount)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(BrandColor.danger, in: Capsule())
                } else if !alertMonitor.activeAlerts.isEmpty {
                    Text("\(alertMonitor.activeAlerts.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(BrandColor.danger)
                }
            }
        }
        .tag(SidebarItem.alerts)
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
        case .alerts: AlertsView()
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
        case .tunnels: TunnelsView()
        case .memory: MemoryView()
        case .settings: SettingsView()
        case nil:
            ContentUnavailableView("Select a Module", systemImage: "sidebar.left")
        }
    }
}
