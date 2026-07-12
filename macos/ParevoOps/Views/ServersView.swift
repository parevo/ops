import SwiftUI
import SwiftData
import UniformTypeIdentifiers

public struct ServersView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Server.name) private var servers: [Server]
    @Binding public var activeServer: Server?
    
    // Form fields
    @State private var name = ""
    @State private var host = ""
    @State private var port = 22
    @State private var username = "ubuntu"
    @State private var privateKeyPath = ""
    @State private var groupName = "production"
    @State private var tags = ""
    
    // State controls
    @State private var showAdvanced = false
    @State private var testingConnection = false
    @State private var testResult: String? = nil
    @State private var testSuccess = false
    @State private var showFilePicker = false
    
    public init(activeServer: Binding<Server?>) {
        self._activeServer = activeServer
    }
    
    public var body: some View {
        HSplitView {
            // Left list panel
            VStack(alignment: .leading, spacing: 16) {
                Text("Registered Server Nodes (\(servers.count))")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal)
                
                if servers.isEmpty {
                    VStack {
                        Spacer()
                        Text("No remote server profiles configured. Use the right form to register your first host.")
                            .font(.caption)
                            .foregroundColor(.zincSecondary)
                            .multilineTextAlignment(.center)
                            .padding()
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    List {
                        ForEach(servers) { srv in
                            serverRowCard(srv)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .padding(.vertical, 4)
                        }
                        .onDelete(perform: deleteStoredServers)
                    }
                    .listStyle(.plain)
                }
            }
            .frame(minWidth: 320, idealWidth: 360, maxWidth: 450)
            .padding(.vertical)
            
            // Right configuration form
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Register Host Profile")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    VStack(alignment: .leading, spacing: 14) {
                        TextField("Connection Name (e.g. AWS Production)", text: $name)
                            .textFieldStyle(.roundedBorder)
                        
                        TextField("Host IP / Domain Address", text: $host)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                        
                        // PEM Selector
                        VStack(alignment: .leading, spacing: 6) {
                            Text("SSH Key File (.pem / .key)")
                                .font(.caption)
                                .foregroundColor(.zincSecondary)
                            
                            HStack {
                                Text(privateKeyPath.isEmpty ? "No key selected..." : privateKeyPath)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(privateKeyPath.isEmpty ? .zincSecondary : .white)
                                    .lineLimit(1)
                                Spacer()
                                Button("Browse...") {
                                    showFilePicker = true
                                }
                                if !privateKeyPath.isEmpty {
                                    Button("Clear") {
                                        privateKeyPath = ""
                                    }
                                }
                            }
                            .padding(8)
                            .background(Color.zincPanel)
                            .cornerRadius(6)
                        }
                        
                        // Advanced Config Toggle
                        Button(action: { withAnimation { showAdvanced.toggle() } }) {
                            Text(showAdvanced ? "↓ Hide Advanced Settings" : "→ Show Advanced Settings (Port, Username, Group)")
                                .font(.caption2)
                                .foregroundColor(.purple)
                        }
                        .buttonStyle(.plain)
                        
                        if showAdvanced {
                            advancedFields
                                .transition(.opacity)
                        }
                        
                        Divider()
                            .background(Color.zincBorder)
                        
                        // Sandbox Console
                        sandboxConsole
                        
                        // Action triggers
                        HStack(spacing: 12) {
                            Button(action: runTestConnection) {
                                HStack {
                                    if testingConnection {
                                        ProgressView().scaleEffect(0.6).tint(.white)
                                    } else {
                                        Image(systemName: "shield.fill")
                                    }
                                    Text("Test Connection")
                                }
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(host.isEmpty ? Color.zincBorder : Color.zincSecondary.opacity(0.2))
                                .cornerRadius(8)
                            }
                            .disabled(host.isEmpty || testingConnection)
                            .buttonStyle(.plain)
                            
                            Button(action: saveServerProfile) {
                                Text("Save Server")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(name.isEmpty || host.isEmpty ? Color.zincBorder : Color.purple)
                                    .cornerRadius(8)
                            }
                            .disabled(name.isEmpty || host.isEmpty)
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(20)
                    .background(Color.zincPanel.opacity(0.3))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.zincBorder, lineWidth: 1)
                    )
                }
                .padding(24)
            }
        }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.item]) { result in
            switch result {
            case .success(let url):
                privateKeyPath = url.path
            case .failure(let err):
                print("Error picking file: \(err)")
            }
        }
    }
    
    private var advancedFields: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Username")
                    .font(.caption)
                    .foregroundColor(.zincSecondary)
                Spacer()
                TextField("ubuntu", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
            }
            
            HStack {
                Text("SSH Port")
                    .font(.caption)
                    .foregroundColor(.zincSecondary)
                Spacer()
                TextField("22", value: $port, formatter: NumberFormatter())
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
            }
            
            Picker("Environment", selection: $groupName) {
                Text("Production").tag("production")
                Text("Staging").tag("staging")
                Text("Development").tag("development")
            }
            .pickerStyle(.segmented)
        }
        .padding(12)
        .background(Color.zincPanel)
        .cornerRadius(8)
    }
    
    private var sandboxConsole: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("$ ssh -i \(privateKeyPath.isEmpty ? "default" : (privateKeyPath as NSString).lastPathComponent) \(username)@\(host.isEmpty ? "host" : host) -p \(port)")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.zincSecondary)
            
            if testingConnection {
                Text("CONNECTING... AUTHENTICATING SEQUENCE ACTIVE")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.purple)
            }
            
            if let msg = testResult {
                Text(msg)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(testSuccess ? .emerald : .red)
                    .fontWeight(.bold)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.6))
        .cornerRadius(8)
    }
    
    private func serverRowCard(_ srv: Server) -> some View {
        let isSelected = activeServer?.id == srv.id
        
        return HStack {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(srv.name)
                        .font(.headline)
                        .foregroundColor(.white)
                    if isSelected {
                        Text("Connected")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.emerald)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.emerald.opacity(0.15))
                            .cornerRadius(4)
                    }
                }
                
                Text("\(srv.username)@\(srv.host):\(srv.port)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.zincSecondary)
            }
            Spacer()
            
            Button(action: {
                if let idx = servers.firstIndex(where: { $0.id == srv.id }) {
                    deleteStoredServers(offsets: IndexSet(integer: idx))
                }
            }) {
                Image(systemName: "trash")
                    .foregroundColor(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color.zincPanel)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.emerald.opacity(0.5) : Color.zincBorder, lineWidth: 1)
        )
        .padding(.horizontal)
        .contentShape(Rectangle())
        .onTapGesture {
            activeServer = srv
        }
    }
    
    private func runTestConnection() {
        testingConnection = true
        testResult = nil
        testSuccess = false
        
        let dummy = Server(name: name, host: host, port: port, username: username, privateKeyPath: privateKeyPath)
        
        Task {
            do {
                let success = try await SSHService.shared.testConnection(on: dummy)
                testSuccess = success
                testResult = "✓ CONNECTION VERIFIED SUCCESSFUL"
            } catch {
                testSuccess = false
                testResult = "✗ FAILED: \(error.localizedDescription)"
            }
            testingConnection = false
        }
    }
    
    private func saveServerProfile() {
        let newSrv = Server(
            name: name,
            host: host,
            port: port,
            username: username,
            privateKeyPath: privateKeyPath.isEmpty ? nil : privateKeyPath,
            groupName: groupName,
            tags: tags
        )
        modelContext.insert(newSrv)
        
        // Reset form
        name = ""
        host = ""
        port = 22
        username = "ubuntu"
        privateKeyPath = ""
        testResult = nil
    }
    
    private func deleteStoredServers(offsets: IndexSet) {
        for index in offsets {
            let srv = servers[index]
            if activeServer?.id == srv.id {
                activeServer = nil
            }
            modelContext.delete(srv)
        }
    }
}
