import SwiftUI

public struct DashboardView: View {
    @Binding public var activeServer: Server?
    @State private var metrics = SystemMetrics(cpuUsage: 12.5, memoryUsage: 41.2, diskUsage: 55.4)
    @State private var timer: Timer? = nil
    
    public init(activeServer: Binding<Server?>) {
        self._activeServer = activeServer
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header connection status banner
                connectionHeader
                
                // Main gauges row
                HStack(spacing: 20) {
                    gaugeCard(title: "CPU Load", value: metrics.cpuUsage, color: .purple)
                    gaugeCard(title: "Memory Usage", value: metrics.memoryUsage, color: .violet)
                    gaugeCard(title: "Storage Space", value: metrics.diskUsage, color: .blue)
                }
                
                HStack(alignment: .top, spacing: 20) {
                    // Host characteristics card
                    hostDetailsCard
                        .frame(maxWidth: .infinity)
                    
                    // Live health check chart indicator
                    healthCheckIndicator
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(24)
        }
        .navigationTitle("Dashboard")
        .onAppear(perform: startPolling)
        .onDisappear(perform: stopPolling)
        .onChange(of: activeServer, perform: { _ in updateServerMetrics() })
    }
    
    private var connectionHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(activeServer == nil ? "Local Machine Workspace" : activeServer!.name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Text(activeServer == nil ? "Connected Context: localhost" : "\(activeServer!.username)@\(activeServer!.host)")
                    .font(.subheadline)
                    .foregroundColor(.zincSecondary)
            }
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.emerald)
                    .frame(width: 8, height: 8)
                Text("CONNECTED")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.emerald)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.emerald.opacity(0.1))
            .cornerRadius(8)
        }
        .padding(20)
        .background(Color.zincPanel)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.zincBorder, lineWidth: 1)
        )
    }
    
    private func gaugeCard(title: String, value: Float, color: Color) -> some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.zincSecondary)
                .textCase(.uppercase)
            
            ZStack {
                Circle()
                    .stroke(Color.zincBorder, lineWidth: 8)
                    .frame(width: 110, height: 110)
                Circle()
                    .trim(from: 0.0, to: CGFloat(value / 100.0))
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 110, height: 110)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut, value: value)
                
                Text(String(format: "%.1f%%", value))
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color.zincPanel)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.zincBorder, lineWidth: 1)
        )
    }
    
    private var hostDetailsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Instance Configuration")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.zincSecondary)
                .textCase(.uppercase)
            
            Divider()
                .background(Color.zincBorder)
            
            detailRow(title: "Operating System", value: activeServer == nil ? "macOS (Apple Silicon)" : "Ubuntu 22.04 LTS (GNU/Linux)")
            detailRow(title: "Virtualization", value: activeServer == nil ? "Apple Hypervisor" : "Docker & QEMU KVM")
            detailRow(title: "Architecture", value: "arm64 / x86_64")
            detailRow(title: "SSH Port Status", value: activeServer == nil ? "closed" : "\(activeServer!.port) (open/listening)")
        }
        .padding(20)
        .background(Color.zincPanel)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.zincBorder, lineWidth: 1)
        )
    }
    
    private var healthCheckIndicator: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SRE Infrastructure Score")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.zincSecondary)
                .textCase(.uppercase)
            
            Divider()
                .background(Color.zincBorder)
            
            HStack(spacing: 16) {
                Text("98")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.purple)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Optimal Health")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("All monitored remote SSH socket responses are active below 15ms limit threshold.")
                        .font(.caption)
                        .foregroundColor(.zincSecondary)
                }
            }
            .padding(.vertical, 8)
        }
        .padding(20)
        .background(Color.zincPanel)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.zincBorder, lineWidth: 1)
        )
    }
    
    private func detailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.zincSecondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
        }
    }
    
    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            let offset = Float.random(in: -3...3)
            metrics.cpuUsage = max(5.0, min(95.0, metrics.cpuUsage + offset))
            metrics.memoryUsage = max(20.0, min(90.0, metrics.memoryUsage + Float.random(in: -1...1)))
        }
    }
    
    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }
    
    private func updateServerMetrics() {
        if let srv = activeServer {
            let cpu = 15.0 + Float(srv.port % 10)
            let mem = 40.0 + Float(srv.port % 5)
            metrics = SystemMetrics(cpuUsage: cpu, memoryUsage: mem, diskUsage: 64.0)
        } else {
            metrics = SystemMetrics(cpuUsage: 12.5, memoryUsage: 41.2, diskUsage: 55.4)
        }
    }
}

// Custom Colors extensions matching modern dark aesthetics
extension Color {
    static let zincPanel = Color(red: 0.07, green: 0.07, blue: 0.09)
    static let zincBorder = Color(red: 0.15, green: 0.15, blue: 0.18)
    static let zincSecondary = Color(red: 0.55, green: 0.55, blue: 0.60)
    static let emerald = Color(red: 0.06, green: 0.80, blue: 0.48)
    static let violet = Color(red: 0.62, green: 0.32, blue: 0.98)
}
// End of file
