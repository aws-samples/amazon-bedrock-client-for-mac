import AppKit
import Carbon
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = PreferencesStore.shared
    @ObservedObject private var store = AppStore.shared
    @ObservedObject private var catalog = ModelCatalog.shared
    @ObservedObject private var mcp = MCPClientManager.shared
    @StateObject private var backend = BedrockConnection()
    @State private var pane: SettingsPane? = .general
    @State private var query = ""
    @State private var highlighted: String?
    @State private var showAddServer = false
    @State private var selectedTool: MCPToolInfo?
    @State private var mcpImport: MCPImportPreview?
    @State private var showHistory = false
    @State private var advancedExpanded = false
    @State private var endpoint = ""
    @State private var runtimeEndpoint = ""
    @State private var apiKey = ""
    @State private var endpointError: String?
    @State private var connectionEdited = false
    @State private var connectionTask: Task<Void, Never>?
    @State private var modifiers: UInt32 = 0
    @State private var keyCode: UInt32 = 49
    @State private var loginEnabled = false
    @State private var loginMessage: String?
    @State private var notificationBusy = false
    @AppStorage("adjustedFontSize") private var fontSize = -1
    private var rows: [SettingsItem] { SettingsItem.all.filter { $0.pane == (pane ?? .general) } }
    private let advancedRows: Set<String> = ["endpoint", "runtimeEndpoint", "context", "summaries", "workingDirectory", "timeout", "output", "domains", "sound", "background", "notificationTest"]
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 12) {
                SearchField(placeholder: "Search settings", text: $query)
                    .padding(.horizontal, 12).padding(.top, 16)
                if query.isEmpty {
                    List(selection: $pane) {
                        ForEach(SettingsPane.allCases) { item in
                            Label {
                                Text(item.title)
                            } icon: {
                                Image(systemName: item.symbol).foregroundStyle(.primary)
                            }.font(DesignTokens.body).padding(.vertical, 4)
                                .background(SidebarScrollChrome())
                                .tag(item)
                        }
                    }.listStyle(.sidebar).scrollContentBackground(.hidden)
                } else {
                    List {
                        ForEach(SettingsItem.all.filter { $0.matches(query) }) { row in
                            Button { open(row.id); query = "" } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(row.title).font(.system(size: 12))
                                    Text(row.pane.title).font(.system(size: 10)).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                            }.buttonStyle(.plain)
                                .background(SidebarScrollChrome())
                        }
                    }.listStyle(.sidebar).scrollContentBackground(.hidden)
                }
                Text("Bedrock for Mac").font(DesignTokens.detail)
                    .foregroundStyle(.secondary).padding(.bottom, 18)
            }
            .frame(width: 190)
            Color.clear.frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(title: (pane ?? .general).title, subtitle: (pane ?? .general).subtitle)
                    .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 2)
                if pane == .skills {
                    SkillsLibraryView()
                } else {
                ScrollViewReader { proxy in
                Form {
                    Section {
                        ForEach(rows.filter { !advancedRows.contains($0.id) }) { row in
                            settingRow(row)
                        }
                    }
                    if rows.contains(where: { advancedRows.contains($0.id) }) {
                        Section {
                            DisclosureGroup("Advanced", isExpanded: $advancedExpanded) {
                                ForEach(rows.filter { advancedRows.contains($0.id) }) { row in settingRow(row) }
                            }
                        }
                    }
                }
                .formStyle(.grouped)
                .font(DesignTokens.body)
                .controlSize(.regular)
                .toggleStyle(AppSwitchStyle())
                .scrollContentBackground(.hidden)
                .background(SidebarScrollChrome())
                .onChange(of: highlighted) { _, id in
                    guard let id else { return }
                    DispatchQueue.main.async { proxy.scrollTo(id, anchor: .center) }
                }
                .onChange(of: pane) { _, _ in
                    if let highlighted { DispatchQueue.main.async { proxy.scrollTo(highlighted, anchor: .center) } }
                }
            }
                }
            }
            .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background {
            SplitWindowSurface(sidebarWidth: 190)
        }
        .background(WindowChrome(hidesTitle: false))
        .disabled(store.isRelocating)
        .frame(minWidth: 740, idealWidth: 860, minHeight: 580, idealHeight: 680)
        .tint(DesignTokens.accent)
        .buttonStyle(AppButtonStyle())
        .toggleStyle(AppSwitchStyle())
        .sheet(isPresented: $showAddServer) { MCPServerEditor(isPresented: $showAddServer) }
        .sheet(item: $selectedTool) { MCPToolDefinitionView(tool: $0) }
        .sheet(item: $mcpImport) { MCPImportView(preview: $0) }
        .sheet(isPresented: $showHistory) { HistorySettingsView() }
        .onAppear {
            endpoint = settings.endpoint; runtimeEndpoint = settings.runtimeEndpoint; apiKey = settings.bedrockApiKey
            modifiers = settings.hotkeyModifiers; keyCode = settings.hotkeyKeyCode
            loginEnabled = SMAppService.mainApp.status == .enabled
            if let id = store.requestedSettingsRow { open(id); store.requestedSettingsRow = nil }
        }
        .onChange(of: store.requestedSettingsRow) { _, id in if let id { open(id); store.requestedSettingsRow = nil } }
        .onChange(of: endpoint) { _, _ in scheduleEndpoints() }
        .onChange(of: runtimeEndpoint) { _, _ in scheduleEndpoints() }
        .onChange(of: modifiers) { _, _ in updateHotkey() }
        .onChange(of: keyCode) { _, _ in updateHotkey() }
        .onDisappear { connectionTask?.cancel(); if connectionEdited { saveEndpoints() } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workbench.settings")
    }
    private func settingRow(_ row: SettingsItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            control(row)
            Text(row.detail).font(DesignTokens.detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .id(row.id)
        .accessibilityIdentifier("setting.\(row.id)")
    }
    @ViewBuilder private func control(_ row: SettingsItem) -> some View {
        switch row.id {
        case "updates": Toggle(row.title, isOn: $settings.checkForUpdates)
        case "login":
            Toggle(row.title, isOn: Binding(get: { loginEnabled }, set: { setLogin($0) }))
            if let loginMessage { Text(loginMessage).font(.caption).foregroundStyle(.orange) }
        case "menubar": Toggle(row.title, isOn: pref(\.showMenuBarItem))
        case "restore": Toggle(row.title, isOn: pref(\.restoreLastThread))
        case "automations": Toggle(row.title, isOn: pref(\.automationsEnabled))
        case "appearance":
            AppSegmentedControl(title: row.title, selection: $settings.appearance,
                                      options: [("auto", "System"), ("light", "Light"), ("dark", "Dark")])
        case "textSize":
            HStack {
                Text(row.title)
                Spacer()
                FontSizeControl()
                Button("Reset") { fontSize = -1 }.controlSize(.small).accessibilityLabel("Reset text size")
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(row.title)
        case "compact": Toggle(row.title, isOn: pref(\.compactSidebar))
        case "timestamps": Toggle(row.title, isOn: pref(\.showTimestamps))
        case "usage": Toggle(row.title, isOn: $settings.showUsageInfo)
        case "region":
            settingsField(row.title) {
                SelectionField(title: row.title, selection: $settings.selectedRegion,
                                   options: AWSRegion.allCases.map { ($0, "\($0.name) · \($0.rawValue)") })
            }
        case "profile":
            settingsField(row.title) {
                HStack(spacing: 10) {
                    SelectionField(title: row.title, selection: $settings.selectedProfile,
                                       options: profileOptions)
                    Button { settings.refreshAWSProfiles() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(LiquidGlassToolbarButtonStyle())
                        .help("Refresh AWS profiles").accessibilityLabel("Refresh AWS profiles")
                }
            }
            if settings.profiles.first(where: { $0.name == settings.selectedProfile })?.type == .sso {
                Text("Uses the local AWS SSO session. Refresh it with aws sso login --profile \(settings.selectedProfile).").font(.caption).textSelection(.enabled)
            }
        case "apiKey":
            settingsField(row.title) {
                HStack(spacing: 10) {
                    SecureField("Optional API key", text: $apiKey)
                        .labelsHidden().textFieldStyle(.plain)
                        .padding(.horizontal, 10).frame(height: 34)
                        .background(DesignTokens.field, in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(DesignTokens.border))
                        .frame(minWidth: 160, maxWidth: .infinity)
                        .accessibilityLabel("Bedrock API key")
                    Button("Save") { settings.bedrockApiKey = apiKey }
                        .fixedSize().disabled(apiKey == settings.bedrockApiKey)
                    if !settings.bedrockApiKey.isEmpty {
                        Button("Remove") { settings.bedrockApiKey = ""; apiKey = "" }.fixedSize()
                    }
                }
            }
            if let error = settings.credentialError { Text(error).font(.caption).foregroundStyle(.orange) }
        case "endpoint":
            settingsField(row.title) {
                TextField(row.title, text: $endpoint, prompt: Text("AWS default"))
                    .labelsHidden().textFieldStyle(.roundedBorder)
                    .accessibilityLabel(row.title)
            }
        case "runtimeEndpoint":
            settingsField(row.title) {
                TextField(row.title, text: $runtimeEndpoint, prompt: Text("AWS default"))
                    .labelsHidden().textFieldStyle(.roundedBorder)
                    .accessibilityLabel(row.title)
            }
        case "connectionTest":
            HStack {
                Button(catalog.isLoading ? "Connecting…" : "Test connection & refresh models") {
                    saveEndpoints()
                    Task {
                        try? await Task.sleep(for: .milliseconds(700))
                        await catalog.refresh(backend: backend.backend)
                    }
                }.disabled(catalog.isLoading || endpointError != nil)
                if catalog.isLoading { ProgressView().controlSize(.small) }
            }
            if let error = endpointError ?? catalog.errorMessage { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
            else if !catalog.models.isEmpty { Label("\(catalog.models.count) models available", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary) }
        case "defaultModel":
            settingsField(row.title) {
                HStack(spacing: 10) {
                    ModelPicker(organizedChatModels: catalog.organized, menuSelection: defaultModelSelection) { value in
                        if case .chat(let model) = value { settings.defaultModelId = model.id }
                    }
                    Spacer(minLength: 8)
                    if let model = catalog.defaultModel {
                        InferenceSettings(currentModelId: .constant(model.id), backend: backend.backend)
                    }
                }
                if let model = catalog.defaultModel {
                    Text(model.id)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2).truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(model.id)
                        .contextMenu {
                            Button("Copy model ID") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(model.id, forType: .string)
                            }
                        }
                        .accessibilityLabel("Model ID: \(model.id)")
                        .accessibilityIdentifier("settings.defaultModelID")
                }
            }
        case "systemPrompt": SystemPromptEditor()
        case "thinking": Toggle(row.title, isOn: $settings.enableModelThinking)
        case "caching": Toggle(row.title, isOn: pref(\.promptCaching))
        case "context":
            HStack {
                Text("Context budget (characters)")
                Spacer(minLength: 12)
                TextField("Characters", value: pref(\.contextCharacterBudget), format: .number.grouping(.never))
                    .labelsHidden().textFieldStyle(.roundedBorder).frame(width: 112)
                    .multilineTextAlignment(.trailing).accessibilityLabel("Context budget in characters")
            }
            Text("Effective limit: \(store.preferences.validContextBudget.formatted()) characters. Images and documents also count toward request size.").font(.caption)
        case "titles": Toggle(row.title, isOn: pref(\.automaticTitles))
        case "summaries": Toggle(row.title, isOn: pref(\.thinkingSummaries))
        case "toolProfile":
            settingsField(row.title) {
                SelectionField(title: row.title, selection: Binding(get: { store.preferences.toolProfile }, set: { profile in
                    store.preferences.toolProfile = profile
                    store.preferences.disabledTools = []
                }), options: ToolProfile.allCases.map { ($0, $0.title) })
            }
        case "approval":
            settingsField(row.title) {
                SelectionField(title: row.title, selection: pref(\.approvalMode),
                                   options: ToolApprovalMode.allCases.map { ($0, $0.title) })
            }
        case "fileAccess":
            Toggle("Allow all local paths", isOn: Binding(get: { store.preferences.restrictFileAccess != true },
                                                        set: { store.preferences.restrictFileAccess = !$0 }))
            if store.preferences.restrictFileAccess == true {
                ForEach(store.preferences.allowedFileDirectories ?? [], id: \.self) { path in
                    HStack(spacing: 8) {
                        Text(path).font(.system(size: 11, design: .monospaced))
                            .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                        Spacer(minLength: 8)
                        Button { store.preferences.allowedFileDirectories?.removeAll { $0 == path } } label: {
                            Image(systemName: "xmark").frame(width: 22, height: 22)
                        }.buttonStyle(.plain).help("Remove \(path)").accessibilityLabel("Remove allowed folder \(path)")
                    }
                }
                Button("Allow folder…") { chooseAllowedFolders() }
                if store.preferences.allowedFileDirectories?.isEmpty != false {
                    Text("Choose at least one folder to use file tools in this mode.").font(.caption).foregroundStyle(.secondary)
                }
            }
        case "workingDirectory":
            settingsField(row.title) {
                TextField("Working directory", text: Binding(get: { store.preferences.workingDirectory ?? "" },
                                                            set: { store.preferences.workingDirectory = $0.isEmpty ? nil : $0 }),
                          prompt: Text("~"))
                    .labelsHidden().textFieldStyle(.roundedBorder).accessibilityLabel(row.title)
            }
        case "turns": Stepper("\(row.title): \(settings.maxToolUseTurns)", value: $settings.maxToolUseTurns, in: 1...100)
        case "timeout": Stepper("Command timeout: \(store.preferences.validCommandTimeout) seconds", value: pref(\.commandTimeout), in: 1...600)
        case "output":
            HStack {
                Text("Output limit (characters)")
                Spacer(minLength: 12)
                TextField("Limit", value: pref(\.toolOutputLimit), format: .number.grouping(.never))
                    .labelsHidden().textFieldStyle(.roundedBorder).frame(width: 112)
                    .multilineTextAlignment(.trailing).accessibilityLabel("Tool output limit in characters")
            }
        case "domains":
            settingsField(row.title) {
                TextField("Allowed domains", text: pref(\.allowedWebDomains), prompt: Text("example.com, docs.example.org"))
                    .labelsHidden().textFieldStyle(.roundedBorder).accessibilityLabel(row.title)
            }
        case "mcp": mcpControls
        case "quickAccess": Toggle(row.title, isOn: $settings.enableQuickAccess)
        case "hotkey":
            HStack {
                Text(row.title)
                Spacer(minLength: 12)
                HotkeyRecorderView(modifiers: $modifiers, keyCode: $keyCode).disabled(!settings.enableQuickAccess)
                Button("Reset") { modifiers = UInt32(optionKey); keyCode = 49 }.fixedSize()
            }
        case "send":
            AppSegmentedControl(title: row.title, selection: pref(\.sendWithCommandReturn),
                                      options: [(false, "Return"), (true, "⌘ Return")])
        case "pasteImages": Toggle(row.title, isOn: $settings.allowImagePasting)
        case "pasteText": Toggle(row.title, isOn: $settings.treatLargeTextAsFile)
        case "shortcutReference": shortcutReference
        case "notifications":
            Toggle(row.title, isOn: Binding(get: { store.preferences.notificationsEnabled }, set: { value in
                if !value { store.preferences.notificationsEnabled = false; return }
                notificationBusy = true
                Task {
                    let granted = await NotificationService.shared.enable()
                    store.preferences.notificationsEnabled = granted
                    notificationBusy = false
                    if !granted { store.errorMessage = "Notifications are disabled in macOS. Open System Settings → Notifications → Bedrock to allow them." }
                }
            })).disabled(notificationBusy)
        case "sound": Toggle(row.title, isOn: pref(\.notificationSound))
        case "background": Toggle(row.title, isOn: pref(\.notifyInBackgroundOnly))
        case "notificationTest": Button(row.title) { Task { if await NotificationService.shared.enable() { await NotificationService.shared.post(title: "Bedrock is ready", body: "Your run notifications are working.", test: true) } } }
        case "dataDirectory":
            Text(settings.defaultDirectory).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
            HStack {
                Button("Reveal folder") { store.reveal(URL(fileURLWithPath: settings.defaultDirectory)) }
                Button(store.isRelocating ? "Copying…" : "Move data folder…") { store.chooseDataDirectory() }
                    .disabled(store.isRelocating || ProcessInfo.processInfo.environment["BEDROCK_WORKBENCH_DATA_DIR"] != nil)
            }
        case "skills":
            HStack {
                Button("Reveal skills") { store.reveal(store.skillsDirectory) }
                Button("Import", action: store.importSkill)
                Button("Refresh", action: store.reloadSkills)
            }
        case "history":
            HStack {
                Text(row.title)
                Spacer()
                Button("Manage…") { showHistory = true }.accessibilityLabel("Manage chat history")
            }
        case "logging": Toggle(row.title, isOn: $settings.enableDebugLog)
        case "logs": Button(row.title) { revealLogs() }
        case "diagnostics": Button(row.title, action: AppActions.exportDiagnostics)
        case "about":
            Text("Bedrock for Mac").font(.headline)
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Development")")
        default:
            if let tool = BuiltInTool(rawValue: row.id) {
                Toggle(tool.title, isOn: Binding(get: { store.preferences.enabledTools.contains(tool) }, set: { value in
                    var preferences = store.preferences
                    let enabled = preferences.enabledTools
                    preferences.toolProfile = .custom
                    preferences.customTools = value ? enabled.union([tool]) : enabled.subtracting([tool])
                    preferences.disabledTools = []
                    store.preferences = preferences
                }))
            }
        }
    }
    private var defaultModelSelection: Binding<SidebarSelection?> {
        Binding(
            get: { catalog.defaultModel.map(SidebarSelection.chat) },
            set: { if case .chat(let model) = $0 { settings.defaultModelId = model.id } }
        )
    }
    private func chooseAllowedFolders() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Allow folders"
        panel.begin { response in
            guard response == .OK else { return }
            var paths = store.preferences.allowedFileDirectories ?? []
            for url in panel.urls {
                let path = url.standardizedFileURL.resolvingSymlinksInPath().path
                if !paths.contains(path) { paths.append(path) }
            }
            store.preferences.allowedFileDirectories = paths
        }
    }
    private var profileOptions: [(value: String, title: String)] {
        var options = settings.profiles.map { (value: $0.name, title: $0.name + ($0.type == .sso ? " · SSO" : "")) }
        if !options.contains(where: { $0.value == settings.selectedProfile }) {
            options.insert((settings.selectedProfile, settings.selectedProfile), at: 0)
        }
        return options
    }

    private func settingsField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(DesignTokens.label)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var mcpControls: some View {
        VStack(alignment: .leading, spacing: 13) {
            Toggle("Enable MCP", isOn: $mcp.mcpEnabled)
            if mcp.wasDisabledDueToCrash { Label("MCP was paused after repeated crashes. Re-enable it to try again.", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange) }
            ForEach(mcp.servers) { server in MCPServerRow(serverName: server.name) }
            if mcp.mcpEnabled && !mcp.toolInfos.isEmpty {
                ActionMenu("Inspect connected tools") {
                    ForEach(mcp.toolInfos) { tool in
                        Button("\(tool.toolName) · \(tool.serverName)") { selectedTool = tool }
                            .help(tool.description)
                    }
                }
                .accessibilityLabel("Inspect connected MCP tools")
            }
            HStack {
                Button("Add server", systemImage: "plus") { showAddServer = true }
                Button("Import…") { MCPConfiguration.importFile { mcpImport = MCPImportPreview(servers: $0) } }
                Button("Export…") { MCPConfiguration.exportFile() }
                Button("Reveal config") { store.reveal(URL(fileURLWithPath: mcp.getConfigPath())) }
            }.controlSize(.small)
            Text("Exports omit credentials. Imported servers stay off until you review and enable them.")
                .font(DesignTokens.detail).foregroundStyle(.secondary)
        }
    }
    private var shortcutReference: some View {
        VStack(spacing: 8) {
            ForEach([("New thread", "⌘N"), ("Move thread to Trash", "⌘D"), ("Command palette", "⌘K"), ("Find in thread", "⌘F"), ("Toggle sidebar", "⌘B"),
                     ("Settings", "⌘,"), ("Import thread", "⇧⌘O"), ("Quick Access", "⇧⌘K"),
                     ("Stop response", "Esc"), ("New line", "⇧ Return"), ("Change text size", "⌘+ / ⌘− / ⌘0")], id: \.0) { shortcut in
                HStack { Text(shortcut.0); Spacer(); Text(shortcut.1).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary) }
            }
        }.font(.system(size: 12))
    }
    private func pref<Value>(_ keyPath: WritableKeyPath<AppPreferences, Value>) -> Binding<Value> {
        Binding(get: { store.preferences[keyPath: keyPath] }, set: { store.preferences[keyPath: keyPath] = $0 })
    }
    private func open(_ id: String) {
        let id = ["archive", "trash"].contains(id) ? "history" : id == "skillsDirectory" ? "skills" : id
        guard let row = SettingsItem.all.first(where: { $0.id == id }) else { return }
        pane = row.pane
        advancedExpanded = advancedRows.contains(id)
        highlighted = nil
        DispatchQueue.main.async { highlighted = id }
    }
    private func scheduleEndpoints() {
        guard endpoint != settings.endpoint || runtimeEndpoint != settings.runtimeEndpoint else { return }
        connectionEdited = true
        connectionTask?.cancel()
        connectionTask = Task { do { try await Task.sleep(for: .milliseconds(600)) } catch { return }; saveEndpoints() }
    }
    private func saveEndpoints() {
        do {
            for value in [endpoint, runtimeEndpoint] where !value.trimmingCharacters(in: .whitespaces).isEmpty {
                _ = try LocalPath.validatedWebURL(value.trimmingCharacters(in: .whitespaces), allowedDomains: "")
            }
            settings.endpoint = endpoint.trimmingCharacters(in: .whitespaces)
            settings.runtimeEndpoint = runtimeEndpoint.trimmingCharacters(in: .whitespaces)
            endpointError = nil
        } catch { endpointError = error.localizedDescription }
    }
    private func updateHotkey() {
        guard modifiers != 0 else { return }
        settings.hotkeyModifiers = modifiers; settings.hotkeyKeyCode = keyCode
        GlobalHotkeyService.shared.updateHotkey(modifiers: modifiers, keyCode: keyCode)
    }
    private func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            loginMessage = SMAppService.mainApp.status == .requiresApproval ? "Allow Bedrock in System Settings → General → Login Items." : nil
        } catch { loginEnabled = SMAppService.mainApp.status == .enabled; loginMessage = error.localizedDescription }
    }
    private func revealLogs() {
        let url = URL(fileURLWithPath: settings.defaultDirectory).appendingPathComponent("logs")
        do { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); store.reveal(url) }
        catch { store.errorMessage = error.localizedDescription }
    }
}
