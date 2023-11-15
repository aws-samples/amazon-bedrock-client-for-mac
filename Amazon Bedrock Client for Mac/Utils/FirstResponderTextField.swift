//
//  FirstResponderTextView.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/06.
//

import SwiftUI
import AppKit
import Combine

struct FirstResponderTextView: NSViewRepresentable, Equatable {
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
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        
        if let textView = scrollView.documentView as? NSTextView {
            textView.delegate = context.coordinator
            textView.font = NSFont.systemFont(ofSize: 15)
            textView.isRichText = false
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.allowsUndo = true
            textView.becomeFirstResponder()
            
            textView.textContainerInset = CGSize(width: 5, height: 10)  // Adjust text container insets

            let isDarkMode = textView.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            textView.textColor = isDarkMode ? NSColor.textDark : NSColor.textLight
            textView.backgroundColor = isDarkMode ? NSColor.backgroundDark : NSColor.backgroundLight
            
            updateHeight(textView: textView)
        }
        return scrollView
    }

    
    func updateNSView(_ nsView: NSScrollView, context: NSViewRepresentableContext<FirstResponderTextView>) {
        if let textView = nsView.documentView as? NSTextView {
            if textView.string != self.text {
                let selectedRange = textView.selectedRange
                textView.string = self.text
                textView.setSelectedRange(selectedRange)
                updateHeight(textView: textView)
            }
        }
    }
    
    private func updateHeight(textView: NSTextView) {
        if let layoutManager = textView.layoutManager,
           let textContainer = textView.textContainer {
            let usedRect = layoutManager.usedRect(for: textContainer)
            self.calculatedHeight = max(70, 32 + usedRect.height + textView.textContainerInset.height * 2)
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
                    self.parent.updateHeight(textView: textView)
                }
            }
        }
        
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if let event = NSApp.currentEvent, event.modifierFlags.contains(.shift) {
                if commandSelector == #selector(NSResponder.insertLineBreak(_:)) {
                    // When Shift+Enter is pressed, insert a new line
                    return false // Allow the default behavior to insert the new line
                }
            } else if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                // When Enter alone is pressed, commit the text
                parent.onCommit()
                return true
            }
            return false
        }
    }
}

extension NSAttributedString {
    func height(withConstrainedWidth width: CGFloat) -> CGFloat {
        let constraintRect = CGSize(width: width, height: .greatestFiniteMagnitude)
        let boundingBox = boundingRect(with: constraintRect, options: .usesLineFragmentOrigin, context: nil)
        
        return ceil(boundingBox.height)
    }
    
    func width(withConstrainedHeight height: CGFloat) -> CGFloat {
        let constraintRect = CGSize(width: .greatestFiniteMagnitude, height: height)
        let boundingBox = boundingRect(with: constraintRect, options: .usesLineFragmentOrigin, context: nil)
        
        return ceil(boundingBox.width)
    }
}
