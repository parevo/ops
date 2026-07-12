import Foundation

public enum OpsError: LocalizedError, Sendable {
    case noActiveServer
    case sshConnectionFailed(String)
    case sshCommandFailed(exitCode: Int, output: String)
    case dockerAPI(String)
    case fileOperation(String)
    case keychain(String)
    case invalidInput(String)
    case notFound(String)

    public var errorDescription: String? {
        switch self {
        case .noActiveServer:
            return "Select a server host before running this action."
        case .sshConnectionFailed(let detail):
            return "SSH connection failed: \(detail)"
        case .sshCommandFailed(let code, let output):
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Remote command failed (exit \(code))." : trimmed
        case .dockerAPI(let detail):
            return "Docker API error: \(detail)"
        case .fileOperation(let detail):
            return detail
        case .keychain(let detail):
            return "Keychain error: \(detail)"
        case .invalidInput(let detail):
            return detail
        case .notFound(let detail):
            return detail
        }
    }
}
