import SwiftUI

public struct ContainersView: View {
    @Binding public var activeServer: Server?
    @State private var containers: [ContainerInfo] = []
    @State private var loading = false
    
    public init(activeServer: Binding<Server?>) {
        self._activeServer = activeServer
    }
    
    public var body: some View {
        NavigationStack {
            List {
                Section(header: Text(activeServer == nil ? "Local Daemon Sockets" : "Remote Node: \(activeServer!.name)").font(.caption).foregroundColor(.zincSecondary)) {
                    if containers.isEmpty {
                        VStack(spacing: 8) {
                            Text("No containers running on this server.")
                                .font(.caption)
                                .foregroundColor(.zincSecondary)
                            Button("Scan Containers", action: loadContainers)
                                .font(.caption2)
                                .foregroundColor(.purple)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                    } else {
                        ForEach(containers) { container in
                            containerRowCard(container)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }
                }
            }
            .navigationTitle("Containers")
            .background(Color(red: 0.03, green: 0.03, blue: 0.05))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: loadContainers) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.purple)
                    }
                }
            }
            .onAppear(perform: loadContainers)
            .onChange(of: activeServer, perform: { _ in loadContainers() })
        }
    }
    
    private func containerRowCard(_ item: ContainerInfo) -> some View {
        let isRunning = item.status == "running"
        
        return HStack(spacing: 14) {
            // Circle color indicator
            Circle()
                .fill(isRunning ? Color.emerald : Color.red)
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text("Image: \(item.image)")
                    .font(.caption2)
                    .foregroundColor(.zincSecondary)
                
                Text(isRunning ? "Up 4 hours" : "Exited (137) 3 minutes ago")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(isRunning ? .emerald : .red)
            }
            
            Spacer()
            
            Button(action: { toggleContainer(item) }) {
                Text(isRunning ? "Stop" : "Start")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(isRunning ? .red : .emerald)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isRunning ? Color.red.opacity(0.1) : Color.emerald.opacity(0.1))
                    .cornerRadius(6)
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
    
    private func loadContainers() {
        loading = true
        let namePrefix = activeServer?.name.lowercased().replacingOccurrences(of: " ", with: "-") ?? "localhost"
        
        // Simulating docker network responses
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
