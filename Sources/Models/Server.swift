import Foundation
import SwiftData

@Model
public final class Server {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var host: String
    public var port: Int
    public var username: String
    public var authMethodRawValue: String
    public var passwordPlain: String? // Key references will be stored via Keychain layer
    public var privateKeyPath: String?
    public var groupName: String?
    public var tags: [String]
    public var isFavorite: Bool
    public var createdAt: Date

    public enum AuthMethod: String, Codable, CaseIterable, Sendable {
        case password
        case sshKey
    }

    public var authMethod: AuthMethod {
        get { AuthMethod(rawValue: authMethodRawValue) ?? .password }
        set { authMethodRawValue = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int = 22,
        username: String = "root",
        authMethod: AuthMethod = .password,
        passwordPlain: String? = nil,
        privateKeyPath: String? = nil,
        groupName: String? = nil,
        tags: [String] = [],
        isFavorite: Bool = false
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.authMethodRawValue = authMethod.rawValue
        self.passwordPlain = passwordPlain
        self.privateKeyPath = privateKeyPath
        self.groupName = groupName
        self.tags = tags
        self.isFavorite = isFavorite
        self.createdAt = Date()
    }
}

// MARK: - Sendable SSH Connection Parameters Struct
public struct SSHConnectionInfo: Sendable, Codable, Hashable {
    public var name: String
    public var host: String
    public var port: Int
    public var username: String
    public var authMethod: Server.AuthMethod
    public var passwordPlain: String?
    public var privateKeyPath: String?
    public var serverID: UUID?

    public init(
        name: String,
        host: String,
        port: Int = 22,
        username: String = "root",
        authMethod: Server.AuthMethod = .password,
        passwordPlain: String? = nil,
        privateKeyPath: String? = nil,
        serverID: UUID? = nil
    ) {
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.authMethod = authMethod
        self.passwordPlain = passwordPlain
        self.privateKeyPath = privateKeyPath
        self.serverID = serverID
    }

    /// Shared ControlMaster socket path (must match SSHService).
    public var controlSocketPath: String {
        let safeHost = host.replacingOccurrences(of: ":", with: "_")
        let safeUser = username.replacingOccurrences(of: "/", with: "_")
        return "/tmp/parevo-ssh-\(safeUser)-\(safeHost)-\(port)"
    }
}

extension Server {
    public var connectionInfo: SSHConnectionInfo {
        SSHConnectionInfo(
            name: name,
            host: host,
            port: port,
            username: username,
            authMethod: authMethod,
            passwordPlain: passwordPlain,
            privateKeyPath: privateKeyPath,
            serverID: id
        )
    }
}
