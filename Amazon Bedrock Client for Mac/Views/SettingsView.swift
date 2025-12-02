//
//  SettingsView.swift
//  Amazon Bedrock Client for Mac
//
//  Redesigned for macOS 15
//

import Foundation
import Logging
import SwiftUI

struct SettingsView: View {
    @StateObject private var settingsManager = SettingManager.shared
    @State private var selectedTab: SettingsTab = .general
    private var logger = Logger(label: "SettingsView")
    
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
        VStack(spacing: 0) {
            // Custom tab bar with icons
            HStack(spacing: 0) {
                ForEach(SettingsTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.imageName)
                                .font(.system(size: 13))
                            Text(tab.title)
                                .font(.system(size: 13))
                        }
                        .fontWeight(selectedTab == tab ? .semibold : .regular)
                        .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                        .background(
                            selectedTab == tab ?
                                Color(nsColor: .controlBackgroundColor) :
                                Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Content
            Group {
                switch selectedTab {
                case .general:
                    GeneralSettingsView(organizedChatModels: organizedChatModels)
                case .developer:
                    DeveloperSettingsView()
                }
            }
        }
        .frame(width: 650, height: 650)
        .onAppear {
            fetchModels()
        }
    }
    
    @State private var organizedChatModels: [String: [ChatModel]] = [:]
    
