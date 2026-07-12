import SwiftUI

struct AlertsView: View {
    @Environment(AlertMonitor.self) private var alerts
    @Environment(AppSession.self) private var session
    @State private var filterServerOnly = false

    private var visibleActive: [OpsAlert] {
        filterServerOnly ? alerts.activeAlerts(for: session.activeServerID) : alerts.activeAlerts
    }

    private var visibleHistory: [OpsAlert] {
        if filterServerOnly, let id = session.activeServerID {
            return alerts.alertHistory.filter { $0.serverID == id }
        }
        return alerts.alertHistory
    }

    var body: some View {
        VStack(spacing: 0) {
            Toggle("Only active host", isOn: $filterServerOnly)
                .toggleStyle(.switch)
                .padding(.horizontal, BrandSpacing.medium)
                .padding(.vertical, BrandSpacing.small)

            if visibleActive.isEmpty && visibleHistory.isEmpty {
                ContentUnavailableView(
                    "No Alerts Yet",
                    systemImage: "bell.slash",
                    description: Text("CPU, RAM, disk, and health breaches appear here — per server.")
                )
            } else {
                List {
                    if !visibleActive.isEmpty {
                        Section("Active · \(visibleActive.count)") {
                            ForEach(visibleActive) { alert in
                                alertRow(alert, active: true)
                            }
                        }
                    }
                    if !visibleHistory.isEmpty {
                        Section("History") {
                            ForEach(visibleHistory) { alert in
                                alertRow(alert, active: false)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .onAppear { alerts.markAllRead() }
        .toolbar {
            ToolbarItemGroup {
                if let last = alerts.lastChecked {
                    Text("Checked \(last.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(BrandColor.textSecondary)
                }
                Button("Clear History") { alerts.clearHistory() }
                    .disabled(alerts.alertHistory.isEmpty)
            }
        }
    }

    private func alertRow(_ alert: OpsAlert, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.small) {
            HStack(alignment: .top, spacing: BrandSpacing.medium) {
                Image(systemName: alert.kind.systemImage)
                    .font(.title3)
                    .foregroundStyle(active ? BrandColor.danger : BrandColor.warning)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(alert.kind.title).font(.headline)
                        if active { StatusBadge(title: "LIVE", tone: .danger) }
                        Spacer()
                        Text(alert.timestamp.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(BrandColor.textMuted)
                    }
                    Text(alert.message)
                        .font(.callout)
                        .foregroundStyle(BrandColor.textSecondary)
                    if !alert.host.isEmpty {
                        Label(alert.host, systemImage: "server.rack")
                            .font(.caption2)
                            .foregroundStyle(BrandColor.textMuted)
                    }
                }
            }

            HStack(spacing: BrandSpacing.small) {
                ForEach(actions(for: alert), id: \.title) { action in
                    Button(action.title) {
                        if let serverID = alert.serverID {
                            session.activeServerID = serverID
                        }
                        action.run()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.leading, 36)
        }
        .padding(.vertical, 4)
    }

    private struct AlertAction {
        let title: String
        let run: () -> Void
    }

    private func actions(for alert: OpsAlert) -> [AlertAction] {
        let sid = alert.serverID
        switch alert.kind {
        case .cpuHigh, .ramHigh, .swapHigh:
            return [
                AlertAction(title: "htop") {
                    session.openInteractiveShell(command: "htop", title: "htop", serverID: sid)
                },
                AlertAction(title: "Metrics") { session.navigate(to: .metrics) }
            ]
        case .diskHigh:
            return [
                AlertAction(title: "df -h") {
                    session.openInteractiveShell(command: "df -h", title: "disk", serverID: sid)
                },
                AlertAction(title: "Files") { session.navigate(to: .files) }
            ]
        case .containerPressure:
            return [
                AlertAction(title: "docker ps -a") {
                    session.openInteractiveShell(command: "docker ps -a", title: "docker", serverID: sid)
                },
                AlertAction(title: "Containers") { session.navigate(to: .containers) }
            ]
        case .healthLow:
            return [
                AlertAction(title: "Dashboard") { session.navigate(to: .dashboard) },
                AlertAction(title: "Metrics") { session.navigate(to: .metrics) }
            ]
        }
    }
}
