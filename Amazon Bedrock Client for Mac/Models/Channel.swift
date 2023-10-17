//
//  Channel.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/06.
//

import Foundation
import SwiftUI
import AWSBedrock

class ChannelViewModel: ObservableObject {
    @Published var highlightMsg: UUID?
}


struct ChannelModel: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let provider: String
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
    }
    
    static func fromSummary(_ summary: BedrockClientTypes.FoundationModelSummary) -> ChannelModel {
        return ChannelModel(id: summary.modelId ?? "", name: summary.modelName ?? "", description: "\(summary.providerName ?? "") \(summary.modelName ?? "") (\(summary.modelId ?? ""))", provider: summary.providerName ?? "")
    }
}
