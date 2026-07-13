import SwiftUI
import Charts
import SwiftData

@MainActor
struct DashboardView: View {
    @Environment(AppSession.self) private var session
    @Environment(AlertMonitor.self) private var alertMonitor
    @Query private var servers: [Server]
    @AppStorage("parevo.autoRefresh") private var autoRefresh = true
    @AppStorage("parevo.refreshInterval") private var refreshInterval = 15.0
    @State private var metrics = SystemMetrics()
    @State private var fleet: [FleetHostMetrics] = []
    @State private var errorMessage: String?
    @State private var isRefreshing = false

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: BrandSpacing.large)]
    private let fleetColumns = [GridItem(.adaptive(minimum: 180), spacing: BrandSpacing.medium)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.xLarge) {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(BrandColor.danger).font(.callout)
                }

                if servers.count > 1 {
                    GroupBox("Fleet · all servers") {
                        LazyVGrid(columns: fleetColumns, spacing: BrandSpacing.medium) {
                            ForEach(fleet) { item in
                                fleetCard(item)
                            }
                        }
                        .padding(.top, 4)
                    }
                }

                    LazyVGrid(columns: columns, spacing: BrandSpacing.large) {
                        tile("Health", "\(metrics.healthScore)%", metrics.hostname,
                             metrics.healthScore > 90 ? BrandColor.success : BrandColor.warning, "heart.text.square") {
                            session.navigate(to: .metrics)
                        }
                        tile(
                            "Alerts",
                            "\(alertMonitor.activeAlerts(for: session.activeServerID).count)",
                            alertMonitor.activeAlerts(for: session.activeServerID).isEmpty ? "All clear" : "Needs attention",
                            alertMonitor.activeAlerts(for: session.activeServerID).isEmpty ? BrandColor.success : BrandColor.danger,
                            "bell.badge"
                        ) {
                            session.navigate(to: .alerts)
                        }
                        usage("CPU", metrics.cpuUsage, String(format: "Load %.2f", metrics.loadAverage1Min), BrandColor.info)
                        usage("Memory", metrics.ramUsage, String(format: "%.1f / %.1f GB", metrics.ramUsed, metrics.ramTotal), BrandColor.accent)
                        usage("Disk", metrics.diskUsage, String(format: "%.0f / %.0f GB", metrics.diskUsed, metrics.diskTotal), BrandColor.success)
                        usage("Swap", metrics.swapUsage, "Swap utilization", BrandColor.warning)
                    }

                    GroupBox("Environment") {
                        Form {
                            LabeledContent("Hostname", value: metrics.hostname)
                            LabeledContent("OS", value: metrics.osName)
                            LabeledContent("Kernel", value: metrics.kernelVersion)
                            LabeledContent("Docker") {
                                Text("\(metrics.runningContainersCount) running · \(metrics.stoppedContainersCount) stopped")
                            }
                            LabeledContent("Services", value: "\(metrics.systemdServicesCount) active")
                        }
                        .formStyle(.grouped)
                    }

                    GroupBox("Top Processes") {
                        Table(metrics.topProcesses) {
                            TableColumn("PID") { Text("\($0.pid)").font(.body.monospaced()) }.width(60)
                            TableColumn("Name", value: \.name)
                            TableColumn("User", value: \.user)
                            TableColumn("CPU") { Text(String(format: "%.1f%%", $0.cpu)).font(.body.monospaced()) }.width(70)
                            TableColumn("Memory") { Text(String(format: "%.0f MB", $0.memory)).font(.body.monospaced()) }.width(90)
                        }
                        .frame(minHeight: 180)
                    }
                }
                .padding(BrandSpacing.large)
            }
        .requiresServer(session.connectionInfo(from: servers) != nil)
        .toolbar {
            ToolbarItem {
                Button { Task { await refresh() } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isRefreshing)
            }
        }
        .task(id: "\(session.activeServerID?.uuidString ?? "")-\(autoRefresh)-\(Int(refreshInterval))-\(servers.count)") {
            await refresh()
            guard autoRefresh else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(max(refreshInterval, 5) * 1_000_000_000))
                await refresh()
            }
        }
    }

    private func fleetCard(_ item: FleetHostMetrics) -> some View {
        SurfaceCard(padding: BrandSpacing.medium) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(item.name).font(.headline)
                    Spacer()
                    if session.activeServerID == item.id {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(BrandColor.success)
                    }
                }
                Text(item.host).font(.caption.monospaced()).foregroundStyle(BrandColor.textMuted)
                if let m = item.metrics {
                    Text(String(format: "CPU %.0f%% · RAM %.0f%% · Health %d", m.cpuUsage, m.ramUsage, m.healthScore))
                        .font(.caption)
                } else if let error = item.error {
                    Text(error).font(.caption2).foregroundStyle(BrandColor.danger).lineLimit(2)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            session.selectServerID(item.id, from: servers)
        }
    }

    private func tile(
        _ title: String, _ value: String, _ detail: String, _ tint: Color, _ icon: String,
        action: (() -> Void)? = nil
    ) -> some View {
        SurfaceCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: BrandSpacing.small) {
                    Text(title).font(.subheadline).foregroundStyle(BrandColor.textSecondary)
                    Text(value).font(.system(size: 28, weight: .semibold, design: .rounded)).foregroundStyle(tint)
                    Text(detail).font(.caption).foregroundStyle(BrandColor.textMuted).lineLimit(1)
                }
                Spacer()
                Image(systemName: icon).font(.title2).foregroundStyle(tint).symbolRenderingMode(.hierarchical)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { action?() }
    }

    private func usage(_ title: String, _ percent: Double, _ subtitle: String, _ tint: Color) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: BrandSpacing.small) {
                Text(title).font(.subheadline).foregroundStyle(BrandColor.textSecondary)
                ProgressView(value: min(max(percent, 0), 100), total: 100).tint(tint)
                HStack {
                    Text(String(format: "%.1f%%", percent)).font(.headline)
                    Spacer()
                    Text(subtitle).font(.caption).foregroundStyle(BrandColor.textSecondary)
                }
            }
        }
    }

    @MainActor
    private func refresh() async {
        guard let info = session.connectionInfo(from: servers) else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            metrics = try await DependencyContainer.shared.resolve(MetricsServiceProtocol.self).fetchLiveMetrics(for: info)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        await refreshFleet()
    }

    @MainActor
    private func refreshFleet() async {
        let snapshot = servers
        var rows: [FleetHostMetrics] = snapshot.map {
            FleetHostMetrics(id: $0.id, name: $0.name, host: $0.host)
        }
        await withTaskGroup(of: (UUID, SystemMetrics?, String?).self) { group in
            for server in snapshot {
                let info = session.resolveConnection(server)
                group.addTask {
                    do {
                        let m = try await DependencyContainer.shared.resolve(MetricsServiceProtocol.self).fetchLiveMetrics(for: info)
                        return (server.id, m, nil)
                    } catch {
                        return (server.id, nil, error.localizedDescription)
                    }
                }
            }
            for await (id, metrics, error) in group {
                if let idx = rows.firstIndex(where: { $0.id == id }) {
                    rows[idx].metrics = metrics
                    rows[idx].error = error
                }
            }
        }
        fleet = rows
    }
}
