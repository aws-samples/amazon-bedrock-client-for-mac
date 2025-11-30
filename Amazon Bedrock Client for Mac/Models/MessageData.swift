//
//  MessageData.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/06.
//

import Foundation
import SwiftUI

/**
 * Tool information structure supporting complex JSON input
 */
struct ToolInfo: Codable, Equatable {
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
enum JSONValue: Codable, Equatable {
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
struct MessageData: Identifiable, Equatable, Codable {
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
    }
    
    static func == (lhs: MessageData, rhs: MessageData) -> Bool {
        return lhs.id == rhs.id &&
               lhs.text == rhs.text &&
               lhs.thinking == rhs.thinking &&
               lhs.thinkingSummary == rhs.thinkingSummary &&
               lhs.toolResult == rhs.toolResult &&
               lhs.user == rhs.user &&
               lhs.isError == rhs.isError &&
               lhs.sentTime == rhs.sentTime &&
               lhs.documentBase64Strings == rhs.documentBase64Strings &&
               lhs.documentFormats == rhs.documentFormats &&
               lhs.documentNames == rhs.documentNames &&
               lhs.pastedTexts == rhs.pastedTexts
    }
}

/// Pasted text information for UI display
struct PastedTextInfo: Codable, Equatable, Identifiable {
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
