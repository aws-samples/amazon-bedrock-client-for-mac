//
//  CodeBlock.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Latman, Michael on 4/9/24.
//

import SwiftUI
import MarkdownUI
import Splash

struct CodeBlockView: View {
    var theme: Splash.Theme
    var configuration: CodeBlockConfiguration
    @State var clipboardScale: CGFloat = 1.0
    @State var clipboardImageName: String = "clipboard"
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(configuration.language ?? "plain text")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundColor(Color(theme.plainTextColor))
                Spacer()
                
                Button(action: {
                    copyToClipboard(configuration.content)
                    clipboardScale = 1.2
                    clipboardImageName = "clipboard.fill"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        clipboardScale = 1.0
                        clipboardImageName = "clipboard"
                    }
                }) {
                    HStack {
                        Image(systemName: "doc.on.doc")
                            .foregroundColor(Color(theme.plainTextColor))
                        Text("Copy")
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.semibold)
                            .foregroundColor(Color(theme.plainTextColor))
                    }
                }
                .scaleEffect(clipboardScale)
                .animation(.spring(), value: clipboardScale)
                .buttonStyle(PlainButtonStyle()) // 여기서 PlainButtonStyle()로 수정합니다.
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.secondaryBackground)
            
            
            Divider()
            ScrollView(.horizontal) {
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .relativeLineSpacing(.em(0.225))
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(.em(0.85))
                    }
                    .padding(16)
            }
            .background(Color.background)
            .markdownMargin(top: 0, bottom: 16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.divider, lineWidth: 1)
        )
        .markdownMargin(top: .zero, bottom: .em(0.8))
    }
}

private func copyToClipboard(_ string: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(string, forType: .string)
}
