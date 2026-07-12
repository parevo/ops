import Foundation

public struct ServerExportDTO: Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var host: String
    public var port: Int
    public var username: String
    public var authMethod: String
    public var privateKeyPath: String?
    public var groupName: String?
    public var tags: [String]
    public var isFavorite: Bool

    public init(from server: Server) {
        id = server.id
        name = server.name
        host = server.host
        port = server.port
        username = server.username
        authMethod = server.authMethod.rawValue
        privateKeyPath = server.privateKeyPath
        groupName = server.groupName
        tags = server.tags
        isFavorite = server.isFavorite
    }

    public func makeServer() -> Server {
        Server(
            id: id,
            name: name,
            host: host,
            port: port,
            username: username,
            authMethod: Server.AuthMethod(rawValue: authMethod) ?? .password,
            passwordPlain: nil,
            privateKeyPath: privateKeyPath,
            groupName: groupName,
            tags: tags,
            isFavorite: isFavorite
        )
    }
}

public enum ServerConfigIO {
    public static func exportJSON(servers: [Server]) throws -> Data {
        let dtos = servers.map(ServerExportDTO.init(from:))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(dtos)
    }

    public static func importJSON(_ data: Data) throws -> [ServerExportDTO] {
        try JSONDecoder().decode([ServerExportDTO].self, from: data)
    }
}
