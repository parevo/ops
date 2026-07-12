import AppKit
import Foundation
import SwiftTerm

/// Keeps SwiftTerm PTY sessions alive across tab switches.
/// One `LocalProcessTerminalView` per tab UUID — never reused across tabs.
@MainActor
@Observable
public final class TerminalHostRegistry {
    private var hosts: [UUID: LocalProcessTerminalView] = [:]
    private var askPassScripts: [UUID: URL] = [:]

    public init() {}

    public func host(
        for tabID: UUID,
        server: SSHConnectionInfo,
        initialCommand: String?
    ) -> LocalProcessTerminalView {
        if let existing = hosts[tabID] {
            return existing
        }

        let view = LocalProcessTerminalView(frame: .zero)
        applyAppearance(to: view)
        view.autoresizingMask = [.width, .height]
        start(view: view, tabID: tabID, server: server, initialCommand: initialCommand)
        hosts[tabID] = view
        return view
    }

    public func dispose(_ tabID: UUID) {
        guard let view = hosts.removeValue(forKey: tabID) else { return }
        view.removeFromSuperview()
        view.terminate()
        if let script = askPassScripts.removeValue(forKey: tabID) {
            try? FileManager.default.removeItem(at: script)
        }
    }

    public func disposeAll() {
        let ids = Array(hosts.keys)
        for id in ids { dispose(id) }
    }

    public func applyAppearance(to view: LocalProcessTerminalView) {
        let fontSize = Self.storedFontSize
        let theme = Self.storedTheme
        let colors = Self.themeColors(theme)

        // Font — triggers SwiftTerm resetFont()
        view.font = NSFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)

        // Native colors used for default text/background painting
        view.nativeForegroundColor = colors.fg
        view.nativeBackgroundColor = colors.bg
        view.caretColor = colors.fg
        view.selectedTextBackgroundColor = colors.fg.withAlphaComponent(0.28)

        // Critical: installColors clears attribute caches via colorsChanged().
        // Setting nativeForegroundColor alone does NOT redraw existing cells.
        view.installColors(Self.ansiPalette(fg: colors.termFg, bg: colors.termBg))

        view.layer?.backgroundColor = colors.bg.cgColor
        view.wantsLayer = true
        view.needsDisplay = true
    }

    public func refreshAppearance() {
        let views = Array(hosts.values)
        for view in views {
            applyAppearance(to: view)
        }
    }

    public var debugHostCount: Int { hosts.count }

    // MARK: - Appearance helpers

    private static var storedFontSize: Double {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "parevo.terminal.fontSize") != nil else { return 13 }
        let value = defaults.double(forKey: "parevo.terminal.fontSize")
        return value > 0 ? value : 13
    }

    private static var storedTheme: String {
        UserDefaults.standard.string(forKey: "parevo.terminal.theme") ?? "system"
    }

    private struct ThemeColors {
        let fg: NSColor
        let bg: NSColor
        let termFg: Color
        let termBg: Color
    }

    private static func themeColors(_ theme: String) -> ThemeColors {
        let fgNS: NSColor
        let bgNS: NSColor
        switch theme {
        case "dark":
            fgNS = NSColor(calibratedRed: 0.92, green: 0.93, blue: 0.94, alpha: 1)
            bgNS = NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.10, alpha: 1)
        case "light":
            fgNS = NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.15, alpha: 1)
            bgNS = NSColor(calibratedRed: 0.98, green: 0.98, blue: 0.97, alpha: 1)
        default:
            fgNS = NSColor.textColor
            bgNS = NSColor.textBackgroundColor
        }
        return ThemeColors(
            fg: fgNS,
            bg: bgNS,
            termFg: termColor(from: fgNS),
            termBg: termColor(from: bgNS)
        )
    }

    private static func termColor(from ns: NSColor) -> Color {
        let c = ns.usingColorSpace(.sRGB) ?? ns
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return Color(
            red: UInt16(clamping: Int(r * 65535)),
            green: UInt16(clamping: Int(g * 65535)),
            blue: UInt16(clamping: Int(b * 65535))
        )
    }

    /// 16 ANSI colors with theme bg/fg as black/white defaults.
    private static func ansiPalette(fg: Color, bg: Color) -> [Color] {
        [
            bg,
            Color(red: 52685, green: 0, blue: 0),           // red
            Color(red: 0, green: 52685, blue: 0),           // green
            Color(red: 52685, green: 52685, blue: 0),       // yellow
            Color(red: 0, green: 0, blue: 61166),           // blue
            Color(red: 52685, green: 0, blue: 52685),       // magenta
            Color(red: 0, green: 52685, blue: 52685),       // cyan
            fg,
            Color(red: 32639, green: 32639, blue: 32639),   // bright black
            Color(red: 65535, green: 0, blue: 0),
            Color(red: 0, green: 65535, blue: 0),
            Color(red: 65535, green: 65535, blue: 0),
            Color(red: 23644, green: 23644, blue: 65535),
            Color(red: 65535, green: 0, blue: 65535),
            Color(red: 0, green: 65535, blue: 65535),
            Color(red: 65535, green: 65535, blue: 65535)
        ]
    }

    private func start(
        view: LocalProcessTerminalView,
        tabID: UUID,
        server: SSHConnectionInfo,
        initialCommand: String?
    ) {
        var args: [String] = [
            "-tt",
            "-o", "ControlMaster=auto",
            "-o", "ControlPersist=30m",
            "-o", "ControlPath=\(server.controlSocketPath)",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "Compression=no",
            "-p", "\(server.port)"
        ]

        var environment: [String]?

        if server.authMethod == .sshKey, let key = server.privateKeyPath, !key.isEmpty {
            let expanded = (key as NSString).expandingTildeInPath
            args += ["-i", expanded, "-o", "IdentitiesOnly=yes", "-o", "BatchMode=yes"]
        } else if server.authMethod == .password, let password = server.passwordPlain, !password.isEmpty {
            if let built = try? SSHAskPass.environment(password: password) {
                askPassScripts[tabID] = built.script
                var envList = Terminal.getEnvironmentVariables(termName: "xterm-256color")
                envList.append("SSH_ASKPASS=\(built.script.path)")
                envList.append("SSH_ASKPASS_REQUIRE=force")
                envList.append("DISPLAY=none")
                environment = envList
            }
        }

        if FileManager.default.fileExists(atPath: server.controlSocketPath) {
            args += ["-o", "BatchMode=yes"]
        }

        args.append("\(server.username)@\(server.host)")

        if let cmd = initialCommand?.trimmingCharacters(in: .whitespacesAndNewlines), !cmd.isEmpty {
            args.append("bash -lc \(shellQuote(cmd))")
        }

        if server.authMethod == .password {
            Task {
                _ = try? await DependencyContainer.shared.resolve(SSHServiceProtocol.self).connect(server: server)
            }
        }

        view.startProcess(executable: "/usr/bin/ssh", args: args, environment: environment, execName: "ssh")
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
