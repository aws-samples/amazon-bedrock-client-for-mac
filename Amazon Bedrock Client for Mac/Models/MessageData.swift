//
//  MessageData.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/06.
//

import Foundation
import SwiftUI

/**
 * Tool information structure
 */
struct ToolInfo: Codable, Equatable {
    let id: String
    let name: String
    let input: [String: String]
}

/**
 * Represents a message in the chat conversation.
 * Includes support for text content, thinking steps, tool usage, and image attachments.
 */
struct MessageData: Identifiable, Equatable, Codable {
    var id = UUID()
    var text: String // Changed to var to allow modification
    var thinking: String?
    let user: String
    var isError: Bool
    let sentTime: Date
    var imageBase64Strings: [String]?
    var toolUse: ToolInfo?  // Information about tool usage in this message
    var toolResult: String?  // Result from tool execution
    
    enum CodingKeys: String, CodingKey {
        case id
        case text
        case thinking
        case user
        case isError = "is_error"
        case sentTime = "sent_time"
        case imageBase64Strings = "image_base64_strings"
        case toolUse = "tool_use"
        case toolResult = "tool_result"
    }
    
    static func == (lhs: MessageData, rhs: MessageData) -> Bool {
        return lhs.id == rhs.id &&
               lhs.text == rhs.text &&
               lhs.thinking == rhs.thinking &&
               lhs.toolResult == rhs.toolResult &&
               lhs.user == rhs.user &&
               lhs.isError == rhs.isError &&
               lhs.sentTime == rhs.sentTime
    }
}
