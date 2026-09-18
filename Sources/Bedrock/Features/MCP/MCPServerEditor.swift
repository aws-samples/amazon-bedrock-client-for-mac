import AppKit
import SwiftUI
import MCP

struct MCPServerEditor: View {
    @Binding var isPresented: Bool
    @ObservedObject private var settingsManager = PreferencesStore.shared
    @ObservedObject private var mcpManager = MCPClientManager.shared
    @ObservedObject private var oauth = MCPOAuthService.shared
    
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
                            AppSegmentedControl(title: "Transport type", selection: $transportType,
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
        let tokenInfo = oauth.token(for: server)
        let hasToken = tokenInfo != nil
        
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("OAuth Status")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
            }
            
            HStack(spacing: 12) {
                if hasToken {
                    if let info = tokenInfo, !info.isExpired() {
                        Label("Authenticated", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        
                        Spacer()
                        
                        Button("Clear Token") {
                            oauth.clearToken(for: server)
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
            if let error = oauth.persistenceError {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(.horizontal)
    }
    
    private func authenticateServer(_ server: MCPServerConfig) async {
        do {
            try await oauth.authenticate(for: server)
            await mcpManager.disconnectServer(server.name)
            mcpManager.connectToServer(server)
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

        do { try MCPConfiguration.validate(serverConfig) }
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
