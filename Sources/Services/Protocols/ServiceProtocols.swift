import Foundation

public enum SSHStreamEvent: Sendable {
    case chunk(String)
    case exit(code: Int)
}

public protocol SSHServiceProtocol: Sendable {
    func connect(server: SSHConnectionInfo) async throws -> Bool
    func executeCommand(_ command: String, on server: SSHConnectionInfo) async throws -> (output: String, exitCode: Int)
    func streamCommand(_ command: String, on server: SSHConnectionInfo) -> AsyncThrowingStream<SSHStreamEvent, Error>
    func disconnect(server: SSHConnectionInfo) async
}

public protocol DockerServiceProtocol: Sendable {
    func fetchContainers(for server: SSHConnectionInfo) async throws -> [ContainerInfo]
    func startContainer(id: String, on server: SSHConnectionInfo) async throws
    func stopContainer(id: String, on server: SSHConnectionInfo) async throws
    func restartContainer(id: String, on server: SSHConnectionInfo) async throws
    func deleteContainer(id: String, on server: SSHConnectionInfo) async throws
    func inspectContainer(id: String, on server: SSHConnectionInfo) async throws -> String
    func fetchImages(for server: SSHConnectionInfo) async throws -> [DockerImageInfo]
    func fetchVolumes(for server: SSHConnectionInfo) async throws -> [DockerVolumeInfo]
    func fetchNetworks(for server: SSHConnectionInfo) async throws -> [DockerNetworkInfo]
    func fetchComposeProjects(for server: SSHConnectionInfo) async throws -> [ComposeProjectInfo]
    func composeUp(project: String, on server: SSHConnectionInfo) async throws
    func composeDown(project: String, on server: SSHConnectionInfo) async throws
}

public protocol CronServiceProtocol: Sendable {
    func fetchCronJobs(for server: SSHConnectionInfo) async throws -> [CronJobInfo]
    func runCronJob(id: String, on server: SSHConnectionInfo) async throws
}

public protocol FileServiceProtocol: Sendable {
    func listFiles(path: String, on server: SSHConnectionInfo) async throws -> [FileInfo]
    func readFile(path: String, on server: SSHConnectionInfo) async throws -> String
    func writeFile(path: String, content: String, on server: SSHConnectionInfo) async throws
    func deletePath(_ path: String, on server: SSHConnectionInfo) async throws
}

public protocol LogServiceProtocol: Sendable {
    func fetchStaticLogs(source: String, on server: SSHConnectionInfo) async throws -> [String]
    func streamLogs(source: String, on server: SSHConnectionInfo) -> AsyncThrowingStream<String, Error>
}

public protocol MetricsServiceProtocol: Sendable {
    func fetchLiveMetrics(for server: SSHConnectionInfo) async throws -> SystemMetrics
}

public protocol MemoryServiceProtocol: Sendable {
    func recordCommand(
        command: String,
        directory: String,
        exitCode: Int,
        isSuccess: Bool,
        serverId: UUID?,
        projectId: UUID?
    ) async throws
    func getSmartSuggestions(input: String, serverId: UUID?, projectId: UUID?) async throws -> [String]
    func getPatternNextStep(currentCommand: String, serverId: UUID?, projectId: UUID?) async throws -> String?
}

public protocol SystemdServiceProtocol: Sendable {
    func fetchServices(for server: SSHConnectionInfo) async throws -> [SystemdServiceInfo]
    func restart(unit: String, on server: SSHConnectionInfo) async throws
    func stop(unit: String, on server: SSHConnectionInfo) async throws
    func start(unit: String, on server: SSHConnectionInfo) async throws
    func enable(unit: String, on server: SSHConnectionInfo) async throws
    func disable(unit: String, on server: SSHConnectionInfo) async throws
}

public protocol DeployServiceProtocol: Sendable {
    func deploy(directory: String, on server: SSHConnectionInfo) async throws -> String
    func rollbackHint(directory: String, on server: SSHConnectionInfo) async throws -> String
    func recentEvents(directory: String, on server: SSHConnectionInfo) async throws -> [DeploymentEvent]
}
