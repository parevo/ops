import Foundation

public struct ProcessInfo: Identifiable, Codable, Hashable {
    public var id: Int { pid }
    public var pid: Int
    public var name: String
    public var cpu: Double
    public var memory: Double
    public var user: String

    public init(pid: Int, name: String, cpu: Double, memory: Double, user: String) {
        self.pid = pid
        self.name = name
        self.cpu = cpu
        self.memory = memory
        self.user = user
    }
}

public struct SystemMetrics: Codable, Hashable {
    public var hostname: String
    public var osName: String
    public var kernelVersion: String
    
    // CPU
    public var cpuUsage: Double
    public var loadAverage1Min: Double
    public var loadAverage5Min: Double
    public var loadAverage15Min: Double
    
    // RAM
    public var ramUsage: Double
    public var ramTotal: Double
    public var ramUsed: Double
    
    // Disk & Swap
    public var diskUsage: Double
    public var diskTotal: Double
    public var diskUsed: Double
    public var swapUsage: Double
    
    // Docker / Systemd Count
    public var runningContainersCount: Int
    public var stoppedContainersCount: Int
    public var systemdServicesCount: Int
    
    // Process list
    public var topProcesses: [ProcessInfo]
    
    // Aggregated Score
    public var healthScore: Int
    public var alertsCount: Int

    public init(
        hostname: String = "localhost",
        osName: String = "Ubuntu 22.04 LTS",
        kernelVersion: String = "5.15.0-88-generic",
        cpuUsage: Double = 0.0,
        loadAverage1Min: Double = 0.0,
        loadAverage5Min: Double = 0.0,
        loadAverage15Min: Double = 0.0,
        ramUsage: Double = 0.0,
        ramTotal: Double = 16.0,
        ramUsed: Double = 0.0,
        diskUsage: Double = 0.0,
        diskTotal: Double = 256.0,
        diskUsed: Double = 0.0,
        swapUsage: Double = 0.0,
        runningContainersCount: Int = 0,
        stoppedContainersCount: Int = 0,
        systemdServicesCount: Int = 0,
        topProcesses: [ProcessInfo] = [],
        healthScore: Int = 100,
        alertsCount: Int = 0
    ) {
        self.hostname = hostname
        self.osName = osName
        self.kernelVersion = kernelVersion
        self.cpuUsage = cpuUsage
        self.loadAverage1Min = loadAverage1Min
        self.loadAverage5Min = loadAverage5Min
        self.loadAverage15Min = loadAverage15Min
        self.ramUsage = ramUsage
        self.ramTotal = ramTotal
        self.ramUsed = ramUsed
        self.diskUsage = diskUsage
        self.diskTotal = diskTotal
        self.diskUsed = diskUsed
        self.swapUsage = swapUsage
        self.runningContainersCount = runningContainersCount
        self.stoppedContainersCount = stoppedContainersCount
        self.systemdServicesCount = systemdServicesCount
        self.topProcesses = topProcesses
        self.healthScore = healthScore
        self.alertsCount = alertsCount
    }
}
