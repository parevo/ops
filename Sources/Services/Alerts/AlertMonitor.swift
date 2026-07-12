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
}

public struct OpsAlert: Identifiable, Sendable, Hashable {
    public let id: String
    public let kind: OpsAlertKind
    public let message: String
    public let value: Double
    public let threshold: Double
    public let timestamp: Date

    public init(kind: OpsAlertKind, message: String, value: Double, threshold: Double, timestamp: Date = Date()) {
        self.id = "\(kind.rawValue)-\(Int(timestamp.timeIntervalSince1970))"
        self.kind = kind
        self.message = message
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
    public private(set) var lastChecked: Date?
    public var thresholds = AlertThresholds()
    public var isEnabled = true

    private var lastFired: [OpsAlertKind: Date] = [:]
    private var task: Task<Void, Never>?

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
                guard let info = session.connectionInfo(from: list) else {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    continue
                }
                do {
                    let metrics = try await DependencyContainer.shared.resolve(MetricsServiceProtocol.self)
                        .fetchLiveMetrics(for: info)
                    await self.evaluate(metrics, host: info.name, notifications: notifications)
                } catch {
                    // Silent — avoid notification spam on SSH blips
                }
                try? await Task.sleep(nanoseconds: 8_000_000_000)
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    private func evaluate(_ metrics: SystemMetrics, host: String, notifications: NotificationServiceProtocol) async {
        lastChecked = Date()
        var fresh: [OpsAlert] = []

        func consider(_ kind: OpsAlertKind, value: Double, threshold: Double, message: String) async {
            guard value >= threshold else { return }
            let alert = OpsAlert(kind: kind, message: message, value: value, threshold: threshold)
            fresh.append(alert)
            let last = lastFired[kind] ?? .distantPast
            if Date().timeIntervalSince(last) >= thresholds.cooldownSeconds {
                lastFired[kind] = Date()
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

        activeAlerts = fresh
    }
}
