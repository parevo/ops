import Foundation

enum SSHAskPass {
    static func makeScript(password: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
        let script = dir.appendingPathComponent("parevo-askpass-\(UUID().uuidString).sh")
        let escaped = password.replacingOccurrences(of: "'", with: "'\\''")
        try "#!/bin/sh\necho '\(escaped)'\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        return script
    }

    static func environment(password: String) throws -> (env: [String: String], script: URL) {
        let script = try makeScript(password: password)
        var env = Foundation.ProcessInfo.processInfo.environment
        env["SSH_ASKPASS"] = script.path
        env["SSH_ASKPASS_REQUIRE"] = "force"
        env["DISPLAY"] = "none"
        return (env, script)
    }
}
