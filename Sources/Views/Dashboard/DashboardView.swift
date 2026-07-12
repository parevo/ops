import SwiftUI
import Charts
import SwiftData

struct DashboardView: View {
    @Environment(AppSession.self) private var session
    @Query private var servers: [Server]
    @State private var metrics = SystemMetrics()
    @State private var errorMessage: String?
    @State private var isRefreshing = false

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: BrandSpacing.large)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.xLarge) {
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(BrandColor.danger)
                        .font(.callout)
                }

                LazyVGrid(columns: columns, spacing: BrandSpacing.large) {
                    tile("Health", "\(metrics.healthScore)%", metrics.hostname, metrics.healthScore > 90 ? BrandColor.success : BrandColor.warning, "heart.text.square")
                    tile("Alerts", "\(metrics.alertsCount)", metrics.alertsCount == 0 ? "All clear" : "Needs attention", metrics.alertsCount == 0 ? BrandColor.success : BrandColor.danger, "bell.badge")
                    usage("CPU", metrics.cpuUsage, String(format: "Load %.2f · %.2f · %.2f", metrics.loadAverage1Min, metrics.loadAverage5Min, metrics.loadAverage15Min), BrandColor.info)
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
                Button {
                    Task { await refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isRefreshing)
            }
        }
        .task(id: session.activeServerID) { await refresh() }
    }

    private func tile(_ title: String, _ value: String, _ detail: String, _ tint: Color, _ icon: String) -> some View {
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
    }
}
