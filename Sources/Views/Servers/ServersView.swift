import SwiftUI
import SwiftData
import UniformTypeIdentifiers

@MainActor
struct ServersView: View {
    @Environment(AppSession.self) private var session
    @Query private var servers: [Server]
    @Environment(\.modelContext) private var modelContext
    @State private var selectedServer: Server?
    @State private var showAddSheet = false
    @State private var connectionMessage: String?
    @State private var exportDocument: ServersExportDocument?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var ioMessage: String?

    var body: some View {
        HSplitView {
            List(selection: $selectedServer) {
                Section {
                    if servers.isEmpty {
                        ContentUnavailableView(
                            "No Servers",
                            systemImage: "server.rack",
                            description: Text("Add EC2, DigitalOcean, Hetzner, or a custom SSH host.")
                        )
                        .frame(minHeight: 160)
                    } else {
                        ForEach(servers) { server in
                            serverRow(server).tag(server)
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 240, idealWidth: 280, maxWidth: 340)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { showImporter = true } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        if let data = try? ServerConfigIO.exportJSON(servers: Array(servers)) {
                            exportDocument = ServersExportDocument(data: data)
                            showExporter = true
                        }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    Button { showAddSheet = true } label: {
                        Label("Add Server", systemImage: "plus")
                    }
                }
            }

            Group {
                if let server = selectedServer {
                    detail(server)
                } else {
                    ContentUnavailableView(
                        "Select a Server",
                        systemImage: "server.rack",
                        description: Text("Pick a profile or add one with a provider quickstart.")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showAddSheet) {
            AddServerSheet { server, password in
                if let password, !password.isEmpty {
                    try? DependencyContainer.shared.resolve(KeychainServiceProtocol.self)
                        .savePassword(password, account: server.id.uuidString)
                }
                modelContext.insert(server)
                selectedServer = server
                if session.activeServerID == nil {
                    session.select(server)
                }
            }
            .frame(minWidth: 580, minHeight: 520)
        }
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "ops-servers"
        ) { result in
            if case .failure(let error) = result {
                ioMessage = error.localizedDescription
            } else {
                ioMessage = "Exported \(servers.count) server profiles (passwords excluded)."
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                do {
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url)
                    let dtos = try ServerConfigIO.importJSON(data)
                    for dto in dtos {
                        if servers.contains(where: { $0.id == dto.id || ($0.host == dto.host && $0.username == dto.username) }) {
                            continue
                        }
                        modelContext.insert(dto.makeServer())
                    }
                    ioMessage = "Imported \(dtos.count) profile(s). Re-enter passwords in Keychain as needed."
                } catch {
                    ioMessage = error.localizedDescription
                }
            case .failure(let error):
                ioMessage = error.localizedDescription
            }
        }
        .overlay(alignment: .bottom) {
            if let ioMessage {
                Text(ioMessage)
                    .font(.caption)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding()
            }
        }
    }

    private func serverRow(_ server: Server) -> some View {
        HStack(spacing: BrandSpacing.small) {
            Image(systemName: "server.rack")
                .foregroundStyle(BrandColor.accent)
                .symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 2) {
                Text(server.name).font(.headline)
                Text("\(server.username)@\(server.host):\(server.port)")
                    .font(.caption)
                    .foregroundStyle(BrandColor.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if session.activeServerID == server.id {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(BrandColor.success)
            }
            if server.isFavorite {
                Image(systemName: "star.fill").foregroundStyle(BrandColor.warning).font(.caption)
            }
        }
        .padding(.vertical, 2)
    }

    private func detail(_ server: Server) -> some View {
        Form {
            Section("Profile") {
                LabeledContent("Name", value: server.name)
                LabeledContent("Host") { Text(server.host).font(.body.monospaced()) }
                LabeledContent("Port", value: "\(server.port)")
                LabeledContent("Username", value: server.username)
                LabeledContent("Auth", value: server.authMethod == .sshKey ? "SSH Key" : "Password")
                if let key = server.privateKeyPath, !key.isEmpty {
                    LabeledContent("Key") { Text(key).font(.caption.monospaced()).lineLimit(2) }
                }
                if let group = server.groupName { LabeledContent("Provider", value: group) }
            }
            if let connectionMessage {
                Section { Text(connectionMessage).foregroundStyle(BrandColor.textSecondary) }
            }
            Section {
                Button("Use as Active Host") { session.select(server) }
                Button("Test Connection") { Task { await test(server) } }
                Toggle("Favorite", isOn: Binding(
                    get: { server.isFavorite },
                    set: { server.isFavorite = $0 }
                ))
                Button("Remove Profile", role: .destructive) {
                    try? DependencyContainer.shared.resolve(KeychainServiceProtocol.self)
                        .deletePassword(account: server.id.uuidString)
                    if session.activeServerID == server.id { session.select(nil) }
                    modelContext.delete(server)
                    selectedServer = nil
                }
            }
        }
        .formStyle(.grouped)
        .padding(BrandSpacing.large)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let server = servers[index]
            try? DependencyContainer.shared.resolve(KeychainServiceProtocol.self)
                .deletePassword(account: server.id.uuidString)
            if session.activeServerID == server.id { session.select(nil) }
            modelContext.delete(server)
        }
    }

    @MainActor
    private func test(_ server: Server) async {
        connectionMessage = "Testing…"
        let info = session.resolveConnection(server)
        do {
            let ok = try await DependencyContainer.shared.resolve(SSHServiceProtocol.self).connect(server: info)
            connectionMessage = ok ? "Connection succeeded." : "Connection failed."
        } catch {
            connectionMessage = error.localizedDescription
        }
    }
}

@MainActor
struct AddServerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (Server, String?) -> Void

    @State private var step: Step = .pickProvider
    @State private var provider: ServerProvider = .custom
    @State private var name = ""
    @State private var host = ""
    @State private var port = "22"
    @State private var username = "root"
    @State private var authMethod: Server.AuthMethod = .sshKey
    @State private var privateKeyPath = ""
    @State private var password = ""
    @State private var showImporter = false
    @State private var isTesting = false
    @State private var statusMessage: String?

    private enum Step { case pickProvider, configure }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                switch step {
                case .pickProvider: providerGrid
                case .configure: configureForm
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.data, .item, UTType(filenameExtension: "pem")].compactMap { $0 },
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                privateKeyPath = url.path
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(step == .pickProvider ? "Add Server" : provider.title).font(.headline)
                Text(step == .pickProvider ? "Choose a cloud provider quickstart or custom SSH." : provider.tip)
                    .font(.caption)
                    .foregroundStyle(BrandColor.textSecondary)
                    .lineLimit(3)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(BrandColor.textMuted)
                    .font(.title2)
            }
            .buttonStyle(.plain)
        }
        .padding(BrandSpacing.large)
    }

    private var providerGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: BrandSpacing.medium)], spacing: BrandSpacing.medium) {
                ForEach(ServerProvider.allCases) { item in
                    Button { apply(item) } label: {
                        VStack(alignment: .leading, spacing: BrandSpacing.small) {
                            Image(systemName: item.systemImage)
                                .font(.title2)
                                .foregroundStyle(BrandColor.accent)
                                .symbolRenderingMode(.hierarchical)
                            Text(item.title).font(.headline).foregroundStyle(BrandColor.textPrimary)
                            Text(item.subtitle).font(.caption).foregroundStyle(BrandColor.textSecondary).multilineTextAlignment(.leading)
                        }
                        .padding(BrandSpacing.medium)
                        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
                        .background(BrandColor.surface, in: RoundedRectangle(cornerRadius: BrandSpacing.radiusMedium, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: BrandSpacing.radiusMedium, style: .continuous)
                                .strokeBorder(BrandColor.border.opacity(0.7), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(BrandSpacing.large)
        }
    }

    private var configureForm: some View {
        Form {
            Section("Connection") {
                TextField("Display Name", text: $name)
                TextField("Host", text: $host, prompt: Text(provider.hostPlaceholder))
                TextField("Port", text: $port).frame(maxWidth: 100)
                TextField("Username", text: $username)
            }
            Section("Authentication") {
                Picker("Method", selection: $authMethod) {
                    Text("SSH Key").tag(Server.AuthMethod.sshKey)
                    Text("Password").tag(Server.AuthMethod.password)
                }
                .pickerStyle(.segmented)

                if authMethod == .sshKey {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Private Key")
                            Text(privateKeyPath.isEmpty ? "No key selected" : privateKeyPath)
                                .font(.caption.monospaced())
                                .foregroundStyle(privateKeyPath.isEmpty ? BrandColor.textMuted : BrandColor.textSecondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Button("Choose…") { showImporter = true }
                        if provider == .amazonEC2 {
                            Text(".pem").font(.caption2).foregroundStyle(BrandColor.textMuted)
                        }
                    }
                } else {
                    SecureField("Password", text: $password)
                    Text("Stored securely in macOS Keychain.")
                        .font(.caption)
                        .foregroundStyle(BrandColor.textMuted)
                }
            }
            if let statusMessage {
                Section { Text(statusMessage).foregroundStyle(BrandColor.textSecondary) }
            }
        }
        .formStyle(.grouped)
        .padding(BrandSpacing.medium)
    }

    private var footer: some View {
        HStack {
            if step == .configure {
                Button("Back") { step = .pickProvider; statusMessage = nil }
            }
            Spacer()
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            if step == .configure {
                Button("Test") { Task { await testDraft() } }
                    .disabled(!canSave || isTesting)
                Button("Add Server") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(BrandSpacing.large)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !username.isEmpty
            && Int(port) != nil
            && (authMethod == .password ? !password.isEmpty : !privateKeyPath.isEmpty)
    }

    private func apply(_ item: ServerProvider) {
        provider = item
        name = item.defaultName
        host = ""
        port = "22"
        username = item.suggestedUsername
        authMethod = item.preferredAuth
        privateKeyPath = ""
        password = ""
        statusMessage = nil
        step = .configure
    }

    private func makeServer() -> Server {
        Server(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: Int(port) ?? 22,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            authMethod: authMethod,
            passwordPlain: nil,
            privateKeyPath: authMethod == .sshKey ? privateKeyPath : nil,
            groupName: provider == .custom ? nil : provider.title
        )
    }

    private func save() {
        let server = makeServer()
        onSave(server, authMethod == .password ? password : nil)
        dismiss()
    }

    @MainActor
    private func testDraft() async {
        isTesting = true
        statusMessage = "Testing connection…"
        var info = makeServer().connectionInfo
        if authMethod == .password { info.passwordPlain = password }
        do {
            _ = try await DependencyContainer.shared.resolve(SSHServiceProtocol.self).connect(server: info)
            statusMessage = "Looks good — you can add this server."
        } catch {
            statusMessage = error.localizedDescription
        }
        isTesting = false
    }
}

struct ServersExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
