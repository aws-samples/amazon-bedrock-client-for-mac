//
//  SettingsView.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/08.
//

import Foundation
import Logging
import SwiftUI

struct SettingsView: View {
    @StateObject private var settingsManager = SettingManager.shared
    @State private var selectedTab: SettingsTab = .general
    private var logger = Logger(label: "SettingsView")
    
    // Simplified tab structure with just two main tabs
    enum SettingsTab: String, CaseIterable, Identifiable {
        case general, developer
        
        var id: String { self.rawValue }
        
        var title: String {
            switch self {
            case .general: return "General"
            case .developer: return "Developer"
            }
        }
        
        var imageName: String {
            switch self {
            case .general: return "gearshape"
            case .developer: return "terminal"
            }
        }
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(SettingsTab.general)
            
            DeveloperSettingsView()
                .tabItem {
                    Label("Developer", systemImage: "terminal")
                }
                .tag(SettingsTab.developer)
        }
        .frame(width: 550, height: 550)
        .padding()
    }
}

// Optimized multiline text field with better rendering performance
struct MultilineRoundedTextField: View {
    @Binding var text: String
    var placeholder: String
    @FocusState private var isFocused: Bool
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Using TextEditor with optimized background handling
            TextEditor(text: $text)
                .font(.body)
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
                .focused($isFocused)
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            isFocused ? Color.accentColor : Color.gray.opacity(0.5),
                            lineWidth: isFocused ? 2 : 1)
                )
            
            // Placeholder with better hit testing
            if text.isEmpty {
                Text(placeholder)
                    .font(.body)
                    .foregroundColor(Color.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(6)
    }
}

