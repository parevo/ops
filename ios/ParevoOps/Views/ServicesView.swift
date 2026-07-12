import SwiftUI

public struct ServicesView: View {
    @Binding public var activeServer: Server?
    @State private var servicesList: [ServiceInfo] = []
    
    public init(activeServer: Binding<Server?>) {
        self._activeServer = activeServer
    }
    
    public var body: some View {
        NavigationStack {
            List {
                Section(header: Text("systemd Daemons Management").font(.caption).foregroundColor(.zincSecondary)) {
                    if servicesList.isEmpty {
                        Text("Scanning systemd service states...")
                            .font(.caption)
                            .foregroundColor(.zincSecondary)
                    } else {
                        ForEach(servicesList) { srv in
                            serviceRowCard(srv)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }
                }
            }
            .navigationTitle("Services")
            .background(Color(red: 0.03, green: 0.03, blue: 0.05))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: loadServices) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.purple)
                    }
                }
            }
            .onAppear(perform: loadServices)
            .onChange(of: activeServer, perform: { _ in loadServices() })
        }
    }
    
    private func serviceRowCard(_ item: ServiceInfo) -> some View {
        let isActive = item.activeState == "active"
        let isFailed = item.activeState == "failed"
        
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(item.name)
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(isActive ? Color.emerald : (isFailed ? Color.red : Color.zincSecondary))
                        .frame(width: 6, height: 6)
                    Text(item.activeState.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(isActive ? .emerald : (isFailed ? .red : .zincSecondary))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isActive ? Color.emerald.opacity(0.1) : (isFailed ? Color.red.opacity(0.1) : Color.zincSecondary.opacity(0.1)))
                .cornerRadius(6)
            }
            
            Text(item.description)
                .font(.caption2)
                .foregroundColor(.zincSecondary)
            
            Divider()
                .background(Color.zincBorder)
            
            HStack(spacing: 8) {
                actionButton("Start", color: .emerald) { runAction("start", on: item) }
                actionButton("Stop", color: .red) { runAction("stop", on: item) }
                actionButton("Restart", color: .purple) { runAction("restart", on: item) }
            }
        }
        .padding()
        .background(Color.zincPanel)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.zincBorder, lineWidth: 1)
        )
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
    
    private func actionButton(_ label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(color.opacity(0.1))
                .cornerRadius(6)
        }
    }
    
    private func loadServices() {
        let serverSuffix = activeServer != nil ? " on \(activeServer!.name)" : " (Local Host)"
        servicesList = [
            ServiceInfo(name: "nginx.service", loadState: "loaded", activeState: "active", subState: "running", description: "Nginx high-performance HTTP web gateway\(serverSuffix)"),
            ServiceInfo(name: "postgresql.service", loadState: "loaded", activeState: "active", subState: "running", description: "PostgreSQL relational query processor engine\(serverSuffix)"),
            ServiceInfo(name: "redis.service", loadState: "loaded", activeState: "failed", subState: "failed", description: "In-memory caching and message-queue store\(serverSuffix)")
        ]
    }
    
    private func runAction(_ action: String, on service: ServiceInfo) {
        if let idx = servicesList.firstIndex(where: { $0.name == service.name }) {
            if action == "stop" {
                servicesList[idx].activeState = "inactive"
                servicesList[idx].subState = "dead"
            } else if action == "start" || action == "restart" {
                servicesList[idx].activeState = "active"
                servicesList[idx].subState = "running"
            }
        }
    }
}
