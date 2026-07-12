import Foundation

public struct CronJobInfo: Identifiable, Codable, Hashable {
    public var id: String
    public var command: String
    public var schedule: String
    public var nextRun: Date?
    public var lastRun: Date?
    public var lastDuration: TimeInterval?
    public var lastExitCode: Int?
    public var isEnabled: Bool
    public var source: String // e.g. "crontab", "systemd-timer"

    public init(
        id: String,
        command: String,
        schedule: String,
        nextRun: Date? = nil,
        lastRun: Date? = nil,
        lastDuration: TimeInterval? = nil,
        lastExitCode: Int? = nil,
        isEnabled: Bool = true,
        source: String = "crontab"
    ) {
        self.id = id
        self.command = command
        self.schedule = schedule
        self.nextRun = nextRun
        self.lastRun = lastRun
        self.lastDuration = lastDuration
        self.lastExitCode = lastExitCode
        self.isEnabled = isEnabled
        self.source = source
    }
}
