import SwiftUI

public enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case dashboard = "Dashboard"
    case servers = "Servers"
    case projects = "Projects"
    case containers = "Containers"
    case images = "Images"
    case volumes = "Volumes"
    case networks = "Networks"
    case compose = "Compose"
    case services = "Services"
    case cronJobs = "Cron Jobs"
    case files = "Files"
    case logs = "Logs"
    case metrics = "Metrics"
    case deployments = "Deployments"
    case terminal = "Terminal"
    case memory = "Memory"
    case settings = "Settings"

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.33percent"
        case .servers: return "server.rack"
        case .projects: return "folder.badge.gearshape"
        case .containers: return "shippingbox"
        case .images: return "photo.stack"
        case .volumes: return "externaldrive"
        case .networks: return "network"
        case .compose: return "square.stack.3d.up"
        case .services: return "gearshape.2"
        case .cronJobs: return "timer"
        case .files: return "folder"
        case .logs: return "doc.text.magnifyingglass"
        case .metrics: return "chart.xyaxis.line"
        case .deployments: return "arrow.up.circle"
        case .terminal: return "terminal"
        case .memory: return "brain"
        case .settings: return "gearshape"
        }
    }
}

struct StatusBadge: View {
    let title: String
    let tone: Tone

    enum Tone {
        case success, danger, warning, neutral
        var color: Color {
            switch self {
            case .success: return BrandColor.success
            case .danger: return BrandColor.danger
            case .warning: return BrandColor.warning
            case .neutral: return BrandColor.textSecondary
            }
        }
    }

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(tone.color)
            .background(tone.color.opacity(0.12), in: Capsule())
    }
}

struct RequiresServerModifier: ViewModifier {
    let hasServer: Bool

    func body(content: Content) -> some View {
        if hasServer {
            content
        } else {
            ContentUnavailableView(
                "No Active Server",
                systemImage: "server.rack",
                description: Text("Choose a host from the toolbar or add one in Servers.")
            )
        }
    }
}

extension View {
    func requiresServer(_ hasServer: Bool) -> some View {
        modifier(RequiresServerModifier(hasServer: hasServer))
    }
}
