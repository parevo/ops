import Foundation
import UserNotifications

public enum OpsAlertKind: String, Sendable, CaseIterable {
    case cpuHigh
    case ramHigh
    case diskHigh
    case swapHigh
    case healthLow
    case containerPressure

    public var title: String {
        switch self {
        case .cpuHigh: return "CPU High"
        case .ramHigh: return "Memory High"
        case .diskHigh: return "Disk Almost Full"
        case .swapHigh: return "Swap Pressure"
        case .healthLow: return "Health Degraded"
        case .containerPressure: return "Stopped Containers"
        }
    }

    public var systemImage: String {
        switch self {
        case .cpuHigh: return "cpu"
        case .ramHigh: return "memorychip"
        case .diskHigh: return "externaldrive"
        case .swapHigh: return "arrow.triangle.swap"
        case .healthLow: return "heart.slash"
        case .containerPressure: return "shippingbox"
        }
    }
}

public struct OpsAlert: Identifiable, Sendable, Hashable {
    public let id: String
    public let kind: OpsAlertKind
    public let message: String
    public let host: String
    public let serverID: UUID?
    public let value: Double
    public let threshold: Double
    public let timestamp: Date

    public init(
        kind: OpsAlertKind,
        message: String,
        host: String = "",
        serverID: UUID? = nil,
        value: Double,
        threshold: Double,
        timestamp: Date = Date()
    ) {
        self.id = "\(serverID?.uuidString ?? host)-\(kind.rawValue)-\(Int(timestamp.timeIntervalSince1970 * 1000))"
        self.kind = kind
        self.message = message
        self.host = host
        self.serverID = serverID
        self.value = value
        self.threshold = threshold
        self.timestamp = timestamp
    }
}

public protocol NotificationServiceProtocol: Sendable {
    func requestAuthorization() async -> Bool
    func post(alert: OpsAlert) async
}

public final class NotificationService: NotificationServiceProtocol, @unchecked Sendable {
    public init() {}

    public func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    public func post(alert: OpsAlert) async {
        let content = UNMutableNotificationContent()
        content.title = "Ops · \(alert.kind.title)"
        content.body = alert.message
        content.sound = .default
        content.interruptionLevel = alert.value >= 95 ? .timeSensitive : .active

        let request = UNNotificationRequest(
            identifier: alert.id,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}

public struct AlertThresholds: Sendable {
    public var cpu: Double = 85
    public var ram: Double = 90
    public var disk: Double = 90
    public var swap: Double = 50
    public var health: Int = 70
    public var cooldownSeconds: TimeInterval = 300

    public init() {}
}

@Observable
@MainActor
public final class AlertMonitor {
    public private(set) var activeAlerts: [OpsAlert] = []
    public private(set) var alertHistory: [OpsAlert] = []
    public private(set) var unreadCount: Int = 0
    public private(set) var lastChecked: Date?
    public var thresholds = AlertThresholds()
    public var isEnabled = true
    /// When true, checks every server; otherwise only the active host.
    public var monitorAllServers = true

    private var lastFired: [String: Date] = [:]
    private var task: Task<Void, Never>?
    private let historyCap = 200

    public init() {}

    public func start(session: AppSession, servers: @escaping @MainActor () -> [Server]) {
        task?.cancel()
        task = Task { [weak self] in
            let notifications = DependencyContainer.shared.resolve(NotificationServiceProtocol.self)
            _ = await notifications.requestAuthorization()

            while !Task.isCancelled {
                guard let self, self.isEnabled else {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    continue
                }
                let list = servers()
                let targets: [Server]
                if self.monitorAllServers {
                    targets = list
                } else if let active = session.server(from: list) {
                    targets = [active]
                } else {
                    targets = []
                }

                if targets.isEmpty {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    continue
                }

                var fresh: [OpsAlert] = []
                for server in targets {
                    let info = session.resolveConnection(server)
                    do {
                        let metrics = try await DependencyContainer.shared.resolve(MetricsServiceProtocol.self)
                            .fetchLiveMetrics(for: info)
                        let hostAlerts = await self.evaluate(
                            metrics,
                            host: server.name,
                            serverID: server.id,
                            notifications: notifications
                        )
                        fresh.append(contentsOf: hostAlerts)
                    } catch {
                        // Silent per-host — avoid spam
                    }
                }
                self.activeAlerts = fresh
                self.lastChecked = Date()
                try? await Task.sleep(nanoseconds: 8_000_000_000)
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    public func markAllRead() {
        unreadCount = 0
    }

    public func clearHistory() {
        alertHistory = []
        unreadCount = 0
    }

    public func activeAlerts(for serverID: UUID?) -> [OpsAlert] {
        guard let serverID else { return activeAlerts }
        return activeAlerts.filter { $0.serverID == serverID }
    }

    private func evaluate(
        _ metrics: SystemMetrics,
        host: String,
        serverID: UUID,
        notifications: NotificationServiceProtocol
    ) async -> [OpsAlert] {
        let previousKinds = Set(activeAlerts.filter { $0.serverID == serverID }.map(\.kind))
        var fresh: [OpsAlert] = []

        func consider(_ kind: OpsAlertKind, value: Double, threshold: Double, message: String) async {
            guard value >= threshold else { return }
            let alert = OpsAlert(kind: kind, message: message, host: host, serverID: serverID, value: value, threshold: threshold)
            fresh.append(alert)

            let isNew = !previousKinds.contains(kind)
            if isNew {
                appendHistory(alert)
            }

            let key = "\(serverID.uuidString)-\(kind.rawValue)"
            let last = lastFired[key] ?? .distantPast
            if Date().timeIntervalSince(last) >= thresholds.cooldownSeconds {
                lastFired[key] = Date()
                await notifications.post(alert: alert)
            }
        }

        await consider(.cpuHigh, value: metrics.cpuUsage, threshold: thresholds.cpu,
                       message: "\(host): CPU \(String(format: "%.0f", metrics.cpuUsage))% (threshold \(Int(thresholds.cpu))%)")
        await consider(.ramHigh, value: metrics.ramUsage, threshold: thresholds.ram,
                       message: "\(host): RAM \(String(format: "%.0f", metrics.ramUsage))% · \(String(format: "%.1f", metrics.ramUsed))/\(String(format: "%.1f", metrics.ramTotal)) GB")
        await consider(.diskHigh, value: metrics.diskUsage, threshold: thresholds.disk,
                       message: "\(host): Disk \(String(format: "%.0f", metrics.diskUsage))% · \(String(format: "%.0f", metrics.diskUsed))/\(String(format: "%.0f", metrics.diskTotal)) GB")
        await consider(.swapHigh, value: metrics.swapUsage, threshold: thresholds.swap,
                       message: "\(host): Swap \(String(format: "%.0f", metrics.swapUsage))%")
        if metrics.healthScore <= thresholds.health {
            await consider(.healthLow, value: Double(100 - metrics.healthScore), threshold: Double(100 - thresholds.health),
                           message: "\(host): Health score \(metrics.healthScore)/100")
        }
        if metrics.stoppedContainersCount >= 3 {
            await consider(.containerPressure, value: Double(metrics.stoppedContainersCount), threshold: 3,
                           message: "\(host): \(metrics.stoppedContainersCount) stopped containers")
        }

        return fresh
    }

    private func appendHistory(_ alert: OpsAlert) {
        alertHistory.insert(alert, at: 0)
        if alertHistory.count > historyCap {
            alertHistory = Array(alertHistory.prefix(historyCap))
        }
        unreadCount += 1
    }
}
