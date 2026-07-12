import Foundation

public final class SystemdService: SystemdServiceProtocol {
    public init() {}

    private var ssh: SSHServiceProtocol {
        DependencyContainer.shared.resolve(SSHServiceProtocol.self)
    }

    public func fetchServices(for server: SSHConnectionInfo) async throws -> [SystemdServiceInfo] {
        // Prefer JSON to avoid ambiguous whitespace parsing / duplicate truncated names.
        let jsonRes = try await ssh.executeCommand(
            "systemctl list-units --type=service --all --no-pager -o json 2>/dev/null || true",
            on: server
        )
        if jsonRes.exitCode == 0,
           let data = try? extractJSONArray(jsonRes.output),
           let rows = try? JSONDecoder().decode([SystemdJSONRow].self, from: data) {
            return uniqueServices(rows.map {
                SystemdServiceInfo(
                    unit: $0.unit ?? $0.Unit ?? "",
                    load: $0.load ?? $0.Load ?? "",
                    active: $0.active ?? $0.Active ?? "",
                    sub: $0.sub ?? $0.Sub ?? "",
                    description: $0.description ?? $0.Description ?? ""
                )
            }.filter { !$0.unit.isEmpty })
        }

        let res = try await ssh.executeCommand(
            "systemctl list-units --type=service --all --no-pager --plain --no-legend",
            on: server
        )
        guard res.exitCode == 0 else {
            throw OpsError.sshCommandFailed(exitCode: res.exitCode, output: res.output)
        }

        let cleaned = res.output.replacingOccurrences(of: "\r", with: "")
        let parsed: [SystemdServiceInfo] = cleaned.components(separatedBy: .newlines).compactMap { line in
            var trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            // Drop status glyphs (● ○)
            if let first = trimmed.first, !"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".contains(first) {
                trimmed = String(trimmed.drop(while: { !$0.isLetter && !$0.isNumber }))
            }
            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 4 else { return nil }
            let unit = String(parts[0])
            guard unit.hasSuffix(".service") || unit.contains("@") || unit.contains(".") else { return nil }
            return SystemdServiceInfo(
                unit: unit,
                load: String(parts[1]),
                active: String(parts[2]),
                sub: String(parts[3]),
                description: parts.dropFirst(4).joined(separator: " ")
            )
        }
        return uniqueServices(parsed)
    }

    private func uniqueServices(_ items: [SystemdServiceInfo]) -> [SystemdServiceInfo] {
        var seen = Set<String>()
        var result: [SystemdServiceInfo] = []
        for (index, item) in items.enumerated() {
            var id = item.unit
            if !seen.insert(id).inserted {
                id = "\(item.unit)#\(index)"
            }
            result.append(SystemdServiceInfo(
                id: id,
                unit: item.unit,
                load: item.load,
                active: item.active,
                sub: item.sub,
                description: item.description
            ))
        }
        return result.sorted { $0.unit.localizedCaseInsensitiveCompare($1.unit) == .orderedAscending }
    }

    private func extractJSONArray(_ raw: String) throws -> Data? {
        let cleaned = raw.replacingOccurrences(of: "\r", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = cleaned.firstIndex(of: "["), let end = cleaned.lastIndex(of: "]") else { return nil }
        return String(cleaned[start...end]).data(using: .utf8)
    }

    public func restart(unit: String, on server: SSHConnectionInfo) async throws {
        try await run("systemctl restart \(shellQuote(unit))", on: server)
    }

    public func stop(unit: String, on server: SSHConnectionInfo) async throws {
        try await run("systemctl stop \(shellQuote(unit))", on: server)
    }

    public func start(unit: String, on server: SSHConnectionInfo) async throws {
        try await run("systemctl start \(shellQuote(unit))", on: server)
    }

    public func enable(unit: String, on server: SSHConnectionInfo) async throws {
        try await run("systemctl enable \(shellQuote(unit))", on: server)
    }

    public func disable(unit: String, on server: SSHConnectionInfo) async throws {
        try await run("systemctl disable \(shellQuote(unit))", on: server)
    }

    private func run(_ cmd: String, on server: SSHConnectionInfo) async throws {
        let res = try await ssh.executeCommand(cmd, on: server)
        guard res.exitCode == 0 else {
            throw OpsError.sshCommandFailed(exitCode: res.exitCode, output: res.output)
        }
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

private struct SystemdJSONRow: Decodable {
    let unit: String?
    let Unit: String?
    let load: String?
    let Load: String?
    let active: String?
    let Active: String?
    let sub: String?
    let Sub: String?
    let description: String?
    let Description: String?
}
