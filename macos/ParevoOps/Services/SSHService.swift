import Foundation

/// SSH remote connection manager and command executor using native macOS ssh client.
public final class SSHService {
    public static let shared = SSHService()
    
    private init() {}
    
    /// Executes a command locally on macOS.
    public func executeLocalCommand(command: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        try process.run()
        process.waitUntilExit()
        
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        
        if process.terminationStatus != 0 {
            let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown local execution error"
            throw NSError(domain: "SSHService", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
        
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    /// Executes a remote shell command on a server node via macOS pre-installed /usr/bin/ssh client.
    public func executeCommand(on server: Server, command: String) async throws -> String {
        // Automatically enforce secure permissions (0600) on private key if provided
        if let key = server.privateKeyPath, !key.isEmpty {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: key) {
                // Execute chmod 600 locally on the keyfile
                do {
                    _ = try await executeLocalCommand(command: "chmod 600 \(key)")
                } catch {
                    print("SSHService warning: Failed to enforce 0600 on keyfile: \(error.localizedDescription)")
                }
            } else {
                throw NSError(domain: "SSHService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Private key file not found at path: \(key)"])
            }
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        
        var args = [
            "-o", "ConnectTimeout=6",
            "-o", "StrictHostKeyChecking=no",
            "-o", "BatchMode=yes",
            "-o", "PubkeyAuthentication=yes"
        ]
        
        if let key = server.privateKeyPath, !key.isEmpty {
            args.append("-i")
            args.append(key)
        }
        
        args.append("-p")
        args.append(String(server.port))
        
        args.append("\(server.username)@\(server.host)")
        args.append(command)
        
        process.arguments = args
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        try process.run()
        process.waitUntilExit()
        
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        
        if process.terminationStatus != 0 {
            let errorMsg = String(data: errorData, encoding: .utf8) ?? "Connection failure or non-zero exit code"
            // Map common SSH exit statuses for user readability
            if process.terminationStatus == 255 {
                throw NSError(domain: "SSHService", code: 255, userInfo: [NSLocalizedDescriptionKey: "Authentication failed or host unreachable. Details: \(errorMsg.trimmingCharacters(in: .whitespacesAndNewlines))"])
            }
            throw NSError(domain: "SSHService", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errorMsg.trimmingCharacters(in: .whitespacesAndNewlines)])
        }
        
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    /// Tests SSH credentials connection status.
    public func testConnection(on server: Server) async throws -> Bool {
        if server.host.isEmpty {
            throw NSError(domain: "SSHService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Host address cannot be empty"])
        }
        
        // Execute simple echo ping
        _ = try await executeCommand(on: server, command: "echo 'ping'")
        return true
    }
}
