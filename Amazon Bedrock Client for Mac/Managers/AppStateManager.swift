//
//  AppStateManager.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 4/1/25.
//

@MainActor
class AppStateManager {
    static let shared = AppStateManager()
    var isSearchFieldActive = false
}
