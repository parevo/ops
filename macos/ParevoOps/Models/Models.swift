import Foundation
import SwiftData

/// Persisted Server node profile using SwiftData.
@Model
public final class Server {
    @Attribute(.unique) public var id: String
    public var name: String
    public var host: String
    public var port: Int
    public var username: String
    public var privateKeyPath: String?
    public var groupName: String
    public var tags: String
    
    public init(id: String = UUID().uuidString,
                name: String,
                host: String,
                port: Int = 22,
                username: String = "ubuntu",
                privateKeyPath: String? = nil,
                groupName: String = "production",
                tags: String = "") {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.privateKeyPath = privateKeyPath
        self.groupName = groupName
        self.tags = tags
    }
}

/// Docker container info detail.
public struct ContainerInfo: Identifiable, Codable {
    public var id: String
    public var name: String
    public var image: String
    public var status: String
    public var state: String
    
    public init(id: String, name: String, image: String, status: String, state: String) {
        self.id = id
        self.name = name
        self.image = image
        self.status = status
        self.state = state
    }
}

/// systemd remote service information.
public struct ServiceInfo: Identifiable, Codable {
    public var id: String { name }
    public var name: String
    public var loadState: String
    public var activeState: String
    public var subState: String
    public var description: String
    
    public init(name: String, loadState: String, activeState: String, subState: String, description: String) {
        self.name = name
        self.loadState = loadState
        self.activeState = activeState
        self.subState = subState
        self.description = description
    }
}

/// Log message details.
public struct LogMessage: Identifiable, Codable {
    public var id: String { timestamp + message }
    public var source: String
    public var level: String
    public var message: String
    public var timestamp: String
    
    public init(source: String, level: String, message: String, timestamp: String) {
        self.source = source
        self.level = level
        self.message = message
        self.timestamp = timestamp
    }
}

/// CPU, RAM, and Disk metrics.
public struct SystemMetrics: Codable {
    public var cpuUsage: Float
    public var memoryUsage: Float
    public var diskUsage: Float
    
    public init(cpuUsage: Float, memoryUsage: Float, diskUsage: Float) {
        self.cpuUsage = cpuUsage
        self.memoryUsage = memoryUsage
        self.diskUsage = diskUsage
    }
}

/// AI SRE Diagnostic report.
public struct DiagnosticReport: Codable {
    public var rootCause: String
    public var evidence: String
    public var suggestedFix: String
    public var confidence: Double
    
    public init(rootCause: String, evidence: String, suggestedFix: String, confidence: Double) {
        self.rootCause = rootCause
        self.evidence = evidence
        self.suggestedFix = suggestedFix
        self.confidence = confidence
    }
}
