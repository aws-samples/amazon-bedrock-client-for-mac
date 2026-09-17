//
//  ChatView.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/08.
//

import SwiftUI
import Combine

struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    @StateObject private var sharedMediaDataSource = AttachmentStore()
    @StateObject private var transcribeManager = DictationService()
    @StateObject private var searchEngine = SearchEngine()
    @StateObject private var viewport = ConversationViewportController()
    @ObservedObject var backendModel: BedrockConnection
    @ObservedObject private var workbench = AppStore.shared

    @FocusState private var isSearchFocused: Bool
    @SwiftUI.Environment(\.colorScheme) private var colorScheme: ColorScheme

    @State private var isAtBottom: Bool = true
    @State private var followsOutput = true
    // Font size adjustment state
    @AppStorage("adjustedFontSize") private var adjustedFontSize: Int = -1

    // Enhanced search state
    @State private var showSearchBar: Bool = false
    @State private var searchQuery: String = ""
    @State private var currentMatchIndex: Int = 0
    @State private var searchResult: SearchResult = SearchResult(matches: [], totalMatches: 0, searchTime: 0)
    @State private var searchDebounceTimer: Timer?

    @State private var keyboardMonitor: Any?
    @State private var scrollTask: Task<Void, Never>?
    @State private var searchScrollTask: Task<Void, Never>?
    @State private var editingMessage: Message?
    @State private var inspectingMessage: MessageData?
    @State private var searchDetail: ConversationSearchDetail?
    @State private var requestedMatchMessageID: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(chatId: String, backendModel: BedrockConnection) {
        let session = ChatSessionPool.shared.session(chatID: chatId, backend: backendModel)
        let position = ConversationViewportMemory.shared.position(for: chatId)
        _viewModel = StateObject(wrappedValue: session)
        _sharedMediaDataSource = StateObject(wrappedValue: session.sharedMediaDataSource)
        _followsOutput = State(initialValue: position == nil)
        _isAtBottom = State(initialValue: position == nil)
        self._backendModel = ObservedObject(wrappedValue: backendModel)
    }

    var body: some View {
        ZStack(alignment: .top) {
            if showSearchBar {
                enhancedFindBar
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }

            VStack(spacing: 0) {
                if viewModel.isLoadingHistory {
                    ProgressView("Opening conversation…")
                        .controlSize(.small).font(DesignTokens.detail)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    messageBarView
                } else if viewModel.messages.isEmpty {
                    Spacer(minLength: 32)
                    VStack(spacing: 24) {
                        Text("How can I help?").font(.system(size: 26, weight: .medium)).tracking(-0.5)
                        messageBarView
                    }
                    Spacer(minLength: 32)
                } else {
                    messageScrollView
                    messageBarView
                    RunFooter(threadID: viewModel.chatId, isBusy: viewModel.isSending || viewModel.isLoadingHistory) {
                        followsOutput = true
                        viewModel.continueResponse()
                    }
                }
            }

        }
        .onAppear {
            // Handle quick access message if this is the target chat
            handleQuickAccessMessage()
            applyRequestedSearch()
        }
        .onChange(of: workbench.chatSearchRequest) { _, _ in applyRequestedSearch() }
        .onReceive(workbench.$destination) { destination in
            if destination != .chats {
                viewport.prepareForDeparture()
                rememberReadingPosition()
            }
        }
        .onReceive(workbench.$selectedThreadID) { id in
            if id != viewModel.chatId {
                viewport.prepareForDeparture()
                rememberReadingPosition()
            }
        }
        .onChange(of: viewModel.isLoadingHistory) { _, loading in if !loading { applyRequestedSearch() } }
        .onReceive(NotificationCenter.default.publisher(for: .findBedrockConversation)) { notification in
            guard notification.object as? String == viewModel.chatId else { return }
            withAnimation(reduceMotion ? nil : AppMotion.standard) {
                showSearchBar = true
            }
            isSearchFocused = true
        }
        .onChange(of: showSearchBar) { _, newValue in
            EditorFocusState.shared.isSearchFieldActive = newValue && isSearchFocused
            if !newValue {
                clearSearch()
            }
        }
        .onChange(of: isSearchFocused) { _, newValue in
            EditorFocusState.shared.isSearchFieldActive = showSearchBar && newValue
        }
        .onChange(of: searchQuery) { _, newQuery in
            searchScrollTask?.cancel()
            viewport.cancelPreservation()
            performDebouncedSearch(query: newQuery)
        }
        .onAppear {
            registerKeyboardShortcuts()
        }
        .onDisappear {
            rememberReadingPosition()
            if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor); self.keyboardMonitor = nil }
            searchDebounceTimer?.invalidate()
            scrollTask?.cancel()
            searchScrollTask?.cancel()
            viewport.disconnect()
            viewModel.usageHandler = nil
            EditorFocusState.shared.isSearchFieldActive = false
        }
        .sheet(item: $editingMessage) { message in
            MessageEditor(message: message) { text in
                try await viewModel.branchAndSend(prompt: message, text: text)
            }
        }
        .sheet(item: $inspectingMessage) { message in
            MessageDetails(message: message, fallbackModelID: viewModel.chatModel.id)
        }
        .sheet(item: $searchDetail) { ConversationSearchDetailView(detail: $0) }
    }

    // MARK: - Keyboard Shortcuts

    private func registerKeyboardShortcuts() {
        guard keyboardMonitor == nil else { return }
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard AppWindows.isMainWindowKey,
                  !event.modifierFlags.contains(.control),
                  !event.modifierFlags.contains(.option) else { return event }
            if event.modifierFlags.contains(.command) {
                switch event.charactersIgnoringModifiers {
                case "+", "=":
                    increaseFontSize()
                    return nil
                case "-", "_":
                    decreaseFontSize()
                    return nil
                case "0":
                    resetFontSize()
                    return nil
                default:
                    break
                }
            }
            return event
        }
    }

    // MARK: - Font Size Controls

    private func increaseFontSize() {
        if adjustedFontSize < 8 {
            adjustedFontSize += 1
        }
    }

    private func decreaseFontSize() {
        if adjustedFontSize > -4 {
            adjustedFontSize -= 1
        }
    }

    private func resetFontSize() {
        adjustedFontSize = -1
    }

    // MARK: - Placeholder

    private var placeholderView: some View {
        VStack {
            if viewModel.messages.isEmpty {
                Spacer()
                Text(viewModel.selectedPlaceholder)
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
        }
        .textSelection(.disabled)
    }

    // MARK: - Message Scroll View

    private var messageScrollView: some View {
        ScrollViewReader { proxy in
            ZStack {
                scrollableMessageList(proxy: proxy)
                enhancedScrollToBottomButton(proxy: proxy)
            }
            .onChange(of: searchResult) { _, newResult in
                jumpToFirstMatch(newResult, proxy: proxy)
            }
            .onChange(of: currentMatchIndex) { _, idx in
                jumpToMatchIndex(idx, proxy: proxy)
            }
        }
    }

    private func scrollableMessageList(proxy: ScrollViewProxy) -> some View {
        let rows = ConversationTranscript.rows(in: viewModel.messages)
        // A List's AppKit accessibility cell proxies instantiate offscreen
        // hosting views when their descriptions are read. Keep the entire
        // transcript in a lazy scroll container without those table proxies.
        return ScrollView {
            LazyVStack(spacing: 0) {
                Color.clear.frame(height: 12).accessibilityHidden(true)
                ForEach(rows) { row in
                    let message = row.message
                    VStack(spacing: 12) {
                        if let change = row.modelTransition {
                            modelTransitionView(change)
                        }
                        if viewModel.currentStreamingMessageId == message.id {
                            StreamingMessageView(stream: viewModel.streamingMessage, fallback: message,
                                                 searchResult: getSearchResultForMessage(row.sourceIndex),
                                                 adjustedFontSize: CGFloat(adjustedFontSize),
                                                 showTimestamp: workbench.preferences.showTimestamps)
                        } else {
                            MessageView(message: message, searchResult: getSearchResultForMessage(row.sourceIndex),
                                        adjustedFontSize: CGFloat(adjustedFontSize),
                                        showTimestamp: workbench.preferences.showTimestamps,
                                        canModify: !viewModel.isSending && !viewModel.isLoadingHistory,
                                        canRetry: message.user != "User" && message.id == rows.last?.id,
                                        onAction: handleMessageAction)
                                .equatable()
                        }
                    }
                    .frame(maxWidth: DesignTokens.contentWidth)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background {
                        ConversationMessageAnchor(messageID: message.id, controller: viewport)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                    .onGeometryChange(for: CGRect.self) { geometry in
                        geometry.frame(in: .named("conversation.content"))
                    } action: { frame in
                        viewport.messageDidLayout(message.id, frame: frame)
                    }
                }
                if let change = ConversationTranscript.pendingTransition(after: rows, to: viewModel.chatModel.id) {
                    modelTransitionView(change)
                        .frame(maxWidth: DesignTokens.contentWidth)
                        .padding(.horizontal, 24).padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .id("PendingModelTransition")
                }
                Color.clear.frame(height: 18).id("Bottom").accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
            .coordinateSpace(name: "conversation.content")
        }
        .environment(\.beginConversationInspection, pauseFollowingForInspection)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("conversation.transcript")
        .background(SidebarScrollChrome(viewport: viewport))
        .modifier(ScrollEdgeEffectModifier())
        .onChange(of: viewModel.messages.last?.id) { _, _ in
            if followsOutput && searchQuery.isEmpty {
                scheduleFollowing(proxy)
            }
        }
        .onChange(of: viewModel.isSending) { _, isSending in
            if isSending && followsOutput && searchQuery.isEmpty {
                scheduleFollowing(proxy)
            }
        }
        .task {
            viewport.observeScrolling(
                didScroll: { nearBottom in
                    if followsOutput != nearBottom { followsOutput = nearBottom }
                    if isAtBottom != nearBottom { isAtBottom = nearBottom }
                },
                didEnd: rememberReadingPosition,
                contentDidResize: {
                    if followsOutput && searchQuery.isEmpty {
                        scheduleFollowing(proxy)
                    } else {
                        isAtBottom = viewport.isNearBottom
                    }
                },
                firstMessageID: rows.first?.id
            )
            await Task.yield()
            guard !Task.isCancelled else { return }
            if let position = ConversationViewportMemory.shared.position(for: viewModel.chatId),
               rows.contains(where: { $0.id == position.anchor.messageID }) {
                isAtBottom = false
                followsOutput = false
                await viewport.restore(position.anchor) {
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        proxy.scrollTo(position.anchor.messageID, anchor: .top)
                    }
                }
                return
            }
            guard !Task.isCancelled, searchQuery.isEmpty else { return }
            proxy.scrollTo("Bottom", anchor: .bottom)
            isAtBottom = true
            followsOutput = true
        }
    }

    private func modelTransitionView(_ change: ConversationTranscript.ModelTransition) -> some View {
        HStack(spacing: 12) {
            Rectangle().fill(DesignTokens.border).frame(height: 1).accessibilityHidden(true)
            HStack(spacing: 6) {
                Image(systemName: "sparkles").accessibilityHidden(true)
                Text("Switched to \(ModelCatalog.shared.model(change.toModelID).name)")
                    .lineLimit(1)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .layoutPriority(1)
            Rectangle().fill(DesignTokens.border).frame(height: 1).accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Switched to \(ModelCatalog.shared.model(change.toModelID).name)")
        .accessibilityIdentifier("conversation.modelSwitch")
    }

    private func rememberReadingPosition() {
        guard !viewModel.isLoadingHistory else { return }
        let position = !followsOutput ? viewport.capture().map {
            ConversationViewportMemory.Position(anchor: $0)
        } : nil
        ConversationViewportMemory.shared.remember(position, for: viewModel.chatId)
        if let position { viewport.preserve(position.anchor) }
    }

    private func pauseFollowingForInspection() {
        // Expanding a tool or reasoning is an explicit reading interaction.
        // Preserve its position before its height changes, including while an
        // answer is still streaming. A queued follow must not move the next
        // control out from underneath the pointer.
        scrollTask?.cancel()
        searchScrollTask?.cancel()
        followsOutput = false
        viewport.cancelPreservation()
        rememberReadingPosition()
    }

    private func handleMessageAction(_ action: MessageAction, message: MessageData) {
        if case .details = action { inspectingMessage = message; return }
        if case .branch = action { AppActions.fork(viewModel.chatModel, through: message.id); return }
        Task {
            do {
                let history = try await ConversationStore.shared.conversationSnapshot(for: viewModel.chatId)
                let prompt = try ConversationEditing.prompt(before: message.id, in: history)
                switch action {
                case .edit: editingMessage = prompt
                case .retry: try await viewModel.branchAndSend(prompt: prompt)
                default: break
                }
            } catch { workbench.errorMessage = error.localizedDescription }
        }
    }

    private func scheduleFollowing(_ proxy: ScrollViewProxy) {
        // Do not reset the timer on every token: that would postpone the scroll
        // forever while a fast stream or a Markdown height update keeps arriving.
        guard scrollTask == nil else { return }
        scrollTask = Task {
            defer { scrollTask = nil }
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
            guard followsOutput, searchQuery.isEmpty else { return }
            proxy.scrollTo("Bottom", anchor: .bottom)
        }
    }

    private func enhancedScrollToBottomButton(proxy: ScrollViewProxy) -> some View {
        Group {
            if !isAtBottom {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            viewport.cancelPreservation()
                            var transaction = Transaction(animation: nil)
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                isAtBottom = true
                                followsOutput = true
                            }
                            DispatchQueue.main.async { proxy.scrollTo("Bottom", anchor: .bottom) }
                        } label: {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.primary)
                                .frame(width: 32, height: 32)
                                .background(
                                    Circle()
                                        .fill(colorScheme == .dark ?
                                              Color(NSColor.windowBackgroundColor).opacity(0.9) :
                                                Color.white.opacity(0.98))
                                        .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                                )
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.gray.opacity(0.2), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityLabel("Scroll to latest message")
                        .contentShape(Circle())
                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                        Spacer()
                    }
                    .padding(.bottom, 16)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
    }

    private var messageBarView: some View {
        VStack(spacing: 4) {
            if !viewModel.outbox.queued.isEmpty { MessageQueueView(viewModel: viewModel).padding(.horizontal, 12) }
            ComposerView(
            chatID: viewModel.chatId,
            userInput: $viewModel.userInput,
            sharedMediaDataSource: sharedMediaDataSource,
            transcribeManager: transcribeManager,
            sendMessage: {
                if !viewModel.isSending {
                    viewport.cancelPreservation()
                    followsOutput = true
                }
                await viewModel.submitDraft()
            },
            cancelSending: viewModel.cancelSending,
            modelId: viewModel.pendingModel?.id ?? viewModel.chatModel.id,
            backend: backendModel.backend,
            onModelChange: viewModel.switchModel,
            modelChangePending: viewModel.pendingModel != nil,
            isPreparingConversation: viewModel.isLoadingHistory || viewModel.isUpdatingQueue,
            supportsQueue: true
        )
        }
        .frame(maxWidth: DesignTokens.contentWidth + 24)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Find Bar Components

    private var searchFieldComponent: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 14))

            TextField("Find in chat", text: $searchQuery)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 14))
                .frame(minWidth: 140)
                .focused($isSearchFocused)
                .onSubmit { goToNextMatch() }
        }
    }

    private var matchCounterComponent: some View {
        HStack(spacing: 4) {
            if searchResult.totalMatches > 0 {
                Text("\(currentMatchIndex + 1) of \(searchResult.totalMatches)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)

            } else if !searchQuery.isEmpty {
                Text("No matches")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                Text("Enter search term")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(minWidth: 100, alignment: .leading)
    }

    private var navigationButtonsComponent: some View {
        HStack(spacing: 2) {
            Button(action: goToPrevMatch) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(searchResult.totalMatches == 0 ? Color.secondary.opacity(0.5) : Color.primary)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(searchResult.totalMatches == 0)
            .help("Previous match")

            Button(action: goToNextMatch) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(searchResult.totalMatches == 0 ? Color.secondary.opacity(0.5) : Color.primary)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(searchResult.totalMatches == 0)
            .help("Next match")
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
                )
        )
    }

    private var doneButtonComponent: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                showSearchBar = false
                clearSearch()
            }
        }) {
            Text("Done")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
        .keyboardShortcut(.escape, modifiers: [])
        .buttonStyle(PlainButtonStyle())
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }

    private var enhancedFindBar: some View {
        HStack(spacing: 10) {
            searchFieldComponent
            matchCounterComponent
            navigationButtonsComponent
            Spacer().frame(width: 4)
            doneButtonComponent
        }
        .task {
            await Task.yield()
            isSearchFocused = true
        }
        .padding(10)
        .background(DesignTokens.canvas, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(DesignTokens.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.12 : 0.04), radius: 8, y: 2)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: - Enhanced Search Logic

    private func performDebouncedSearch(query: String) {
        // Cancel previous timer
        searchDebounceTimer?.invalidate()

        // Set new timer for debounced search
        searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
            Task { @MainActor in
                performSearch(query: query)
            }
        }
    }

    private func performSearch(query: String) {
        let result = searchEngine.search(query: query, in: viewModel.messagesIncludingStream)
        let requestedID = requestedMatchMessageID
        requestedMatchMessageID = nil
        let requestedIndex = requestedID.flatMap { id in viewModel.messages.firstIndex { $0.id == id } }
        let selected = requestedIndex.map { index in
            result.matches.prefix { $0.messageIndex < index }.reduce(0) { $0 + $1.ranges.count }
        } ?? 0

        DispatchQueue.main.async {
            self.searchResult = result
            self.currentMatchIndex = min(selected, max(0, result.totalMatches - 1))
        }
    }

    private func applyRequestedSearch() {
        guard let request = workbench.chatSearchRequest, request.threadID == viewModel.chatId,
              !viewModel.isLoadingHistory else { return }
        workbench.chatSearchRequest = nil
        followsOutput = false
        if let message = viewModel.messages.first(where: { $0.id == request.messageID }) {
            switch request.target {
            case .pastedText(let id):
                if let text = message.pastedTexts?.first(where: { $0.id == id }) {
                    searchDetail = .init(title: text.filename, text: text.content, query: request.query)
                    return
                }
            case .tool(let id):
                if let tool = message.toolUses?.first(where: { $0.toolId == id }) {
                    searchDetail = .init(title: tool.displayName ?? BuiltInTool(rawValue: tool.toolName)?.title ?? tool.toolName,
                                         text: tool.result ?? "", query: request.query)
                    return
                }
                if let tool = message.toolUse, tool.id == id {
                    searchDetail = .init(title: tool.name, text: message.toolResult ?? "", query: request.query)
                    return
                }
            case .message: break
            }
        }
        showSearchBar = true
        requestedMatchMessageID = request.messageID
        if searchQuery == request.query { performSearch(query: request.query) }
        else { searchQuery = request.query }
    }

    private func clearSearch() {
        searchQuery = ""
        searchResult = SearchResult(matches: [], totalMatches: 0, searchTime: 0)
        currentMatchIndex = 0
        searchDebounceTimer?.invalidate()
    }

    private func getSearchResultForMessage(_ messageIndex: Int) -> SearchMatch? {
        guard var match = searchResult.matches.first(where: { $0.messageIndex == messageIndex }) else { return nil }
        let preceding = searchResult.matches.prefix { $0.messageIndex < messageIndex }.reduce(0) { $0 + $1.ranges.count }
        let localIndex = currentMatchIndex - preceding
        if match.ranges.indices.contains(localIndex) { match.selectedRangeIndex = localIndex }
        return match
    }

    private func jumpToFirstMatch(_ result: SearchResult, proxy: ScrollViewProxy) {
        guard !result.matches.isEmpty else { return }
        jumpToMatchIndex(currentMatchIndex, proxy: proxy)
    }

    private func jumpToMatchIndex(_ idx: Int, proxy: ScrollViewProxy) {
        guard searchResult.totalMatches > 0 else { return }

        // Find the message and match position for the current match index
        var currentCount = 0
        for match in searchResult.matches {
            let matchCount = match.ranges.count
            if idx < currentCount + matchCount {
                scrollToMatch(messageIndex: match.messageIndex, proxy: proxy)
                return
            }
            currentCount += matchCount
        }
    }

    private func scrollToMatch(messageIndex: Int, proxy: ScrollViewProxy) {
        guard viewModel.messages.indices.contains(messageIndex) else { return }
        searchScrollTask?.cancel()
        viewport.cancelPreservation()
        // Search holds its position until the user returns to the bottom.
        isAtBottom = false
        followsOutput = false

        let message = viewModel.messages[messageIndex]
        if viewport.isVisible(messageID: message.id),
           message.user != "User", MarkdownPreparation.usesWebRenderer(message.text) {
            // The WebKit renderer scrolls to the exact match. A coarse scroll
            // here can run afterward and incorrectly recenter a long response.
            return
        }
        // The lazy stack initially seeks using estimated offscreen heights.
        // Seek until the actual row exists, then use its measured coordinates.
        searchScrollTask = Task {
            await viewport.align(messageID: message.id, fraction: 0.5) {
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) { proxy.scrollTo(message.id, anchor: .center) }
            }
        }
    }

    private func goToPrevMatch() {
        guard searchResult.totalMatches > 0 else { return }
        if currentMatchIndex > 0 {
            currentMatchIndex -= 1
        } else {
            currentMatchIndex = searchResult.totalMatches - 1
        }
    }

    private func goToNextMatch() {
        guard searchResult.totalMatches > 0 else { return }
        if currentMatchIndex < searchResult.totalMatches - 1 {
            currentMatchIndex += 1
        } else {
            currentMatchIndex = 0
        }
    }

    // MARK: - Quick Access Message Handler

    private func handleQuickAccessMessage() {
        // Check if this chat is the target for a quick access message
        guard let targetChatId = AppCoordinator.shared.targetChatId,
              targetChatId == viewModel.chatId,
              AppCoordinator.shared.isProcessingQuickAccess else { return }

        let message = AppCoordinator.shared.quickAccessMessage ?? ""
        let attachments = AppCoordinator.shared.quickAccessAttachments

        // Must have either message or attachments
        guard !message.isEmpty || (attachments != nil && (!attachments!.images.isEmpty || !attachments!.documents.isEmpty)) else { return }

        print("DEBUG: Handling quick access message for chat: \(viewModel.chatId)")

        // Handle attachments if present
        if let attachments = attachments {
            // Copy attachments to the view model's shared media data source
            viewModel.sharedMediaDataSource.copy(from: attachments)
        }

        // Clear the message and attachments to prevent re-processing
        AppCoordinator.shared.quickAccessMessage = nil
        AppCoordinator.shared.quickAccessAttachments = nil

        Task {
            await viewModel.waitUntilReady()
            if !message.isEmpty {
                self.viewModel.sendMessage(message)
            } else {
                // If only attachments, send empty message to trigger attachment sending
                self.viewModel.userInput = " " // Space to trigger send
                self.viewModel.sendMessage()
            }
        }
    }
}
