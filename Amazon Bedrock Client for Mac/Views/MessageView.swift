//
//  MessageView.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/06.
//

import MarkdownUI
import Splash
import SwiftUI
import AppKit  // Import AppKit to use NSPasteboard

class MessageViewModel: ObservableObject {
    @Published var selectedImageData: String? = nil
    @Published var isShowingImageModal: Bool = false
    
    func selectImage(with data: String) {
        self.selectedImageData = data
        self.isShowingImageModal = true
    }
    
    func clearSelection() {
        self.selectedImageData = nil
        self.isShowingImageModal = false
    }
}

extension NSImage {
    convenience init?(base64Encoded: String) {
        guard let imageData = Data(base64Encoded: base64Encoded) else {
            return nil
        }
        self.init(data: imageData)
    }
}

struct MessageView: View {
    var message: MessageData
    @StateObject var viewModel = MessageViewModel()
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    @Environment(\.fontSize) private var fontSize: CGFloat
    @State private var isHovering = false
    
    private let imageSize: CGFloat = 100
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 12) {
                userImage
                
                VStack(alignment: .leading, spacing: 2) {
                    messageHeader
                    messageContent
                    copyButton
                        .opacity(isHovering ? 1 : 0)  // 호버 시 투명도 조절
                        .animation(.easeInOut, value: isHovering)  // 애니메이션 적용
                }
                
                Spacer()
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut) {
                isHovering = hovering
            }
        }
        .textSelection(.enabled)
    }
    
    
    private var userImage: some View {
        Group {
            if message.user == "User" {
                Image(systemName: "person.crop.square.fill")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .foregroundColor(Color.link)
                    .opacity(0.8)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.link, lineWidth: 2))
            } else {
                userImage(for: message.user)
            }
        }
        .frame(width: 40, height: 40)
    }
    
    private var messageHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(message.user)
                .font(.system(size: fontSize))
                .bold()
            
            Text(format(date: message.sentTime))
                .font(.callout)
                .foregroundColor(Color.secondary)
        }
    }
    
    @ViewBuilder
    private var messageContent: some View {
        if message.user != "User" {
            LazyMarkdownView(text: message.text, fontSize: fontSize, theme: theme)
        } else {
            userMessageContent
        }
    }
    
    private var userMessageContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let imageBase64Strings = message.imageBase64Strings, !imageBase64Strings.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(imageBase64Strings, id: \.self) { imageData in
                            LazyImageView(imageData: imageData, size: imageSize) {
                                viewModel.selectImage(with: imageData)
                            }
                        }
                    }
                }
                .frame(height: imageSize)
            }
            
            Text(message.text)
                .font(.system(size: fontSize))
        }
        .sheet(isPresented: $viewModel.isShowingImageModal) {
            if let imageData = viewModel.selectedImageData,
               let imageToShow = NSImage(base64Encoded: imageData) {
                ImageViewerModal(image: imageToShow) {
                    viewModel.clearSelection()
                }
            }
        }
    }
    
    private var copyButton: some View {
        Button(action: {
            copyMessageToClipboard()
        }) {
            Image(systemName: "doc.on.doc")
                .foregroundColor(Color.secondary)
                .font(.system(size: 12))
                .padding(2)
                .clipShape(Circle())
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var theme: Splash.Theme {
        colorScheme == .dark ? .wwdc17(withFont: .init(size: fontSize)) : .sunset(withFont: .init(size: fontSize))
    }
    
    private func copyMessageToClipboard() {
        if containsLocalhostImage {
            if let urlRange = message.text.range(of: "http://localhost:[^)]+", options: .regularExpression),
               let url = URL(string: String(message.text[urlRange])) {
                NSWorkspace.shared.open(url)
            }
        } else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(message.text, forType: .string)
        }
    }
    
    private var containsLocalhostImage: Bool {
        message.text.contains("![](http://localhost:8080/")
    }
    
    private func format(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func userImage(for user: String) -> some View {
        let imageName: String
        let isDefaultImage: Bool
        
        if user.starts(with: "Claude") {
            imageName = "anthropic sq"
            isDefaultImage = false
        } else if user.starts(with: "Mistral") {
            imageName = "mistral sq"
            isDefaultImage = false
        } else if user.starts(with: "Mixtral") {
            imageName = "mistral sq"
            isDefaultImage = false
        } else if user.starts(with: "Command") {
            imageName = "cohere sq"
            isDefaultImage = false
        } else if user.starts(with: "Llama") {
            imageName = "meta sq"
            isDefaultImage = false
        } else if user.starts(with: "Jurrasic") {
            imageName = "AI21"
            isDefaultImage = false
        } else if user.starts(with: "Jamba") {
            imageName = "AI21"
            isDefaultImage = false
        } else if user.starts(with: "Titan") {
            imageName = "amazon"
            isDefaultImage = false
        } else if user.starts(with: "SD") {
            imageName = "stability ai"
            isDefaultImage = false
        } else {
            imageName = "bedrock sq"
            isDefaultImage = true
        } 
        
        let image = Image(imageName)
        return Group {
            if isDefaultImage {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white, lineWidth: 2))
            } else {
                image
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white, lineWidth: 2))
            }
        }
    }
}

