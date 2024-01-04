//
//  MessageData.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/06.
//

import Foundation
import SwiftUI

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

struct MessageData: Identifiable, Equatable, Codable {
    let id: UUID
    var text: String
    let user: String
    var isError: Bool
    let sentTime: Date
    
    static func == (lhs: MessageData, rhs: MessageData) -> Bool {
        return lhs.id == rhs.id && lhs.text == rhs.text && lhs.user == rhs.user && lhs.isError == rhs.isError
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, text, user, isError, sentTime
    }
}
