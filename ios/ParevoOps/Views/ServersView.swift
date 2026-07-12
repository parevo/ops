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
        NavigationStack {
            List {
                Section(header: Text("Create Server Profile").font(.caption).foregroundColor(.zincSecondary)) {
                    VStack(alignment: .leading, spacing: 14) {
                        // Connection info
                        Group {
                            TextField("Connection Name (e.g. AWS Production)", text: $name)
                                .textFieldStyle(.plain)
                                .padding(10)
                                .background(Color.zincPanel)
                                .cornerRadius(8)
                            
                            TextField("Host IP / Domain Address", text: $host)
                                .textFieldStyle(.plain)
                                .padding(10)
                                .background(Color.zincPanel)
                                .cornerRadius(8)
                                .autocorrectionDisabled()
                        }
                        
                        // PEM Selector
                        VStack(alignment: .leading, spacing: 6) {
                            Text("SSH Key File (.pem / .key)")
                                .font(.caption)
                                .foregroundColor(.zincSecondary)
                            
                            HStack {
                                Text(privateKeyPath.isEmpty ? "No key selected..." : (privateKeyPath as NSString).lastPathComponent)
                                    .font(.caption)
                                    .foregroundColor(privateKeyPath.isEmpty ? .zincSecondary : .white)
                                    .lineLimit(1)
                                Spacer()
                                Button(action: { showFilePicker = true }) {
                                    Text("Browse...")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.purple.opacity(0.15))
                                        .cornerRadius(6)
                                }
                                if !privateKeyPath.isEmpty {
                                    Button(action: { privateKeyPath = "" }) {
                                        Text("Clear")
                                            .font(.caption2)
                                            .foregroundColor(.red)
                                    }
                                }
                            }
                            .padding(10)
                            .background(Color.zincPanel)
                            .cornerRadius(8)
                        }
                        
                        // Advanced Config Toggle
                        Button(action: { withAnimation { showAdvanced.toggle() } }) {
                          Text(showAdvanced ? "↓ Hide Advanced Settings" : "→ Show Advanced Settings (Port, Username, Group)")
                              .font(.caption2)
                              .foregroundColor(.purple)
                        }
                        
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
                                        ProgressView()
                                            .tint(.white)
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "shield.fill")
                                    }
                                    Text("Test Connection")
                                }
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(host.isEmpty ? Color.zincBorder : Color.zincSecondary.opacity(0.2))
                                .cornerRadius(8)
                            }
                            .disabled(host.isEmpty || testingConnection)
                            
                            Button(action: saveServerProfile) {
                                Text("Save Server")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(name.isEmpty || host.isEmpty ? Color.zincBorder : Color.purple)
                                    .cornerRadius(8)
                            }
                            .disabled(name.isEmpty || host.isEmpty)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.zincPanel.opacity(0.4))
                .listRowSeparator(.hidden)
                
                Section(header: Text("Stored Nodes").font(.caption).foregroundColor(.zincSecondary)) {
                    if servers.isEmpty {
                        Text("No remote server profiles configured.")
                            .font(.caption)
                            .foregroundColor(.zincSecondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    } else {
                        ForEach(servers) { srv in
                            serverRowCard(srv)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                        .onDelete(perform: deleteStoredServers)
                    }
                }
            }
            .navigationTitle("Servers")
            .background(Color(red: 0.03, green: 0.03, blue: 0.05))
            .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.item]) { result in
                switch result {
                case .success(let url):
                    privateKeyPath = url.path
                case .failure(let err):
                    print("Error picking file: \(err)")
                }
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
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(.white)
            }
            
            HStack {
                Text("SSH Port")
                    .font(.caption)
                    .foregroundColor(.zincSecondary)
                Spacer()
                TextField("22", value: $port, formatter: NumberFormatter())
                    .textFieldStyle(.plain)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(.white)
            }
            
            Picker("Environment", selection: $groupName) {
                Text("Production").tag("production")
                Text("Staging").tag("staging")
                Text("Development").tag("development")
                Text("Monitoring").tag("monitoring")
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
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.zincSecondary)
            
            if testingConnection {
                Text("CONNECTING... AUTHENTICATING SEQUENCE ACTIVE")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.purple)
            }
            
            if let msg = testResult {
                Text(msg)
                    .font(.system(.caption2, design: .monospaced))
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
                
                if let key = srv.privateKeyPath {
                    Text("Key: \((key as NSString).lastPathComponent)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.zincSecondary)
                }
            }
            Spacer()
            
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .emerald : .zincBorder)
                .font(.title2)
        }
        .padding()
        .background(Color.zincPanel)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.emerald.opacity(0.5) : Color.zincBorder, lineWidth: 1)
        )
        .padding(.horizontal)
        .padding(.vertical, 4)
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
