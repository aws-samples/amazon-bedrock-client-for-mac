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
    
    @ObservedObject var viewModel = MessageViewModel()
    
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    @Environment(\.fontSize) private var fontSize: CGFloat
    
    func userImage(for user: String) -> some View {
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
                    .alignmentGuide(VerticalAlignment.center) { d in d[.top] }
            } else {
                image
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white, lineWidth: 2))
                    .alignmentGuide(VerticalAlignment.center) { d in d[.top] }
            }
        }
    }
    
    private var theme: Splash.Theme {
        switch self.colorScheme {
        case .dark:
            return .wwdc17(withFont: .init(size: self.fontSize))
        default:
            return .sunset(withFont: .init(size: self.fontSize))
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            if message.user == "User" {
                Image(systemName: "person.crop.square.fill")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .foregroundColor(Color.link)
                    .opacity(0.8)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.link, lineWidth: 2)
                    )
                    .alignmentGuide(VerticalAlignment.center) { d in d[.top] }
            } else {
                userImage(for: message.user)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(message.user)
                        .font(.system(size: self.fontSize))
                        .bold()
                        .textSelection(.enabled)
                    
                    Text(format(date: message.sentTime))
                        .font(.callout)
                        .foregroundColor(Color.secondary)
                        .textSelection(.enabled)
                }
                
                if message.user != "User" {
                    Markdown(message.text)
                        .id(message.id)
                        .textSelection(.enabled)
                        .markdownTheme(
                          .gitHub
                            .codeBlock() {
                              CodeBlockView(theme: theme, configuration: $0)
                            }
                        )
                        .markdownCodeSyntaxHighlighter(SplashCodeSyntaxHighlighter.splash(theme: self.theme))
                        .font(.system(size: self.fontSize))
                } else {
                    HStack(spacing: 10) {
                        ForEach(message.imageBase64Strings ?? [], id: \.self) { imageData in
                            Button(action: {
                                viewModel.selectImage(with: imageData)
                            }) {
                                if let image = NSImage(base64Encoded: imageData) {
                                    if let compressedData = image.compressedData(maxFileSize: 100 * 1024, maxDimension: 500),
                                       let compressedImage = NSImage(data: compressedData) {
                                        Image(nsImage: compressedImage)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 100, height: 100)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                                            )
                                    } else {
                                        Image(nsImage: image)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 100, height: 100)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                                            )
                                    }
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                            .onHover { isHovering in
                                if isHovering {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                        }
                    }
                    .sheet(isPresented: $viewModel.isShowingImageModal) {
                        if let imageData = viewModel.selectedImageData, let imageToShow = NSImage(base64Encoded: imageData) {
                            ImageViewerModal(image: imageToShow) {
                                viewModel.clearSelection()
                            }
                        }
                    }
                    
                    Text(message.text)
                        .font(.system(size: self.fontSize))
                        .textSelection(.enabled)
                }
            }
            .alignmentGuide(VerticalAlignment.center) { d in d[.top] }
            .textSelection(.enabled)
            
            Spacer()
            
            Button(action: {
                if containsLocalhostImage {
                    if let urlRange = message.text.range(of: "http://localhost:[^)]+", options: .regularExpression),
                       let url = URL(string: String(message.text[urlRange])) {
                        NSWorkspace.shared.open(url)
                    }
                } else {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(message.text, forType: .string)
                }
            }) {
                Image(systemName: "doc.on.doc")
                    .foregroundColor(Color.secondary)
                    .font(.system(size: 15))
                    .padding(.horizontal, 10)
            }
            .buttonStyle(PlainButtonStyle())
            .alignmentGuide(VerticalAlignment.center) { d in d[.top] }
        }.textSelection(.enabled)
    }
    
    
    var containsLocalhostImage: Bool {
        return message.text.contains("![](http://localhost:8080/")
    }
    
    func format(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct ImageViewerModal: View {
    var image: NSImage
    var closeModal: () -> Void
    
    var body: some View {
        ZStack {
            Color.white.opacity(0.5).edgesIgnoringSafeArea(.all)
            
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .cornerRadius(10)
                .padding()
            
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

