import Foundation
import SwiftUI
import SwiftData

public struct TerminalTab: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var serverID: UUID
    public var initialCommand: String?

    public init(
        id: UUID = UUID(),
        title: String,
        serverID: UUID,
        initialCommand: String? = nil
    ) {
        self.id = id
        self.title = title
        self.serverID = serverID
        self.initialCommand = initialCommand
    }
}

@Observable
@MainActor
public final class AppSession {
    public var activeServerID: UUID?
    public var terminalVisible = false
    public var terminalHeight: CGFloat = 280
    public var lastErrorMessage: String?

    public var selectedSidebar: SidebarItem? = .dashboard
    public var showCommandPalette = false
    public var selectedProjectID: UUID?

    public var terminalTabs: [TerminalTab] = []
    public var selectedTerminalTabID: UUID?
    public var splitTerminalEnabled = false
    public var splitTerminalTabID: UUID?
    public let terminalHosts = TerminalHostRegistry()

    public var activeTunnels: [PortTunnel] = []

    /// Terminal appearance (source of truth; mirrored to UserDefaults).
    public var terminalFontSize: Double {
        didSet {
            UserDefaults.standard.set(terminalFontSize, forKey: "parevo.terminal.fontSize")
            terminalHosts.refreshAppearance()
        }
    }
    public var terminalTheme: String {
        didSet {
            UserDefaults.standard.set(terminalTheme, forKey: "parevo.terminal.theme")
            terminalHosts.refreshAppearance()
        }
    }

    public init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "parevo.terminal.fontSize") != nil {
            let stored = defaults.double(forKey: "parevo.terminal.fontSize")
            terminalFontSize = stored > 0 ? stored : 13
        } else {
            terminalFontSize = 13
        }
        terminalTheme = defaults.string(forKey: "parevo.terminal.theme") ?? "system"
    }

    public func connectionInfo(from servers: [Server]) -> SSHConnectionInfo? {
        guard let id = activeServerID,
              let server = servers.first(where: { $0.id == id }) else { return nil }
        return resolveConnection(server)
    }

    public func connectionInfo(for tab: TerminalTab, from servers: [Server]) -> SSHConnectionInfo? {
        guard let server = servers.first(where: { $0.id == tab.serverID }) else { return nil }
        return resolveConnection(server)
    }

    public func connectionInfo(serverID: UUID, from servers: [Server]) -> SSHConnectionInfo? {
        guard let server = servers.first(where: { $0.id == serverID }) else { return nil }
        return resolveConnection(server)
    }

    public func server(from servers: [Server]) -> Server? {
        guard let id = activeServerID else { return nil }
        return servers.first(where: { $0.id == id })
    }

    public func select(_ server: Server?) {
        activeServerID = server?.id
    }

    public func selectServerID(_ id: UUID?, from servers: [Server]) {
        guard let id, let server = servers.first(where: { $0.id == id }) else {
            activeServerID = id
            return
        }
        select(server)
    }

    public func resolveConnection(_ server: Server) -> SSHConnectionInfo {
        var info = server.connectionInfo
        if info.authMethod == .password {
            let keychain = DependencyContainer.shared.resolve(KeychainServiceProtocol.self)
            info.passwordPlain = try? keychain.loadPassword(account: server.id.uuidString)
        }
        return info
    }

    public func requireConnection(from servers: [Server]) throws -> SSHConnectionInfo {
        guard let info = connectionInfo(from: servers) else {
            throw OpsError.noActiveServer
        }
        return info
    }

    public func projects(for serversList: [Project], scoped: Bool = true) -> [Project] {
        guard scoped, let activeServerID else { return serversList }
        return serversList.filter { $0.serverId == nil || $0.serverId == activeServerID }
    }

    public func openInteractiveShell(
        command: String? = nil,
        title: String? = nil,
        preferPanel: Bool = false,
        serverID: UUID? = nil
    ) {
        let targetID = serverID ?? activeServerID
        guard let targetID else {
            lastErrorMessage = "Select a host before opening a shell."
            return
        }

        let tab = TerminalTab(
            title: title ?? Self.makeTabTitle(command: command),
            serverID: targetID,
            initialCommand: command
        )
        terminalTabs.append(tab)
        selectedTerminalTabID = tab.id

        if preferPanel {
            terminalVisible = true
        } else {
            selectedSidebar = .terminal
            terminalVisible = false
        }
    }

    public func newTerminalTab(title: String = "Shell") {
        openInteractiveShell(command: nil, title: title)
    }

    public func toggleSplitTerminal() {
        if splitTerminalEnabled {
            splitTerminalEnabled = false
            splitTerminalTabID = nil
            return
        }
        guard let selected = selectedTerminalTabID else {
            ensureTerminalTab()
            return
        }
        // Create a sibling tab on the same server for the split pane.
        if let tab = terminalTabs.first(where: { $0.id == selected }) {
            let sibling = TerminalTab(title: "\(tab.title) · split", serverID: tab.serverID)
            terminalTabs.append(sibling)
            splitTerminalTabID = sibling.id
            splitTerminalEnabled = true
        }
    }

    public func closeTerminalTab(_ id: UUID) {
        guard let index = terminalTabs.firstIndex(where: { $0.id == id }) else { return }
        terminalTabs.remove(at: index)
        terminalHosts.dispose(id)
        if splitTerminalTabID == id {
            splitTerminalTabID = nil
            splitTerminalEnabled = false
        }
        if selectedTerminalTabID == id {
            selectedTerminalTabID = terminalTabs[safe: index]?.id
                ?? terminalTabs[safe: index - 1]?.id
                ?? terminalTabs.last?.id
        }
        if terminalTabs.isEmpty {
            terminalVisible = false
            splitTerminalEnabled = false
            splitTerminalTabID = nil
        }
    }

    public func ensureTerminalTab() {
        if terminalTabs.isEmpty {
            newTerminalTab()
        } else if selectedTerminalTabID == nil {
            selectedTerminalTabID = terminalTabs.first?.id
        }
    }

    public func navigate(to item: SidebarItem) {
        selectedSidebar = item
        showCommandPalette = false
        if item == .terminal {
            ensureTerminalTab()
        }
    }

    public func addTunnel(_ tunnel: PortTunnel) {
        activeTunnels.append(tunnel)
    }

    public func removeTunnel(_ id: UUID) {
        activeTunnels.removeAll { $0.id == id }
        Task {
            await DependencyContainer.shared.resolve(PortForwardServiceProtocol.self).stopTunnel(id: id)
        }
    }

    private static func makeTabTitle(command: String?) -> String {
        guard let command, !command.isEmpty else { return "Shell" }
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("docker exec") { return "exec" }
        if trimmed.hasPrefix("docker logs") { return "logs" }
        if trimmed.hasPrefix("journalctl") { return "journal" }
        if trimmed.hasPrefix("cd ") { return "cwd" }
        if trimmed.hasPrefix("htop") || trimmed.hasPrefix("top") { return "top" }
        let first = trimmed.split(separator: " ").first.map(String.init) ?? "Shell"
        return String(first.prefix(16))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
