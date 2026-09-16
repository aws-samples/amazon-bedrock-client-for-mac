import SwiftUI

struct MCPImportPreview: Identifiable {
    let id = UUID()
    let servers: [MCPServerConfig]
}

struct MCPImportView: View {
    let preview: MCPImportPreview
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var manager = MCPClientManager.shared
    @State private var selected: Set<String> = []
    @State private var importing = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Import MCP servers").font(.title2.weight(.semibold))
            Text("Choose the servers to import. Existing names are only replaced when selected. Imported servers remain disabled.")
                .font(DesignTokens.body).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(preview.servers) { server in
                        let replacement = manager.servers.contains { $0.name == server.name }
                        VStack(alignment: .leading, spacing: 7) {
                            Toggle(isOn: Binding(get: { selected.contains(server.name) }, set: {
                                if $0 { selected.insert(server.name) } else { selected.remove(server.name) }
                            })) {
                                HStack {
                                    Text(server.name).font(DesignTokens.label).lineLimit(1)
                                    Spacer()
                                    Text(replacement ? "Replace existing" : "Add")
                                        .font(DesignTokens.detail).foregroundStyle(.secondary)
                                }
                            }.toggleStyle(AppSwitchStyle())
                            Text(server.transportType.displayName)
                                .font(DesignTokens.detail).foregroundStyle(.secondary)
                            Text(MCPConfiguration.previewAddress(server))
                                .font(.system(size: 11, design: .monospaced)).lineLimit(2)
                                .textSelection(.enabled)
                            if !(server.env ?? [:]).isEmpty || !(server.headers ?? [:]).isEmpty || server.clientSecret != nil {
                                Text("Credential values are hidden in this preview.")
                                    .font(DesignTokens.detail).foregroundStyle(.secondary)
                            }
                        }
                        .padding(14)
                        .background(DesignTokens.surface, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }.frame(maxHeight: 360)
            if let error { Text(error).font(DesignTokens.detail).foregroundStyle(.orange) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(importing)
                Spacer()
                if importing { ProgressView().controlSize(.small) }
                Button("Import \(selected.count) server\(selected.count == 1 ? "" : "s")", action: importSelected)
                    .buttonStyle(AppButtonStyle(prominent: true))
                    .disabled(selected.isEmpty || importing)
            }
        }
        .padding(24).frame(width: 560)
        .buttonStyle(AppButtonStyle())
        .interactiveDismissDisabled(importing)
        .onAppear {
            let existing = Set(manager.servers.map(\.name))
            selected = Set(preview.servers.map(\.name)).subtracting(existing)
        }
    }

    private func importSelected() {
        importing = true
        Task {
            defer { importing = false }
            do {
                // Validate every chosen server before disconnecting or writing.
                _ = try MCPConfiguration.merging(preview.servers, selected: selected, into: manager.servers)
                for name in selected where manager.servers.contains(where: { $0.name == name }) {
                    await manager.disconnectServer(name)
                }
                manager.servers = try MCPConfiguration.merging(preview.servers, selected: selected, into: manager.servers)
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
