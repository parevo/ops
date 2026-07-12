import Foundation

public final class FileService: FileServiceProtocol {
    public init() {}

    private var ssh: SSHServiceProtocol {
        DependencyContainer.shared.resolve(SSHServiceProtocol.self)
    }

    public func listFiles(path: String, on server: SSHConnectionInfo) async throws -> [FileInfo] {
        let safePath = path.isEmpty ? "/" : path
        let quoted = shellQuote(safePath)
        let cmd = "ls -la --time-style=+%s \(quoted)"
        let res = try await ssh.executeCommand(cmd, on: server)
        guard res.exitCode == 0 else {
            throw OpsError.fileOperation(res.output.isEmpty ? "Unable to list \(safePath)" : res.output)
        }

        var files: [FileInfo] = []
        for line in res.output.components(separatedBy: .newlines) {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 7 else { continue }
            let permissions = String(parts[0])
            if permissions.hasPrefix("total") { continue }
            guard let size = Int64(parts[4]), let epoch = Double(parts[5]) else { continue }
            let name = parts[6...].joined(separator: " ")
            if name == "." || name == ".." { continue }
            let fullPath = safePath == "/" ? "/\(name)" : "\(safePath)/\(name)"
            files.append(FileInfo(
                name: name,
                path: fullPath,
                isDirectory: permissions.hasPrefix("d"),
                size: size,
                permissions: permissions,
                lastModified: Date(timeIntervalSince1970: epoch),
                owner: String(parts[2]),
                group: String(parts[3])
            ))
        }

        return files.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    public func readFile(path: String, on server: SSHConnectionInfo) async throws -> String {
        let res = try await ssh.executeCommand("cat \(shellQuote(path))", on: server)
        guard res.exitCode == 0 else {
            throw OpsError.fileOperation(res.output)
        }
        return res.output
    }

    public func writeFile(path: String, content: String, on server: SSHConnectionInfo) async throws {
        guard let base64 = content.data(using: .utf8)?.base64EncodedString() else {
            throw OpsError.fileOperation("Unable to encode file content.")
        }
        let cmd = "echo \(shellQuote(base64)) | base64 -d > \(shellQuote(path))"
        let res = try await ssh.executeCommand(cmd, on: server)
        guard res.exitCode == 0 else {
            throw OpsError.fileOperation(res.output)
        }
    }

    public func deletePath(_ path: String, on server: SSHConnectionInfo) async throws {
        let res = try await ssh.executeCommand("rm -rf \(shellQuote(path))", on: server)
        guard res.exitCode == 0 else {
            throw OpsError.fileOperation(res.output)
        }
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
