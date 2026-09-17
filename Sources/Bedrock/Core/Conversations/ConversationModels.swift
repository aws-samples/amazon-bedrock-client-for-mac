//
//  ConversationModels.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/06.
//

import Foundation

/**
 * Tool information structure supporting complex JSON input
 */
struct ToolInfo: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let input: JSONValue
    
    // Custom Codable implementation for input
    enum CodingKeys: String, CodingKey {
        case id, name, input
    }
    
    // Custom equality comparison
    static func == (lhs: ToolInfo, rhs: ToolInfo) -> Bool {
        return lhs.id == rhs.id &&
               lhs.name == rhs.name &&
               lhs.input == rhs.input
    }
}

/**
 * JSON value representation supporting nested structures
 */
enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null
    
    // Custom decoding
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            self = .null
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode JSON value"
            )
        }
    }
    
    // Custom encoding
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
    
    // Helper to create from Any
    static func from(_ value: Any) -> JSONValue {
        switch value {
        case let string as String:
            return .string(string)
        case let number as NSNumber:
            if number.isBool {
                return .bool(number.boolValue)
            } else {
                return .number(number.doubleValue)
            }
        case let dict as [String: Any]:
            var result = [String: JSONValue]()
            for (key, value) in dict {
                result[key] = JSONValue.from(value)
            }
            return .object(result)
        case let array as [Any]:
            return .array(array.map(JSONValue.from))
        default:
            return .null
        }
    }
    
    // Helper to convert to dictionary for tool execution
    var asDictionary: [String: Any]? {
        if case .object(let dict) = self {
            var result = [String: Any]()
            for (key, value) in dict {
                result[key] = value.asAny
            }
            return result
        }
        return nil
    }

    /// JSON numbers are represented as Double. Do not silently fall back to
    /// the default when a tool supplies an integer, or accept booleans as 0/1.
    func integer(_ key: String, default fallback: Int, in range: ClosedRange<Int>) throws -> Int {
        guard case .object(let values) = self else {
            throw LocalOperationError.invalid("Tool input must be a JSON object.")
        }
        guard let value = values[key] else { return fallback }
        guard case .number(let number) = value, let integer = Int(exactly: number), range.contains(integer) else {
            throw LocalOperationError.invalid("\(key) must be an integer between \(range.lowerBound) and \(range.upperBound).")
        }
        return integer
    }
    
    // Helper to convert to Any
    var asAny: Any {
        switch self {
        case .string(let value): return value
        case .number(let value): return value
        case .bool(let value): return value
        case .null: return NSNull()
        case .array(let values):
            return values.map { $0.asAny }
        case .object(let dict):
            var result = [String: Any]()
            for (key, value) in dict {
                result[key] = value.asAny
            }
            return result
        }
    }
}

// Extension to NSNumber to help distinguish between number and boolean
private extension NSNumber {
    var isBool: Bool {
        return CFBooleanGetTypeID() == CFGetTypeID(self as CFTypeRef)
    }
}

/**
 * Represents a message in the chat conversation.
 * Includes support for text content, thinking steps, tool usage, and image/document attachments.
 */
struct MessageData: Identifiable, Equatable, Codable, Sendable {
    var id = UUID()
    var text: String // Changed to var to allow modification
    var thinking: String?
    var thinkingSummary: String?  // Summary of thinking process for display
    var signature: String?
    var user: String
    var isError: Bool = false
    let sentTime: Date
    var imageBase64Strings: [String]?
    var documentBase64Strings: [String]?
    var documentFormats: [String]?
    var documentNames: [String]?
    var pastedTexts: [PastedTextInfo]?  // Pasted text attachments (sent as text block, not document)
    var toolUse: ToolInfo?  // Information about tool usage in this message
    var toolResult: String?  // Result from tool execution
    var videoUrl: URL?  // Local URL for generated video playback
    var videoS3Uri: String?  // S3 URI for video (for reference)
    var toolUses: [Message.ToolUse]?
    var modelID: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case text
        case thinking
        case thinkingSummary = "thinking_summary"
        case signature
        case user
        case isError = "is_error"
        case sentTime = "sent_time"
        case imageBase64Strings = "image_base64_strings"
        case documentBase64Strings = "document_base64_strings"
        case documentFormats = "document_formats"
        case documentNames = "document_names"
        case pastedTexts = "pasted_texts"
        case toolUse = "tool_use"
        case toolResult = "tool_result"
        case videoUrl = "video_url"
        case videoS3Uri = "video_s3_uri"
        case toolUses = "tool_uses"
        case modelID = "model_id"
    }
    
    static func == (lhs: MessageData, rhs: MessageData) -> Bool {
        return lhs.id == rhs.id &&
               lhs.text == rhs.text &&
               lhs.thinking == rhs.thinking &&
               lhs.thinkingSummary == rhs.thinkingSummary &&
               lhs.toolResult == rhs.toolResult &&
               lhs.toolUse == rhs.toolUse &&
               lhs.toolUses == rhs.toolUses &&
               lhs.signature == rhs.signature &&
               lhs.imageBase64Strings == rhs.imageBase64Strings &&
               lhs.user == rhs.user &&
               lhs.isError == rhs.isError &&
               lhs.sentTime == rhs.sentTime &&
               lhs.documentBase64Strings == rhs.documentBase64Strings &&
               lhs.documentFormats == rhs.documentFormats &&
               lhs.documentNames == rhs.documentNames &&
               lhs.pastedTexts == rhs.pastedTexts &&
               lhs.videoUrl == rhs.videoUrl &&
               lhs.videoS3Uri == rhs.videoS3Uri &&
               lhs.modelID == rhs.modelID
    }
}

