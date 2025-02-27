//
//  MessageBarView.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/06.
//

import SwiftUI
import Combine
import UniformTypeIdentifiers

struct ImageViewer: View {
    var image: NSImage
    var body: some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .frame(width: 100, height: 100)
            .cornerRadius(12)
            .shadow(radius: 7)
    }
}

struct MessageBarView: View {
    var chatID: String
    @Binding var userInput: String
    @ObservedObject private var settingManager = SettingManager.shared
    @ObservedObject var chatManager: ChatManager = ChatManager.shared
    @StateObject var sharedImageDataSource: SharedImageDataSource
    var transcribeManager: TranscribeStreamingManager
    
    @State private var calculatedHeight: CGFloat = 40
    @State private var isImagePickerPresented: Bool = false
    @State private var isLoading: Bool = false
    
    // Track previously appended transcript text.
    @State private var previousTranscript: String = ""
    @FocusState private var isInputFocused: Bool
    
    var sendMessage: () async -> Void
    var cancelSending: () -> Void
    var modelId: String
    
    var body: some View {
        VStack {
            if !sharedImageDataSource.images.isEmpty {
                imagePreview
            }
            // The main message bar with file upload, mic, input, and send buttons.
            HStack(alignment: .center, spacing: 2) {
                fileUploadButton
                advancedOptionsButton
                inputArea
                micButton
                sendButton
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(NSColor.windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
        .foregroundColor(Color.text)
        .onExitCommand {
            if isLoading { cancelSending() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            DispatchQueue.main.async {
                isInputFocused = true
            }
        }
    }
    
    private var imagePreview: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(sharedImageDataSource.images.indices, id: \.self) { index in
                    ImageViewer(image: sharedImageDataSource.images[index])
                        .overlay(deleteButton(at: index), alignment: .topTrailing)
                }
            }
            .padding(.horizontal)
            .frame(height: 110)
        }
    }
    
    private func deleteButton(at index: Int) -> some View {
        Button(action: {
            sharedImageDataSource.images.remove(at: index)
        }) {
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.gray)
                .background(Color.white)
                .clipShape(Circle())
        }
        .buttonStyle(PlainButtonStyle())
        .padding(2)
    }
    
    private var advancedOptionsButton: some View {
        Menu {
            Text("More Options")
                .font(.headline)
                .foregroundColor(.secondary)
            
            if modelId.contains("3-7") {
                Toggle("Enable Thinking", isOn: $settingManager.enableModelThinking)
                    .help("Allow Claude 3.7 to show its thinking process")
            }
            
            Toggle("Allow Image Pasting", isOn: $settingManager.allowImagePasting)
                .help("Enable or disable image pasting functionality")
            
            
            if !settingManager.systemPrompt.isEmpty {
                Button(action: {
                    // Create alert to view system prompt
                    let alert = NSAlert()
                    alert.messageText = "System Prompt"
                    alert.informativeText = settingManager.systemPrompt
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }) {
                    Label("View System Prompt", systemImage: "info.circle")
                }
            }
        } label: {
            Image(systemName: "plus.circle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
        }
        .buttonStyle(PlainButtonStyle())
        .menuIndicator(.hidden)
        .frame(width: 32, height: 32)
        .clipShape(Circle())
        
    }
    
    private var fileUploadButton: some View {
        Button(action: {
            isImagePickerPresented = true
        }) {
            Image(systemName: "paperclip")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.primary)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: 32, height: 32)
        .clipShape(Circle())
        .fileImporter(
            isPresented: $isImagePickerPresented,
            allowedContentTypes: [.jpeg, .png],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                urls.forEach { url in
                    if let image = NSImage(contentsOf: url) {
                        sharedImageDataSource.images.append(image)
                        sharedImageDataSource.fileExtensions.append(url.pathExtension)
                    }
                }
            case .failure(let error):
                print("Failed to import images: \(error.localizedDescription)")
            }
        }
    }
    
    private var micButton: some View {
        Button(action: {
            Task {
                if transcribeManager.isTranscribing {
                    transcribeManager.stopTranscription()
                } else {
                    await transcribeManager.startTranscription()
                }
            }
        }) {
            Image(systemName: transcribeManager.isTranscribing ? "mic.fill" : "mic.slash")
                .font(.system(size: 20))
                .foregroundColor(transcribeManager.isTranscribing ? .red : .primary)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: 32, height: 32)
        .clipShape(Circle())
    }
    
    private var inputArea: some View {
        FirstResponderTextView(
            text: $userInput,
            isDisabled: .constant(false),
            calculatedHeight: $calculatedHeight,
            onCommit: {
                if !userInput.isEmpty {
                    Task { await sendMessage()
                        transcribeManager.resetTranscript()
                    }
                }
            },
            onPaste: { image in
                if settingManager.allowImagePasting {
                    if let compressedData = image.compressedData(maxFileSize: 1024 * 1024, maxDimension: 1024, format: .jpeg),
                       let compressedImage = NSImage(data: compressedData) {
                        sharedImageDataSource.images.append(compressedImage)
                        sharedImageDataSource.fileExtensions.append("jpeg")
                    } else {
                        sharedImageDataSource.images.append(image)
                        sharedImageDataSource.fileExtensions.append("png")
                    }
                }
            }
        )
        .focused($isInputFocused)
        .frame(minHeight: 40, maxHeight: calculatedHeight)
        .padding(.horizontal, 4)
        .onReceive(transcribeManager.$transcript) { newTranscript in
            guard !newTranscript.isEmpty else { return }
            
            DispatchQueue.main.async {
                // 현재 커서 위치 저장
                let currentPosition = userInput.count
                
                // 새로운 텍스트 추가 시 기본 공백 처리
                if !userInput.isEmpty && !userInput.hasSuffix(" ") {
                    userInput += " "
                }
                
                // 실시간으로 텍스트 추가
                let words = newTranscript.split(separator: " ")
                if let lastWord = words.last {
                    // 마지막 단어가 반복되는 경우 제거
                    let previousWords = userInput.split(separator: " ")
                    if let prevWord = previousWords.last,
                       prevWord.lowercased() == lastWord.lowercased() {
                        // Skip duplicate word
                    } else {
                        userInput = newTranscript
                    }
                } else {
                    userInput = newTranscript
                }
                
                // 커서 위치 조정
                NotificationCenter.default.post(
                    name: .transcriptUpdated,
                    object: nil
                )
            }
        }
        .onAppear {
            // Listen for transcript updates to handle cursor position
            NotificationCenter.default.addObserver(
                forName: .transcriptUpdated,
                object: nil,
                queue: .main
            ) { _ in
                // Implement in FirstResponderTextView to move cursor to end
                // You'll need to add a method to your NSTextView to handle this
            }
        }
    }
    
    private var sendButton: some View {
        Button(action: {
            if isLoading {
                cancelSending()
            } else {
                Task { await sendMessage()
                    transcribeManager.resetTranscript()
                }
            }
        }) {
            Image(systemName: isLoading ? "stop.fill" : "arrow.up")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Color.black)
                .clipShape(Circle())
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(userInput.isEmpty && !isLoading)
        .onChange(of: chatManager.getIsLoading(for: chatID)) { isLoading = $0 }
    }
}
