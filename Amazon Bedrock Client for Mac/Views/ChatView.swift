//  ChatView.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/08.
//

import SwiftUI
import Combine

/// A preference key that stores the vertical position of the bottom anchor in global space.
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
    @ObservedObject var backendModel: BackendModel
    
    /// Tracks if the user is currently at the bottom of the message list
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
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                streamingToggle
            }
        }
        .onAppear(perform: viewModel.loadInitialData)
    }
    
    /// Displays a placeholder if there are no messages.
    private var placeholderView: some View {
        VStack(alignment: .center) {
            if viewModel.messages.isEmpty {
                Spacer()
                Text(viewModel.selectedPlaceholder)
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
        }
        .textSelection(.disabled)
    }
    
    /// Main scrollable message area with anchor-based detection of the bottom.
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
                                .anchorPreference(
                                    key: BottomAnchorPreferenceKey.self,
                                    value: .bottom
                                ) { anchor in
                                    // Return the y-coordinate of the bottom anchor in global space
                                    outerGeo[anchor].y
                                }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.messages) { _ in
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
                    .onChange(of: viewModel.messages.count) { _ in
                        withAnimation {
                            proxy.scrollTo("Bottom", anchor: .bottom)
                        }
                    }
                    
                    .task {
                        // Initial delay before scrolling down to let content load
                        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                        proxy.scrollTo("Bottom", anchor: .bottom)
                        isAtBottom = true
                    }
                    
                    // A floating scroll-to-bottom button that appears if the user isn't at the bottom
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
                    }                }
                .onPreferenceChange(BottomAnchorPreferenceKey.self) { bottomY in
                    // Compare bottomY to the visible height of the container.
                    // If the bottom anchor is within a threshold of the container height, the user is at the bottom.
                    let visibleHeight = outerGeo.size.height
                    let threshold: CGFloat = 50
                    if bottomY <= visibleHeight + threshold {
                        isAtBottom = true
                    } else {
                        isAtBottom = false
                    }
                }
                
                
            }
        }
    }
    
    /// The message input area at the bottom.
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
    
    /// A toggle to enable or disable streaming mode.
    private var streamingToggle: some View {
        HStack {
            Text("Streaming")
                .font(.caption)
            Toggle("Stream", isOn: $viewModel.isStreamingEnabled)
                .toggleStyle(SwitchToggleStyle())
                .labelsHidden()
        }
        .onChange(of: viewModel.isStreamingEnabled) { newValue in
            UserDefaults.standard.set(
                newValue,
                forKey: "isStreamingEnabled_\(viewModel.chatId)"
            )
        }
    }
}
