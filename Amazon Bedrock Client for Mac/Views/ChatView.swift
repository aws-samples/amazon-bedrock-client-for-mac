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
    @ObservedObject var backendModel: BackendModel
    
    @FocusState private var isSearchFocused: Bool
    @SwiftUI.Environment(\.colorScheme) private var colorScheme: ColorScheme
    
    @State private var isAtBottom: Bool = true
    
    // Font size adjustment state
    @AppStorage("adjustedFontSize") private var adjustedFontSize: Int = -1
    
    // Search bar
    @State private var showSearchBar: Bool = false
    @State private var searchQuery: String = ""
    @State private var currentMatchIndex: Int = 0
    @State private var matches: [Int] = []
    
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
        }
        .onAppear {
            // Restore existing messages from disk or other storage
            viewModel.loadInitialData()
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
                searchQuery = ""
                matches = []
                currentMatchIndex = 0
            }
        }
        .onChange(of: isSearchFocused) { _, newValue in
            AppStateManager.shared.isSearchFieldActive = showSearchBar && newValue
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
                .onChange(of: matches) { _, newMatches in
                    jumpToFirstMatch(newMatches, proxy: proxy)
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
                MessageView(message: message, searchQuery: searchQuery, adjustedFontSize: CGFloat(adjustedFontSize))
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
            // If the user was at bottom, wait briefly for layout and scroll down again
            if isAtBottom {
                Task {
                    try? await Task.sleep(nanoseconds: 50_000_000) // 0.05s
                    withAnimation {
                        proxy.scrollTo("Bottom", anchor: .bottom)
                    }
                }
            }
        }
        // Scroll to bottom whenever the count of messages changes
        .onChange(of: viewModel.messages.count) { _, _ in
            withAnimation {
                proxy.scrollTo("Bottom", anchor: .bottom)
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
                .onChange(of: searchQuery) { _, _ in
                    performSearch()
                }
        }
    }
    
    private var matchCounterComponent: some View {
        Text("\(currentMatchIndex + (matches.isEmpty ? 0 : 1)) of \(matches.count)")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(width: 70, alignment: .leading)
            .opacity(matches.isEmpty ? 0.5 : 1.0)
    }
    
    private var navigationButtonsComponent: some View {
        HStack(spacing: 4) {
            Button(action: goToPrevMatch) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 13))
                    .foregroundColor(matches.isEmpty ? Color.secondary.opacity(0.5) : Color.secondary)
                    .padding(4)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(matches.isEmpty)
            .contentShape(Rectangle())
            
            Button(action: goToNextMatch) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 13))
                    .foregroundColor(matches.isEmpty ? Color.secondary.opacity(0.5) : Color.secondary)
                    .padding(4)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(matches.isEmpty)
            .contentShape(Rectangle())
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.7))
        )
    }
    
    private var doneButtonComponent: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                showSearchBar = false
                searchQuery = ""
                matches = []
                currentMatchIndex = 0
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
    
    // MARK: - Search Logic
    
    private func handleBottomAnchorChange(_ bottomY: CGFloat, containerHeight: CGFloat) {
        let threshold: CGFloat = 50
        isAtBottom = (bottomY <= containerHeight + threshold)
    }
    
    private func jumpToFirstMatch(_ newMatches: [Int], proxy: ScrollViewProxy) {
        if let first = newMatches.first {
            withAnimation {
                proxy.scrollTo(first, anchor: .center)
            }
        }
    }
    
    private func jumpToMatchIndex(_ idx: Int, proxy: ScrollViewProxy) {
        guard matches.indices.contains(idx) else { return }
        let targetId = matches[idx]
        withAnimation {
            proxy.scrollTo(targetId, anchor: .center)
        }
    }
    
    private func performSearch() {
        let lowerQuery = searchQuery.lowercased()
        if lowerQuery.isEmpty {
            matches = []
            currentMatchIndex = 0
            return
        }
        matches = viewModel.messages.indices.filter { idx in
            viewModel.messages[idx].text.lowercased().contains(lowerQuery)
        }
        currentMatchIndex = 0
    }
    
    private func goToPrevMatch() {
        guard !matches.isEmpty else { return }
        if currentMatchIndex > 0 {
            currentMatchIndex -= 1
        } else {
            currentMatchIndex = matches.count - 1
        }
    }
    
    private func goToNextMatch() {
        guard !matches.isEmpty else { return }
        if currentMatchIndex < matches.count - 1 {
            currentMatchIndex += 1
        } else {
            currentMatchIndex = 0
        }
    }
}
