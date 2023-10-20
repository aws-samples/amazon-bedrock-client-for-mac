//
//  FirstResponderTextView.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/06.
//

import SwiftUI
import AppKit
import Combine

struct FirstResponderTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var isDisabled: Bool
    @Binding var calculatedHeight: CGFloat

    var onCommit: () -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    static func == (lhs: FirstResponderTextView, rhs: FirstResponderTextView) -> Bool {
        return lhs.text == rhs.text && lhs.isDisabled == rhs.isDisabled
    }
    
    func makeNSView(context: NSViewRepresentableContext<FirstResponderTextView>) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.backgroundColor = NSColor.white  // Set scrollbar background to white

        if let textView = scrollView.documentView as? NSTextView {
            textView.delegate = context.coordinator
            textView.font = NSFont.systemFont(ofSize: 15)
            textView.isRichText = false
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.allowsUndo = true
            textView.becomeFirstResponder()
            
            let isDarkMode = textView.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            textView.textColor = isDarkMode ? NSColor.textDark : NSColor.textLight
            textView.backgroundColor = isDarkMode ? NSColor.backgroundDark : NSColor.backgroundLight
            
            if let layoutManager = textView.layoutManager,
               let textContainer = textView.textContainer {
                let usedRect = layoutManager.usedRect(for: textContainer)
                self.calculatedHeight = max(60, 32 + usedRect.height + textView.textContainerInset.height * 2)
            }
        }
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: NSViewRepresentableContext<FirstResponderTextView>) {
        if let textView = nsView.documentView as? NSTextView, textView.string != self.text {
            let selectedRange = textView.selectedRange
            textView.string = self.text
            textView.setSelectedRange(selectedRange)
        }
    }
    
    public class Coordinator: NSObject, NSTextViewDelegate {
        var parent: FirstResponderTextView

        init(_ parent: FirstResponderTextView) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            if let textView = notification.object as? NSTextView {
                DispatchQueue.main.async {
                    self.parent.text = textView.string
                    
                    if let layoutManager = textView.layoutManager,
                       let textContainer = textView.textContainer {
                        let usedRect = layoutManager.usedRect(for: textContainer)
                        self.parent.calculatedHeight = max(60, 32 + usedRect.height + textView.textContainerInset.height * 2)
                    }
                }
            }
        }
        
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onCommit()
                return true
            }
            return false
        }
    }
}
