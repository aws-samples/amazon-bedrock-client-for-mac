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
    var imageBase64Strings: [String]?
    
    init(id: UUID = UUID(), text: String, user: String, isError: Bool = false, sentTime: Date = Date(), imageBase64Strings: [String]? = nil) {
        self.id = id
        self.text = text
        self.user = user
        self.isError = isError
        self.sentTime = sentTime
        self.imageBase64Strings = imageBase64Strings
    }
    
    static func == (lhs: MessageData, rhs: MessageData) -> Bool {
        lhs.id == rhs.id &&
        lhs.text == rhs.text &&
        lhs.user == rhs.user &&
        lhs.isError == rhs.isError &&
        lhs.sentTime == rhs.sentTime &&
        lhs.imageBase64Strings == rhs.imageBase64Strings
    }
    
    enum CodingKeys: String, CodingKey {
        case id, text, user, isError, sentTime, imageBase64Strings
    }
}