struct LazyImageView: View {
    let imageData: String
    let size: CGFloat
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            AsyncImage(url: URL(string: "data:image/jpeg;base64,\(imageData)")) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: size)
                case .failure:
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.red)
                @unknown default:
                    EmptyView()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            Button(action: {
                copyImageToClipboard(imageData: imageData)
            }) {
                Text("Copy Image")
                Image(systemName: "doc.on.doc")
            }
        }
    }
    
    func copyImageToClipboard(imageData: String) {
        if let data = Data(base64Encoded: imageData),
           let image = NSImage(data: data) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([image])
        }
    }
}


struct LazyMarkdownView: View {
    let text: String
    let fontSize: CGFloat
    let theme: Splash.Theme
    
    var body: some View {
        Markdown(text)
            .textSelection(.enabled)
            .markdownTheme(
                .gitHub
                    .codeBlock { configuration in
                        CodeBlockView(theme: theme, configuration: configuration)
                    }
            )
            .markdownCodeSyntaxHighlighter(SplashCodeSyntaxHighlighter.splash(theme: theme))
            .font(.system(size: fontSize))
    }
}

struct ImageViewerModal: View {
    var image: NSImage
    var closeModal: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.8).edgesIgnoringSafeArea(.all)
            
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .cornerRadius(10)
                .padding()
                .contextMenu {
                    Button(action: {
                        copyNSImageToClipboard(image: image)
                    }) {
                        Text("Copy Image")
                        Image(systemName: "doc.on.doc")
                    }
                }
            
            VStack {
                HStack {
                    Spacer()
                    Button(action: closeModal) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.black)
                            .font(.title)
                    }
                    .padding([.top, .trailing])
                    .buttonStyle(PlainButtonStyle())
                }
                Spacer()
            }
        }
    }
    
    func copyNSImageToClipboard(image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }
}

extension NSImage {
    func resized(to targetSize: NSSize) -> NSImage? {
        let newSize = NSSize(width: targetSize.width, height: targetSize.height)
        let newImage = NSImage(size: newSize)
        
        newImage.lockFocus()
        self.draw(in: NSRect(origin: .zero, size: newSize),
                  from: NSRect(origin: .zero, size: self.size),
                  operation: .sourceOver,
                  fraction: 1.0)
        newImage.unlockFocus()
        
        return newImage
    }
    
    func resizedMaintainingAspectRatio(maxDimension: CGFloat) -> NSImage? {
        let aspectRatio = self.size.width / self.size.height
        let newSize: NSSize
        
        if self.size.width > self.size.height {
            newSize = NSSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            newSize = NSSize(width: maxDimension * aspectRatio, height: maxDimension)
        }
        
        return resized(to: newSize)
    }
    
    func compressedData(maxFileSize: Int, maxDimension: CGFloat, format: NSBitmapImageRep.FileType = .jpeg) -> Data? {
        guard let resizedImage = self.resizedMaintainingAspectRatio(maxDimension: maxDimension),
              let tiffRepresentation = resizedImage.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        
        var compressionFactor: CGFloat = 1.0
        var data = bitmapImage.representation(using: format, properties: [.compressionFactor: compressionFactor])
        
        // 이미지 크기가 maxFileSize보다 클 때 압축률을 증가시키면서 파일 크기를 줄입니다.
        while let imageData = data, imageData.count > maxFileSize && compressionFactor > 0 {
            compressionFactor -= 0.1
            data = bitmapImage.representation(using: format, properties: [.compressionFactor: compressionFactor])
        }
        
        return data
    }
}

