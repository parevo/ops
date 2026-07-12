import SwiftUI
import SwiftData

@main
struct ParevoOpsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: Server.self)
    }
}
