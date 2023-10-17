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

struct MessageData: Identifiable & Equatable {
    let id: UUID
    var text: String
    let user: String
    var isError: Bool  // 에러 상태를 나타내는 필드 추가
    let sentTime: Date
    
    static func == (lhs: MessageData, rhs: MessageData) -> Bool {
        return lhs.id == rhs.id && lhs.text == rhs.text && lhs.user == rhs.user && lhs.isError == rhs.isError
    }
}
