//
//  EditorFocusState.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 4/1/25.
//

@MainActor
class EditorFocusState {
    static let shared = EditorFocusState()
    var isSearchFieldActive = false
}
