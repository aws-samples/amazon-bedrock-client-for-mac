import AppKit
import SwiftUI

struct MainWindowView: View {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var backendModel = BedrockConnection()
    @ObservedObject private var store = AppStore.shared
    @ObservedObject private var chats = ConversationStore.shared
    @ObservedObject private var catalog = ModelCatalog.shared
    @ObservedObject private var settings = PreferencesStore.shared
    @ObservedObject private var coordinator = AppCoordinator.shared
    @ObservedObject private var approvals = ToolApprovalCenter.shared
    @StateObject private var newThreadDraft = ComposerDraft.welcome
    private var newThreadMedia: AttachmentStore { newThreadDraft.media }
    @StateObject private var transcribeManager = DictationService()
    @State private var sidebarVisible = true
    @State private var menuSelection: SidebarSelection?
    @State private var demoToConfigure: DemoPreset?
    @State private var showComparison = false
    @State private var approval: PendingToolApproval?
    @State private var showApproval = false
    @State private var didLoad = false
    @State private var newDraftText = ""
    @AppStorage("workbench.sidebarWidth.v2") private var savedSidebarWidth = 240.0
    @State private var resizeStart: Double?
    @State private var navigationHistory = NavigationHistory()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var location: NavigationLocation {
        .init(destination: store.destination, threadID: store.selectedThreadID)
    }
    private var canGoBack: Bool { navigationHistory.canGoBack(where: canOpen) }
    private var sidebarWidth: CGFloat { CGFloat(min(320, max(220, savedSidebarWidth))) }

    private var selectedChat: ChatModel? { chats.chats.first { $0.chatId == store.selectedThreadID } }
    private var selectedModel: ChatModel? {
        if let selectedChat { return selectedChat }
        if case .chat(let model) = menuSelection { return model }
        return catalog.defaultModel
    }

