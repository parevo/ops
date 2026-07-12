import SwiftUI
import SwiftData

public struct ContentView: View {
    @State private var activeTab: String? = "dashboard"
    @State private var activeServer: Server? = nil
    
    public init() {}
    
    public var body: some View {
        NavigationSplitView {
            List(selection: $activeTab) {
                Section(header: Text("Infrastructure")) {
                    NavigationLink(value: "dashboard") {
                        Label("Dashboard", systemImage: "chart.bar.fill")
                    }
                    NavigationLink(value: "servers") {
                        Label("Servers", systemImage: "server.rack")
                    }
                }
                
                Section(header: Text("Management")) {
                    NavigationLink(value: "containers") {
                        Label("Containers", systemImage: "shippingbox.fill")
                    }
                    NavigationLink(value: "services") {
                        Label("Services", systemImage: "cpu")
                    }
                    NavigationLink(value: "files") {
                        Label("Files", systemImage: "folder.fill")
                    }
                    NavigationLink(value: "logs") {
                        Label("Logs", systemImage: "doc.text.fill")
                    }
                }
                
                Section(header: Text("Diagnostics")) {
                    NavigationLink(value: "ai") {
                        Label("AI SRE", systemImage: "sparkles")
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Parevo Ops")
            .safeAreaInset(edge: .bottom) {
                sidebarFooter
            }
        } detail: {
            NavigationStack {
                detailView
                    .background(Color(red: 0.03, green: 0.03, blue: 0.05))
            }
        }
        .preferredColorScheme(.dark)
    }
    
    @ViewBuilder
    private var detailView: some View {
        switch activeTab {
        case "dashboard":
            DashboardView(activeServer: $activeServer)
        case "servers":
            ServersView(activeServer: $activeServer)
        case "containers":
            ContainersView(activeServer: $activeServer)
        case "services":
            ServicesView(activeServer: $activeServer)
        case "files":
            FilesView(activeServer: $activeServer)
        case "logs":
            LogsView(activeServer: $activeServer)
        case "ai":
            AiAssistantView(activeServer: $activeServer)
        default:
            Text("Select an option from the sidebar")
                .foregroundColor(.zincSecondary)
        }
    }
    
    private var sidebarFooter: some View {
        VStack(spacing: 8) {
            Divider()
                .background(Color.zincBorder)
            
            if let srv = activeServer {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.emerald)
                            .frame(width: 6, height: 6)
                        Text(srv.name)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.emerald)
                    }
                    Text("\(srv.username)@\(srv.host)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.zincSecondary)
                        .lineLimit(1)
                    
                    Button(action: { activeServer = nil }) {
                        Text("Disconnect to Local")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.zincSecondary)
                            .padding(.vertical, 3)
                            .frame(maxWidth: .infinity)
                            .background(Color.zincBorder.opacity(0.4))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.emerald.opacity(0.04))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.emerald.opacity(0.15), lineWidth: 1)
                )
            } else {
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color.emerald)
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Local Node")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        Text("Localhost connected")
                            .font(.system(size: 9))
                            .foregroundColor(.zincSecondary)
                    }
                    Spacer()
                }
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(Color.zincPanel.opacity(0.6))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.zincBorder, lineWidth: 1)
                )
            }
            
            Text("PAREVO OPS v0.1.0")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.zincSecondary.opacity(0.6))
                .padding(.top, 4)
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }
}
