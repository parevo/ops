import SwiftUI
import SwiftData

@main
struct ParevoOpsApp: App {
    let modelContainer: ModelContainer
    @State private var session = AppSession()
    @State private var alertMonitor = AlertMonitor()

    init() {
        DependencyContainer.shared.registerDefaultServices()
        do {
            let schema = Schema([Server.self, Project.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("SwiftData failed: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
                .environment(alertMonitor)
                .frame(minWidth: 1100, minHeight: 700)
                .modelContainer(modelContainer)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(after: .sidebar) {
                Button("Command Palette") {
                    session.showCommandPalette = true
                }
                .keyboardShortcut("k", modifiers: [.command])

                Button("New Terminal Tab") {
                    session.newTerminalTab()
                }
                .keyboardShortcut("t", modifiers: [.command])

                Button("Close Terminal Tab") {
                    if let id = session.selectedTerminalTabID {
                        session.closeTerminalTab(id)
                    }
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])

                Button("Interactive Shell") {
                    session.openInteractiveShell()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Button("Toggle Terminal Panel") {
                    if session.terminalVisible {
                        session.terminalVisible = false
                    } else {
                        session.ensureTerminalTab()
                        session.terminalVisible = true
                    }
                }
                .keyboardShortcut("`", modifiers: [.control])

                Button("Alert Center") {
                    session.navigate(to: .alerts)
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            }
        }
    }
}
