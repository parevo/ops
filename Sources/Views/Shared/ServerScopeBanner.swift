import SwiftUI
import SwiftData

/// Sidebar footer — active server is the primary label (customer switcher).
@MainActor
struct SidebarServerSwitcher: View {
    @Environment(AppSession.self) private var session
    @Query private var servers: [Server]

    private var active: Server? { session.server(from: servers) }

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            VStack(alignment: .leading, spacing: BrandSpacing.small) {
                Text("Active server")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BrandColor.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.4)

                if let active {
                    Text(active.name)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(BrandColor.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("\(active.username)@\(active.host)")
                        .font(.caption.monospaced())
                        .foregroundStyle(BrandColor.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("No server")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(BrandColor.warning)

                    Text("Choose a host to continue")
                        .font(.caption)
                        .foregroundStyle(BrandColor.textSecondary)
                }

                Menu {
                    if servers.isEmpty {
                        Text("No servers yet")
                    } else {
                        ForEach(servers) { server in
                            Button {
                                session.select(server)
                            } label: {
                                if session.activeServerID == server.id {
                                    Label(server.name, systemImage: "checkmark")
                                } else {
                                    Text(server.name)
                                }
                            }
                        }
                    }
                    Divider()
                    Button("Manage Servers…") {
                        session.navigate(to: .servers)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.left.arrow.right")
                        Text(active == nil ? "Select Server" : "Switch Server")
                            .fontWeight(.semibold)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, BrandSpacing.medium)
                    .padding(.vertical, 8)
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(active == nil ? BrandColor.warning : BrandColor.accent)
            }
            .padding(BrandSpacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(active.map { "Active server \($0.name)" } ?? "No active server")
    }
}
