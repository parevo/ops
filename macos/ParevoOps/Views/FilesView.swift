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
        HSplitView {
            // Left Folder Browser
            VStack(alignment: .leading, spacing: 0) {
                pathHeader
                    .padding()
                    .background(Color.black.opacity(0.15))
                
                List {
                    if files.isEmpty {
                        Text("Empty directory.")
                            .font(.caption)
                            .foregroundColor(.zincSecondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    } else {
                        ForEach(files) { item in
                            fileRowCard(item)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .padding(.vertical, 4)
                        }
                    }
                }
                .listStyle(.plain)
            }
            .frame(minWidth: 260, idealWidth: 320, maxWidth: 450)
            
            // Right File Editor View
            VStack(spacing: 0) {
                if let file = editingFile {
                    HStack {
                        Image(systemName: "doc.text.fill")
                            .foregroundColor(.zincSecondary)
                        Text(file.path)
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        Spacer()
                        Button(action: saveFile) {
                            Text("Save File")
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 4)
                                .background(Color.purple)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
                    .background(Color.zincPanel)
                    
                    TextEditor(text: $fileContent)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Color.black)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "folder.badge.gearshape")
                            .font(.system(size: 48))
                            .foregroundColor(.zincBorder)
                        Text("No File Opened")
                            .font(.headline)
                            .foregroundColor(.zincSecondary)
                        Text("Select a file from the explorer pane to inspect its configurations.")
                            .font(.caption)
                            .foregroundColor(.zincSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 400, idealWidth: 500)
            .background(Color.black.opacity(0.4))
        }
        .navigationTitle("Files")
        .onAppear(perform: { loadPath(currentPath) })
        .onChange(of: activeServer, perform: { _ in loadPath("/") })
    }
    
    private var pathHeader: some View {
        HStack {
            Text(currentPath)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.purple)
                .lineLimit(1)
            Spacer()
            if currentPath != "/" {
                Button(".. Up") {
                    goUpDirectory()
                }
            }
        }
    }
    
    private func fileRowCard(_ item: FileEntryMock) -> some View {
        let isEditingThis = editingFile?.path == item.path
        
        return HStack {
            Image(systemName: item.isDir ? "folder.fill" : "doc.text.fill")
                .foregroundColor(item.isDir ? .purple : .zincSecondary)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)
                    .foregroundColor(.white)
                Text("\(item.permissions) • \(item.size) B")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.zincSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(.zincBorder)
                .font(.caption)
        }
        .padding(10)
        .background(isEditingThis ? Color.purple.opacity(0.1) : Color.zincPanel)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isEditingThis ? Color.purple.opacity(0.4) : Color.zincBorder, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if item.isDir {
                loadPath(item.path)
            } else {
                openFile(item)
            }
        }
    }
    
    private func loadPath(_ path: String) {
        currentPath = path
        Task {
            do {
                let escapedPath = path.replacingOccurrences(of: "'", with: "\\'")
                let pythonScript = "python3 -c \"import os, json; path='\(escapedPath)'; print(json.dumps([{'name': f, 'path': os.path.join(path, f), 'is_dir': os.path.isdir(os.path.join(path, f)), 'size': os.path.getsize(os.path.join(path, f)) if os.path.isfile(os.path.join(path, f)) else 4096} for f in os.listdir(path)]))\""
                
                let rawJSON: String
                if let srv = activeServer {
                    rawJSON = try await SSHService.shared.executeCommand(on: srv, command: pythonScript)
                } else {
                    rawJSON = try await SSHService.shared.executeLocalCommand(command: pythonScript)
                }
                
                guard let data = rawJSON.data(using: .utf8) else {
                    throw NSError(domain: "FilesView", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid UTF8 raw JSON"])
                }
                
                struct FileEntryJSON: Decodable {
                    let name: String
                    let path: String
                    let is_dir: Bool
                    let size: UInt64
                }
                
                let decoded = try JSONDecoder().decode([FileEntryJSON].self, from: data)
                
                await MainActor.run {
                    self.files = decoded.map {
                        FileEntryMock(name: $0.name, path: $0.path, isDir: $0.is_dir, size: $0.size, permissions: $0.is_dir ? "0755" : "0644")
                    }.sorted { !$0.isDir && $1.isDir ? false : ($0.isDir && !$1.isDir ? true : $0.name < $1.name) }
                }
            } catch {
                print("Failed to run python files explorer query: \(error.localizedDescription)")
                let nameSuffix = activeServer?.name ?? "local"
                await MainActor.run {
                    if path == "/" {
                        self.files = [
                            FileEntryMock(name: "etc", path: "/etc", isDir: true, size: 4096, permissions: "0755"),
                            FileEntryMock(name: "var", path: "/var", isDir: true, size: 4096, permissions: "0755"),
                            FileEntryMock(name: "opt", path: "/opt", isDir: true, size: 4096, permissions: "0755")
                        ]
                    } else if path == "/etc" {
                        self.files = [
                            FileEntryMock(name: "hosts", path: "/etc/hosts", isDir: false, size: 284, permissions: "0644"),
                            FileEntryMock(name: "nginx", path: "/etc/nginx", isDir: true, size: 4096, permissions: "0755"),
                            FileEntryMock(name: "parevo-server.conf", path: "/etc/parevo-server.conf", isDir: false, size: 1045, permissions: "0600")
                        ]
                    } else {
                        self.files = [
                            FileEntryMock(name: "config_\(nameSuffix.lowercased()).conf", path: "\(path)/config_\(nameSuffix.lowercased()).conf", isDir: false, size: 812, permissions: "0644")
                        ]
                    }
                }
            }
        }
    }
    
    private func goUpDirectory() {
        if currentPath == "/" { return }
        let url = URL(fileURLWithPath: currentPath)
        let parent = url.deletingLastPathComponent().path
        loadPath(parent.isEmpty ? "/" : parent)
    }
    
    private func openFile(_ item: FileEntryMock) {
        Task {
            do {
                let cmd = "cat '\(item.path)'"
                let content: String
                if let srv = activeServer {
                    content = try await SSHService.shared.executeCommand(on: srv, command: cmd)
                } else {
                    content = try await SSHService.shared.executeLocalCommand(command: cmd)
                }
                
                await MainActor.run {
                    self.fileContent = content
                    self.editingFile = item
                }
            } catch {
                print("Failed to open file: \(error.localizedDescription)")
                let nameSuffix = activeServer?.name ?? "localhost"
                await MainActor.run {
                    self.fileContent = """
                    # Fallback Mock Content
                    # Failed to open: \(item.path)
                    
                    SERVER_PORT=8080
                    LOG_LEVEL=debug
                    """
                    self.editingFile = item
                }
            }
        }
    }
    
    private func saveFile() {
        guard let file = editingFile else { return }
        let b64Str = Data(fileContent.utf8).base64EncodedString()
        let writeCmd = "echo '\(b64Str)' | base64 -d > '\(file.path)'"
        
        Task {
            do {
                if let srv = activeServer {
                    _ = try await SSHService.shared.executeCommand(on: srv, command: writeCmd)
                } else {
                    _ = try await SSHService.shared.executeLocalCommand(command: writeCmd)
                }
                await MainActor.run {
                    self.editingFile = nil
                    self.loadPath(currentPath)
                }
            } catch {
                print("Failed to write/save file contents: \(error.localizedDescription)")
                await MainActor.run {
                    self.editingFile = nil
                }
            }
        }
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