struct GeneralSettingsView: View {
    @ObservedObject private var settingsManager = SettingManager.shared
    @State private var showingLoginSheet = false
    @State private var showPausedRegions: Bool = false
    @State private var showGovCloudRegions: Bool = false
    @State private var loginError: String?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) { // Reduced spacing
                // AWS Configuration section
                Group {
                    Text("AWS Configuration")
                        .font(.headline)
                    
                    // AWS Region (inline style)
                    HStack(alignment: .center) {
                        Text("AWS Region:")
                            .frame(width: 100, alignment: .leading)
                        
                        Picker("", selection: $settingsManager.selectedRegion) {
                            // North America regions
                            Section(AWSRegionSection.northAmerica.rawValue) {
                                ForEach(AWSRegion.regions(in: .northAmerica, includePaused: showPausedRegions), id: \.self) { region in
                                    Text(region.name).tag(region)
                                }
                            }
                            
                            // Europe regions
                            Section(AWSRegionSection.europe.rawValue) {
                                ForEach(AWSRegion.regions(in: .europe, includePaused: showPausedRegions), id: \.self) { region in
                                    Text(region.name).tag(region)
                                }
                            }
                            
                            // Asia Pacific regions
                            Section(AWSRegionSection.asiaPacific.rawValue) {
                                ForEach(AWSRegion.regions(in: .asiaPacific, includePaused: showPausedRegions), id: \.self) { region in
                                    Text(region.name).tag(region)
                                }
                            }
                            
                            // Other regions
                            Section(AWSRegionSection.other.rawValue) {
                                ForEach(AWSRegion.regions(in: .other, includePaused: showPausedRegions), id: \.self) { region in
                                    Text(region.name).tag(region)
                                }
                            }
                            
                            // GovCloud regions
                            if showGovCloudRegions {
                                Section(AWSRegionSection.govCloud.rawValue) {
                                    ForEach(AWSRegion.regions(in: .govCloud), id: \.self) { region in
                                        Text(region.name).tag(region)
                                    }
                                }
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                    
                    // AWS Profile section (already inline)
                    HStack(alignment: .center) {
                        Text("AWS Profile:")
                            .frame(width: 100, alignment: .leading)
                        //                    Button(action: {
                        //                        showingLoginSheet = true
                        //                    }) {
                        //                        HStack {
                        //                            Image(systemName: "person.crop.circle.badge.plus")
                        //                            Text("Sign in with AWS Identity Center")
                        //                        }
                        //                    }
                        //                    .buttonStyle(PlainButtonStyle())
                        if settingsManager.isSSOLoggedIn {
                            HStack {
                                Text("Logged in with AWS Identity Center")
                                Spacer()
                                Button("Log Out") {
                                    // SSO logout functionality
                                }
                                .buttonStyle(.bordered)
                            }
                        } else {
                            Picker("", selection: $settingsManager.selectedProfile) {
                                ForEach(settingsManager.profiles) { profile in
                                    Text(profile.name).tag(profile.name)
                                }
                            }
                            .labelsHidden()
                        }
                    }
                }
                
                Divider().padding(.vertical, 8)
                
                // App settings section
                Group {
                    Text("Application")
                        .font(.headline)
                    
                    Toggle("Check for Updates", isOn: $settingsManager.checkForUpdates)
                        .padding(.vertical, 2)
                    
                    // Appearance controls
                    HStack(alignment: .center) {
                        Text("Appearance:")
                            .frame(width: 100, alignment: .leading)
                        
                        Picker("", selection: $settingsManager.appearance) {
                            Text("Light").tag("Light")
                            Text("Dark").tag("Dark")
                            Text("Auto").tag("Auto")
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .labelsHidden()
                        .onChange(of: settingsManager.appearance) { newValue in
                            applyAppearance(newValue)
                        }
                    }
                }
                
                Divider().padding(.vertical, 8)
                
                // Model settings section
                Group {
                    Text("Model Settings")
                        .font(.headline)
                    
                    HStack(alignment: .center) {
                        Text("Default Model:")
                            .frame(width: 100, alignment: .leading)
                        
                        Picker("", selection: $settingsManager.defaultModelId) {
                            ForEach(settingsManager.availableModels, id: \.id) { model in
                                Text(model.id).tag(model.id)
                            }
                        }
                        .labelsHidden()
                    }
                    
                    Text("System prompt:")
                    MultilineRoundedTextField(
                        text: $settingsManager.systemPrompt,
                        placeholder: "Tell me more about yourself or how you want me to respond"
                    )
                    .frame(height: 120)
                }
            }
            .padding()
            //        .sheet(isPresented: $showingLoginSheet) {
            //            AwsIdentityCenterLoginView(isPresented: $showingLoginSheet, loginError: $loginError)
            //        }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            applyAppearance(settingsManager.appearance)
        }
    }
    
    private func applyAppearance(_ appearance: String) {
        switch appearance {
        case "Light":
            NSApp.appearance = NSAppearance(named: .aqua)
        case "Dark":
            NSApp.appearance = NSAppearance(named: .darkAqua)
        default:
            NSApp.appearance = nil  // Use system default
        }
    }
}

struct DeveloperSettingsView: View {
    @ObservedObject private var settingsManager = SettingManager.shared
    @ObservedObject private var mcpManager = MCPManager.shared
    @State private var newServerName: String = ""
    @State private var newServerCommand: String = ""
    @State private var newServerArgs: String = ""
    @State private var showingAddServerSheet = false
    @State private var nodeInstalled: Bool = true
    @State private var isCheckingNode: Bool = false
    @State private var tempEndpoint: String = ""
    @State private var tempRuntimeEndpoint: String = ""
    
    private var logger = Logger(label: "DeveloperSettingsView")
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) { // Reduced spacing
                // Model Context Protocol section
                Group {
                    Text("Model Context Protocol (MCP)")
                        .font(.headline)
                    
                    Toggle("Enable MCP", isOn: $settingsManager.mcpEnabled)
                        .help("Enable integration with Model Context Protocol servers")
                        .padding(.vertical, 2)
                    
                    if settingsManager.mcpEnabled {
                        VStack(alignment: .leading, spacing: 10) {
                            // Server section header
                            HStack {
                                Text("Configured Servers")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button(action: {
                                    showingAddServerSheet = true
                                }) {
                                    Label("Add Server", systemImage: "plus")
                                }
                                .buttonStyle(.bordered)
                            }
                            
                            // Server list
                            if settingsManager.mcpServers.isEmpty {
                                Text("No MCP servers configured")
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(settingsManager.mcpServers) { server in
                                        ServerRow(server: server)
                                        if server.id != settingsManager.mcpServers.last?.id {
                                            Divider()
                                        }
                                    }
                                }
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                )
                            }
                            
                            // Helper text
                            Text("MCP allows your LLM to access tools from your local machine. Add servers only from trusted sources.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Divider().padding(.vertical, 8)
                
                // Advanced section
                Group {
                    Text("Advanced Settings")
                        .font(.headline)
                    
                    // Directory settings
                    HStack(alignment: .center) {
                        Text("Default Directory:")
                            .frame(width: 140, alignment: .leading)
                            
                        TextField("", text: $settingsManager.defaultDirectory)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .disabled(true)
                        
                        Button(action: {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = false
                            panel.canChooseDirectories = true
                            panel.allowsMultipleSelection = false
                            panel.canCreateDirectories = true
                            panel.prompt = "Select"
                            
                            if panel.runModal() == .OK, let url = panel.url {
                                settingsManager.defaultDirectory = url.path
                            }
                        }) {
                            Text("Browse")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 2)
                    
                    // Endpoint settings with onEditingChanged to apply when focus is lost
                    HStack(alignment: .center) {
                        Text("Bedrock Endpoint:")
                            .frame(width: 140, alignment: .leading)
                            
                        TextField("", text: $tempEndpoint)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onAppear { tempEndpoint = settingsManager.endpoint }
                            .onSubmit {
                                settingsManager.endpoint = tempEndpoint
                            }
                            .onExitCommand {
                                settingsManager.endpoint = tempEndpoint
                            }
                    }
                    .padding(.vertical, 0)
                    
                    HStack(alignment: .center) {
                        Text("Bedrock Runtime Endpoint:")
                            .frame(width: 140, alignment: .leading)
                            
                        TextField("", text: $tempRuntimeEndpoint)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onAppear { tempRuntimeEndpoint = settingsManager.runtimeEndpoint }
                            .onSubmit {
                                settingsManager.runtimeEndpoint = tempRuntimeEndpoint
                            }
                            .onExitCommand {
                                settingsManager.runtimeEndpoint = tempRuntimeEndpoint
                            }
                    }
                    .padding(.vertical, 2)
                    
                    Toggle("Enable Logging", isOn: $settingsManager.enableDebugLog)
                        .padding(.vertical, 2)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .bottom) {
            // Node.js warning banner, shown only when needed
            if !nodeInstalled && !isCheckingNode {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Node.js is required to run MCP servers. It doesn't appear to be installed on your system.")
                    
                    Button("Install Node.js") {
                        NSWorkspace.shared.open(URL(string: "https://nodejs.org/")!)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
                .padding()
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $showingAddServerSheet) {
            AddServerView(isPresented: $showingAddServerSheet)
        }
        .onAppear {
            settingsManager.loadMCPServers()
            // Run Node.js check asynchronously to avoid UI lag
            isCheckingNode = true
            Task {
                await checkNodeInstalled()
                isCheckingNode = false
            }
        }
    }
    
    // Asynchronous Node.js detection remains the same
    private func checkNodeInstalled() async {
        // Try multiple methods to detect Node.js
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        
        // Method 1: Try sourcing profile and running node
        let sourceProfileScript = """
        source ~/.zshrc 2>/dev/null || source ~/.bash_profile 2>/dev/null || source ~/.profile 2>/dev/null
        command -v node >/dev/null 2>&1 && node --version || echo 'node not found'
        """
        
        // Method 2: Try common Node.js locations
        let checkCommonPathsScript = """
        for path in /usr/local/bin/node /usr/bin/node /opt/homebrew/bin/node ~/.nvm/versions/node/*/bin/node; do
            if [ -x "$path" ]; then
                $path --version
                exit 0
            fi
        done
        echo 'node not found'
        """
        
        // Try each method in sequence
        for (methodIndex, script) in [sourceProfileScript, checkCommonPathsScript].enumerated() {
            let task = Process()
            let pipe = Pipe()
            
            task.standardOutput = pipe
            task.standardError = pipe
            
            task.executableURL = URL(fileURLWithPath: "/bin/zsh")
            task.arguments = ["-c", script]
            
            // Set HOME environment variable explicitly
            var env = ProcessInfo.processInfo.environment
            env["HOME"] = homeDir
            task.environment = env
            
            do {
                try task.run()
                task.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                
                logger.info("Node.js detection method \(methodIndex + 1) output: \(output)")
                
                // If we found Node.js
                if !output.contains("not found") && task.terminationStatus == 0 {
                    await MainActor.run {
                        self.nodeInstalled = true
                    }
                    return
                }
            } catch {
                logger.info("Error in Node.js detection method \(methodIndex + 1): \(error)")
            }
        }
        
        // If all methods failed, Node.js is not installed
        await MainActor.run {
            self.nodeInstalled = false
        }
    }
}

// Server row view for MCP server list
struct ServerRow: View {
    @ObservedObject private var settingsManager = SettingManager.shared
    @ObservedObject private var mcpManager = MCPManager.shared
    var server: MCPServerConfig
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(server.name)
                    .fontWeight(.medium)
                Text("\(server.command) \(server.args.joined(separator: " "))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Connection status indicator
            connectionStatusView
                .frame(width: 16)
            
            // Enable/disable toggle
            Toggle("", isOn: Binding(
                get: {
                    if let index = settingsManager.mcpServers.firstIndex(where: { $0.name == server.name }) {
                        return settingsManager.mcpServers[index].enabled
                    }
                    return false
                },
                set: { newValue in
                    if let index = settingsManager.mcpServers.firstIndex(where: { $0.name == server.name }) {
                        settingsManager.mcpServers[index].enabled = newValue
                        if newValue {
                            mcpManager.connectToServer(settingsManager.mcpServers[index])
                        } else {
                            Task {
                                await mcpManager.disconnectServer(server.name)
                            }
                        }
                        settingsManager.saveMCPConfigFile()
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(12)
        .contentShape(Rectangle())
        .contextMenu {
            Button(role: .destructive) {
                if let index = settingsManager.mcpServers.firstIndex(where: { $0.name == server.name }) {
                    Task {
                        await mcpManager.disconnectServer(server.name)
                    }
                    settingsManager.mcpServers.remove(at: index)
                    settingsManager.saveMCPConfigFile()
                }
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }
    
    // Connection status indicator
    private var connectionStatusView: some View {
        Group {
            switch mcpManager.connectionStatus[server.name] {
            case .none, .notConnected:
                Image(systemName: "circle")
                    .foregroundColor(.gray)
            case .connecting:
                ProgressView()
                    .scaleEffect(0.7)
            case .connected:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .failed(let error):
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.red)
                    .help(error)
            }
        }
    }
}

// Add server sheet view
struct AddServerView: View {
    @Binding var isPresented: Bool
    @ObservedObject private var settingsManager = SettingManager.shared
    @ObservedObject private var mcpManager = MCPManager.shared
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var name: String = ""
    @State private var command: String = ""
    @State private var args: String = ""
    @State private var errorMessage: String?
    @FocusState private var focusField: Field?
    
    enum Field {
        case name, command, args
    }
    
    // 서버 템플릿 확장
    private let templates = [
        ("Filesystem", "npx", "-y @modelcontextprotocol/server-filesystem \"$HOME\""),
        ("Time", "uvx", "mcp-server-time"),
        ("Memory", "npx", "-y @modelcontextprotocol/server-memory")
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // 헤더
            HStack {
                Text("Add MCP Server")
                    .font(.headline)
                Spacer()
            }
            .padding([.horizontal, .top])
            .padding(.bottom, 8)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 폼 필드 그룹
                    Group {
                        // 서버 이름 필드
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Server Name")
                                .fontWeight(.medium)
                            
                            TextField("e.g., filesystem", text: $name)
                                .textFieldStyle(.roundedBorder)
                                .focused($focusField, equals: .name)
                        }
                        
                        // 명령어 필드
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Command")
                                .fontWeight(.medium)
                            
                            TextField("e.g., npx", text: $command)
                                .textFieldStyle(.roundedBorder)
                                .focused($focusField, equals: .command)
                        }
                        
                        // 인자 필드
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Arguments (space-separated)")
                                .fontWeight(.medium)
                            
                            TextField("e.g., -y @modelcontextprotocol/server-filesystem", text: $args)
                                .textFieldStyle(.roundedBorder)
                                .focused($focusField, equals: .args)
                        }
                    }
                    
                    // 에러 메시지
                    if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    
                    // 템플릿 섹션
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Quick Templates")
                            .font(.headline)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(templates, id: \.0) { template in
                                Button {
                                    name = template.0.lowercased()
                                    command = template.1
                                    args = template.2
                                    errorMessage = nil
                                } label: {
                                    HStack {
                                        Image(systemName: "server.rack")
                                            .imageScale(.small)
                                        Text(template.0)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.regular)
                            }
                        }
                    }
                    
                    // GitHub 정보
                    VStack(alignment: .leading, spacing: 4) {
                        Divider().padding(.vertical, 4)
                        
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.secondary)
                            Text("Find more MCP servers on")
                                .foregroundColor(.secondary)
                            Link("GitHub", destination: URL(string: "https://github.com/modelcontextprotocol/servers")!)
                        }
                        .font(.caption)
                    }
                }
                .padding()
            }
            
            Divider()
            
            // 액션 버튼
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Add") {
                    if validateInputs() {
                        let argArray = args.split(separator: " ").map(String.init)
                        let newServer = MCPServerConfig(
                            name: name,
                            command: command,
                            args: argArray,
                            enabled: true
                        )
                        
                        // 중복 이름 확인
                        if !settingsManager.mcpServers.contains(where: { $0.name == name }) {
                            settingsManager.mcpServers.append(newServer)
                            settingsManager.saveMCPConfigFile()
                            
                            // MCP가 활성화된 경우 서버 연결
                            if settingsManager.mcpEnabled {
                                Task {
                                    await MainActor.run {
                                        isPresented = false
                                    }
                                    
                                    mcpManager.connectToServer(newServer)
                                    
                                    try? await Task.sleep(nanoseconds: 3_000_000_000) // 3초 대기
                                    
                                    await MainActor.run {
                                        if case .failed = mcpManager.connectionStatus[newServer.name] {
                                            Task {
                                                await mcpManager.disconnectServer(newServer.name)
                                                
                                                if let index = settingsManager.mcpServers.firstIndex(where: { $0.name == newServer.name }) {
                                                    settingsManager.mcpServers.remove(at: index)
                                                    settingsManager.saveMCPConfigFile()
                                                    
                                                    NotificationCenter.default.post(
                                                        name: NSNotification.Name("ShowNotification"),
                                                        object: nil,
                                                        userInfo: [
                                                            "title": "Server Connection Failed",
                                                            "message": "Failed to connect to server '\(newServer.name)'. The configuration has been removed."
                                                        ]
                                                    )
                                                }
                                            }
                                        }
                                    }
                                }
                            } else {
                                isPresented = false
                            }
                        } else {
                            errorMessage = "A server with this name already exists"
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 480)
        .fixedSize(horizontal: true, vertical: false)
    }
    
    private var isValid: Bool {
        return !name.isEmpty && !command.isEmpty
    }
    
    private func validateInputs() -> Bool {
        if name.isEmpty {
            errorMessage = "Server name cannot be empty"
            focusField = .name
            return false
        }
        
        if command.isEmpty {
            errorMessage = "Command cannot be empty"
            focusField = .command
            return false
        }
        
        return true
    }
}