/// Pasted text information for UI display
struct PastedTextInfo: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    let filename: String
    let content: String
    
    var preview: String {
        let truncated = String(content.prefix(150))
        let cleaned = truncated
            .split(separator: "\n", omittingEmptySubsequences: false)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.count > 100 ? String(cleaned.prefix(97)) + "..." : cleaned
    }
}

// MARK: - Unified Message Structure
struct Message: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var text: String
    var role: Role
    let timestamp: Date
    let isError: Bool

    // Separate fields for different content types
    var thinking: String?
    var thinkingSummary: String?  // Summary of thinking process
    var thinkingSignature: String?
    var imageBase64Strings: [String]?
    var documentBase64Strings: [String]?
    var documentFormats: [String]?
    var documentNames: [String]?
    var pastedTexts: [PastedTextInfo]?  // Pasted text attachments

    // Video generation
    var videoUrl: URL?  // Local URL for generated video
    var videoS3Uri: String?  // S3 URI for video reference

    // Tool use is a separate concern - not mixed with message text
    var toolUse: ToolUse?
    var toolUses: [ToolUse]?
    var modelID: String?

    enum Role: String, Codable, Sendable {
        case user
        case assistant
    }

    struct ToolUse: Codable, Equatable, Sendable {
        let toolId: String
        let toolName: String
        let inputs: JSONValue
        var result: String?
        var resultTimestamp: Date?
        var status: String?
        var elapsedSeconds: Double?
        var displayName: String?
        var serverName: String?
        var resultImages: [ToolResultImage]?
    }
}

// MARK: - Unified Conversation History

/// Unified conversation history structure
struct ConversationHistory: Codable, Equatable, Sendable {
    let chatId: String
    var modelId: String
    var messages: [Message]
    var lastUpdated: Date
    var systemPrompt: String?
    var formatVersion: Int? = 2

    init(chatId: String, modelId: String, messages: [Message] = [], systemPrompt: String? = nil) {
        self.chatId = chatId
        self.modelId = modelId
        self.messages = messages
        self.lastUpdated = Date()
        self.systemPrompt = systemPrompt
    }

    /// Preserve the origin of older messages before changing the next reply's
    /// model. Existing files remain readable by older app versions.
    mutating func switchModel(to modelID: String) {
        guard modelId != modelID else { return }
        for index in messages.indices where messages[index].modelID == nil {
            messages[index].modelID = modelId
        }
        modelId = modelID
        formatVersion = 2
        lastUpdated = Date()
    }

    static func fromMessages(_ source: [MessageData], chatID: String, modelID: String,
                             systemPrompt: String? = nil) -> Self {
        let messages = source.map { data in
            let legacyTool = data.toolUse.map {
                Message.ToolUse(toolId: $0.id, toolName: $0.name, inputs: $0.input, result: data.toolResult,
                                resultTimestamp: data.toolResult == nil ? nil : data.sentTime)
            }
            return Message(id: data.id, text: data.text,
                           role: data.user == "User" || data.user == "ToolResult" ? .user : .assistant,
                           timestamp: data.sentTime, isError: data.isError, thinking: data.thinking,
                           thinkingSummary: data.thinkingSummary, thinkingSignature: data.signature,
                           imageBase64Strings: data.imageBase64Strings, documentBase64Strings: data.documentBase64Strings,
                           documentFormats: data.documentFormats, documentNames: data.documentNames,
                           pastedTexts: data.pastedTexts, videoUrl: data.videoUrl, videoS3Uri: data.videoS3Uri,
                           toolUse: legacyTool, toolUses: data.toolUses, modelID: data.modelID ?? modelID)
        }
        return .init(chatId: chatID, modelId: modelID, messages: messages, systemPrompt: systemPrompt)
    }

    // Improved implementation of addMessage
    mutating func addMessage(_ message: Message) {
        messages.append(message)
        lastUpdated = Date()
    }

    // Improved implementation of updateMessage
    mutating func updateMessage(id: UUID,
                              newText: String? = nil,
                              thinking: String? = nil,
                              thinkingSignature: String? = nil,
                              toolResult: String? = nil) {
        if let index = messages.firstIndex(where: { $0.id == id }) {
            // Update specific fields only if provided
            if let newText = newText {
                messages[index].text = newText
            }

            if let thinking = thinking {
                messages[index].thinking = thinking
            }

            if let thinkingSignature = thinkingSignature {
                messages[index].thinkingSignature = thinkingSignature
            }

            if let toolResult = toolResult, messages[index].toolUse != nil {
                messages[index].toolUse?.result = toolResult
            }

            lastUpdated = Date()
        }
    }
}
