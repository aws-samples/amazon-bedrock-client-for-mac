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
    
    @State private var isAtBottom: Bool = true
    
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
        VStack(spacing: 0) {
            placeholderView
            messageScrollView
            messageBarView
        }
        .onAppear(perform: viewModel.loadInitialData)
    }
    
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
    
    private var messageScrollView: some View {
        GeometryReader { outerGeo in
            ScrollViewReader { proxy in
                ZStack {
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(viewModel.messages) { message in
                                MessageView(message: message)
                                    .id(message.id)
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
                    }
                    .onChange(of: viewModel.messages) { _ in
                        if isAtBottom {
                            Task {
                                try? await Task.sleep(nanoseconds: 50_000_000)
                                withAnimation { proxy.scrollTo("Bottom", anchor: .bottom) }
                            }
                        }
                    }
                    .onChange(of: viewModel.messages.count) { _ in
                        withAnimation { proxy.scrollTo("Bottom", anchor: .bottom) }
                    }
                    .task {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        proxy.scrollTo("Bottom", anchor: .bottom)
                        isAtBottom = true
                    }
                    
                    if !isAtBottom {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Button(action: {
                                    withAnimation {
                                        proxy.scrollTo("Bottom", anchor: .bottom)
                                        isAtBottom = true
                                    }
                                }) {
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
                .onPreferenceChange(BottomAnchorPreferenceKey.self) { bottomY in
                    let visibleHeight = outerGeo.size.height
                    let threshold: CGFloat = 50
                    isAtBottom = (bottomY <= visibleHeight + threshold)
                }
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
}
