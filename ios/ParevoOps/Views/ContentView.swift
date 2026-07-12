import SwiftUI
import SwiftData

public struct ContentView: View {
    @State private var activeTab = "dashboard"
    @State private var activeServer: Server? = nil
    
    public init() {}
    
    public var body: some View {
        TabView(selection: $activeTab) {
            DashboardView(activeServer: $activeServer)
                .tabItem {
                    Label("Dashboard", systemImage: "chart.bar.fill")
                }
                .tag("dashboard")
            
            ServersView(activeServer: $activeServer)
                .tabItem {
                    Label("Servers", systemImage: "server.rack")
                }
                .tag("servers")
            
            ContainersView(activeServer: $activeServer)
                .tabItem {
                    Label("Containers", systemImage: "shippingbox.fill")
                }
                .tag("containers")
            
            ServicesView(activeServer: $activeServer)
                .tabItem {
                    Label("Services", systemImage: "cpu")
                }
                .tag("services")
            
            FilesView(activeServer: $activeServer)
                .tabItem {
                    Label("Files", systemImage: "folder.fill")
                }
                .tag("files")
            
            LogsView(activeServer: $activeServer)
                .tabItem {
                    Label("Logs", systemImage: "doc.text.fill")
                }
                .tag("logs")
            
            AiAssistantView(activeServer: $activeServer)
                .tabItem {
                    Label("AI SRE", systemImage: "sparkles")
                }
                .tag("ai")
        }
        .tint(.purple)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
}