    private var windowContent: some View {
        GeometryReader { window in
            HStack(spacing: 0) {
                Group {
                    if sidebarVisible {
                        SidebarView(onNew: beginNewThread)
                            .frame(width: sidebarWidth)
                            .transition(.opacity)
                    }
                }
                    .frame(width: sidebarVisible ? sidebarWidth : 0, alignment: .leading)
                    .clipped()
                    .allowsHitTesting(sidebarVisible)
                Rectangle().fill(.clear)
                    .frame(width: sidebarVisible ? 1 : 0)
                    .overlay {
                        Color.clear.frame(width: 7).contentShape(Rectangle())
                            .onHover { if $0 { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() } }
                            .gesture(DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if resizeStart == nil { resizeStart = savedSidebarWidth }
                                    savedSidebarWidth = min(320, max(220, (resizeStart ?? 240) + value.translation.width))
                                }
                                .onEnded { _ in resizeStart = nil })
                    }
                    .accessibilityLabel("Resize sidebar")
                VStack(spacing: 0) {
                    if let error = catalog.errorMessage, store.destination == .chats { connectionBanner(error) }
                    detail
                }
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .background(DesignTokens.canvas)
                .clipped()
            }
            .allowsHitTesting(!store.showCommandPalette)
            .accessibilityHidden(store.showCommandPalette)
            .navigationTitle("")
            .toolbar { navigationToolbar; toolbar }
            .toolbarBackground(.hidden, for: .windowToolbar)
            // Nested AppKit split views otherwise contribute their ideal height
            // to the window and can push the sidebar/header above the screen.
            .frame(width: window.size.width, height: window.size.height, alignment: .topLeading)
        }
    }

    private var styledContent: some View {
        windowContent
        .background {
            SplitWindowSurface(sidebarWidth: sidebarVisible ? sidebarWidth : 0)
        }
        .background(WindowChrome())
        .disabled(store.isRelocating)
        .overlay {
            if store.showCommandPalette {
                ZStack {
                    Color.black.opacity(0.12)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { closeSearch() }
                        .accessibilityLabel("Dismiss search")
                    GlobalSearchView(onNewThread: beginNewThread, onDemo: useDemo, onDismiss: closeSearch)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(DesignTokens.border))
                        .shadow(color: .black.opacity(0.16), radius: 28, y: 12)
                        .padding(24)
                }
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .tint(DesignTokens.accent)
        .buttonStyle(AppButtonStyle())
        .toggleStyle(AppSwitchStyle())
    }

    private var navigationContent: some View {
        styledContent
        .onChange(of: location) { previous, next in navigationHistory.record(from: previous, to: next) }
        .onAppear {
            AppWindows.openMain = { openWindow(id: "MainWindow") }
            AppWindows.newThread = beginNewThread
            newDraftText = store.thread("new-thread").draft
        }
        .onChange(of: newDraftText) { _, draft in store.updateDraft("new-thread", text: draft) }
        .task {
            guard !didLoad else { return }
            didLoad = true
            applyAppearance()
            await catalog.refresh(backend: backendModel.backend)
            if menuSelection == nil, let model = selectedChat ?? catalog.defaultModel { menuSelection = .chat(model) }
            AutomationScheduler.shared.start(backend: backendModel)
        }
        .onChange(of: backendModel.backend) { _, backend in Task { await catalog.refresh(backend: backend) } }
        .onChange(of: store.selectedThreadID) { _, _ in
            menuSelection = (selectedChat ?? catalog.defaultModel).map(SidebarSelection.chat)
        }
        .onChange(of: selectedChat?.id) { _, _ in if let chat = selectedChat { menuSelection = .chat(chat) } }
        .onChange(of: settings.defaultModelId) { _, _ in
            if selectedChat == nil { menuSelection = catalog.defaultModel.map(SidebarSelection.chat) }
        }
        .onChange(of: settings.appearance) { _, _ in applyAppearance() }
        .onChange(of: store.requestedDemoID) { _, id in
            if let id, let demo = store.demos.first(where: { $0.id == id }) { store.requestedDemoID = nil; useDemo(demo) }
        }
    }

    private var coordinatedContent: some View {
        navigationContent
        .onChange(of: coordinator.shouldCreateNewChat) { _, create in
            guard create else { return }
            coordinator.shouldCreateNewChat = false
            if coordinator.isProcessingQuickAccess { sendQuickAccess() } else { beginNewThread() }
        }
        .onChange(of: coordinator.shouldDeleteChat) { _, delete in
            guard delete else { return }
            coordinator.shouldDeleteChat = false
            if let selectedChat { store.archive(selectedChat.chatId) }
        }
        .onChange(of: chats.persistenceError) { _, value in if let value { store.errorMessage = value } }
        .onReceive(approvals.$pending) { requests in
            if let approval, !requests.contains(where: { $0.id == approval.id }) { showApproval = false }
            if approval == nil, let first = requests.first { approval = first; showApproval = true }
        }
    }

    private var presentedContent: some View {
        coordinatedContent
        .sheet(isPresented: $showApproval, onDismiss: {
            if let approval { approvals.resolve(approval.id, allow: false) }
            approval = nil
            if let first = approvals.pending.first { DispatchQueue.main.async { approval = first; showApproval = true } }
        }) {
            if let approval { ToolApprovalView(request: approval) }
        }
        .sheet(item: $demoToConfigure) { demo in
            DemoVariablesSheet(demo: demo) { prompt in
                demoToConfigure = nil
                prepareDemo(demo, prompt: prompt)
            }
        }
        .sheet(isPresented: $showComparison) {
            ModelComparisonSheet(models: catalog.models.filter { compatible($0, with: .text) }, backend: backendModel)
        }
        .alert("Bedrock", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }

    var body: some View {
        presentedContent
        .focusedSceneValue(\.workbenchCommands, WindowCommands(
            canArchive: selectedChat != nil && store.destination == .chats && !store.showCommandPalette,
            archive: {
                if let selectedChat, store.destination == .chats { store.archive(selectedChat.chatId) }
            },
            toggleSidebar: toggleSidebar,
            canGoBack: canGoBack,
            goBack: goBack,
            canFind: selectedChat != nil && store.destination == .chats && !store.showCommandPalette,
            find: { NotificationCenter.default.post(name: .findBedrockConversation, object: store.selectedThreadID) }
        ))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workbench.main")
    }

    @ViewBuilder private var detail: some View {
        switch store.destination {
        case .chats:
            if let selectedChat { ChatView(chatId: selectedChat.chatId, backendModel: backendModel).id(selectedChat.chatId) }
            else { welcome }
        case .demos: DemoLibraryView(onUse: useDemo)
        case .automations: AutomationsView()
        case .activity: ActivityView()
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if store.destination != .chats {
            ToolbarItem(placement: .principal) {
                Text(store.destination.title).font(DesignTokens.label)
            }
        }
        if #available(macOS 26.0, *) {
            ToolbarItemGroup(placement: .primaryAction) { toolbarActions }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItemGroup(placement: .primaryAction) { toolbarActions }
        }
    }

    private var toolbarActions: some View {
        Group {
            if let selectedChat, store.destination == .chats {
                ActionMenu(horizontalPadding: 0) { ThreadContextMenu(chat: selectedChat) } label: {
                    ToolbarIcon("ellipsis")
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Chat options").accessibilityLabel("Chat options")
                .accessibilityIdentifier("toolbar.chatOptions")
            } else {
                Color.clear
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
            }
            Button { store.showCommandPalette.toggle() } label: {
                ToolbarIcon("magnifyingglass")
            }
                .buttonStyle(LiquidGlassToolbarButtonStyle())
                .help("Search chats and commands (⌘K)").accessibilityLabel("Search")
                .accessibilityIdentifier("toolbar.search")
        }
    }

    @ToolbarContentBuilder private var navigationToolbar: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItemGroup(placement: .navigation) { navigationButtons }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItemGroup(placement: .navigation) { navigationButtons }
        }
    }

    private var navigationButtons: some View {
        // Each action needs its own native toolbar item. A single hosted HStack
        // can reuse the first button's accessibility label for its siblings.
        Group {
            Button(action: toggleSidebar) { ToolbarIcon("sidebar.left", weight: .medium) }
                .buttonStyle(LiquidGlassToolbarButtonStyle())
                .help("Toggle sidebar (⌘B)")
                .accessibilityLabel(sidebarVisible ? "Hide sidebar" : "Show sidebar")
                .accessibilityIdentifier("toolbar.toggleSidebar")
            Button(action: goBack) { ToolbarIcon("arrow.left") }
                .buttonStyle(LiquidGlassToolbarButtonStyle())
                .disabled(!canGoBack)
                .help("Back (⌘[)").accessibilityLabel("Back")
                .accessibilityIdentifier("toolbar.back")
        }
    }

    private func connectionBanner(_ error: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
            Text("AWS connection needs attention").font(.system(size: 12))
            Spacer()
            Button("Settings") { store.showSettings(row: "connectionTest") }.buttonStyle(.link)
            Button("Retry") { Task { await catalog.refresh(backend: backendModel.backend) } }.buttonStyle(.link)
        }
        .padding(.horizontal, 22).padding(.vertical, 9)
        .background(Color.orange.opacity(0.065)).help(error)
    }

    private func toggleSidebar() {
        withAnimation(reduceMotion ? nil : AppMotion.standard) {
            sidebarVisible.toggle()
        }
    }
    private func closeSearch() {
        store.showCommandPalette = false
        AppWindows.focusComposer()
    }
    private func canOpen(_ location: NavigationLocation) -> Bool {
        guard location.destination == .chats, let id = location.threadID else { return true }
        return chats.chats.contains(where: { $0.chatId == id }) &&
            !store.thread(id).archived
    }
    private func goBack() {
        guard let previous = navigationHistory.back(where: canOpen) else { return }
        if previous.destination == .chats { store.selectThread(previous.threadID) }
        else { store.destination = previous.destination }
    }
}

