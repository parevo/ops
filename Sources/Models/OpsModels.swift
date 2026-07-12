import Foundation

public struct DockerImageInfo: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var repository: String
    public var tag: String
    public var size: String
    public var created: String

    public init(id: String, repository: String, tag: String, size: String, created: String) {
        self.id = id
        self.repository = repository
        self.tag = tag
        self.size = size
        self.created = created
    }

    public var displayName: String {
        tag.isEmpty || tag == "<none>" ? repository : "\(repository):\(tag)"
    }
}

public struct DockerVolumeInfo: Identifiable, Codable, Hashable, Sendable {
    public var id: String { name }
    public var name: String
    public var driver: String
    public var mountpoint: String

    public init(name: String, driver: String, mountpoint: String) {
        self.name = name
        self.driver = driver
        self.mountpoint = mountpoint
    }
}

public struct DockerNetworkInfo: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var driver: String
    public var scope: String

    public init(id: String, name: String, driver: String, scope: String) {
        self.id = id
        self.name = name
        self.driver = driver
        self.scope = scope
    }
}

public struct ComposeProjectInfo: Identifiable, Codable, Hashable, Sendable {
    public var id: String { name }
    public var name: String
    public var status: String
    public var configFiles: String

    public init(name: String, status: String, configFiles: String) {
        self.name = name
        self.status = status
        self.configFiles = configFiles
    }
}

public struct SystemdServiceInfo: Identifiable, Codable, Hashable, Sendable {
    public var id: String { unit }
    public var unit: String
    public var load: String
    public var active: String
    public var sub: String
    public var description: String

    public init(unit: String, load: String, active: String, sub: String, description: String) {
        self.unit = unit
        self.load = load
        self.active = active
        self.sub = sub
        self.description = description
    }

    public var isRunning: Bool { active == "active" && sub == "running" }
}

public struct DeploymentEvent: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var detail: String
    public var timestamp: Date
    public var kind: String

    public init(id: UUID = UUID(), title: String, detail: String, timestamp: Date = Date(), kind: String) {
        self.id = id
        self.title = title
        self.detail = detail
        self.timestamp = timestamp
        self.kind = kind
    }
}
