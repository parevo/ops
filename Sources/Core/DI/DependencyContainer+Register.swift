import Foundation

extension DependencyContainer {
    public func registerDefaultServices() {
        register(KeychainServiceProtocol.self) { KeychainService() }
        register(SSHServiceProtocol.self) { SSHService() }
        register(DockerServiceProtocol.self) { DockerService() }
        register(CronServiceProtocol.self) { CronService() }
        register(FileServiceProtocol.self) { FileService() }
        register(LogServiceProtocol.self) { LogService() }
        register(MetricsServiceProtocol.self) { MetricsService() }
        register(MemoryServiceProtocol.self) { MemoryEngine() }
        register(SystemdServiceProtocol.self) { SystemdService() }
        register(DeployServiceProtocol.self) { DeployService() }
    }
}
