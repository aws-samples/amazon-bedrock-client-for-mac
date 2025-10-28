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
    private let serverPort: Int

    init(serverPort: Int = 11434, defaultDirectory: String = NSHomeDirectory()) async throws {
        self.serverPort = serverPort
        
        // Create a new Vapor application
        let env = try await Environment.detect()
        app = try await Application.make(env)
        
        // Configure the server port
        app.http.server.configuration.port = serverPort
        
        // Determine directory and create if necessary
        let directoryURL = URL(fileURLWithPath: defaultDirectory)
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
