import Foundation

public final class MetricsService: MetricsServiceProtocol {
    public init() {}

    private var ssh: SSHServiceProtocol {
        DependencyContainer.shared.resolve(SSHServiceProtocol.self)
    }

    public func fetchLiveMetrics(for server: SSHConnectionInfo) async throws -> SystemMetrics {
        let cmd = """
        echo "===HOST===" && hostname && (grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"' || true) && uname -r
        echo "===LOAD===" && cat /proc/loadavg
        echo "===CPU===" && (top -bn1 | grep "Cpu(s)" | awk '{print $2+$4}' || echo 0)
        echo "===MEM===" && (free -m | awk '/Mem:/ {print $2,$3}' || echo "0 0")
        echo "===SWAP===" && (free -m | awk '/Swap:/ {print $2,$3}' || echo "0 0")
        echo "===DISK===" && (df -m / | tail -n 1 | awk '{print $2,$3}')
        echo "===DOCKER===" && (docker ps -q 2>/dev/null | wc -l || echo 0) && (docker ps -aq -f status=exited 2>/dev/null | wc -l || echo 0)
        echo "===SERVICES===" && (systemctl list-units --type=service --state=running --no-pager --no-legend 2>/dev/null | wc -l || echo 0)
        echo "===PS===" && ps -eo pid,comm,%cpu,%mem,user --sort=-%cpu | head -n 8
        """
        let res = try await ssh.executeCommand(cmd, on: server)
        guard res.exitCode == 0 else {
            throw OpsError.sshCommandFailed(exitCode: res.exitCode, output: res.output)
        }
        return parse(res.output, hostnameDefault: server.name)
    }

    private func parse(_ output: String, hostnameDefault: String) -> SystemMetrics {
        var metrics = SystemMetrics(hostname: hostnameDefault)
        let lines = output.components(separatedBy: .newlines)
        var section = ""
        var hostLines: [String] = []
        var psLines: [String] = []
        var dockerLines: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("===") {
                section = trimmed
                continue
            }
            switch section {
            case "===HOST===": hostLines.append(trimmed)
            case "===LOAD===":
                let parts = trimmed.split(separator: " ")
                if parts.count >= 3 {
                    metrics.loadAverage1Min = Double(parts[0]) ?? 0
                    metrics.loadAverage5Min = Double(parts[1]) ?? 0
                    metrics.loadAverage15Min = Double(parts[2]) ?? 0
                }
            case "===CPU===":
                metrics.cpuUsage = Double(trimmed.replacingOccurrences(of: ",", with: ".")) ?? 0
            case "===MEM===":
                let parts = trimmed.split(separator: " ")
                if parts.count >= 2 {
                    let total = Double(parts[0]) ?? 1
                    let used = Double(parts[1]) ?? 0
                    metrics.ramTotal = (total / 1024).rounded(toPlaces: 1)
                    metrics.ramUsed = (used / 1024).rounded(toPlaces: 1)
                    metrics.ramUsage = ((used / total) * 100).rounded(toPlaces: 1)
                }
            case "===SWAP===":
                let parts = trimmed.split(separator: " ")
                if parts.count >= 2 {
                    let total = Double(parts[0]) ?? 0
                    let used = Double(parts[1]) ?? 0
                    metrics.swapUsage = total > 0 ? ((used / total) * 100).rounded(toPlaces: 1) : 0
                }
            case "===DISK===":
                let parts = trimmed.split(separator: " ")
                if parts.count >= 2 {
                    let total = Double(parts[0]) ?? 1
                    let used = Double(parts[1]) ?? 0
                    metrics.diskTotal = (total / 1024).rounded(toPlaces: 1)
                    metrics.diskUsed = (used / 1024).rounded(toPlaces: 1)
                    metrics.diskUsage = ((used / total) * 100).rounded(toPlaces: 1)
                }
            case "===DOCKER===": dockerLines.append(trimmed)
            case "===SERVICES===":
                metrics.systemdServicesCount = Int(trimmed) ?? 0
            case "===PS===": psLines.append(trimmed)
            default: break
            }
        }

        if hostLines.indices.contains(0) { metrics.hostname = hostLines[0] }
        if hostLines.indices.contains(1) { metrics.osName = hostLines[1] }
        if hostLines.indices.contains(2) { metrics.kernelVersion = hostLines[2] }
        if dockerLines.indices.contains(0) { metrics.runningContainersCount = Int(dockerLines[0].trimmingCharacters(in: .whitespaces)) ?? 0 }
        if dockerLines.indices.contains(1) { metrics.stoppedContainersCount = Int(dockerLines[1].trimmingCharacters(in: .whitespaces)) ?? 0 }

        var processes: [ProcessInfo] = []
        for (idx, line) in psLines.enumerated() where idx > 0 {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 5 else { continue }
            processes.append(ProcessInfo(
                pid: Int(parts[0]) ?? 0,
                name: String(parts[1]),
                cpu: Double(parts[2].replacingOccurrences(of: ",", with: ".")) ?? 0,
                memory: (Double(parts[3].replacingOccurrences(of: ",", with: ".")) ?? 0) * metrics.ramTotal * 10.24,
                user: String(parts[4])
            ))
        }
        metrics.topProcesses = processes

        let cpuPenalty = metrics.cpuUsage > 80 ? (metrics.cpuUsage - 80) * 1.5 : 0
        let ramPenalty = metrics.ramUsage > 85 ? (metrics.ramUsage - 85) * 1.2 : 0
        let diskPenalty = metrics.diskUsage > 90 ? (metrics.diskUsage - 90) * 2 : 0
        metrics.healthScore = min(100, max(0, Int(100 - cpuPenalty - ramPenalty - diskPenalty)))
        metrics.alertsCount =
            (metrics.cpuUsage > 85 ? 1 : 0) +
            (metrics.ramUsage > 90 ? 1 : 0) +
            (metrics.diskUsage > 92 ? 1 : 0)
        return metrics
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
