import SwiftUI

public struct LogsView: View {
    @Binding public var activeServer: Server?
    @State private var logs: [LogMessage] = []
    @State private var filterQuery = ""
    @State private var selectedLevel = "all"
    
    public init(activeServer: Binding<Server?>) {
        self._activeServer = activeServer
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filters Header
                HStack(spacing: 10) {
                    TextField("Filter with query or regex...", text: $filterQuery)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(Color.zincPanel)
                        .cornerRadius(6)
                        .autocorrectionDisabled()
                    
                    Picker("Level", selection: $selectedLevel) {
                        Text("ALL").tag("all")
                        Text("INFO").tag("info")
                        Text("WARN").tag("warn")
                        Text("ERROR").tag("error")
                    }
                    .pickerStyle(.menu)
                    .tint(.purple)
                }
                .padding()
                .background(Color.black.opacity(0.2))
                
                // Console Area
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            if filteredLogs.isEmpty {
                                Text("No logs matching filter query.")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.zincSecondary)
                                    .padding()
                            } else {
                                ForEach(filteredLogs) { log in
                                    logLine(log)
                                        .id(log.id)
                                }
                            }
                        }
                        .padding()
                    }
                    .background(Color.black)
                    .onChange(of: logs.count) { _ in
                        if let lastLog = filteredLogs.last {
                            withAnimation { proxy.scrollTo(lastLog.id, anchor: .bottom) }
                        }
                    }
                }
            }
            .navigationTitle("Logs")
            .background(Color(red: 0.03, green: 0.03, blue: 0.05))
            .onAppear(perform: loadInitialLogs)
            .onChange(of: activeServer, perform: { _ in loadInitialLogs() })
        }
    }
    
    private var filteredLogs: [LogMessage] {
        logs.filter { log in
            let matchQuery = filterQuery.isEmpty || log.message.lowercased().contains(filterQuery.lowercased())
            let matchLevel = selectedLevel == "all" || log.level.lowercased() == selectedLevel.lowercased()
            return matchQuery && matchLevel
        }
    }
    
    private func logLine(_ item: LogMessage) -> some View {
        let levelColor: Color = {
            switch item.level.lowercased() {
            case "error": return .red
            case "warn": return .yellow
            default: return .emerald
            }
        }()
        
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(item.timestamp)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.zincSecondary)
                
                Text(item.level.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(levelColor)
                
                Text("[\(item.source)]")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(.purple)
            }
            
            Text(item.message)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.white)
        }
        .padding(.vertical, 2)
    }
    
    private func loadInitialLogs() {
        let nameSuffix = activeServer?.name ?? "localhost"
        let now = ISO8601DateFormatter().string(from: Date())
        
        logs = [
            LogMessage(source: "nginx", level: "info", message: "[\(nameSuffix)] Initiating upstream connection socket on port 80", timestamp: now),
            LogMessage(source: "docker", level: "info", message: "[\(nameSuffix)] Loaded configuration schema from storage manager", timestamp: now),
            LogMessage(source: "systemd", level: "warn", message: "[\(nameSuffix)] Memory consumption boundary warning: CPU load 84% on core 2", timestamp: now),
            LogMessage(source: "app", level: "error", message: "[\(nameSuffix)] SocketException connection handshake timed out on DB backend", timestamp: now)
        ]
    }
}
