import Foundation

public final class CronService: CronServiceProtocol {
    public init() {}

    private var ssh: SSHServiceProtocol {
        DependencyContainer.shared.resolve(SSHServiceProtocol.self)
    }

    public func fetchCronJobs(for server: SSHConnectionInfo) async throws -> [CronJobInfo] {
        var jobs: [CronJobInfo] = []

        let userCron = try await ssh.executeCommand("crontab -l 2>/dev/null || true", on: server)
        if userCron.exitCode == 0 {
            jobs += parseCrontab(userCron.output, source: "crontab", prefix: "user")
        }

        let systemCron = try await ssh.executeCommand("cat /etc/crontab 2>/dev/null || true", on: server)
        if systemCron.exitCode == 0 {
            jobs += parseCrontab(systemCron.output, source: "/etc/crontab", prefix: "system")
        }

        let cronD = try await ssh.executeCommand(
            "for f in /etc/cron.d/*; do [ -f \"$f\" ] && echo \"###FILE:$f\" && cat \"$f\"; done 2>/dev/null || true",
            on: server
        )
        if cronD.exitCode == 0 {
            var currentFile = "cron.d"
            for line in cronD.output.components(separatedBy: .newlines) {
                if line.hasPrefix("###FILE:") {
                    currentFile = String(line.dropFirst("###FILE:".count))
                    continue
                }
                if let job = parseCronLine(line, source: currentFile, id: "\(currentFile)-\(jobs.count)") {
                    jobs.append(job)
                }
            }
        }

        let timers = try await ssh.executeCommand(
            "systemctl list-timers --all --no-pager --no-legend 2>/dev/null || true",
            on: server
        )
        if timers.exitCode == 0 {
            for (idx, line) in timers.output.components(separatedBy: .newlines).enumerated() {
                let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                guard parts.count >= 5 else { continue }
                let unit = String(parts.last ?? "timer")
                jobs.append(CronJobInfo(
                    id: "timer-\(idx)-\(unit)",
                    command: "systemctl start \(unit.replacingOccurrences(of: ".timer", with: ".service"))",
                    schedule: "systemd-timer",
                    source: "systemd-timer"
                ))
            }
        }

        return jobs
    }

    public func runCronJob(id: String, on server: SSHConnectionInfo) async throws {
        let jobs = try await fetchCronJobs(for: server)
        guard let job = jobs.first(where: { $0.id == id }) else {
            throw OpsError.notFound("Cron job not found.")
        }
        let res = try await ssh.executeCommand(job.command, on: server)
        guard res.exitCode == 0 else {
            throw OpsError.sshCommandFailed(exitCode: res.exitCode, output: res.output)
        }
    }

    private func parseCrontab(_ output: String, source: String, prefix: String) -> [CronJobInfo] {
        output.components(separatedBy: .newlines).enumerated().compactMap { idx, line in
            parseCronLine(line, source: source, id: "\(prefix)-\(idx)")
        }
    }

    private func parseCronLine(_ line: String, source: String, id: String) -> CronJobInfo? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
        let parts = trimmed.split(separator: " ", maxSplits: 5, omittingEmptySubsequences: true)
        guard parts.count >= 6 else { return nil }
        // Skip /etc/crontab user column style if 7+ fields with known user-like 6th token
        if parts.count >= 7, !parts[5].contains("/"), !parts[5].contains("=") {
            let schedule = parts[0...4].joined(separator: " ")
            let command = parts[6...].joined(separator: " ")
            return CronJobInfo(id: id, command: command, schedule: schedule, source: source)
        }
        let schedule = parts[0...4].joined(separator: " ")
        let command = String(parts[5])
        return CronJobInfo(id: id, command: command, schedule: schedule, source: source)
    }
}