private extension MainWindowView {
    var welcome: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 32)
            VStack(spacing: 24) {
                Text("How can I help?")
                    .font(.system(size: 26, weight: .medium)).tracking(-0.5)
                ComposerView(chatID: "new-thread", userInput: $newDraftText, sharedMediaDataSource: newThreadMedia,
                               transcribeManager: transcribeManager, sendMessage: sendNewThread,
                               cancelSending: {}, modelId: selectedModel?.id ?? "", backend: backendModel.backend, onModelChange: { model in
                                   menuSelection = .chat(model)
                               }, isPreparingConversation: newThreadDraft.isRestoring)
                    .frame(maxWidth: DesignTokens.contentWidth + 24)
            }
            .padding(.horizontal, 16)
            Spacer(minLength: 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("workbench.welcome")
    }

    func beginNewThread() {
        // As in the original client, ⌘N creates a distinct blank chat using the
        // current model. A draft in the previous conversation stays there.
        guard let model = selectedModel ?? catalog.defaultModel else {
            store.selectThread(nil)
            AppWindows.focusComposer()
            return
        }
        let chat = AppActions.newThread(model: model)
        menuSelection = .chat(chat)
        AppWindows.focusComposer()
    }

    func sendNewThread() async {
        guard await newThreadDraft.prepareForSending() else { return }
        guard let model = selectedModel else { store.showSettings(row: "connectionTest"); return }
        let metadata = store.thread("new-thread")
        let chat = AppActions.newThread(model: model, draft: newDraftText, skillIDs: metadata.skillIDs)
        // Settings calls this “Use in the next chat”. Keep the selected skills
        // on the created conversation without silently applying them forever.
        store.updateThread("new-thread") { $0.skillIDs.removeAll() }
        let session = ChatSessionPool.shared.session(chatID: chat.chatId, backend: backendModel)
        copyMedia(newThreadMedia, to: session.sharedMediaDataSource)
        newThreadMedia.clear()
        newDraftText = ""
        store.updateDraft("new-thread", text: "")
        await session.waitUntilReady()
        session.sendMessage()
    }

    func sendQuickAccess() {
        guard let model = selectedModel ?? catalog.defaultModel else { store.showSettings(row: "connectionTest"); return }
        let chat = AppActions.newThread(model: model, draft: coordinator.quickAccessMessage ?? "")
        let session = ChatSessionPool.shared.session(chatID: chat.chatId, backend: backendModel)
        if let attachments = coordinator.quickAccessAttachments { copyMedia(attachments, to: session.sharedMediaDataSource) }
        coordinator.quickAccessMessage = nil
        coordinator.quickAccessAttachments = nil
        coordinator.isProcessingQuickAccess = false
        coordinator.targetChatId = nil
        Task { await session.waitUntilReady(); session.sendMessage() }
    }

    func copyMedia(_ source: AttachmentStore, to destination: AttachmentStore) {
        destination.copy(from: source)
    }

    func changeModel(_ value: SidebarSelection?) {
        guard case .chat(let model) = value, let chat = selectedChat, model.id != chat.id else { return }
        ChatSessionPool.shared.session(chatID: chat.chatId, backend: backendModel).switchModel(to: model)
    }
    func useDemo(_ demo: DemoPreset) {
        if demo.id == "compare" { showComparison = true }
        else if demo.variables.isEmpty { prepareDemo(demo, prompt: demo.prompt) }
        else { demoToConfigure = demo }
    }
    func prepareDemo(_ demo: DemoPreset, prompt: String) {
        let choices = BedrockModelChoice.make(descriptors: catalog.descriptors, selectedID: nil,
                                              favoriteIDs: [], region: settings.selectedRegion.rawValue)
            .map { catalog.model($0.preferredID) }
            .filter { compatible($0, with: demo.category) }
            .sorted {
                let first = DemoModelPolicy.preference($0.id, category: demo.category)
                let second = DemoModelPolicy.preference($1.id, category: demo.category)
                return first == second ? $0.id < $1.id : first < second
            }
        let model = selectedModel.flatMap { compatible($0, with: demo.category) ? $0 : nil }
            ?? choices.first
        guard let model else {
            store.errorMessage = "No compatible \(demo.category.rawValue.lowercased()) model is available in the current catalog. Check your region and AWS connection."
            return
        }
        if demo.category == .images {
            // A creation preset must not inherit the previous image-editing mode.
            if model.id.contains("stability.") { settings.stabilityAIConfig.taskType = StabilityAITaskType.textToImage.rawValue }
            else if model.id.contains("titan-image") { settings.titanImageConfig.taskType = TitanImageTaskType.textToImage.rawValue }
        }
        let chat = AppActions.newThread(model: model, draft: prompt, skillIDs: demo.skillIDs, systemPrompt: demo.systemPrompt)
        store.updateThread(chat.chatId) { $0.demoID = demo.id }
        menuSelection = .chat(chat)
    }
    func compatible(_ model: ChatModel, with category: DemoCategory) -> Bool {
        guard DemoModelPolicy.supports(model.id, category: category) else { return false }
        let backend = backendModel.backend
        switch category {
        case .images, .video, .embeddings, .text: return true
        case .documents: return backend.isDocumentChatSupported(model.id)
        case .vision: return backend.isVisionSupported(model.id) && !backend.isImageGenerationModel(model.id)
        case .tools: return backend.isStreamingToolUseSupported(model.id)
        case .reasoning: return backend.isReasoningSupported(model.id)
        }
    }
    func applyAppearance() {
        settings.applyAppearance()
    }
}
