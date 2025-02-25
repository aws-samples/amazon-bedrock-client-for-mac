//
//  MessageData.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/06.
//

import Foundation
import SwiftUI

struct MessageData: Identifiable, Equatable, Codable {
    var id = UUID()
    var text: String
    var thinking: String?
    let user: String
    var isError: Bool
    let sentTime: Date
    var imageBase64Strings: [String]?
}
