//
//  ChatView.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/08.
//

import SwiftUI
import Combine

struct BottomAnchorPreferenceKey: PreferenceKey {
    typealias Value = CGFloat
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    @StateObject private var sharedMediaDataSource = SharedMediaDataSource()
    @StateObject private var transcribeManager = TranscribeStreamingManager()
    @StateObject private var searchEngine = SearchEngine()
    @ObservedObject var backendModel: BackendModel
    
    @FocusState private var isSearchFocused: Bool
    @SwiftUI.Environment(\.colorScheme) private var colorScheme: ColorScheme
    
    @State private var isAtBottom: Bool = true
    @State private var isSearchActive: Bool = false // Add search state tracking
    
    // Font size adjustment state
    @AppStorage("adjustedFontSize") private var adjustedFontSize: Int = -1
    
    // Enhanced search state
    @State private var showSearchBar: Bool = false
    @State private var searchQuery: String = ""
    @State private var currentMatchIndex: Int = 0
    @State private var searchResult: SearchResult = SearchResult(matches: [], totalMatches: 0, searchTime: 0)
    @State private var searchDebounceTimer: Timer?
    
    // Usage toast state
    @State private var showUsageToast: Bool = false
    @State private var currentUsage: String = ""
    @State private var usageToastTimer: Timer?
    
    init(chatId: String, backendModel: BackendModel) {
        let sharedMediaDataSource = SharedMediaDataSource()
        _viewModel = StateObject(
            wrappedValue: ChatViewModel(
                chatId: chatId,
                backendModel: backendModel,
                sharedMediaDataSource: sharedMediaDataSource
            )
        )
        _sharedMediaDataSource = StateObject(wrappedValue: sharedMediaDataSource)
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
                placeholderView
                messageScrollView
                messageBarView
            }
            
