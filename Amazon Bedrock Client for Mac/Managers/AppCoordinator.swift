//
//  AppCoordinator.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 6/29/24.
//

import Foundation

class AppCoordinator: ObservableObject {
    static let shared = AppCoordinator()
    private init() {}

    @Published var shouldCreateNewChat: Bool = false
}
