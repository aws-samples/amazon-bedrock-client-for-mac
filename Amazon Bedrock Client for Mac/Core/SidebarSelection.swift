//
//  SidebarSelection.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/06.
//

import Foundation

enum SidebarSelection: Hashable, Identifiable {
    var id: String {
        switch self {
        case .preferences: return "Preferences"
        case .channel(let channel): return channel.id
        }
    }
    
    case preferences
    case channel(ChannelModel)
}
