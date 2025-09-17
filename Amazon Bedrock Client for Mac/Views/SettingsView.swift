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
                    
                    Toggle("Show Usage Information", isOn: $settingsManager.showUsageInfo)
                        .help("Display token usage information below assistant messages")
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
                            
                            HStack(alignment: .center) {
                                Text("Max Tool Use Turns:")
                                    .frame(width: 140, alignment: .leading)
                                
                                TextField("", value: $settingsManager.maxToolUseTurns, formatter: NumberFormatter())
                                    .frame(width: 60)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .onChange(of: settingsManager.maxToolUseTurns) { newValue in
                                        if newValue < 1 {
                                            settingsManager.maxToolUseTurns = 1
                                        } else if newValue > 1000 {
                                            settingsManager.maxToolUseTurns = 1000
                                        }
                                    }
                            }
                            .padding(.vertical, 2)
                            
                            // Helper text
                            Text("MCP allows your LLM to access tools from your local machine. Add servers only from trusted sources.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Button {
                                // Get the path for the MCP config file
                                let configDir = settingsManager.defaultDirectory.isEmpty
                                    ? FileManager.default.homeDirectoryForCurrentUser.path
                                    : settingsManager.defaultDirectory
                                
                                let configFilePath = URL(fileURLWithPath: configDir)
                                    .appendingPathComponent("mcp_config.json")
                                    .path
                                
                                // Get the parent directory path
                                let parentDirPath = URL(fileURLWithPath: configFilePath).deletingLastPathComponent().path
                                
                                // Create the directory if it doesn't exist
                                if !FileManager.default.fileExists(atPath: parentDirPath) {
                                    try? FileManager.default.createDirectory(atPath: parentDirPath, withIntermediateDirectories: true)
                                }
                                
                                // Show the config file in Finder (or open the directory if file doesn't exist)
                                if FileManager.default.fileExists(atPath: configFilePath) {
                                    NSWorkspace.shared.selectFile(configFilePath, inFileViewerRootedAtPath: parentDirPath)
                                } else {
                                    NSWorkspace.shared.open(URL(fileURLWithPath: parentDirPath))
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "folder")
                                    Text("Open Config File")
                                }
                            }
                            .buttonStyle(.link)
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
                
                Divider().padding(.vertical, 8)
                
                // Local Server section
                Group {
                    Text("Local Server")
                        .font(.headline)
                    
                    Toggle("Enable Local Server", isOn: $settingsManager.enableLocalServer)
                        .help("Enable the local HTTP server for document previews and content rendering")
                        .padding(.vertical, 2)
                    
                    if settingsManager.enableLocalServer {
                        HStack(alignment: .center) {
                            Text("Server Port:")
                                .frame(width: 140, alignment: .leading)
                            
                            TextField("", value: $settingsManager.serverPort, formatter: NumberFormatter())
                                .frame(width: 80)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .onChange(of: settingsManager.serverPort) { newValue in
                                    if newValue < 1024 {
                                        settingsManager.serverPort = 1024
                                    } else if newValue > 65535 {
                                        settingsManager.serverPort = 65535
                                    }
                                }
                            
                            Text("(Requires app restart)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                        
                        Text("The local server is used for document previews and content rendering. Change the port if 8080 conflicts with other services.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $showingAddServerSheet) {
            ServerFormView(isPresented: $showingAddServerSheet)
        }
        .onAppear {
            settingsManager.loadMCPServers()
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
    @State private var showingEditSheet = false
    
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
                        // No need to explicitly call saveMCPConfigFile() as it's handled by didSet
                    }
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
                if let index = settingsManager.mcpServers.firstIndex(where: { $0.name == server.name }) {
                    Task {
                        await mcpManager.disconnectServer(server.name)
                    }
                    settingsManager.mcpServers.remove(at: index)
                    // No need to explicitly call saveMCPConfigFile() as it's handled by didSet
                }
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            ServerFormView(isPresented: $showingEditSheet, editingServer: server)
        }
    }
    
    // Connection status indicator remains unchanged
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

// Define a typealias for templates with optional values
private typealias ServerTemplate = (name: String, command: String, args: String, env: [String: String]?, cwd: String?)

struct ServerFormView: View {
    @Binding var isPresented: Bool
    @ObservedObject private var settingsManager = SettingManager.shared
    @ObservedObject private var mcpManager = MCPManager.shared
    @Environment(\.colorScheme) private var colorScheme
    
    // Optional server to edit
    var editingServer: MCPServerConfig?
    
    // Form state
    @State private var name: String = ""
    @State private var command: String = ""
    @State private var args: String = ""
    @State private var envPairs: [(key: String, value: String)] = [("", "")]
    @State private var cwd: String = ""
    @State private var errorMessage: String?
    @State private var originalName: String = ""
    @FocusState private var focusField: Field?
    
    enum Field: Hashable {
        case name, command, args, envKey(Int), envValue(Int), cwd
    }
    
    // Server templates
    private let templates: [(name: String, command: String, args: String, env: [String: String]?, cwd: String?)] = [
        ("Memory", "npx", "-y @modelcontextprotocol/server-memory", nil, nil),
        ("Filesystem", "npx", "-y @modelcontextprotocol/server-filesystem ~", nil, nil),
        ("GitHub", "npx", "-y @modelcontextprotocol/server-github", ["GITHUB_PERSONAL_ACCESS_TOKEN": "<YOUR_TOKEN>"], nil)
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(editingServer == nil ? "Add MCP Server" : "Edit MCP Server")
                    .font(.headline)
                Spacer()
            }
            .padding([.horizontal, .top])
            .padding(.bottom, 8)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Only show templates when adding a new server
                    if editingServer == nil {
                        // Server templates section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Quick Templates")
                                .font(.headline)
                            
                            HStack(spacing: 8) {
                                ForEach(templates, id: \.name) { template in
                                    Button {
                                        applyTemplate(template)
                                    } label: {
                                        HStack {
                                            Image(systemName: "server.rack")
                                                .imageScale(.small)
                                            Text(template.name)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.regular)
                                }
                            }
                        }
                        
                        Divider()
                    }
                    
                    // Form fields
                    Group {
                        // Server Name field (disabled if editing)
                        FormField(label: "Server Name", hint: "e.g., github") {
                            TextField("", text: $name)
                                .focused($focusField, equals: .name)
                                .disabled(editingServer != nil) // Disable name field if editing
                        }
                        
                        // Command field
                        FormField(label: "Command", hint: "e.g., npx") {
                            TextField("", text: $command)
                                .focused($focusField, equals: .command)
                        }
                        
                        // Arguments field
                        FormField(label: "Arguments", hint: "e.g., -y @modelcontextprotocol/server-github") {
                            TextField("", text: $args)
                                .focused($focusField, equals: .args)
                        }
                        
                        // Working Directory field
                        FormField(label: "Working Directory", hint: "Optional", required: false) {
                            HStack {
                                TextField("", text: $cwd)
                                    .focused($focusField, equals: .cwd)
                                
                                Button {
                                    let panel = NSOpenPanel()
                                    panel.canChooseFiles = false
                                    panel.canChooseDirectories = true
                                    panel.allowsMultipleSelection = false
                                    panel.canCreateDirectories = true
                                    panel.prompt = "Select"
                                    
                                    if panel.runModal() == .OK, let url = panel.url {
                                        cwd = url.path
                                    }
                                } label: {
                                    Image(systemName: "folder")
                                        .foregroundColor(.accentColor)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    
                    // Environment Variables section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Environment Variables")
                                .font(.headline)
                            Text("(optional)")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                            Spacer()
                            Button {
                                envPairs.append(("", ""))
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .imageScale(.medium)
                            }
                            .buttonStyle(.plain)
                            .disabled(envPairs.isEmpty || envPairs.last?.key.isEmpty == true || envPairs.last?.value.isEmpty == true)
                        }
                        
                        ForEach(Array(envPairs.enumerated()), id: \.offset) { index, pair in
                            HStack(spacing: 8) {
                                TextField("Key", text: $envPairs[index].key)
                                    .focused($focusField, equals: .envKey(index))
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                
                                Text("=")
                                    .foregroundColor(.secondary)
                                
                                TextField("Value", text: $envPairs[index].value)
                                    .focused($focusField, equals: .envValue(index))
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                
                                if envPairs.count > 1 {
                                    Button {
                                        envPairs.remove(at: index)
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    
                    // Error message
                    if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    
                    // Helper text with links
                    HStack(spacing: 2) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.secondary)
                        Text("Find more MCP servers on")
                            .foregroundColor(.secondary)
                        Link("GitHub", destination: URL(string: "https://github.com/modelcontextprotocol/servers")!)
                        Text("or")
                            .foregroundColor(.secondary)
                        Link("Smithery.ai", destination: URL(string: "https://smithery.ai/")!)
                    }
                    .font(.caption)
                    .padding(.top, 8)
                }
                .padding()
            }
            
            Divider()
            
            // Action buttons
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button(editingServer == nil ? "Add" : "Save") {
                    if validateInputs() {
                        let argArray = args.split(separator: " ").map(String.init)
                        
                        // Create environment variables dictionary from key-value pairs
                        var envDict: [String: String]? = nil
                        let filteredPairs = envPairs.filter { !$0.key.isEmpty && !$0.value.isEmpty }
                        if !filteredPairs.isEmpty {
                            envDict = Dictionary(uniqueKeysWithValues: filteredPairs)
                        }
                        
                        let serverConfig = MCPServerConfig(
                            name: name,
                            command: command,
                            args: argArray,
                            enabled: true,
                            env: envDict,
                            cwd: cwd.isEmpty ? nil : cwd
                        )
                        
                        if let editingServer = editingServer {
                            // Editing existing server
                            if let index = settingsManager.mcpServers.firstIndex(where: { $0.name == editingServer.name }) {
                                // Disconnect existing server
                                Task {
                                    await mcpManager.disconnectServer(editingServer.name)
                                    
                                    await MainActor.run {
                                        // Update server config
                                        settingsManager.mcpServers[index] = serverConfig
                                        settingsManager.saveMCPConfigFile()
                                        
                                        // Reconnect if MCP is enabled
                                        if settingsManager.mcpEnabled {
                                            mcpManager.connectToServer(serverConfig)
                                        }
                                        
                                        isPresented = false
                                    }
                                }
                            }
                        } else {
                            // Adding new server
                            if !settingsManager.mcpServers.contains(where: { $0.name == name }) {
                                settingsManager.mcpServers.append(serverConfig)
                                settingsManager.saveMCPConfigFile()
                                
                                // Connect to server if MCP is enabled
                                if settingsManager.mcpEnabled {
                                    Task {
                                        await MainActor.run {
                                            isPresented = false
                                        }
                                        
                                        mcpManager.connectToServer(serverConfig)
                                        
                                        try? await Task.sleep(nanoseconds: 3_000_000_000) // Wait 3 seconds
                                        
                                        await MainActor.run {
                                            if case .failed = mcpManager.connectionStatus[serverConfig.name] {
                                                Task {
                                                    await mcpManager.disconnectServer(serverConfig.name)
                                                    
                                                    if let index = settingsManager.mcpServers.firstIndex(where: { $0.name == serverConfig.name }) {
                                                        settingsManager.mcpServers.remove(at: index)
                                                        settingsManager.saveMCPConfigFile()
                                                        
                                                        NotificationCenter.default.post(
                                                            name: NSNotification.Name("ShowNotification"),
                                                            object: nil,
                                                            userInfo: [
                                                                "title": "Server Connection Failed",
                                                                "message": "Failed to connect to server '\(serverConfig.name)'. The configuration has been removed."
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
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 480)
        .onAppear {
            loadServerData()
        }
    }
    
    private var isValid: Bool {
        return !name.isEmpty && !command.isEmpty
    }
    
    private func loadServerData() {
        if let server = editingServer {
            // Load data from existing server
            name = server.name
            originalName = server.name
            command = server.command
            args = server.args.joined(separator: " ")
            cwd = server.cwd ?? ""
            
            // Load environment variables
            if let env = server.env, !env.isEmpty {
                envPairs = env.map { ($0.key, $0.value) }
            } else {
                envPairs = [("", "")]
            }
        } else {
            // Default state for new server
            envPairs = [("", "")]
        }
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
        
        // When adding a new server, check for duplicate name
        if editingServer == nil && settingsManager.mcpServers.contains(where: { $0.name == name }) {
            errorMessage = "A server with this name already exists"
            focusField = .name
            return false
        }
        
        return true
    }
    
    private func applyTemplate(_ template: (name: String, command: String, args: String, env: [String: String]?, cwd: String?)) {
        // Apply basic template info
        name = template.name.lowercased()
        command = template.command
        args = template.args
        cwd = template.cwd ?? ""
        
        // Set environment variables if provided in template
        if let templateEnv = template.env, !templateEnv.isEmpty {
            envPairs = templateEnv.map { ($0.key, $0.value) }
            if envPairs.isEmpty {
                envPairs = [("", "")]  // Add one empty pair if no environment variables
            }
        } else {
            envPairs = [("", "")]  // Reset to one empty pair
        }
        
        errorMessage = nil
    }
}


// Helper component for form fields
struct FormField<Content: View>: View {
    let label: String
    let hint: String
    let required: Bool
    let content: Content
    
    init(label: String, hint: String, required: Bool = true, @ViewBuilder content: () -> Content) {
        self.label = label
        self.hint = hint
        self.required = required
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(label)
                    .fontWeight(.medium)
                if required {
                    Text("*")
                        .foregroundColor(.red)
                }
                Text(hint)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            content
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
}
