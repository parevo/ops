import Foundation

/// Docker Engine API via remote unix socket (`curl --unix-socket`) over SSH.
public final class DockerService: DockerServiceProtocol {
    public init() {}

    private var ssh: SSHServiceProtocol {
        DependencyContainer.shared.resolve(SSHServiceProtocol.self)
    }

    // MARK: - Low-level HTTP

    private struct HTTPResult {
        let status: Int
        let body: String
    }

    /// Performs a Docker Engine API call. Empty bodies (204/304) are valid — never force JSON parse.
    private func request(
        _ path: String,
        method: String = "GET",
        on server: SSHConnectionInfo,
        timeout: Int = 60
    ) async throws -> HTTPResult {
        let escapedPath = path.replacingOccurrences(of: "'", with: "'\\''")
        // Append status code on its own marker line so empty 204 bodies still work.
        let cmd = """
        curl -sS --unix-socket /var/run/docker.sock \
          -X \(method) \
          -H 'Content-Type: application/json' \
          --max-time \(timeout) \
          -w '\\n__HTTP_STATUS__%{http_code}' \
          "http://localhost\(escapedPath)"
        """

        let res = try await ssh.executeCommand(cmd, on: server)
        let raw = res.output.replacingOccurrences(of: "\r", with: "")

        guard let markerRange = raw.range(of: "__HTTP_STATUS__", options: .backwards) else {
            if res.exitCode != 0 {
                throw OpsError.dockerAPI(raw.isEmpty ? "curl failed (\(res.exitCode))" : raw)
            }
            // Fallback: treat whole body as payload with unknown status
            return HTTPResult(status: res.exitCode == 0 ? 200 : 500, body: raw.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let body = String(raw[..<markerRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let statusString = String(raw[markerRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let status = Int(statusString) ?? (res.exitCode == 0 ? 200 : 500)

        if status >= 400 {
            throw OpsError.dockerAPI(Self.errorMessage(status: status, body: body))
        }

        return HTTPResult(status: status, body: body)
    }

    private static func errorMessage(status: Int, body: String) -> String {
        if let data = try? jsonData(from: body, allowEmpty: false),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = obj["message"] as? String, !message.isEmpty {
            return "HTTP \(status): \(message)"
        }
        let preview = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if preview.isEmpty {
            return "HTTP \(status)"
        }
        return "HTTP \(status): \(String(preview.prefix(240)))"
    }

    /// Strip noise and extract JSON. Empty input allowed when `allowEmpty` is true.
    static func jsonData(from raw: String, allowEmpty: Bool = false) throws -> Data {
        let cleaned = raw
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.isEmpty {
            if allowEmpty { return Data("null".utf8) }
            throw OpsError.dockerAPI("Expected JSON from Docker API, got empty response.")
        }

        guard let start = cleaned.firstIndex(where: { $0 == "[" || $0 == "{" }) else {
            throw OpsError.dockerAPI("Expected JSON from Docker API, got: \(String(cleaned.prefix(180)))")
        }

        var payload = String(cleaned[start...])
        if payload.hasPrefix("["), let end = payload.lastIndex(of: "]") {
            payload = String(payload[...end])
        } else if payload.hasPrefix("{"), let end = payload.lastIndex(of: "}") {
            payload = String(payload[...end])
        }

        guard let data = payload.data(using: .utf8) else {
            throw OpsError.dockerAPI("Unable to encode Docker API response.")
        }
        return data
    }

    private func decodeJSON<T: Decodable>(_ type: T.Type, from body: String) throws -> T {
        let data = try Self.jsonData(from: body, allowEmpty: false)
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            let preview = String(body.prefix(240))
            throw OpsError.dockerAPI("JSON decode failed: \(error.localizedDescription) · \(preview)")
        }
    }

    /// Mutating endpoints: 204/200/304 are success; body may be empty.
    private func mutate(_ path: String, method: String, on server: SSHConnectionInfo) async throws {
        let result = try await request(path, method: method, on: server)
        // 204 No Content, 200 OK, 304 Not Modified (already in desired state)
        guard (200...299).contains(result.status) || result.status == 304 else {
            throw OpsError.dockerAPI(Self.errorMessage(status: result.status, body: result.body))
        }
    }

    private func requireOK(_ res: (output: String, exitCode: Int)) throws {
        guard res.exitCode == 0 else {
            throw OpsError.dockerAPI(res.output.isEmpty ? "Command failed (\(res.exitCode))" : res.output)
        }
    }

    // MARK: - Containers

    public func fetchContainers(for server: SSHConnectionInfo) async throws -> [ContainerInfo] {
        let result = try await request("/containers/json?all=true", on: server)
        let raw = try decodeJSON([APIContainer].self, from: result.body)
        return raw.map { item in
            let name = item.Names.first?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? item.Id
            let ports = (item.Ports ?? []).map { port in
                if let pub = port.PublicPort {
                    return "\(pub)->\(port.PrivatePort)/\(port.portType)"
                }
                return "\(port.PrivatePort)/\(port.portType)"
            }.joined(separator: ", ")
            return ContainerInfo(
                id: item.Id, // keep full id for reliable start/stop
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
        try await mutate("/containers/\(Self.pathEscape(id))/start", method: "POST", on: server)
    }

    public func stopContainer(id: String, on server: SSHConnectionInfo) async throws {
        try await mutate("/containers/\(Self.pathEscape(id))/stop?t=10", method: "POST", on: server)
    }

    public func restartContainer(id: String, on server: SSHConnectionInfo) async throws {
        try await mutate("/containers/\(Self.pathEscape(id))/restart?t=10", method: "POST", on: server)
    }

    public func deleteContainer(id: String, on server: SSHConnectionInfo) async throws {
        try await mutate("/containers/\(Self.pathEscape(id))?force=true", method: "DELETE", on: server)
    }

    public func inspectContainer(id: String, on server: SSHConnectionInfo) async throws -> String {
        let result = try await request("/containers/\(Self.pathEscape(id))/json", on: server)
        // Pretty-print if possible
        if let data = try? Self.jsonData(from: result.body, allowEmpty: false),
           let obj = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: pretty, encoding: .utf8) {
            return text
        }
        return result.body
    }

    private static func pathEscape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    // MARK: - Images / Volumes / Networks / Compose

    public func fetchImages(for server: SSHConnectionInfo) async throws -> [DockerImageInfo] {
        let result = try await request("/images/json", on: server)
        let raw = try decodeJSON([APIImage].self, from: result.body)
        var seen = Set<String>()
        var output: [DockerImageInfo] = []

        for image in raw {
            let shortID = String(image.Id.replacingOccurrences(of: "sha256:", with: "").prefix(12))
            let tags = image.RepoTags?.filter { $0 != "<none>:<none>" } ?? []
            let refs = tags.isEmpty ? [image.RepoDigests?.first ?? "<none>"] : tags

            for (idx, ref) in refs.enumerated() {
                let parts = splitImageRef(ref)
                let rowID = tags.isEmpty ? shortID : "\(shortID)-\(idx)-\(parts.repo)-\(parts.tag)"
                guard seen.insert(rowID).inserted else { continue }
                output.append(DockerImageInfo(
                    id: rowID,
                    repository: parts.repo,
                    tag: parts.tag,
                    size: ByteCountFormatter.string(fromByteCount: image.Size, countStyle: .file),
                    created: "\(image.Created)"
                ))
            }
        }
        return output
    }

    private func splitImageRef(_ ref: String) -> (repo: String, tag: String) {
        if ref.contains("@") {
            let digestParts = ref.split(separator: "@", maxSplits: 1).map(String.init)
            return (digestParts.first ?? ref, digestParts.count > 1 ? "@\(digestParts[1].prefix(12))" : "<none>")
        }
        if let slash = ref.lastIndex(of: "/"),
           let colon = ref[slash...].lastIndex(of: ":") {
            return (String(ref[..<colon]), String(ref[ref.index(after: colon)...]))
        }
        if let colon = ref.lastIndex(of: ":"), !ref[ref.index(after: colon)...].contains("/") {
            return (String(ref[..<colon]), String(ref[ref.index(after: colon)...]))
        }
        return (ref, "<none>")
    }

    public func fetchVolumes(for server: SSHConnectionInfo) async throws -> [DockerVolumeInfo] {
        let result = try await request("/volumes", on: server)
        let raw = try decodeJSON(APIVolumeList.self, from: result.body)
        return (raw.Volumes ?? []).map {
            DockerVolumeInfo(name: $0.Name, driver: $0.Driver, mountpoint: $0.Mountpoint)
        }
    }

    public func fetchNetworks(for server: SSHConnectionInfo) async throws -> [DockerNetworkInfo] {
        let result = try await request("/networks", on: server)
        let raw = try decodeJSON([APINetwork].self, from: result.body)
        var seen = Set<String>()
        return raw.compactMap { net in
            var id = net.Id.count > 12 ? String(net.Id.prefix(12)) : net.Id
            if !seen.insert(id).inserted {
                id = "\(id)-\(net.Name)"
                guard seen.insert(id).inserted else { return nil }
            }
            return DockerNetworkInfo(id: id, name: net.Name, driver: net.Driver, scope: net.Scope)
        }
    }

    public func fetchComposeProjects(for server: SSHConnectionInfo) async throws -> [ComposeProjectInfo] {
        let res = try await ssh.executeCommand(
            "docker compose ls --format json 2>/dev/null || docker-compose ls --format json 2>/dev/null || echo '[]'",
            on: server
        )
        try requireOK(res)
        let payload = res.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "[]" : res.output
        let data = try Self.jsonData(from: payload, allowEmpty: false)
        if let list = try? JSONDecoder().decode([APICompose].self, from: data) {
            return list.map {
                ComposeProjectInfo(name: $0.Name, status: $0.Status ?? "", configFiles: $0.ConfigFiles ?? "")
            }
        }
        let cleaned = String(data: data, encoding: .utf8) ?? ""
        return cleaned.split(separator: "\n").compactMap { line in
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
    let Created: FlexibleInt
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

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        PrivatePort = try c.decode(Int.self, forKey: .PrivatePort)
        PublicPort = try c.decodeIfPresent(Int.self, forKey: .PublicPort)
        portType = try c.decodeIfPresent(String.self, forKey: .portType) ?? "tcp"
    }
}

private struct APIImage: Decodable {
    let Id: String
    let RepoTags: [String]?
    let RepoDigests: [String]?
    let Size: Int64
    let Created: FlexibleInt
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

private struct FlexibleInt: Decodable, CustomStringConvertible {
    let value: Int
    var description: String { "\(value)" }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) {
            value = i
        } else if let d = try? c.decode(Double.self) {
            value = Int(d)
        } else if let s = try? c.decode(String.self), let i = Int(s) {
            value = i
        } else {
            value = 0
        }
    }
}
