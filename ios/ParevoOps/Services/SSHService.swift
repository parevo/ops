import Foundation

/// SSH remote connection manager and command executor.
public final class SSHService {
    public static let shared = SSHService()
    
    private init() {}
    
    /// Simulates executing a remote shell command on a server node.
    public func executeCommand(on server: Server, command: String) async throws -> String {
        // Simulate minor network delay
        try await Task.sleep(nanoseconds: 600_000_000)
        
        // Auto-chmod simulation warning if key path has bad permissions (mock check)
        if let key = server.privateKeyPath {
            if key.isEmpty {
                throw NSError(domain: "SSHService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Identity file path cannot be empty"])
            }
            print("SSHService: Automatically setting secure permissions (0600) on private key: \(key)")
        }
        
        // Simulate command output
        switch command {
        case "echo 'ping'":
            return "ping: success"
        case "docker ps --format '{{json .}}'":
            return """
            {"ID":"ae834927","Names":"\(server.name.lowercased())-web-nginx","Image":"nginx:alpine","Status":"Up 4 hours","State":"running"}
            {"ID":"bf394829","Names":"\(server.name.lowercased())-postgres-db","Image":"postgres:15-alpine","Status":"Up 2 days","State":"running"}
            """
        case "free -m":
            return "total: 8192, used: 4120, free: 4072"
        default:
            return "Successfully executed '\(command)' on \(server.host)"
        }
    }
    
    /// Tests SSH credentials connection status.
    public func testConnection(on server: Server) async throws -> Bool {
        // Validate host address
        if server.host.isEmpty {
            throw NSError(domain: "SSHService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Host address cannot be empty"])
        }
        
        // Simulate connection sequence
        try await Task.sleep(nanoseconds: 800_000_000)
        
        if server.host == "127.0.0.1" || server.host == "localhost" {
            return true
        }
        
        // Simulate authentication error if host contains "fail"
        if server.host.lowercased().contains("fail") {
            throw NSError(domain: "SSHService", code: 142, userInfo: [NSLocalizedDescriptionKey: "Connection timed out (SIGALRM/142). Please verify your AWS Security Groups allow port 22 access."])
        }
        
        return true
    }
}
