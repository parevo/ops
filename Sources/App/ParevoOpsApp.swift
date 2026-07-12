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

                Button("Interactive Shell") {
                    session.openInteractiveShell()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Button("Toggle Terminal Panel") {
                    session.terminalVisible.toggle()
                }
                .keyboardShortcut("`", modifiers: [.control])
            }
        }
    }
}
