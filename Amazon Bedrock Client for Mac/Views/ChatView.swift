//  ChatView.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/08.
//

import SwiftUI
import Combine

struct ScrollViewOffsetPreferenceKey: PreferenceKey {
    typealias Value = CGFloat
    static var defaultValue = CGFloat.zero
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    @StateObject private var sharedImageDataSource = SharedImageDataSource()
    @ObservedObject var backendModel: BackendModel
    
    @State private var isUserScrolling = false
    @State private var previousOffset: CGFloat = 0
    
    init(chatId: String, backendModel: BackendModel) {
        let sharedImageDataSource = SharedImageDataSource()
        _viewModel = StateObject(wrappedValue: ChatViewModel(chatId: chatId, backendModel: backendModel, sharedImageDataSource: sharedImageDataSource))
        _sharedImageDataSource = StateObject(wrappedValue: sharedImageDataSource)
        self._backendModel = ObservedObject(wrappedValue: backendModel)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            placeholderView
            messageScrollView
            messageBarView
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                streamingToggle
            }
        }
        .onAppear(perform: viewModel.loadInitialData)
    }
    
    private var placeholderView: some View {
        VStack(alignment: .center) {
            if viewModel.messages.isEmpty {
                Spacer()
                Text(viewModel.selectedPlaceholder).font(.title2).foregroundColor(.secondary)
            }
        }
        .textSelection(.disabled)
    }
    
    private var messageScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(viewModel.messages) { message in
                        MessageView(message: message)
                            .id(message.id)
                            .frame(maxWidth: .infinity)
                    }
                    // 맨 아래에 보이지 않는 뷰 추가
                    Color.clear
                        .frame(height: 1)
                        .id("Bottom")
                        .onAppear {
                            isUserScrolling = false
                        }
                        .onDisappear {
                            isUserScrolling = true
                        }
                }
                .padding()
            }
            .onChange(of: viewModel.messages) { _ in
                if !isUserScrolling {
                    withAnimation {
                        proxy.scrollTo("Bottom", anchor: .bottom)
                    }
                }
            }
            .task {
                // 초기 로드 시 맨 아래로 스크롤
                try? await Task.sleep(nanoseconds: 300_000_000) // 0.3초 대기
                proxy.scrollTo("Bottom", anchor: .bottom)
            }
        }
    }
    
    
    private var messageBarView: some View {
        MessageBarView(
            chatID: viewModel.chatId,
            userInput: $viewModel.userInput,
            sharedImageDataSource: sharedImageDataSource,
            sendMessage: viewModel.sendMessage,
            cancelSending: viewModel.cancelSending,
            modelId: viewModel.chatModel.id
        )
    }
    
    private var streamingToggle: some View {
        HStack {
            Text("Streaming")
                .font(.caption)
            Toggle("Stream", isOn: $viewModel.isStreamingEnabled)
                .toggleStyle(SwitchToggleStyle())
                .labelsHidden()
        }
        .onChange(of: viewModel.isStreamingEnabled) { newValue in
            UserDefaults.standard.set(newValue, forKey: "isStreamingEnabled_\(viewModel.chatId)")
        }
    }
}

struct ViewOffsetKey: PreferenceKey {
    typealias Value = CGFloat
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
