//
//  LocalHostServer.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/09.
//

import Vapor
import Foundation

class LocalhostServer {
    let app: Application
    private var settingManager = SettingManager.shared

    init() throws {
        // Create a new Vapor application
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)
        app = Application(env)
        
        // Determine directory and create if necessary
        let directoryURL = URL(fileURLWithPath: settingManager.defaultDirectory)
        let directoryPath = directoryURL.path
        
        if !FileManager.default.fileExists(atPath: directoryPath) {
            do {
                try FileManager.default.createDirectory(atPath: directoryPath, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("An error occurred while creating directory: \(error)")
            }
        }
        
        // Middleware for serving files
        let fileMiddleware = FileMiddleware(publicDirectory: String(directoryPath))
        app.middleware.use(fileMiddleware)
    }

    // Start running the server
    func start() throws {
        try app.run()
    }
}
