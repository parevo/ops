import SwiftUI
import SwiftData

struct CommandPaletteItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let action: Action

    enum Action: Hashable {
        case navigate(SidebarItem)
        case selectServer(UUID)
        case openShell
        case openShellCommand(String)
        case openProject(UUID)
    }
}

@MainActor
struct CommandPaletteView: View {
    @Environment(AppSession.self) private var session
    @Query private var servers: [Server]
    @Query private var projects: [Project]
    @Binding var isPresented: Bool
    @State private var query = ""
    @FocusState private var focused: Bool

    private var items: [CommandPaletteItem] {
        var result: [CommandPaletteItem] = []

        for item in SidebarItem.allCases {
            result.append(.init(
                id: "nav-\(item.id)",
                title: item.rawValue,
                subtitle: "Go to \(item.rawValue)",
                systemImage: item.systemImage,
                action: .navigate(item)
            ))
        }

        result.append(.init(
            id: "shell",
            title: "Interactive Shell",
            subtitle: "Open live SSH PTY session",
            systemImage: "terminal.fill",
            action: .openShell
        ))

        for server in servers {
            result.append(.init(
                id: "server-\(server.id)",
                title: server.name,
                subtitle: "\(server.username)@\(server.host)",
                systemImage: "server.rack",
                action: .selectServer(server.id)
            ))
        }

        for project in projects {
            result.append(.init(
                id: "project-\(project.id)",
                title: project.name,
                subtitle: project.directoryPath,
                systemImage: "folder.fill",
                action: .openProject(project.id)
            ))
        }

        let quick: [(String, String, String)] = [
            ("docker ps", "List containers", "shippingbox"),
            ("docker compose ps", "Compose status", "square.stack.3d.up"),
            ("htop", "Process monitor", "gauge.with.dots.needle.33percent"),
            ("journalctl -f", "Follow system logs", "doc.text.magnifyingglass")
        ]
        for (cmd, subtitle, icon) in quick {
            result.append(.init(
                id: "cmd-\(cmd)",
                title: cmd,
                subtitle: subtitle,
                systemImage: icon,
                action: .openShellCommand(cmd)
            ))
        }

        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return result }
        return result.filter {
            $0.title.lowercased().contains(q) || $0.subtitle.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: BrandSpacing.small) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(BrandColor.textSecondary)
                TextField("Search modules, servers, projects, commands…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit { runFirst() }
                Button("Esc") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.borderless)
            }
            .padding(BrandSpacing.large)

            Divider()

            List(items) { item in
                Button {
                    run(item)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.headline)
                            Text(item.subtitle)
                                .font(.caption)
                                .foregroundStyle(BrandColor.textSecondary)
                        }
                    } icon: {
                        Image(systemName: item.systemImage)
                            .foregroundStyle(BrandColor.accent)
                    }
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
        .frame(width: 560, height: 420)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
        .onAppear { focused = true }
    }

    private func runFirst() {
        if let first = items.first { run(first) }
    }

    private func run(_ item: CommandPaletteItem) {
        switch item.action {
        case .navigate(let sidebar):
            session.navigate(to: sidebar)
        case .selectServer(let id):
            session.activeServerID = id
            session.showCommandPalette = false
        case .openShell:
            session.openInteractiveShell()
            session.showCommandPalette = false
        case .openShellCommand(let cmd):
            session.openInteractiveShell(command: cmd)
            session.showCommandPalette = false
        case .openProject(let id):
            session.selectedProjectID = id
            session.navigate(to: .projects)
        }
        isPresented = false
    }
}
