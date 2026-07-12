import Foundation
import SwiftUI
import SwiftData

@Observable
@MainActor
public final class AppSession {
    public var activeServerID: UUID?
    public var terminalVisible = false
    public var terminalHeight: CGFloat = 260
    public var lastErrorMessage: String?

    public init() {}

    public func connectionInfo(from servers: [Server]) -> SSHConnectionInfo? {
        guard let id = activeServerID,
              let server = servers.first(where: { $0.id == id }) else { return nil }
        return resolveConnection(server)
    }

    public func server(from servers: [Server]) -> Server? {
        guard let id = activeServerID else { return nil }
        return servers.first(where: { $0.id == id })
    }

    public func select(_ server: Server?) {
        activeServerID = server?.id
    }

    public func resolveConnection(_ server: Server) -> SSHConnectionInfo {
        var info = server.connectionInfo
        if info.authMethod == .password {
            let keychain = DependencyContainer.shared.resolve(KeychainServiceProtocol.self)
            info.passwordPlain = try? keychain.loadPassword(account: server.id.uuidString)
        }
        return info
    }

    public func requireConnection(from servers: [Server]) throws -> SSHConnectionInfo {
        guard let info = connectionInfo(from: servers) else {
            throw OpsError.noActiveServer
        }
        return info
    }
}
