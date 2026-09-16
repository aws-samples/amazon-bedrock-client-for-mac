import Foundation
import Logging
import SwiftUI

struct MultilineRoundedTextField: View {
    @Binding var text: String
    var placeholder: String
    @FocusState private var isFocused: Bool
    @State private var localText = ""
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $localText)
                .font(WorkbenchStyle.body)
                .padding(6)
                .focused($isFocused)
                .scrollContentBackground(.hidden)
                .accessibilityLabel("System prompt")
                .accessibilityIdentifier("settings.systemPromptEditor")
            if localText.isEmpty {
                Text(placeholder)
                    .font(WorkbenchStyle.body).foregroundStyle(.tertiary)
                    .padding(.horizontal, 11).padding(.vertical, 8)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(isFocused ? WorkbenchStyle.accent.opacity(0.65) : WorkbenchStyle.border, lineWidth: 1))
        .onAppear { localText = text }
        .onChange(of: localText) { _, value in
            saveTask?.cancel()
            guard value != text else { return }
            saveTask = Task { @MainActor in
                do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
                if text != value { text = value }
            }
        }
        .onChange(of: text) { _, value in
            guard value != localText else { return }
            saveTask?.cancel()
            localText = value
        }
        .onChange(of: isFocused) { _, focused in if !focused { flush() } }
        .onDisappear { flush() }
    }

    private func flush() {
        saveTask?.cancel()
        if text != localText { text = localText }
    }
}

// MARK: - Server Row

struct ServerRow: View {
    @ObservedObject private var settingsManager = SettingManager.shared
    @ObservedObject private var mcpManager = MCPManager.shared
    let serverName: String
    @State private var showingEditSheet = false
    
    // Get server from MCPManager to ensure we always have the latest data
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
            ServerFormView(isPresented: $showingEditSheet, editingServer: server)
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
        let tokenInfo = MCPOAuthManager.shared.tokenStorage[server.name]
        
