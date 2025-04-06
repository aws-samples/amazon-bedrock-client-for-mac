//
//  Amazon_Bedrock_Client_for_MacApp.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/04.
//

import SwiftUI

@main
struct Amazon_Bedrock_Client_for_MacApp: App {
    @ObservedObject private var settingManager = SettingManager.shared
    
    // Use StateObject for AppDelegate to ensure it stays alive
    @StateObject private var appDelegateProvider = AppDelegateProvider()
    
    // Use NSApplicationDelegateAdaptor with the provider
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        if SettingManager.shared.enableDebugLog {
            redirectStdoutAndStderrToFile()
        }
    }
    
    var body: some Scene {
        Window("Amazon Bedrock Client", id: "MainWindow") {
            MainView()
                .frame(minWidth: 800, minHeight: 600)
                .environmentObject(settingManager)
        }
        .windowStyle(DefaultWindowStyle())
        .commands {
            customCommands
        }
    }
    
    @CommandsBuilder
    private var customCommands: some Commands {
        // Remove default 'New Window' and 'New Tab' commands
        CommandGroup(replacing: .newItem) {
            Button("New Chat") {
                // Send action to AppDelegate's newChat method
                NSApp.sendAction(#selector(AppDelegate.newChat(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("n", modifiers: [.command])
            
            Button("Delete Chat") {
                NSApp.sendAction(#selector(AppDelegate.deleteChat(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("d", modifiers: [.command])
//            .disabled(!ChatManager.shared.hasChats) // Disable if no chats
        }
        
        // Remove 'Show All Tabs' and 'Merge All Windows' menu items
        CommandGroup(replacing: .windowArrangement) { }
        
        CommandGroup(replacing: .help) {
            Button("Bedrock Help") {
                openBedrockHelp()
            }
            .keyboardShortcut("?", modifiers: [.command, .shift])
        }
        
        CommandGroup(after: .appSettings) {
            Button("Settings") {
                // Send action to AppDelegate's openSettings method
                NSApp.sendAction(#selector(AppDelegate.openSettings), to: nil, from: nil)
            }
            .keyboardShortcut(",", modifiers: [.command])
        }
        
        // Add on the menu "View"
        CommandGroup(before: .toolbar) {
            Button("View sidebar") {
                Amazon_Bedrock_Client_for_MacApp.toggleSidebar()
            }.keyboardShortcut("b", modifiers: [.command])
        }
    }
    
    private func openBedrockHelp() {
        if let url = URL(string: "https://docs.aws.amazon.com/bedrock/latest/userguide/what-is-bedrock.html") {
            NSWorkspace.shared.open(url)
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
            
            print("Logging started")
        } catch {
            print("Failed to redirect stdout and stderr to file: \(error)")
        }
    }
    
    static func toggleSidebar() {
        NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
    }
}

class AppDelegateProvider: ObservableObject {
    // This class helps ensure the AppDelegate is properly retained
}