    private func fetchModels() {
        let backend = BackendModel().backend
        
        Task {
            async let foundationModelsResult = backend.listFoundationModels()
            async let inferenceProfilesResult = backend.listInferenceProfiles()
            
            let (foundationModels, inferenceProfiles) = await (
                foundationModelsResult,
                inferenceProfilesResult
            )
            
            let foundationChatModels = Dictionary(
                grouping: (try? foundationModels.get())?.map(ChatModel.fromSummary) ?? []
            ) { $0.provider }
            
            let inferenceChatModels = Dictionary(
                grouping: inferenceProfiles.map { ChatModel.fromInferenceProfile($0) }
            ) { $0.provider }
            
            let mergedChatModels = foundationChatModels.merging(inferenceChatModels) { current, _ in
                current
            }
            
            await MainActor.run {
                self.organizedChatModels = mergedChatModels
            }
        }
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    let organizedChatModels: [String: [ChatModel]]
    @ObservedObject private var settingsManager = SettingManager.shared
    @State private var showPausedRegions: Bool = false
    @State private var showGovCloudRegions: Bool = false
    @State private var tempHotkeyModifiers: UInt32 = 0
    @State private var tempHotkeyKeyCode: UInt32 = 0
    @State private var modelSelection: SidebarSelection?
    
    var body: some View {
        Form {
            // AWS Configuration
            Section("AWS Configuration") {
                LabeledContent("Region") {
                    Picker("", selection: $settingsManager.selectedRegion) {
                        Section("North America") {
                            ForEach(AWSRegion.regions(in: .northAmerica, includePaused: showPausedRegions), id: \.self) { region in
                                Text(region.name).tag(region)
                            }
                        }
                        
                        Section("Europe") {
                            ForEach(AWSRegion.regions(in: .europe, includePaused: showPausedRegions), id: \.self) { region in
                                Text(region.name).tag(region)
                            }
                        }
                        
                        Section("Asia Pacific") {
                            ForEach(AWSRegion.regions(in: .asiaPacific, includePaused: showPausedRegions), id: \.self) { region in
                                Text(region.name).tag(region)
                            }
                        }
                        
                        Section("Other") {
                            ForEach(AWSRegion.regions(in: .other, includePaused: showPausedRegions), id: \.self) { region in
                                Text(region.name).tag(region)
                            }
                        }
                        
                        if showGovCloudRegions {
                            Section("GovCloud") {
                                ForEach(AWSRegion.regions(in: .govCloud), id: \.self) { region in
                                    Text(region.name).tag(region)
                                }
                            }
                        }
                    }
                    .labelsHidden()
                }
                
                LabeledContent("Profile") {
                    if settingsManager.isSSOLoggedIn {
                        HStack {
                            Text("AWS Identity Center")
                                .foregroundStyle(.secondary)
                            Button("Log Out") {
                                // SSO logout
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
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
            
            // Application Settings
            Section("Application") {
                Toggle("Check for Updates", isOn: $settingsManager.checkForUpdates)
                
                Toggle("Show Usage Information", isOn: $settingsManager.showUsageInfo)
                
                Toggle("Enable Quick Access", isOn: $settingsManager.enableQuickAccess)
                
                Toggle("Treat Large Text as File", isOn: $settingsManager.treatLargeTextAsFile)
                    .help("When enabled, large pasted text (10KB+) will be attached as a file instead of inline text")
                
                if settingsManager.enableQuickAccess {
                    LabeledContent("Hotkey") {
                        HotkeyRecorderView(
                            modifiers: $tempHotkeyModifiers,
                            keyCode: $tempHotkeyKeyCode
                        )
                        .onAppear {
                            tempHotkeyModifiers = settingsManager.hotkeyModifiers
                            tempHotkeyKeyCode = settingsManager.hotkeyKeyCode
                        }
                        .onChange(of: tempHotkeyModifiers) { _, newValue in
                            settingsManager.hotkeyModifiers = newValue
                            HotkeyManager.shared.updateHotkey(modifiers: newValue, keyCode: tempHotkeyKeyCode)
                        }
                        .onChange(of: tempHotkeyKeyCode) { _, newValue in
                            settingsManager.hotkeyKeyCode = newValue
                            HotkeyManager.shared.updateHotkey(modifiers: tempHotkeyModifiers, keyCode: newValue)
                        }
                    }
                }
                
                LabeledContent("Appearance") {
                    Picker("", selection: $settingsManager.appearance) {
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                        Text("Auto").tag("auto")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: settingsManager.appearance) { _, newValue in
                        applyAppearance(newValue)
                    }
                }
                
                LabeledContent("Text Size") {
                    FontSizeControl()
                }
            }
            
            // Model Settings
            Section("Model Settings") {
                HStack(alignment: .center) {
                    Text("Default Model")
                    
                    Spacer()
                    
                    if !organizedChatModels.isEmpty {
                        ModelSelectorDropdown(
                            organizedChatModels: organizedChatModels,
                            menuSelection: $modelSelection,
                            handleSelectionChange: { newSelection in
                                if case let .chat(model) = newSelection {
                                    settingsManager.defaultModelId = model.id
                                }
                            }
                        )
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(maxWidth: 300, alignment: .trailing)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onAppear {
                    // Initialize modelSelection from defaultModelId
                    if let defaultModel = settingsManager.availableModels.first(where: { $0.id == settingsManager.defaultModelId }) {
                        modelSelection = .chat(defaultModel)
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("System Prompt")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    MultilineRoundedTextField(
                        text: $settingsManager.systemPrompt,
                        placeholder: "Tell me more about yourself or how you want me to respond"
                    )
                    .frame(height: 100)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            applyAppearance(settingsManager.appearance)
        }
    }
    
    private func applyAppearance(_ appearance: String) {
        switch appearance.lowercased() {
        case "light":
            NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":
            NSApp.appearance = NSAppearance(named: .darkAqua)
        default:
            NSApp.appearance = nil
        }
    }
}

// MARK: - Developer Settings

struct DeveloperSettingsView: View {
    @ObservedObject private var settingsManager = SettingManager.shared
    @ObservedObject private var mcpManager = MCPManager.shared
    @State private var showingAddServerSheet = false
    @State private var tempEndpoint: String = ""
    @State private var tempRuntimeEndpoint: String = ""
    
    var body: some View {
        Form {
            // Model Context Protocol
            Section {
                Toggle("Enable MCP", isOn: $mcpManager.mcpEnabled)
                
                // Show warning if MCP was disabled due to crash
                if mcpManager.wasDisabledDueToCrash && !mcpManager.mcpEnabled {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("MCP was automatically disabled due to repeated crashes. Enable to try again.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Model Context Protocol")
            } footer: {
                if !mcpManager.mcpEnabled && !mcpManager.wasDisabledDueToCrash {
                    Text("MCP allows your LLM to access tools from your local machine. Add servers only from trusted sources.")
                        .font(.caption)
                }
            }
            
            if mcpManager.mcpEnabled {
                Section {
                    HStack {
                        Text("Configured Servers")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            showingAddServerSheet = true
                        } label: {
                            Label("Add Server", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    if mcpManager.servers.isEmpty {
                        Text("No servers configured")
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(mcpManager.servers) { server in
                                ServerRow(server: server)
                                if server.id != mcpManager.servers.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.gray.opacity(0.2), lineWidth: 0.5)
                        )
                    }
                    
                    LabeledContent("Max Tool Use Turns") {
                        TextField("", value: $settingsManager.maxToolUseTurns, formatter: NumberFormatter())
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .onChange(of: settingsManager.maxToolUseTurns) { _, newValue in
                                if newValue < 1 {
                                    settingsManager.maxToolUseTurns = 1
                                } else if newValue > 1000 {
                                    settingsManager.maxToolUseTurns = 1000
                                }
                            }
                    }
                    
                    Button {
                        let configDir = settingsManager.defaultDirectory.isEmpty
                            ? FileManager.default.homeDirectoryForCurrentUser.path
                            : settingsManager.defaultDirectory
                        
                        let configFilePath = URL(fileURLWithPath: configDir)
                            .appendingPathComponent("mcp_config.json")
                            .path
                        
                        let parentDirPath = URL(fileURLWithPath: configFilePath).deletingLastPathComponent().path
                        
                        if !FileManager.default.fileExists(atPath: parentDirPath) {
                            try? FileManager.default.createDirectory(atPath: parentDirPath, withIntermediateDirectories: true)
                        }
                        
                        if FileManager.default.fileExists(atPath: configFilePath) {
                            NSWorkspace.shared.selectFile(configFilePath, inFileViewerRootedAtPath: parentDirPath)
                        } else {
                            NSWorkspace.shared.open(URL(fileURLWithPath: parentDirPath))
                        }
                    } label: {
                        Label("Open Config File", systemImage: "folder")
                    }
                    .buttonStyle(.link)
                } footer: {
                    Text("MCP allows your LLM to access tools from your local machine. Add servers only from trusted sources.")
                        .font(.caption)
                }
            }
            
            // Advanced Settings
            Section("Advanced") {
                LabeledContent("Default Directory") {
                    HStack {
                        TextField("", text: $settingsManager.defaultDirectory)
                            .textFieldStyle(.roundedBorder)
                            .disabled(true)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        Button("Browse") {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = false
                            panel.canChooseDirectories = true
                            panel.allowsMultipleSelection = false
                            panel.canCreateDirectories = true
                            panel.prompt = "Select"
                            
                            if panel.runModal() == .OK, let url = panel.url {
                                settingsManager.defaultDirectory = url.path
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                
                LabeledContent("Bedrock Endpoint") {
                    TextField("", text: $tempEndpoint)
                        .textFieldStyle(.roundedBorder)
                        .onAppear { tempEndpoint = settingsManager.endpoint }
                        .onSubmit {
                            settingsManager.endpoint = tempEndpoint
                        }
                }
                
                LabeledContent("Runtime Endpoint") {
                    TextField("", text: $tempRuntimeEndpoint)
                        .textFieldStyle(.roundedBorder)
                        .onAppear { tempRuntimeEndpoint = settingsManager.runtimeEndpoint }
                        .onSubmit {
                            settingsManager.runtimeEndpoint = tempRuntimeEndpoint
                        }
                }
                
                Toggle("Enable Logging", isOn: $settingsManager.enableDebugLog)
            }
            
            // Local Server
            Section {
                Toggle("Enable Local Server", isOn: $settingsManager.enableLocalServer)
                
                if settingsManager.enableLocalServer {
                    LabeledContent("Server Port") {
                        HStack {
                            TextField("", value: $settingsManager.serverPort, formatter: NumberFormatter())
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                .onChange(of: settingsManager.serverPort) { _, newValue in
                                    if newValue < 1024 {
                                        settingsManager.serverPort = 1024
                                    } else if newValue > 65535 {
                                        settingsManager.serverPort = 65535
                                    }
                                }
                            
                            Text("(Requires restart)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Local Server")
            } footer: {
                Text("The local server is used for document previews and content rendering.")
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showingAddServerSheet) {
            ServerFormView(isPresented: $showingAddServerSheet)
        }
    }
}

// MARK: - Supporting Views (keep existing implementations)

// MultilineRoundedTextField - keep existing
struct MultilineRoundedTextField: View {
    @Binding var text: String
    var placeholder: String
    @FocusState private var isFocused: Bool
    @State private var localText: String = ""
    @State private var saveTimer: Timer?
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $localText)
                .font(.body)
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
                .focused($isFocused)
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.gray.opacity(0.3), lineWidth: 1)
                )
                .onChange(of: localText) { _, newValue in
                    saveTimer?.invalidate()
                    saveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [newValue] _ in
                        Task { @MainActor in
                            text = newValue
                        }
                    }
                }
                .onChange(of: isFocused) { _, focused in
                    if !focused {
                        saveTimer?.invalidate()
                        text = localText
                    }
                }
                .onAppear {
                    localText = text
                }
                .onChange(of: text) { _, newValue in
                    if newValue != localText {
                        localText = newValue
                    }
                }
            
            if localText.isEmpty {
                Text(placeholder)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)
            }
        }
        .onDisappear {
            saveTimer?.invalidate()
            text = localText
        }
    }
}

// MARK: - Server Row

struct ServerRow: View {
    @ObservedObject private var settingsManager = SettingManager.shared
    @ObservedObject private var mcpManager = MCPManager.shared
    var server: MCPServerConfig
    @State private var showingEditSheet = false
    
    var body: some View {
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
                                .fill(server.transportType == .http ? Color.blue.opacity(0.15) : Color.gray.opacity(0.15))
                        )
                        .foregroundStyle(server.transportType == .http ? .blue : .secondary)
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
            
            connectionStatusView
            
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
                mcpManager.removeServer(named: server.name)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            ServerFormView(isPresented: $showingEditSheet, editingServer: server)
        }
    }
    
    private var connectionStatusView: some View {
        HStack(spacing: 6) {
            // OAuth status for HTTP servers
            if server.transportType == .http {
                oauthStatusIcon
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
    private var oauthStatusIcon: some View {
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
                            Picker("", selection: $transportType) {
                                ForEach(MCPTransportType.allCases, id: \.self) { type in
                                    Text(type.displayName).tag(type)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
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
            args = server.args.joined(separator: " ")
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
            let argArray = args.split(separator: " ").map(String.init)
            
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
