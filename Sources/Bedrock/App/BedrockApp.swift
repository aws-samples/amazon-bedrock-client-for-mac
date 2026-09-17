//
//  BedrockApp.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/04.
//

import SwiftUI
import Logging

/// Custom LogHandler for standardized logging across the application
struct AppLogHandler: LogHandler {
    var logLevel: Logger.Level = .debug
    var metadata: Logger.Metadata = [:]
    let label: String
    
    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(event: LogEvent) {
        log(level: event.level, message: event.message, metadata: event.metadata,
            source: event.source, file: event.file, function: event.function, line: event.line)
    }
    
    // Updated to use the non-deprecated method signature with source parameter
    func log(level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?, source: String, file: String, function: String, line: UInt) {
        // Generate timestamp in ISO8601 format
        let timestamp = ISO8601DateFormatter().string(from: Date())
        
        // Extract current filename
        let fileName = (file as NSString).lastPathComponent
        
        // Merge additional metadata
        var mergedMetadata = self.metadata
        if let metadata = metadata {
            for (key, value) in metadata {
                mergedMetadata[key] = value
            }
        }
        
        // Format final metadata string
        let metadataString = mergedMetadata.isEmpty ? "" : " \(mergedMetadata)"
        
        // Standardized log message format with source included
        let logMessage = "[\(timestamp)] [\(level)] [\(fileName):\(line)] \(message)\(metadataString)"
        print(logMessage)
    }
    
    // For backward compatibility (can be removed later)
    @available(*, deprecated, message: "Use the updated log method instead")
    func log(level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?, file: String, function: String, line: UInt) {
        log(level: level, message: message, metadata: metadata, source: "", file: file, function: function, line: line)
    }
}


@main
struct BedrockApp: App {
    @StateObject private var settingManager = PreferencesStore.shared
    
    // Use StateObject for AppDelegate to ensure it stays alive
    @StateObject private var appDelegateProvider = AppDelegateProvider()
    @ObservedObject private var workbench = AppStore.shared
    
    // Use NSApplicationDelegateAdaptor with the provider
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // Logger for app initialization
    private let logger = Logger(label: "AppInitialization")

    init() {
        let debugLogging = UserDefaults.standard.bool(forKey: "enableDebugLog")
        LoggingSystem.bootstrap { label in
            var handler = AppLogHandler(label: label)
            handler.logLevel = debugLogging ? .debug : .info
            return handler
        }
    }
    
    // Lazily configure debug logging when needed
    private func setupDebugLogging() {
        if PreferencesStore.shared.enableDebugLog {
            redirectStdoutAndStderrToFile()
        }
    }

    private var initialWindowSize: CGSize {
        let available = NSScreen.screens.first?.visibleFrame.size ?? CGSize(width: 1120, height: 800)
        // defaultSize describes content. Leave room for the native titlebar on
        // small displays; a 1,120-point window otherwise opens offscreen at 1,024.
        return CGSize(width: min(1120, available.width),
                      height: min(760, max(580, available.height - 40)))
    }

    var body: some Scene {
        Window("Amazon Bedrock Client", id: "MainWindow") {
            MainWindowView()
                .frame(minWidth: 820, minHeight: 580)
                .environmentObject(settingManager)
                .onAppear {
                    // Setup debug logging when the UI appears, ensuring PreferencesStore is initialized first
                    setupDebugLogging()
                }
        }
        .windowStyle(DefaultWindowStyle())
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: initialWindowSize.width, height: initialWindowSize.height)
        .commands {
            AppCommands()
        }
        MenuBarExtra("Bedrock", systemImage: "sparkle", isInserted: Binding(
            get: { workbench.preferences.showMenuBarItem }, set: { workbench.preferences.showMenuBarItem = $0 }
        )) {
            Button("Open Bedrock", action: AppWindows.showMain)
            Button("Quick Access") { QuickAccessWindowController.shared.showWindow() }
            Button("New thread") { NSApp.sendAction(#selector(AppDelegate.newChat(_:)), to: nil, from: nil) }
            Divider()
            Button("Settings…") { workbench.showSettings() }
            Button("Quit Bedrock") { NSApp.terminate(nil) }
        }
    }
    
    private func redirectStdoutAndStderrToFile() {
        let fileManager = FileManager.default
        let logsDir = URL(fileURLWithPath: settingManager.defaultDirectory).appendingPathComponent("logs")

        do {
            // Create the logs directory if it doesn't exist
            try fileManager.createDirectory(at: logsDir, withIntermediateDirectories: true, attributes: nil)
            
            // Generate a log file name based on the current date
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateStr = dateFormatter.string(from: Date())
            let logFileURL = logsDir.appendingPathComponent("log-\(dateStr).log")
            
            // Create the log file if it does not already exist
            if !fileManager.fileExists(atPath: logFileURL.path) {
                fileManager.createFile(atPath: logFileURL.path, contents: nil, attributes: nil)
            }
            
            // Obtain a file handle for writing to the log file
            let fileHandle = try FileHandle(forWritingTo: logFileURL)
            // Move to the end of the file to append new logs
            fileHandle.seekToEndOfFile()
            
            // Redirect stdout and stderr to the log file
            let fileDescriptor = fileHandle.fileDescriptor
            dup2(fileDescriptor, STDOUT_FILENO)
            dup2(fileDescriptor, STDERR_FILENO)
            
            logger.info("Logging redirected to file: \(logFileURL.path)")
        } catch {
            logger.error("Failed to redirect stdout and stderr to file: \(error)")
        }
    }
    
    static func toggleSidebar() {
        NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
    }
}

class AppDelegateProvider: ObservableObject {
    // This class helps ensure the AppDelegate is properly retained
}
