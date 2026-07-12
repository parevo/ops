import SwiftUI
import SwiftData

@main
struct ParevoOpsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1000, minHeight: 650)
        }
        .windowStyle(.titleBar)
        .modelContainer(for: Server.self)
    }
}
