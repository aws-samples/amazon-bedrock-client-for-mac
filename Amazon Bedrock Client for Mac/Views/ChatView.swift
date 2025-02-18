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
    @StateObject private var sharedImageDataSource = SharedImageDataSource()
    @StateObject private var transcribeManager = TranscribeStreamingManager()
    @ObservedObject var backendModel: BackendModel
    
    @FocusState private var isSearchFocused: Bool
    
    @State private var isAtBottom: Bool = true
    
    // Search bar
    @State private var showSearchBar: Bool = false
    @State private var searchQuery: String = ""
    @State private var currentMatchIndex: Int = 0
    @State private var matches: [Int] = []
    
    init(chatId: String, backendModel: BackendModel) {
        let sharedImageDataSource = SharedImageDataSource()
        _viewModel = StateObject(
            wrappedValue: ChatViewModel(
                chatId: chatId,
                backendModel: backendModel,
                sharedImageDataSource: sharedImageDataSource
            )
        )
        _sharedImageDataSource = StateObject(wrappedValue: sharedImageDataSource)
        self._backendModel = ObservedObject(wrappedValue: backendModel)
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            if showSearchBar {
                findBar
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
            Button("Find") {
                withAnimation {
                    showSearchBar.toggle()
                }
            }
            .keyboardShortcut("f", modifiers: [.command])
        }
        .onChange(of: showSearchBar) { newValue in
            if !newValue {
                searchQuery = ""
                matches = []
                currentMatchIndex = 0
            }
        }
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
                    floatingScrollToBottomButton(outerGeo: outerGeo, proxy: proxy)
                }
                .onPreferenceChange(BottomAnchorPreferenceKey.self) { bottomY in
                    handleBottomAnchorChange(bottomY, containerHeight: outerGeo.size.height)
                }
                .onChange(of: matches) { newMatches in
                    jumpToFirstMatch(newMatches, proxy: proxy)
                }
                .onChange(of: currentMatchIndex) { idx in
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
                MessageView(message: message, searchQuery: searchQuery)
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
        .onChange(of: viewModel.messages) { _ in
            guard isAtBottom else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if isAtBottom { 
                    withAnimation {
                        proxy.scrollTo("Bottom", anchor: .bottom)
                    }
                }
            }
        }
        .onChange(of: viewModel.messages.count) { _ in
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
    
    private func floatingScrollToBottomButton(
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
                            withAnimation {
                                proxy.scrollTo("Bottom", anchor: .bottom)
                                isAtBottom = true
                            }
                        } label: {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.blue)
                                .frame(width: 36, height: 36)
                                .background(
                                    Circle()
                                        .fill(Color.white)
                                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                        Spacer()
                    }
                    .padding(.bottom, 16)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
    }
    
    private var messageBarView: some View {
        MessageBarView(
            chatID: viewModel.chatId,
            userInput: $viewModel.userInput,
            sharedImageDataSource: sharedImageDataSource,
            transcribeManager: transcribeManager,
            sendMessage: viewModel.sendMessage,
            cancelSending: viewModel.cancelSending,
            modelId: viewModel.chatModel.id
        )
    }
    
    // MARK: - Find Bar
    
    private var findBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Find", text: $searchQuery)
                .textFieldStyle(PlainTextFieldStyle())
                .frame(minWidth: 120)
                .focused($isSearchFocused)
                .onSubmit { goToNextMatch() }
                .onChange(of: searchQuery) { _ in
                    performSearch()
                }
            
            Text("\(matches.count) found")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            
            Button(action: goToPrevMatch) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(matches.isEmpty)
            
            Button(action: goToNextMatch) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(matches.isEmpty)
            
            Spacer().frame(width: 8)
            
            Button(action: {
                withAnimation {
                    showSearchBar = false
                    searchQuery = ""
                    matches = []
                    currentMatchIndex = 0
                }
            }) {
                Text("Done")
            }
            .keyboardShortcut(.escape, modifiers: [])
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 6)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(4)
        }
        .onAppear {
            isSearchFocused = true
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 10)
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
