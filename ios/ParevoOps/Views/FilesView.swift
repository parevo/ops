import SwiftUI

public struct FilesView: View {
    @Binding public var activeServer: Server?
    @State private var currentPath = "/"
    @State private var files: [FileEntryMock] = []
    
    // File editor details
    @State private var editingFile: FileEntryMock? = nil
    @State private var fileContent = ""
    
    public init(activeServer: Binding<Server?>) {
        self._activeServer = activeServer
    }
    
    public var body: some View {
        NavigationStack {
            List {
                Section(header: pathHeader) {
                    if files.isEmpty {
                        Text("Empty directory.")
                            .font(.caption)
                            .foregroundColor(.zincSecondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        ForEach(files) { item in
                            fileRowCard(item)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }
                }
            }
            .navigationTitle("Files")
            .background(Color(red: 0.03, green: 0.03, blue: 0.05))
            .onAppear(perform: { loadPath(currentPath) })
            .onChange(of: activeServer, perform: { _ in loadPath("/") })
            .sheet(item: $editingFile) { file in
                fileEditorSheet(file)
            }
        }
    }
    
    private var pathHeader: some View {
        HStack {
            Text(currentPath)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.purple)
            Spacer()
            if currentPath != "/" {
                Button(action: goUpDirectory) {
                    Text(".. Go Up")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.zincSecondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func fileRowCard(_ item: FileEntryMock) -> some View {
        HStack {
            Image(systemName: item.isDir ? "folder.fill" : "doc.text.fill")
                .foregroundColor(item.isDir ? .purple : .zincSecondary)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)
                    .foregroundColor(.white)
                Text("\(item.permissions) • \(item.size) Bytes")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.zincSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(.zincBorder)
                .font(.caption)
        }
        .padding()
        .background(Color.zincPanel)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.zincBorder, lineWidth: 1)
        )
        .padding(.horizontal)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if item.isDir {
                loadPath(item.path)
            } else {
                openFile(item)
            }
        }
    }
    
    private func fileEditorSheet(_ file: FileEntryMock) -> some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $fileContent)
                    .font(.system(.subheadline, design: .monospaced))
                    .padding()
                    .background(Color.zincPanel)
                    .foregroundColor(.white)
            }
            .navigationTitle(file.name)
            .navigationBarTitleDisplayMode(.inline)
            .background(Color.zincPanel)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        editingFile = nil
                    }
                    .foregroundColor(.zincSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveFile()
                    }
                    .foregroundColor(.purple)
                }
            }
        }
    }
    
    private func loadPath(_ path: String) {
        currentPath = path
        let nameSuffix = activeServer?.name ?? "local"
        
        if path == "/" {
            files = [
                FileEntryMock(name: "etc", path: "/etc", isDir: true, size: 4096, permissions: "0755"),
                FileEntryMock(name: "var", path: "/var", isDir: true, size: 4096, permissions: "0755"),
                FileEntryMock(name: "opt", path: "/opt", isDir: true, size: 4096, permissions: "0755")
            ]
        } else if path == "/etc" {
            files = [
                FileEntryMock(name: "hosts", path: "/etc/hosts", isDir: false, size: 284, permissions: "0644"),
                FileEntryMock(name: "nginx", path: "/etc/nginx", isDir: true, size: 4096, permissions: "0755"),
                FileEntryMock(name: "parevo-server.conf", path: "/etc/parevo-server.conf", isDir: false, size: 1045, permissions: "0600")
            ]
        } else {
            files = [
                FileEntryMock(name: "config_\(nameSuffix.lowercased()).conf", path: "\(path)/config_\(nameSuffix.lowercased()).conf", isDir: false, size: 812, permissions: "0644")
            ]
        }
    }
    
    private func goUpDirectory() {
        if currentPath == "/etc/nginx" {
            loadPath("/etc")
        } else {
            loadPath("/")
        }
    }
    
    private func openFile(_ item: FileEntryMock) {
        let nameSuffix = activeServer?.name ?? "localhost"
        fileContent = """
        # Parevo Config File for \(nameSuffix) Node
        # Path: \(item.path)
        # Modified locally on iOS Client
        
        SERVER_PORT=8080
        LOG_LEVEL=debug
        ENABLE_SWAP=true
        MAX_WORKER_CONNS=1024
        """
        editingFile = item
    }
    
    private func saveFile() {
        editingFile = nil
        loadPath(currentPath)
    }
}

/// Identifiable representation of mock file.
struct FileEntryMock: Identifiable {
    var id: String { path }
    var name: String
    var path: String
    var isDir: Bool
    var size: UInt64
    var permissions: String
    
    init(name: String, path: String, isDir: Bool, size: UInt64, permissions: String) {
        self.name = name
        self.path = path
        self.isDir = isDir
        self.size = size
        self.permissions = permissions
    }
}
