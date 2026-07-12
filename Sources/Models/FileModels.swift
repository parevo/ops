import Foundation

public struct FileInfo: Identifiable, Codable, Hashable {
    public var id: String { path }
    public var name: String
    public var path: String
    public var isDirectory: Bool
    public var size: Int64
    public var permissions: String
    public var lastModified: Date
    public var owner: String
    public var group: String

    public init(
        name: String,
        path: String,
        isDirectory: Bool,
        size: Int64 = 0,
        permissions: String = "rw-r--r--",
        lastModified: Date = Date(),
        owner: String = "root",
        group: String = "root"
    ) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.size = size
        self.permissions = permissions
        self.lastModified = lastModified
        self.owner = owner
        self.group = group
    }
}
