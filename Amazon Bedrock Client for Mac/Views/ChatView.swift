//  ChatView.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/08.
//

import SwiftUI
import Combine

struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    @StateObject private var sharedImageDataSource = SharedImageDataSource()
    @ObservedObject var backendModel: BackendModel
    
    @State private var isUserScrolling = false
    
    init(chatId: String, backendModel: BackendModel) {
        let sharedImageDataSource = SharedImageDataSource()
        _viewModel = StateObject(wrappedValue: ChatViewModel(chatId: chatId, backend: backendModel.backend, sharedImageDataSource: sharedImageDataSource))
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
        .onChange(of: viewModel.messages) { _ in
            if !isUserScrolling {
                viewModel.scrollToBottom()
            }
        }
        .onChange(of: backendModel.backend) { newBackend in
            viewModel.updateBackend(newBackend)
        }
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
           ScrollView {
               ScrollViewReader { proxy in
                   LazyVStack(spacing: 2) {
                       ForEach(viewModel.messages) { message in
                           MessageView(message: message)
                               .id(message.id)
                       }
                   }
                   .background(GeometryReader { geometry in
                       Color.clear.preference(key: ViewOffsetKey.self, value: geometry.frame(in: .named("scroll")).origin.y)
                   })
                   .onPreferenceChange(ViewOffsetKey.self) { value in
                       if value > 50 {
                           isUserScrolling = true
                       } else {
                           isUserScrolling = false
                       }
                   }
                   .onChange(of: viewModel.scrollToBottomTrigger) { _ in
                       if !isUserScrolling {
                           withAnimation {
                               proxy.scrollTo(viewModel.messages.last?.id, anchor: .bottom)
                           }
                       }
                   }
               }
               .padding()
           }
           .coordinateSpace(name: "scroll")
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
