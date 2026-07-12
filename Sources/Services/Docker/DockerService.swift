import Foundation

/// Docker Engine API via remote unix socket (`curl --unix-socket`) over SSH.
public final class DockerService: DockerServiceProtocol {
    public init() {}

    private var ssh: SSHServiceProtocol {
        DependencyContainer.shared.resolve(SSHServiceProtocol.self)
    }

    private func api(
        _ path: String,
        method: String = "GET",
        on server: SSHConnectionInfo
    ) async throws -> Data {
        let escapedPath = path.replacingOccurrences(of: "'", with: "'\\''")
        let cmd = """
        curl -sS --unix-socket /var/run/docker.sock \
          -X \(method) \
          -H 'Content-Type: application/json' \
          "http://localhost\(escapedPath)"
        """
        let res = try await ssh.executeCommand(cmd, on: server)
        guard res.exitCode == 0 else {
            throw OpsError.dockerAPI(res.output.isEmpty ? "HTTP request failed (\(res.exitCode))" : res.output)
        }
        return Data(res.output.utf8)
    }

    private func requireOK(_ res: (output: String, exitCode: Int)) throws {
        guard res.exitCode == 0 else {
            throw OpsError.dockerAPI(res.output)
        }
    }

    public func fetchContainers(for server: SSHConnectionInfo) async throws -> [ContainerInfo] {
        let data = try await api("/v1.43/containers/json?all=true", on: server)
        let raw = try JSONDecoder().decode([APIContainer].self, from: data)
        return raw.map { item in
            let name = item.Names.first?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? item.Id
            let ports = (item.Ports ?? []).map { port in
                if let pub = port.PublicPort {
                    return "\(pub)->\(port.PrivatePort)/\(port.portType)"
                }
                return "\(port.PrivatePort)/\(port.portType)"
            }.joined(separator: ", ")
            return ContainerInfo(
                id: String(item.Id.prefix(12)),
                name: name,
                image: item.Image,
                status: item.Status,
                state: item.State,
                ports: ports,
                created: "\(item.Created)"
            )
        }
    }

    public func startContainer(id: String, on server: SSHConnectionInfo) async throws {
        _ = try await api("/v1.43/containers/\(id)/start", method: "POST", on: server)
    }

    public func stopContainer(id: String, on server: SSHConnectionInfo) async throws {
        _ = try await api("/v1.43/containers/\(id)/stop", method: "POST", on: server)
    }

    public func restartContainer(id: String, on server: SSHConnectionInfo) async throws {
        _ = try await api("/v1.43/containers/\(id)/restart", method: "POST", on: server)
    }

    public func deleteContainer(id: String, on server: SSHConnectionInfo) async throws {
        _ = try await api("/v1.43/containers/\(id)?force=true", method: "DELETE", on: server)
    }

    public func fetchImages(for server: SSHConnectionInfo) async throws -> [DockerImageInfo] {
        let data = try await api("/v1.43/images/json", on: server)
        let raw = try JSONDecoder().decode([APIImage].self, from: data)
        return raw.map { image in
            let ref = image.RepoTags?.first ?? image.RepoDigests?.first ?? "<none>"
            let parts = ref.split(separator: ":", maxSplits: 1).map(String.init)
            return DockerImageInfo(
                id: String(image.Id.replacingOccurrences(of: "sha256:", with: "").prefix(12)),
                repository: parts.first ?? "<none>",
                tag: parts.count > 1 ? parts[1] : "<none>",
                size: ByteCountFormatter.string(fromByteCount: image.Size, countStyle: .file),
                created: "\(image.Created)"
            )
        }
    }

    public func fetchVolumes(for server: SSHConnectionInfo) async throws -> [DockerVolumeInfo] {
        let data = try await api("/v1.43/volumes", on: server)
        let raw = try JSONDecoder().decode(APIVolumeList.self, from: data)
        return (raw.Volumes ?? []).map {
            DockerVolumeInfo(name: $0.Name, driver: $0.Driver, mountpoint: $0.Mountpoint)
        }
    }

    public func fetchNetworks(for server: SSHConnectionInfo) async throws -> [DockerNetworkInfo] {
        let data = try await api("/v1.43/networks", on: server)
        let raw = try JSONDecoder().decode([APINetwork].self, from: data)
        return raw.map {
            DockerNetworkInfo(id: String($0.Id.prefix(12)), name: $0.Name, driver: $0.Driver, scope: $0.Scope)
        }
    }

    public func fetchComposeProjects(for server: SSHConnectionInfo) async throws -> [ComposeProjectInfo] {
        let res = try await ssh.executeCommand(
            "docker compose ls --format json 2>/dev/null || docker-compose ls --format json 2>/dev/null",
            on: server
        )
        guard res.exitCode == 0 else { throw OpsError.dockerAPI(res.output) }
        let trimmed = res.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "[]" else { return [] }
        if let list = try? JSONDecoder().decode([APICompose].self, from: Data(trimmed.utf8)) {
            return list.map {
                ComposeProjectInfo(name: $0.Name, status: $0.Status ?? "", configFiles: $0.ConfigFiles ?? "")
            }
        }
        // Sometimes compose prints NDJSON
        return trimmed.split(separator: "\n").compactMap { line in
            guard let item = try? JSONDecoder().decode(APICompose.self, from: Data(line.utf8)) else { return nil }
            return ComposeProjectInfo(name: item.Name, status: item.Status ?? "", configFiles: item.ConfigFiles ?? "")
        }
    }

    public func composeUp(project: String, on server: SSHConnectionInfo) async throws {
        let safe = project.replacingOccurrences(of: "'", with: "'\\''")
        let res = try await ssh.executeCommand("docker compose -p '\(safe)' up -d", on: server)
        try requireOK(res)
    }

    public func composeDown(project: String, on server: SSHConnectionInfo) async throws {
        let safe = project.replacingOccurrences(of: "'", with: "'\\''")
        let res = try await ssh.executeCommand("docker compose -p '\(safe)' down", on: server)
        try requireOK(res)
    }
}

// MARK: - API DTOs

private struct APIContainer: Decodable {
    let Id: String
    let Names: [String]
    let Image: String
    let State: String
    let Status: String
    let Created: Int
    let Ports: [APIPort]?
}

private struct APIPort: Decodable {
    let PrivatePort: Int
    let PublicPort: Int?
    let portType: String

    enum CodingKeys: String, CodingKey {
        case PrivatePort, PublicPort
        case portType = "Type"
    }
}

private struct APIImage: Decodable {
    let Id: String
    let RepoTags: [String]?
    let RepoDigests: [String]?
    let Size: Int64
    let Created: Int
}

private struct APIVolumeList: Decodable {
    let Volumes: [APIVolume]?
}

private struct APIVolume: Decodable {
    let Name: String
    let Driver: String
    let Mountpoint: String
}

private struct APINetwork: Decodable {
    let Id: String
    let Name: String
    let Driver: String
    let Scope: String
}

private struct APICompose: Decodable {
    let Name: String
    let Status: String?
    let ConfigFiles: String?
}
