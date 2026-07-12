import SwiftUI

public struct ContainersView: View {
    @Binding public var activeServer: Server?
    @State private var containers: [ContainerInfo] = []
    @State private var loading = false
    
    public init(activeServer: Binding<Server?>) {
        self._activeServer = activeServer
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Action bar
            HStack {
                Text(activeServer == nil ? "Local Daemon Sockets" : "Remote Node: \(activeServer!.name)")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button(action: loadContainers) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .padding()
            .background(Color.black.opacity(0.15))
            
            // Containers grid
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280))], spacing: 16) {
                    if containers.isEmpty {
                        VStack(spacing: 8) {
                            Text("No containers running on this server.")
                                .font(.caption)
                                .foregroundColor(.zincSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        ForEach(containers) { container in
                            containerGridCard(container)
                        }
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Containers")
        .onAppear(perform: loadContainers)
        .onChange(of: activeServer, perform: { _ in loadContainers() })
    }
    
    private func containerGridCard(_ item: ContainerInfo) -> some View {
        let isRunning = item.status == "running"
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isRunning ? Color.emerald : Color.red)
                        .frame(width: 8, height: 8)
                    Text(item.status.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(isRunning ? .emerald : .red)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isRunning ? Color.emerald.opacity(0.1) : Color.red.opacity(0.1))
                .cornerRadius(6)
                
                Spacer()
                
                Text(item.id.prefix(8))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.zincSecondary)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline)
                    .foregroundColor(.white)
                Text("Image: \(item.image)")
                    .font(.caption)
                    .foregroundColor(.zincSecondary)
                    .lineLimit(1)
            }
            
            Divider()
                .background(Color.zincBorder)
            
            HStack {
                Spacer()
                Button(action: { toggleContainer(item) }) {
                    Text(isRunning ? "Stop Container" : "Start Container")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(isRunning ? .red : .emerald)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(isRunning ? Color.red.opacity(0.1) : Color.emerald.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Color.zincPanel)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.zincBorder, lineWidth: 1)
        )
    }
    
    private func loadContainers() {
        loading = true
        let namePrefix = activeServer?.name.lowercased().replacingOccurrences(of: " ", with: "-") ?? "localhost"
        
        containers = [
            ContainerInfo(id: "1", name: "\(namePrefix)-web-nginx", image: "nginx:alpine", status: "running", state: "running"),
            ContainerInfo(id: "2", name: "\(namePrefix)-postgres-db", image: "postgres:15-alpine", status: "running", state: "running"),
            ContainerInfo(id: "3", name: "\(namePrefix)-api-worker", image: "parevo-api:latest", status: "exited", state: "exited")
        ]
        loading = false
    }
    
    private func toggleContainer(_ item: ContainerInfo) {
        if let idx = containers.firstIndex(where: { $0.id == item.id }) {
            let nextStatus = containers[idx].status == "running" ? "exited" : "running"
            containers[idx].status = nextStatus
            containers[idx].state = nextStatus
        }
    }
}
