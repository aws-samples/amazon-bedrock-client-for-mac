//
//  MessageData.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/06.
//

import Foundation
import SwiftUI

struct MessageData: Identifiable, Equatable, Codable {
    let id: UUID
    var text: String
    let user: String
    var isError: Bool
    let sentTime: Date
    var imageBase64Strings: [String]? // Stores Base64 string representations of images

    static func == (lhs: MessageData, rhs: MessageData) -> Bool {
        return lhs.id == rhs.id && lhs.text == rhs.text && lhs.user == rhs.user && lhs.isError == rhs.isError && lhs.imageBase64Strings == rhs.imageBase64Strings
    }
    
    // CodingKeys only need to include the properties you want to encode/decode
    private enum CodingKeys: String, CodingKey {
        case id, text, user, isError, sentTime, imageBase64Strings
    }
}
