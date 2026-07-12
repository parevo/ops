import Foundation

public struct ContainerInfo: Identifiable, Codable, Hashable {
    public var id: String
    public var name: String
    public var image: String
    public var status: String
    public var state: String
    public var ports: String
    public var created: String

    public init(id: String, name: String, image: String, status: String, state: String, ports: String, created: String) {
        self.id = id
        self.name = name
        self.image = image
        self.status = status
        self.state = state
        self.ports = ports
        self.created = created
    }
    
    public var isRunning: Bool {
        state.lowercased() == "running"
    }
}
