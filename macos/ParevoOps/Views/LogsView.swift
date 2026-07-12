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
        VStack(spacing: 0) {
            // Filters Header
            HStack(spacing: 12) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundColor(.zincSecondary)
                
                TextField("Filter with query or regex (e.g. timeout)...", text: $filterQuery)
                    .textFieldStyle(.plain)
                    .padding(6)
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
                .frame(width: 100)
            }
            .padding()
            .background(Color.black.opacity(0.15))
            
            // Console Scroll Area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if filteredLogs.isEmpty {
                            Text("No SRE telemetry logs matching filters.")
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundColor(.zincSecondary)
                                .padding()
                        } else {
                            ForEach(filteredLogs) { log in
                                logLine(log)
                                    .id(log.id)
                            }
                        }
                    }
                    .padding(16)
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
        .onAppear(perform: loadInitialLogs)
        .onChange(of: activeServer, perform: { _ in loadInitialLogs() })
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
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.zincSecondary)
                
                Text(item.level.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(levelColor)
                
                Text("[\(item.source)]")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.purple)
            }
            
            Text(item.message)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundColor(.white)
        }
        .padding(.vertical, 4)
    }
    
    private func loadInitialLogs() {
        let nameSuffix = activeServer?.name ?? "localhost"
        let now = ISO8601DateFormatter().string(from: Date())
        
        logs = [
            LogMessage(source: "nginx", level: "info", message: "[\(nameSuffix)] Initiating upstream connection socket listener proxy on port 80", timestamp: now),
            LogMessage(source: "docker", level: "info", message: "[\(nameSuffix)] Loaded config JSON schemas from persistence sqlite repository", timestamp: now),
            LogMessage(source: "systemd", level: "warn", message: "[\(nameSuffix)] Memory warning: threshold limits exceed 90% boundary constraints on root node", timestamp: now),
            LogMessage(source: "app", level: "error", message: "[\(nameSuffix)] SocketException handshake timed out: check security groups port 22 listening state", timestamp: now)
        ]
    }
}
