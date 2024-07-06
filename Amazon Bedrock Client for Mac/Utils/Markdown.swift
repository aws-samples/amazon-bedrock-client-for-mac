//
//  Markdown.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 7/5/24.
//

//import SwiftUI
//import Splash
//
//struct Markdown: View {
//    let text: String
//    @Environment(\.font) private var font
//    @Environment(\.markdownTheme) private var theme
//    @Environment(\.markdownCodeSyntaxHighlighter) private var syntaxHighlighter
//    
//    var body: some View {
//        ScrollView {
//            VStack(alignment: .leading, spacing: 0) {
//                ForEach(parseMarkdown(text), id: \.id) { element in
//                    elementView(for: element)
//                }
//            }
//            .padding()
//        }
//        .textSelection(.enabled)
//    }
//    
//    @ViewBuilder
//    private func elementView(for element: MarkdownElement) -> some View {
//        switch element {
//        case .text(let content):
//            Text(content)
//                .font(font)
//        case .codeBlock(let code):
//            syntaxHighlighter(code)
//                .font(.system(size: font?.size ?? 14, design: .monospaced))
//                .padding()
//                .background(Color(theme.backgroundColor))
//                .cornerRadius(8)
//        case .inlineCode(let code):
//            Text(code)
//                .font(.system(size: font?.size ?? 14, design: .monospaced))
//                .padding(4)
//                .background(Color(theme.backgroundColor))
//                .cornerRadius(4)
//        }
//    }
//    
//    private func parseMarkdown(_ markdown: String) -> [MarkdownElement] {
//        var elements: [MarkdownElement] = []
//        let lines = markdown.components(separatedBy: .newlines)
//        var isInCodeBlock = false
//        var currentCodeBlock = ""
//        
//        for line in lines {
//            if line.hasPrefix("```") {
//                if isInCodeBlock {
//                    elements.append(.codeBlock(currentCodeBlock.trimmingCharacters(in: .whitespacesAndNewlines)))
//                    currentCodeBlock = ""
//                }
//                isInCodeBlock.toggle()
//            } else if isInCodeBlock {
//                currentCodeBlock += line + "\n"
//            } else {
//                let parts = line.components(separatedBy: "`")
//                for (index, part) in parts.enumerated() {
//                    if index % 2 == 0 {
//                        elements.append(.text(part))
//                    } else {
//                        elements.append(.inlineCode(part))
//                    }
//                }
//            }
//        }
//        
//        return elements
//    }
//}
//
//enum MarkdownElement: Identifiable {
//    case text(String)
//    case codeBlock(String)
//    case inlineCode(String)
//    
//    var id: String {
//        switch self {
//        case .text(let content): return "text_\(content.hashValue)"
//        case .codeBlock(let code): return "codeBlock_\(code.hashValue)"
//        case .inlineCode(let code): return "inlineCode_\(code.hashValue)"
//        }
//    }
//}
//
//extension View {
//    func markdownTheme(_ theme: Splash.Theme) -> some View {
//        self.environment(\.markdownTheme, theme)
//    }
//    
//    func markdownCodeSyntaxHighlighter(_ highlighter: @escaping (String) -> Text) -> some View {
//        self.environment(\.markdownCodeSyntaxHighlighter, highlighter)
//    }
//}
//
//struct MarkdownThemeKey: EnvironmentKey {
//    static let defaultValue: Splash.Theme = Splash.Theme {
//        colorScheme == .dark ? .wwdc17(withFont: .init(size: fontSize)) : .sunset(withFont: .init(size: fontSize))
//    }
//}
//
//struct MarkdownCodeSyntaxHighlighterKey: EnvironmentKey {
//    static let defaultValue: (String) -> Text = { Text($0) }
//}
//
//extension EnvironmentValues {
//    var markdownTheme: Splash.Theme {
//        get { self[MarkdownThemeKey.self] }
//        set { self[MarkdownThemeKey.self] = newValue }
//    }
//    
//    var markdownCodeSyntaxHighlighter: (String) -> Text {
//        get { self[MarkdownCodeSyntaxHighlighterKey.self] }
//        set { self[MarkdownCodeSyntaxHighlighterKey.self] = newValue }
//    }
//}
