//
//  Amazon_Bedrock_Client_for_MacApp.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/04.
//

import SwiftUI

@main
struct Amazon_Bedrock_Client_for_MacApp: App {
    @StateObject private var settingManager = SettingManager.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var alertIsPresented = false

    init() {
        if SettingManager.shared.enableDebugLog {
            redirectStdoutAndStderrToFile()
        }
    }
    
    var body: some Scene {
        WindowGroup {
            MainView()
                .frame(idealWidth: 1200, idealHeight: 800)
                .onAppear(perform: setupWindow)
                .environmentObject(settingManager)
        }
        .windowStyle(DefaultWindowStyle())
        .commands {
            SidebarCommands()
            customCommands
        }
    }
    
    @CommandsBuilder
    private var customCommands: some Commands {
        CommandGroup(replacing: .help) {
            Button("Version") {
                alertIsPresented = true
            }
            .alert(isPresented: $alertIsPresented) {
                Alert(title: Text("Alert Title"), message: Text("Alert Message"), dismissButton: .default(Text("OK")))
            }
        }
        
        CommandGroup(replacing: .newItem) {
            Button("New Chat", action: appDelegate.newChat)
                .keyboardShortcut("n", modifiers: [.command])
        }
        
        CommandGroup(after: .appSettings) {
            Button("Settings", action: appDelegate.openSettings)
                .keyboardShortcut(",", modifiers: [.command])
        }
    }
    
    private func setupWindow() {
        guard let window = NSApplication.shared.keyWindow else { return }
        window.delegate = appDelegate
        appDelegate.restoreWindowSize(window: window, id: window.windowNumber)
    }
    
    private func redirectStdoutAndStderrToFile() {
        let fileManager = FileManager.default
        let logsDir = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Amazon Bedrock Client/logs")
        
        do {
            try fileManager.createDirectory(at: logsDir, withIntermediateDirectories: true, attributes: nil)
            
            // 날짜별 파일 이름 생성
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateStr = dateFormatter.string(from: Date())
            let logFileURL = logsDir.appendingPathComponent("log-\(dateStr).log")
            
            // 파일이 존재하면 열고, 없으면 생성
            if !fileManager.fileExists(atPath: logFileURL.path) {
                fileManager.createFile(atPath: logFileURL.path, contents: nil, attributes: nil)
            }
            
            // 파일 핸들을 얻음
            let fileHandle = try FileHandle(forWritingTo: logFileURL)
            // 파일의 끝으로 이동하여 추가 모드로 설정
            fileHandle.seekToEndOfFile()
            
            // stdout과 stderr을 파일로 리디렉션
            let fileDescriptor = fileHandle.fileDescriptor
            dup2(fileDescriptor, STDOUT_FILENO)
            dup2(fileDescriptor, STDERR_FILENO)
            
            print("Logging started")
        } catch {
            print("Failed to redirect stdout and stderr to file: \(error)")
        }
    }
}
