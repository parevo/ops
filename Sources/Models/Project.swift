import Foundation
import SwiftData

@Model
public final class Project {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var projectDescription: StringText // Renamed to avoid keyword collision if any
    public var serverId: UUID?
    public var directoryPath: String
    public var composeFiles: [String]
    public var gitUrl: String?
    public var tags: [String]
    public var createdAt: Date

    // Support SwiftData compat for large text fields
    public typealias StringText = String

    public init(
        id: UUID = UUID(),
        name: String,
        projectDescription: String = "",
        serverId: UUID? = nil,
        directoryPath: String = "",
        composeFiles: [String] = [],
        gitUrl: String? = nil,
        tags: [String] = []
    ) {
        self.id = id
        self.name = name
        self.projectDescription = projectDescription
        self.serverId = serverId
        self.directoryPath = directoryPath
        self.composeFiles = composeFiles
        self.gitUrl = gitUrl
        self.tags = tags
        self.createdAt = Date()
    }
}