            // Usage toast
            if showUsageToast && SettingManager.shared.showUsageInfo {
                VStack {
                    usageToastView
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(5)
                    Spacer()
                }
                .padding(.top, showSearchBar ? 80 : 12)
                .allowsHitTesting(false)
            }
        }
        .onAppear {
            // Restore existing messages from disk or other storage
            viewModel.loadInitialData()
            
            // Set up usage handler for toast notifications
            viewModel.usageHandler = { usage in
                DispatchQueue.main.async {
                    showUsageToast(with: usage)
                }
            }
        }
        .toolbar {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showSearchBar.toggle()
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(ToolbarButtonStyle())
            .help("Find")
            .keyboardShortcut("f", modifiers: [.command])
        }
        .onChange(of: showSearchBar) { _, newValue in
            AppStateManager.shared.isSearchFieldActive = newValue && isSearchFocused
            if !newValue {
                clearSearch()
            }
        }
        .onChange(of: isSearchFocused) { _, newValue in
            AppStateManager.shared.isSearchFieldActive = showSearchBar && newValue
        }
        .onChange(of: searchQuery) { _, newQuery in
            performDebouncedSearch(query: newQuery)
        }
        .onAppear {
            registerKeyboardShortcuts()
        }
    }
    
    // MARK: - Keyboard Shortcuts
    
    private func registerKeyboardShortcuts() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
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
        GeometryReader { outerGeo in
            ScrollViewReader { proxy in
                ZStack {
                    scrollableMessageList(outerGeo: outerGeo, proxy: proxy)
                    enhancedScrollToBottomButton(outerGeo: outerGeo, proxy: proxy)
                }
                .onPreferenceChange(BottomAnchorPreferenceKey.self) { bottomY in
                    handleBottomAnchorChange(bottomY, containerHeight: outerGeo.size.height)
                }
                .onChange(of: searchResult) { _, newResult in
                    jumpToFirstMatch(newResult, proxy: proxy)
                }
                .onChange(of: currentMatchIndex) { _, idx in
                    jumpToMatchIndex(idx, proxy: proxy)
                }
            }
        }
    }
    
    private func scrollableMessageList(
        outerGeo: GeometryProxy,
        proxy: ScrollViewProxy
    ) -> some View {
        let messageList = VStack(spacing: 2) {
            ForEach(Array(viewModel.messages.enumerated()), id: \.offset) { idx, message in
                MessageView(
                    message: message, 
                    searchResult: getSearchResultForMessage(idx),
                    adjustedFontSize: CGFloat(adjustedFontSize)
                )
                    .id(idx)
                    .frame(maxWidth: .infinity)
            }
            Color.clear
                .frame(height: 1)
                .id("Bottom")
                .anchorPreference(key: BottomAnchorPreferenceKey.self, value: .bottom) { anchor in
                    outerGeo[anchor].y
                }
        }
            .padding()
        
        return ScrollView {
            messageList
        }
        .onChange(of: viewModel.messages) { _, _ in
            // If the user was at bottom and not searching, wait briefly for layout and scroll down again
            if isAtBottom && searchQuery.isEmpty {
                Task {
                    try? await Task.sleep(nanoseconds: 50_000_000) // 0.05s
                    withAnimation {
                        proxy.scrollTo("Bottom", anchor: .bottom)
                    }
                }
            }
        }
        // Scroll to bottom whenever the count of messages changes (but not during search)
        .onChange(of: viewModel.messages.count) { _, _ in
            if searchQuery.isEmpty {
                withAnimation {
                    proxy.scrollTo("Bottom", anchor: .bottom)
                }
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            proxy.scrollTo("Bottom", anchor: .bottom)
            isAtBottom = true
        }
    }
    
    private func enhancedScrollToBottomButton(
        outerGeo: GeometryProxy,
        proxy: ScrollViewProxy
    ) -> some View {
        Group {
            if !isAtBottom {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                proxy.scrollTo("Bottom", anchor: .bottom)
                                isAtBottom = true
                            }
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
        MessageBarView(
            chatID: viewModel.chatId,
            userInput: $viewModel.userInput,
            sharedMediaDataSource: sharedMediaDataSource,
            transcribeManager: transcribeManager,
            sendMessage: viewModel.sendMessage,
            cancelSending: viewModel.cancelSending,
            modelId: viewModel.chatModel.id
        )
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
                .onReceive(NotificationCenter.default.publisher(for: NSControl.textDidChangeNotification)) { _ in
                    // Additional change detection for more responsive search
                }
        }
    }
    
    private var matchCounterComponent: some View {
        HStack(spacing: 4) {
            if searchResult.totalMatches > 0 {
                Text("\(currentMatchIndex + 1) of \(searchResult.totalMatches)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                
                if searchResult.searchTime > 0.001 {
                    Text("(\(String(format: "%.1f", searchResult.searchTime * 1000))ms)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
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
        .onAppear {
            isSearchFocused = true
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ?
                      Color(NSColor.windowBackgroundColor).opacity(0.95) :
                        Color(NSColor.windowBackgroundColor).opacity(0.95))
                .shadow(color: Color.black.opacity(0.15), radius: 5, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.15), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
    
    // MARK: - Enhanced Search Logic
    
    private func performDebouncedSearch(query: String) {
        // Cancel previous timer
        searchDebounceTimer?.invalidate()
        
        // Set new timer for debounced search
        searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
            performSearch(query: query)
        }
    }
    
    private func performSearch(query: String) {
        let result = searchEngine.search(query: query, in: viewModel.messages)
        
        DispatchQueue.main.async {
            self.searchResult = result
            self.currentMatchIndex = 0
        }
    }
    
    private func clearSearch() {
        searchQuery = ""
        searchResult = SearchResult(matches: [], totalMatches: 0, searchTime: 0)
        currentMatchIndex = 0
        searchDebounceTimer?.invalidate()
    }
    
    private func getSearchResultForMessage(_ messageIndex: Int) -> SearchMatch? {
        return searchResult.matches.first { $0.messageIndex == messageIndex }
    }
    
    private func handleBottomAnchorChange(_ bottomY: CGFloat, containerHeight: CGFloat) {
        let threshold: CGFloat = 50
        isAtBottom = (bottomY <= containerHeight + threshold)
    }
    
    private func jumpToFirstMatch(_ result: SearchResult, proxy: ScrollViewProxy) {
        guard let firstMatch = result.matches.first else { return }
        scrollToMatch(messageIndex: firstMatch.messageIndex, matchIndex: 0, proxy: proxy)
    }
    
    private func jumpToMatchIndex(_ idx: Int, proxy: ScrollViewProxy) {
        guard searchResult.totalMatches > 0 else { return }
        
        // Find the message and match position for the current match index
        var currentCount = 0
        for match in searchResult.matches {
            let matchCount = match.ranges.count
            if idx < currentCount + matchCount {
                let localMatchIndex = idx - currentCount
                scrollToMatch(messageIndex: match.messageIndex, matchIndex: localMatchIndex, proxy: proxy)
                return
            }
            currentCount += matchCount
        }
    }
    
    private func scrollToMatch(messageIndex: Int, matchIndex: Int, proxy: ScrollViewProxy) {
        // Temporarily disable auto-scroll to bottom
        let wasAtBottom = isAtBottom
        isAtBottom = false
        
        withAnimation(.easeInOut(duration: 0.3)) {
            // First scroll to the message
            proxy.scrollTo(messageIndex, anchor: .center)
        }
        
        // Then notify the specific message to highlight and scroll to the exact match
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NotificationCenter.default.post(
                name: NSNotification.Name("ScrollToSearchMatch"),
                object: nil,
                userInfo: [
                    "messageIndex": messageIndex,
                    "matchIndex": matchIndex,
                    "searchQuery": self.searchQuery
                ]
            )
            
            // Keep auto-scroll disabled for a bit longer to prevent interference
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                // Only restore auto-scroll if we were actually at bottom before
                if wasAtBottom {
                    self.isAtBottom = true
                }
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
    
    // MARK: - Usage Toast
    
    private var usageToastView: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            
            Text(currentUsage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(colorScheme == .dark ?
                      Color(NSColor.windowBackgroundColor).opacity(0.95) :
                      Color(NSColor.windowBackgroundColor).opacity(0.95))
                .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
        )
    }
    
    private func showUsageToast(with usage: String) {
        currentUsage = usage
        
        // Cancel existing timer
        usageToastTimer?.invalidate()
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showUsageToast = true
        }
        
        // Hide after 3 seconds
        usageToastTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                showUsageToast = false
            }
        }
    }
}
