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
    @Published var userInput: String = ""
    
    func addBoldMarkdown() {
        // Add the logic to bold the selected text, similar to how it was done in FirstResponderTextView
        // For demonstration, I'll just add ** at the start and end. You would replace this with the actual implementation.
        self.userInput = "**\(self.userInput)**"
    }
}

struct MessageView: View {
    var message: MessageData
    
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    @Environment(\.fontSize) private var fontSize: CGFloat  // Inject the fontSize environment value
    
    
    private var theme: Splash.Theme {
        // NOTE: We are ignoring the Splash theme font
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
                    .resizable()  // Make the icon resizable
                    .scaledToFill()  // Fill the frame
                    .frame(width: 40, height: 40)  // Set the frame
                    .foregroundColor(Color.link)
                    .opacity(0.8)
                    .clipShape(Circle())  // Clip into a circle
                    .shadow(radius: 3)  // Optional shadow for depth
                    .overlay(  // Optional border
                        Circle()
                            .stroke(Color.blue, lineWidth: 2)
                    )
                    .alignmentGuide(VerticalAlignment.center) { d in d[.top] }
            } else {
                Image("bedrock sq")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                    .shadow(radius: 3)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .alignmentGuide(VerticalAlignment.center) { d in d[.top] }
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(message.user)
                        .font(.system(size: self.fontSize))  // Increase username text size
                        .bold()
                        .textSelection(.enabled)

                    Text(format(date: message.sentTime))
                        .font(.callout)
                        .foregroundColor(Color.secondary)
                        .textSelection(.enabled)
                }
                
                if message.user != "User" {
                    Markdown(message.text)  // Use MarkdownUI directly
                        .id(message.id)
                        .textSelection(.enabled)
                    
                        .markdownTheme(.gitHub)
                        .markdownCodeSyntaxHighlighter(SplashCodeSyntaxHighlighter.splash(theme: self.theme))
                        .font(.system(size: self.fontSize))
                } else {
                    Text(message.text)
                    .font(.system(size: self.fontSize))
                    .textSelection(.enabled)
                }
                

            }
            .alignmentGuide(VerticalAlignment.center) { d in d[.top] }
            .textSelection(.enabled)
            
            Spacer()
            
            // Copy button
            Button(action: {
                if containsLocalhostImage {
                    // Copy the image URL to the clipboard
                    // Extract the URL from the Markdown-like string
                    if let urlRange = message.text.range(of: "http://localhost:[^)]+", options: .regularExpression),
                       let url = URL(string: String(message.text[urlRange])) {
                        // Open the URL with NSWorkspace
                        NSWorkspace.shared.open(url)}
                } else {
                    // Copy the message to the clipboard
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
