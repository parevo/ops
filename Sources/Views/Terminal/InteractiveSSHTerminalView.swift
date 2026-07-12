import AppKit
import SwiftUI
import SwiftTerm

/// Embeds a registry-backed SwiftTerm session so tab switches don't restart SSH.
/// Each `tabID` maps to exactly one `LocalProcessTerminalView` — never shared.
struct InteractiveSSHTerminalView: NSViewRepresentable {
    let tabID: UUID
    let server: SSHConnectionInfo
    var initialCommand: String?
    let registry: TerminalHostRegistry

    func makeCoordinator() -> Coordinator {
        Coordinator(tabID: tabID)
    }

    func makeNSView(context: Context) -> NSView {
        let container = TerminalHostContainer()
        context.coordinator.attachedTabID = nil
        attach(to: container, context: context)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        attach(to: container, context: context)
    }

    static func dismantleNSView(_ container: NSView, coordinator: Coordinator) {
        container.subviews.forEach { $0.removeFromSuperview() }
        coordinator.attachedTabID = nil
    }

    private func attach(to container: NSView, context: Context) {
        let host = registry.host(for: tabID, server: server, initialCommand: initialCommand)

        // Critical: remove ANY other terminal views so tabs never visually mix.
        for subview in container.subviews where subview !== host {
            subview.removeFromSuperview()
        }

        if context.coordinator.attachedTabID != tabID || host.superview !== container {
            host.removeFromSuperview()
            host.frame = container.bounds
            host.autoresizingMask = [.width, .height]
            container.addSubview(host)
            context.coordinator.attachedTabID = tabID
        } else {
            host.frame = container.bounds
        }

        registry.applyAppearance(to: host)
    }

    final class Coordinator {
        var attachedTabID: UUID?

        init(tabID: UUID) {
            self.attachedTabID = nil
        }
    }
}

/// Plain container that only hosts one terminal subview at a time.
private final class TerminalHostContainer: NSView {
    override var isFlipped: Bool { true }
}
