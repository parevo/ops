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

public struct ComposeServiceInfo: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var state: String
    public var status: String
    public var ports: String

    public init(id: String, name: String, state: String, status: String, ports: String) {
        self.id = id
        self.name = name
        self.state = state
        self.status = status
        self.ports = ports
    }

    public var isRunning: Bool {
        state.lowercased() == "running"
    }
}

public struct ContainerInspectSummary: Hashable, Sendable {
    public var env: [String]
    public var mounts: [String]
    public var ports: [String]
    public var cmd: String
    public var image: String
    public var networkMode: String
    public var restartPolicy: String
    public var memoryLimit: String
    public var cpuShares: String
    public var rawJSON: String

    public init(
        env: [String] = [],
        mounts: [String] = [],
        ports: [String] = [],
        cmd: String = "",
        image: String = "",
        networkMode: String = "",
        restartPolicy: String = "",
        memoryLimit: String = "—",
        cpuShares: String = "—",
        rawJSON: String = ""
    ) {
        self.env = env
        self.mounts = mounts
        self.ports = ports
        self.cmd = cmd
        self.image = image
        self.networkMode = networkMode
        self.restartPolicy = restartPolicy
        self.memoryLimit = memoryLimit
        self.cpuShares = cpuShares
        self.rawJSON = rawJSON
    }
}

public struct DeployStep: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var detail: String
    public var isSuccess: Bool
    public var timestamp: Date

    public init(id: UUID = UUID(), title: String, detail: String, isSuccess: Bool, timestamp: Date = Date()) {
        self.id = id
        self.title = title
        self.detail = detail
        self.isSuccess = isSuccess
        self.timestamp = timestamp
    }
}

public struct CommandHistoryEntry: Identifiable, Hashable, Sendable {
    public var id: String
    public var command: String
    public var directory: String
    public var exitCode: Int
    public var isSuccess: Bool
    public var serverId: UUID?
    public var projectId: UUID?
    public var timestamp: Date

    public init(
        id: String,
        command: String,
        directory: String,
        exitCode: Int,
        isSuccess: Bool,
        serverId: UUID?,
        projectId: UUID?,
        timestamp: Date
    ) {
        self.id = id
        self.command = command
        self.directory = directory
        self.exitCode = exitCode
        self.isSuccess = isSuccess
        self.serverId = serverId
        self.projectId = projectId
        self.timestamp = timestamp
    }
}

public struct FleetHostMetrics: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var host: String
    public var metrics: SystemMetrics?
    public var error: String?

    public init(id: UUID, name: String, host: String, metrics: SystemMetrics? = nil, error: String? = nil) {
        self.id = id
        self.name = name
        self.host = host
        self.metrics = metrics
        self.error = error
    }
}

public struct SystemdServiceInfo: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var unit: String
    public var load: String
    public var active: String
    public var sub: String
    public var description: String

    public init(id: String? = nil, unit: String, load: String, active: String, sub: String, description: String) {
        self.id = id ?? unit
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