        if let info = tokenInfo {
            if info.isExpired {
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

struct ServerFormView: View {
    @Binding var isPresented: Bool
    @ObservedObject private var settingsManager = SettingManager.shared
    @ObservedObject private var mcpManager = MCPManager.shared
    
    var editingServer: MCPServerConfig?
    
    @State private var name: String = ""
    @State private var transportType: MCPTransportType = .stdio
    
    // Stdio fields
    @State private var command: String = ""
    @State private var args: String = ""
    @State private var envPairs: [(key: String, value: String)] = [("", "")]
    @State private var cwd: String = ""
    
    // HTTP fields
    @State private var url: String = ""
    @State private var headerPairs: [(key: String, value: String)] = [("", "")]
    
    // OAuth credentials (for servers that don't support Dynamic Client Registration)
    @State private var clientId: String = ""
    @State private var clientSecret: String = ""
    
    @State private var errorMessage: String?
    @FocusState private var focusField: Field?
    
    enum Field: Hashable {
        case name, command, args, envKey(Int), envValue(Int), cwd, url, headerKey(Int), headerValue(Int)
    }
    
    private let stdioTemplates: [(name: String, command: String, args: String, env: [String: String]?, cwd: String?)] = [
        ("Memory", "npx", "-y @modelcontextprotocol/server-memory", nil, nil),
        ("Filesystem", "npx", "-y @modelcontextprotocol/server-filesystem ~", nil, nil),
        ("GitHub", "npx", "-y @modelcontextprotocol/server-github", ["GITHUB_PERSONAL_ACCESS_TOKEN": "<YOUR_TOKEN>"], nil)
    ]
    
    private let httpTemplates: [(name: String, url: String, headers: [String: String]?)] = [
        ("Remote MCP", "https://api.example.com/mcp", nil),
        ("Authenticated", "https://api.example.com/mcp", ["Authorization": "Bearer <YOUR_TOKEN>"])
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(editingServer == nil ? "Add MCP Server" : "Edit MCP Server")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Form Fields
                    VStack(alignment: .leading, spacing: 16) {
                        // Server Name
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Server Name")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            TextField("e.g., github", text: $name)
                                .textFieldStyle(.roundedBorder)
                                .focused($focusField, equals: .name)
                                .disabled(editingServer != nil)
                        }
                        
                        // Transport Type
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Transport Type")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            WorkbenchSegmentedControl(title: "Transport type", selection: $transportType,
                                                      options: MCPTransportType.allCases.map { ($0, $0.displayName) })
                        }
                    }
                    .padding(.horizontal)
                    
                    // Templates (only for new servers)
                    if editingServer == nil {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Quick Templates")
                                .font(.headline)
                            
                            if transportType == .stdio {
                                HStack(spacing: 12) {
                                    ForEach(stdioTemplates, id: \.name) { template in
                                        Button {
                                            applyStdioTemplate(template)
                                        } label: {
                                            VStack(spacing: 6) {
                                                Image(systemName: "terminal")
                                                    .font(.title2)
                                                Text(template.name)
                                                    .font(.caption)
                                            }
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 16)
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                            } else {
                                HStack(spacing: 12) {
                                    ForEach(httpTemplates, id: \.name) { template in
                                        Button {
                                            applyHTTPTemplate(template)
                                        } label: {
                                            VStack(spacing: 6) {
                                                Image(systemName: "globe")
                                                    .font(.title2)
                                                Text(template.name)
                                                    .font(.caption)
                                            }
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 16)
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    // Transport-specific fields
                    if transportType == .stdio {
                        stdioConfigurationView
                    } else {
                        httpConfigurationView
                    }
                    
                    if let error = errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                            .padding(.horizontal)
                    }
                    
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                        Text("Find more MCP servers on")
                            .foregroundStyle(.secondary)
                        Link("GitHub", destination: URL(string: "https://github.com/modelcontextprotocol/servers")!)
                    }
                    .font(.caption)
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            
            Divider()
            
            // Footer
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button(editingServer == nil ? "Add" : "Save") {
                    saveServer()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 500, height: 600)
        .onAppear {
            loadServerData()
        }
    }
    
    private var isValid: Bool {
        if name.isEmpty { return false }
        
        switch transportType {
        case .stdio:
            return !command.isEmpty
        case .http:
            guard !url.isEmpty else { return false }
            guard let urlObj = URL(string: url) else { return false }
            return urlObj.scheme == "http" || urlObj.scheme == "https"
        }
    }
    
    // MARK: - Stdio Configuration View
    
    private var stdioConfigurationView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Command
            VStack(alignment: .leading, spacing: 6) {
                Text("Command")
                    .font(.subheadline)
                    .fontWeight(.medium)
                TextField("e.g., npx", text: $command)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusField, equals: .command)
            }
            
            // Arguments
            VStack(alignment: .leading, spacing: 6) {
                Text("Arguments")
                    .font(.subheadline)
                    .fontWeight(.medium)
                TextField("e.g., -y @modelcontextprotocol/server-github", text: $args)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusField, equals: .args)
            }
            
            // Working Directory
            VStack(alignment: .leading, spacing: 6) {
                Text("Working Directory")
                    .font(.subheadline)
                    .fontWeight(.medium)
                HStack {
                    TextField("Optional", text: $cwd)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusField, equals: .cwd)
                    
                    Button {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        panel.canCreateDirectories = true
                        panel.prompt = "Select"
                        
                        if panel.runModal() == .OK, let selectedUrl = panel.url {
                            cwd = selectedUrl.path
                        }
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            
            // Environment Variables
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Environment Variables")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Button {
                        envPairs.append(("", ""))
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .imageScale(.large)
                    }
                    .buttonStyle(.plain)
                    .disabled(envPairs.last?.key.isEmpty == true || envPairs.last?.value.isEmpty == true)
                }
                
                ForEach(Array(envPairs.enumerated()), id: \.offset) { index, _ in
                    HStack(spacing: 8) {
                        TextField("Key", text: $envPairs[index].key)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusField, equals: .envKey(index))
                        
                        Text("=")
                            .foregroundStyle(.secondary)
                        
                        TextField("Value", text: $envPairs[index].value)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusField, equals: .envValue(index))
                        
                        if envPairs.count > 1 {
                            Button {
                                envPairs.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                                    .imageScale(.large)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - HTTP Configuration View
    
    private var httpConfigurationView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Server URL
            VStack(alignment: .leading, spacing: 6) {
                Text("Server URL")
                    .font(.subheadline)
                    .fontWeight(.medium)
                TextField("https://api.example.com/mcp", text: $url)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusField, equals: .url)
                
                Text("Supports Streamable HTTP (MCP 2025-03-26 spec)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // OAuth Status (for editing existing servers)
            if let server = editingServer, server.transportType == .http {
                oauthStatusView(for: server)
            }
            
            // Custom Headers
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Custom Headers")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Button {
                        headerPairs.append(("", ""))
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .imageScale(.large)
                    }
                    .buttonStyle(.plain)
                    .disabled(headerPairs.last?.key.isEmpty == true || headerPairs.last?.value.isEmpty == true)
                }
                
                ForEach(Array(headerPairs.enumerated()), id: \.offset) { index, _ in
                    HStack(spacing: 8) {
                        TextField("Header Name", text: $headerPairs[index].key)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusField, equals: .headerKey(index))
                        
                        Text(":")
                            .foregroundStyle(.secondary)
                        
                        TextField("Value", text: $headerPairs[index].value)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusField, equals: .headerValue(index))
                        
                        if headerPairs.count > 1 {
                            Button {
                                headerPairs.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                                    .imageScale(.large)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                Text("e.g., Authorization: Bearer your-token")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // OAuth Credentials (optional)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("OAuth Credentials")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("(Optional)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Text("For servers like Box that require pre-registered OAuth clients")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Client ID", text: $clientId)
                        .textFieldStyle(.roundedBorder)
                    
                    SecureField("Client Secret", text: $clientSecret)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private func oauthStatusView(for server: MCPServerConfig) -> some View {
        let hasToken = MCPOAuthManager.shared.tokenStorage[server.name] != nil
        let tokenInfo = MCPOAuthManager.shared.tokenStorage[server.name]
        
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("OAuth Status")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
            }
            
            HStack(spacing: 12) {
                if hasToken {
                    if let info = tokenInfo, !info.isExpired {
                        Label("Authenticated", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        
                        Spacer()
                        
                        Button("Clear Token") {
                            MCPOAuthManager.shared.clearToken(for: server.name)
                        }
                        .font(.caption)
                        .foregroundStyle(.red)
                    } else {
                        Label("Token Expired", systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                        
                        Spacer()
                        
                        Button("Re-authenticate") {
                            Task {
                                await authenticateServer(server)
                            }
                        }
                        .font(.caption)
                    }
                } else {
                    Label("Not authenticated", systemImage: "lock.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    
                    Text("OAuth will be triggered automatically on connection if required")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
        }
        .padding(.horizontal)
    }
    
    private func authenticateServer(_ server: MCPServerConfig) async {
        do {
            _ = try await MCPOAuthManager.shared.authenticate(for: server)
        } catch {
            errorMessage = "Authentication failed: \(error.localizedDescription)"
        }
    }
    
    private func loadServerData() {
        if let server = editingServer {
            name = server.name
            transportType = server.transportType
            
            // Stdio fields
            command = server.command
            args = LocalArguments.display(server.args)
            cwd = server.cwd ?? ""
            
            if let env = server.env, !env.isEmpty {
                envPairs = env.map { ($0.key, $0.value) }
            } else {
                envPairs = [("", "")]
            }
            
            // HTTP fields
            url = server.url ?? ""
            clientId = server.clientId ?? ""
            clientSecret = server.clientSecret ?? ""
            
            if let headers = server.headers, !headers.isEmpty {
                headerPairs = headers.map { ($0.key, $0.value) }
            } else {
                headerPairs = [("", "")]
            }
        } else {
            envPairs = [("", "")]
            headerPairs = [("", "")]
        }
    }
    
    private func applyStdioTemplate(_ template: (name: String, command: String, args: String, env: [String: String]?, cwd: String?)) {
        name = template.name.lowercased()
        command = template.command
        args = template.args
        cwd = template.cwd ?? ""
        
        if let templateEnv = template.env, !templateEnv.isEmpty {
            envPairs = templateEnv.map { ($0.key, $0.value) }
        } else {
            envPairs = [("", "")]
        }
        
        errorMessage = nil
    }
    
    private func applyHTTPTemplate(_ template: (name: String, url: String, headers: [String: String]?)) {
        name = template.name.lowercased().replacingOccurrences(of: " ", with: "-")
        url = template.url
        
        if let templateHeaders = template.headers, !templateHeaders.isEmpty {
            headerPairs = templateHeaders.map { ($0.key, $0.value) }
        } else {
            headerPairs = [("", "")]
        }
        
        errorMessage = nil
    }
    
    private func saveServer() {
        guard validateInputs() else { return }
        
        let serverConfig: MCPServerConfig
        
        switch transportType {
        case .stdio:
            let argArray: [String]
            do { argArray = try LocalArguments.parse(args) }
            catch { errorMessage = error.localizedDescription; return }
            
            var envDict: [String: String]? = nil
            let filteredPairs = envPairs.filter { !$0.key.isEmpty && !$0.value.isEmpty }
            if !filteredPairs.isEmpty {
                envDict = Dictionary(uniqueKeysWithValues: filteredPairs)
            }
            
            serverConfig = MCPServerConfig(
                name: name,
                transportType: .stdio,
                command: command,
                args: argArray,
                env: envDict,
                cwd: cwd.isEmpty ? nil : cwd,
                enabled: true
            )
            
        case .http:
            var headersDict: [String: String]? = nil
            let filteredHeaders = headerPairs.filter { !$0.key.isEmpty && !$0.value.isEmpty }
            if !filteredHeaders.isEmpty {
                headersDict = Dictionary(uniqueKeysWithValues: filteredHeaders)
            }
            
            serverConfig = MCPServerConfig(
                name: name,
                transportType: .http,
                url: url,
                headers: headersDict,
                clientId: clientId.isEmpty ? nil : clientId,
                clientSecret: clientSecret.isEmpty ? nil : clientSecret,
                enabled: true
            )
        }

        do { try WorkbenchMCPConfiguration.validate(serverConfig) }
        catch { errorMessage = error.localizedDescription; return }
        
        if let editingServer = editingServer {
            // Update existing server
            mcpManager.updateServer(serverConfig)
            isPresented = false
        } else {
            // Add new server
            if !mcpManager.servers.contains(where: { $0.name == name }) {
                mcpManager.addServer(serverConfig)
                isPresented = false
            } else {
                errorMessage = "A server with this name already exists"
            }
        }
    }
    
    private func validateInputs() -> Bool {
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let environmentKeys = envPairs.map(\.key).filter { !$0.isEmpty }
        let headerKeys = headerPairs.map { $0.key.lowercased() }.filter { !$0.isEmpty }
        guard Set(environmentKeys).count == environmentKeys.count, Set(headerKeys).count == headerKeys.count else {
            errorMessage = "Remove duplicate environment variable or header names."
            return false
        }
        if name.isEmpty {
            errorMessage = "Server name cannot be empty"
            focusField = .name
            return false
        }
        
        if editingServer == nil && mcpManager.servers.contains(where: { $0.name == name }) {
            errorMessage = "A server with this name already exists"
            focusField = .name
            return false
        }
        
        switch transportType {
        case .stdio:
            if command.isEmpty {
                errorMessage = "Command cannot be empty"
                focusField = .command
                return false
            }
            
        case .http:
            if url.isEmpty {
                errorMessage = "Server URL cannot be empty"
                focusField = .url
                return false
            }
            
            guard let urlObj = URL(string: url) else {
                errorMessage = "Invalid URL format"
                focusField = .url
                return false
            }
            
            if urlObj.scheme != "http" && urlObj.scheme != "https" {
                errorMessage = "URL must start with http:// or https://"
                focusField = .url
                return false
            }
        }
        
        return true
    }
}

// MARK: - Font Size Control

struct FontSizeControl: View {
    @AppStorage("adjustedFontSize") private var adjustedFontSize: Int = -1
    
    // Map internal values to display values (0-12 scale)
    private var displayValue: Int {
        adjustedFontSize + 5  // -4 becomes 1, -1 becomes 4, 0 becomes 5, 8 becomes 13
    }
    
    private func setDisplayValue(_ value: Int) {
        adjustedFontSize = value - 5  // Convert back to internal scale
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Button {
                if adjustedFontSize > -4 {
                    adjustedFontSize -= 1
                }
            } label: {
                Image(systemName: "textformat.size.smaller")
                    .font(.system(size: 13))
            }
            .buttonStyle(.borderless)
            .disabled(adjustedFontSize <= -4)
            .help("Decrease text size")
            .accessibilityLabel("Decrease text size")
            
            Text(fontSizeLabel)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 50)
            
            Button {
                if adjustedFontSize < 8 {
                    adjustedFontSize += 1
                }
            } label: {
                Image(systemName: "textformat.size.larger")
                    .font(.system(size: 13))
            }
            .buttonStyle(.borderless)
            .disabled(adjustedFontSize >= 8)
            .help("Increase text size")
            .accessibilityLabel("Increase text size")
        }
    }
    
    private var fontSizeLabel: String {
        let displayNum = displayValue
        if adjustedFontSize == -1 {
            return "Default"
        } else {
            return "\(displayNum)"
        }
    }
}

// MARK: - System Prompt Section (for GeneralSettingsView)

struct SystemPromptSection: View {
    @StateObject private var templateManager = PromptTemplateManager.shared
    @State private var showingAddSheet = false
    @State private var showingRenameSheet = false
    @State private var showingDeleteAlert = false
    @State private var newName = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Menu-style template selector with management options
            HStack(spacing: 12) {
                Text("System prompt").font(WorkbenchStyle.label)
                Spacer(minLength: 12)
                WorkbenchActionMenu {
                    // Template list
                    ForEach(templateManager.templates) { template in
                        Button {
                            templateManager.selectTemplate(template)
                        } label: {
                            HStack {
                                Text(template.name)
                                if templateManager.selectedTemplateId == template.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Management options
                    Button {
                        newName = ""
                        showingAddSheet = true
                    } label: {
                        Label("Add New Preset...", systemImage: "plus")
                    }
                    
                    if templateManager.selectedTemplate != nil {
                        Button {
                            newName = templateManager.selectedTemplate?.name ?? ""
                            showingRenameSheet = true
                        } label: {
                            Label("Rename...", systemImage: "pencil")
                        }
                        
                        if templateManager.templates.count > 1 {
                            Button(role: .destructive) {
                                showingDeleteAlert = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(templateManager.selectedTemplate?.name ?? "Default")
                            .font(WorkbenchStyle.body).lineLimit(1).truncationMode(.tail)
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(.primary)
                    .frame(maxWidth: 220, alignment: .trailing)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("System prompt preset")
            }

            if let selected = templateManager.selectedTemplate {
                // Capture the preset identity: a pending edit must never write
                // into the next preset when the selection changes.
                MultilineRoundedTextField(
                    text: Binding(
                        get: { templateManager.templates.first { $0.id == selected.id }?.content ?? "" },
                        set: { newContent in
                            if var template = templateManager.templates.first(where: { $0.id == selected.id }), template.content != newContent {
                                template.content = newContent
                                templateManager.updateTemplate(template)
                            }
                        }
                    ),
                    placeholder: "Instructions for how the model should respond…"
                )
                .id(selected.id)
                .frame(height: 128)
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            PromptNameSheet(
                isPresented: $showingAddSheet,
                title: "New System Prompt",
                name: $newName,
                buttonTitle: "Create",
                onSave: {
                    templateManager.addTemplate(name: newName, content: "")
                }
            )
        }
        .sheet(isPresented: $showingRenameSheet) {
            PromptNameSheet(
                isPresented: $showingRenameSheet,
                title: "Rename Preset",
                name: $newName,
                buttonTitle: "Save",
                onSave: {
                    if var template = templateManager.selectedTemplate {
                        template.name = newName
                        templateManager.updateTemplate(template)
                    }
                }
            )
        }
        .alert("Delete Preset?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let template = templateManager.selectedTemplate {
                    templateManager.deleteTemplate(template)
                }
            }
        } message: {
            Text("Are you sure you want to delete \"\(templateManager.selectedTemplate?.name ?? "")\"?")
        }
    }
}

// MARK: - Prompt Name Sheet (for Add/Rename)
struct PromptNameSheet: View {
    @Binding var isPresented: Bool
    let title: String
    @Binding var name: String
    let buttonTitle: String
    let onSave: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.headline)
            
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
            
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button(buttonTitle) {
                    onSave()
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 280)
    }
}
