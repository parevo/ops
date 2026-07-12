import SwiftUI
import Charts
import SwiftData

struct MetricSample: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let cpu: Double
    let ram: Double
    let disk: Double
    let swap: Double
    let load1: Double
    let health: Int
}

struct MetricsView: View {
    @Environment(AppSession.self) private var session
    @Environment(AlertMonitor.self) private var alerts
    @Query private var servers: [Server]
    @State private var metrics = SystemMetrics()
    @State private var history: [MetricSample] = []
    @State private var errorMessage: String?
    @State private var selectedRange: RangeOption = .live

    private enum RangeOption: String, CaseIterable, Identifiable {
        case live = "Live"
        case m5 = "5m"
        case m15 = "15m"
        var id: String { rawValue }
        var maxPoints: Int {
            switch self {
            case .live: return 90
            case .m5: return 60
            case .m15: return 180
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.large) {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(BrandColor.danger)
                }

                HStack {
                    Picker("Range", selection: $selectedRange) {
                        ForEach(RangeOption.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 280)
                    Spacer()
                    if let last = alerts.lastChecked {
                        Text("Alerts checked \(last.formatted(date: .omitted, time: .standard))")
                            .font(.caption)
                            .foregroundStyle(BrandColor.textSecondary)
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: BrandSpacing.medium)], spacing: BrandSpacing.medium) {
                    gauge("CPU", metrics.cpuUsage, BrandColor.info)
                    gauge("RAM", metrics.ramUsage, BrandColor.accent)
                    gauge("Disk", metrics.diskUsage, BrandColor.success)
                    gauge("Swap", metrics.swapUsage, BrandColor.warning)
                    gauge("Health", Double(metrics.healthScore), metrics.healthScore > 80 ? BrandColor.success : BrandColor.danger, total: 100, suffix: "")
                    SurfaceCard(padding: BrandSpacing.medium) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Load").font(.caption).foregroundStyle(BrandColor.textSecondary)
                            Text(String(format: "%.2f", metrics.loadAverage1Min))
                                .font(.title2.monospacedDigit().weight(.semibold))
                            Text(String(format: "%.2f / %.2f", metrics.loadAverage5Min, metrics.loadAverage15Min))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(BrandColor.textMuted)
                        }
                    }
                }

                if !alerts.activeAlerts.isEmpty {
                    GroupBox("Active Alerts") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(alerts.activeAlerts) { alert in
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(BrandColor.danger)
                                    VStack(alignment: .leading) {
                                        Text(alert.kind.title).font(.headline)
                                        Text(alert.message).font(.caption).foregroundStyle(BrandColor.textSecondary)
                                    }
                                    Spacer()
                                    Text(String(format: "%.0f%%", alert.value))
                                        .font(.caption.monospacedDigit())
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }

                GroupBox("CPU · RAM · Disk") {
                    Chart {
                        ForEach(history) { s in
                            LineMark(x: .value("t", s.date), y: .value("%", s.cpu))
                                .foregroundStyle(by: .value("m", "CPU"))
                                .interpolationMethod(.catmullRom)
                            LineMark(x: .value("t", s.date), y: .value("%", s.ram))
                                .foregroundStyle(by: .value("m", "RAM"))
                                .interpolationMethod(.catmullRom)
                            LineMark(x: .value("t", s.date), y: .value("%", s.disk))
                                .foregroundStyle(by: .value("m", "Disk"))
                                .interpolationMethod(.catmullRom)
                        }
                    }
                    .chartForegroundStyleScale([
                        "CPU": BrandColor.info,
                        "RAM": BrandColor.accent,
                        "Disk": BrandColor.success
                    ])
                    .chartYScale(domain: 0...100)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 6))
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: [0, 25, 50, 75, 100])
                    }
                    .chartLegend(position: .top, alignment: .leading)
                    .frame(height: 260)
                    .padding(.top, 6)
                }

                HStack(alignment: .top, spacing: BrandSpacing.large) {
                    GroupBox("Load Average") {
                        Chart(history) { s in
                            AreaMark(x: .value("t", s.date), y: .value("load", s.load1))
                                .foregroundStyle(BrandColor.warning.opacity(0.25))
                            LineMark(x: .value("t", s.date), y: .value("load", s.load1))
                                .foregroundStyle(BrandColor.warning)
                                .interpolationMethod(.catmullRom)
                        }
                        .frame(height: 160)
                    }

                    GroupBox("Health Score") {
                        Chart(history) { s in
                            LineMark(x: .value("t", s.date), y: .value("health", s.health))
                                .foregroundStyle(BrandColor.success)
                                .interpolationMethod(.catmullRom)
                            AreaMark(x: .value("t", s.date), y: .value("health", s.health))
                                .foregroundStyle(BrandColor.success.opacity(0.15))
                        }
                        .chartYScale(domain: 0...100)
                        .frame(height: 160)
                    }
                }

                GroupBox("Swap") {
                    Chart(history) { s in
                        BarMark(x: .value("t", s.date), y: .value("swap", s.swap))
                            .foregroundStyle(BrandColor.warning.opacity(0.8))
                    }
                    .chartYScale(domain: 0...100)
                    .frame(height: 120)
                }

                GroupBox("Snapshot") {
                    Form {
                        LabeledContent("Host", value: metrics.hostname)
                        LabeledContent("OS", value: metrics.osName)
                        LabeledContent("Kernel", value: metrics.kernelVersion)
                        LabeledContent("RAM", value: String(format: "%.1f / %.1f GB", metrics.ramUsed, metrics.ramTotal))
                        LabeledContent("Disk", value: String(format: "%.0f / %.0f GB", metrics.diskUsed, metrics.diskTotal))
                        LabeledContent("Containers", value: "\(metrics.runningContainersCount) up · \(metrics.stoppedContainersCount) stopped")
                        LabeledContent("Services", value: "\(metrics.systemdServicesCount)")
                    }
                    .formStyle(.grouped)
                }
            }
            .padding(BrandSpacing.large)
        }
        .requiresServer(session.connectionInfo(from: servers) != nil)
        .task(id: session.activeServerID) {
            while !Task.isCancelled {
                await sample()
                let delay: UInt64 = selectedRange == .live ? 1_500_000_000 : 3_000_000_000
                try? await Task.sleep(nanoseconds: delay)
            }
        }
    }

    private func gauge(_ title: String, _ value: Double, _ tint: Color, total: Double = 100, suffix: String = "%") -> some View {
        SurfaceCard(padding: BrandSpacing.medium) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.caption).foregroundStyle(BrandColor.textSecondary)
                Text(suffix.isEmpty ? "\(Int(value))" : String(format: "%.0f%@", value, suffix))
                    .font(.title2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(value >= 90 && !suffix.isEmpty ? BrandColor.danger : tint)
                ProgressView(value: min(max(value, 0), total), total: total)
                    .tint(value >= 90 && !suffix.isEmpty ? BrandColor.danger : tint)
            }
        }
    }

    @MainActor
    private func sample() async {
        guard let info = session.connectionInfo(from: servers) else { return }
        do {
            metrics = try await DependencyContainer.shared.resolve(MetricsServiceProtocol.self).fetchLiveMetrics(for: info)
            history.append(MetricSample(
                date: Date(),
                cpu: metrics.cpuUsage,
                ram: metrics.ramUsage,
                disk: metrics.diskUsage,
                swap: metrics.swapUsage,
                load1: metrics.loadAverage1Min,
                health: metrics.healthScore
            ))
            let maxPoints = selectedRange.maxPoints
            if history.count > maxPoints {
                history.removeFirst(history.count - maxPoints)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
