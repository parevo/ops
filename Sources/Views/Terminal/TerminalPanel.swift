import SwiftUI
import SwiftData

/// Shared SwiftTerm workspace with tabs + optional split — used as full Terminal page and bottom panel.
struct TerminalWorkspace: View {
    var compact: Bool = false

    @Environment(AppSession.self) private var session
    @Query private var servers: [Server]

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            terminalBody
        }
        .onAppear { session.ensureTerminalTab() }
        .requiresServer(session.activeServerID != nil)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(session.terminalTabs) { tab in
                        TerminalTabChip(
                            title: tabTitle(tab),
                            isSelected: session.selectedTerminalTabID == tab.id,
                            onSelect: { session.selectedTerminalTabID = tab.id },
                            onClose: { session.closeTerminalTab(tab.id) }
                        )
                    }
                }
                .padding(.horizontal, BrandSpacing.small)
            }

            Button {
                session.toggleSplitTerminal()
            } label: {
                Image(systemName: session.splitTerminalEnabled ? "rectangle.split.2x1.fill" : "rectangle.split.2x1")
            }
            .buttonStyle(.borderless)
            .help("Split Terminal")
            .padding(.trailing, BrandSpacing.tiny)

            Button {
                session.newTerminalTab()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("New Tab (⌘T)")
            .padding(.trailing, BrandSpacing.tiny)

            if compact {
                Button {
                    session.terminalVisible = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(BrandColor.textMuted)
                }
                .buttonStyle(.plain)
                .help("Close panel")
                .padding(.trailing, BrandSpacing.small)
            }
        }
        .frame(height: compact ? 32 : 36)
        .background(.bar)
    }

    @ViewBuilder
    private var terminalBody: some View {
        if session.terminalTabs.isEmpty {
            ContentUnavailableView(
                "No Terminal Tabs",
                systemImage: "terminal",
                description: Text("Press ⌘T or the + button to open a shell.")
            )
        } else if session.splitTerminalEnabled,
                  let leftID = session.selectedTerminalTabID,
                  let rightID = session.splitTerminalTabID,
                  session.terminalTabs.contains(where: { $0.id == leftID }),
                  session.terminalTabs.contains(where: { $0.id == rightID }) {
            HSplitView {
                pane(for: leftID)
                pane(for: rightID)
            }
        } else if let selected = session.selectedTerminalTabID,
                  session.terminalTabs.contains(where: { $0.id == selected }) {
            pane(for: selected)
        } else {
            ContentUnavailableView(
                "Host Unavailable",
                systemImage: "server.rack",
                description: Text("The server for this tab is missing.")
            )
        }
    }

    @ViewBuilder
    private func pane(for tabID: UUID) -> some View {
        if let tab = session.terminalTabs.first(where: { $0.id == tabID }),
           let info = session.connectionInfo(for: tab, from: servers) {
            InteractiveSSHTerminalView(
                tabID: tab.id,
                server: info,
                initialCommand: tab.initialCommand,
                registry: session.terminalHosts
            )
            .id(tab.id)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView("Unavailable", systemImage: "terminal")
        }
    }

    private func tabTitle(_ tab: TerminalTab) -> String {
        let host = servers.first(where: { $0.id == tab.serverID })?.name
        if let host, host != tab.title {
            return "\(tab.title) · \(host)"
        }
        return tab.title
    }
}

private struct TerminalTabChip: View {
    let title: String
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onSelect) {
                Text(title)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .buttonStyle(.plain)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(BrandColor.textMuted)
            }
            .buttonStyle(.plain)
            .help("Close Tab")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            isSelected ? BrandColor.surface : Color.clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(isSelected ? BrandColor.border : Color.clear, lineWidth: 1)
        )
    }
}

struct TerminalPanel: View {
    var body: some View {
        TerminalWorkspace(compact: true)
    }
}

struct TerminalView: View {
    var body: some View {
        TerminalWorkspace(compact: false)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
