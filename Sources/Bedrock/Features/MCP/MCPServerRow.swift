import AppKit
import SwiftUI
import MCP

struct MCPServerRow: View {
    @ObservedObject private var settingsManager = PreferencesStore.shared
    @ObservedObject private var mcpManager = MCPClientManager.shared
    @ObservedObject private var oauth = MCPOAuthService.shared
    let serverName: String
    @State private var showingEditSheet = false

    // Get server from MCPClientManager to ensure we always have the latest data
    private var server: MCPServerConfig? {
        mcpManager.servers.first { $0.name == serverName }
    }

    var body: some View {
        if let server = server {
            serverContent(server)
        }
    }

    @ViewBuilder
    private func serverContent(_ server: MCPServerConfig) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(server.name)
                        .fontWeight(.medium)

                    // Transport type badge
                    Text(server.transportType.rawValue.uppercased())
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.primary.opacity(0.08))
                        )
                        .foregroundStyle(Color.secondary)
                }

                if server.transportType == .stdio {
                    Text("\(server.command) \(server.args.joined(separator: " "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(server.url ?? "No URL")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            connectionStatusView(server)

            Toggle("", isOn: Binding(
                get: {
                    if let index = mcpManager.servers.firstIndex(where: { $0.name == server.name }) {
                        return mcpManager.servers[index].enabled
                    }
                    return false
                },
                set: { newValue in
                    mcpManager.toggleServer(named: server.name, enabled: newValue)
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(12)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                showingEditSheet = true
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Button(role: .destructive) {
                mcpManager.removeServer(named: serverName)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            MCPServerEditor(isPresented: $showingEditSheet, editingServer: server)
        }
    }

    @ViewBuilder
    private func connectionStatusView(_ server: MCPServerConfig) -> some View {
        HStack(spacing: 6) {
            // OAuth status for HTTP servers
            if server.transportType == .http {
                oauthStatusIcon(server)
            }

            // Connection status
            Group {
                switch mcpManager.connectionStatus[server.name] {
                case .none, .notConnected:
                    Image(systemName: "circle.fill")
                        .foregroundStyle(.tertiary)
                        .imageScale(.small)
                case .connecting:
                    ProgressView()
                        .controlSize(.small)
                case .connected:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .imageScale(.small)
                case .failed(let error):
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                        .imageScale(.small)
                        .help(error)
                }
            }
        }
    }

    @ViewBuilder
    private func oauthStatusIcon(_ server: MCPServerConfig) -> some View {
        let tokenInfo = oauth.token(for: server)

        if let info = tokenInfo {
            if info.isExpired() {
                Image(systemName: "key.fill")
                    .foregroundStyle(.orange)
                    .imageScale(.small)
                    .help("OAuth token expired - will refresh on next connection")
            } else {
                Image(systemName: "key.fill")
                    .foregroundStyle(.green)
                    .imageScale(.small)
                    .help("OAuth authenticated")
            }
        } else {
            EmptyView()
        }
    }
}

// MARK: - Server Form View
