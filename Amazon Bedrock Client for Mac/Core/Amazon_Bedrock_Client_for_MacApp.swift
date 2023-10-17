//
//  Amazon_Bedrock_Client_for_MacApp.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/04.
//

import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    var localhostServer: LocalhostServer?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        for window in NSApplication.shared.windows {
            window.delegate = self
            let windowID = window.windowNumber
            restoreWindowSize(window: window, id: windowID)
        }
        
        DispatchQueue.global(qos: .background).async {
            do {
                self.localhostServer = try LocalhostServer()
                try self.localhostServer?.start()
            } catch {
                print("Could not start localhost server: \(error)")
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            let windowID = window.windowNumber
            saveWindowSize(window: window, id: windowID)
        }
    }
    
    func restoreWindowSize(window: NSWindow, id: Int) {
        if let size = UserDefaults.standard.size(forKey: "windowSize_\(id)") {
            window.setContentSize(size)
        }
    }
    
    func saveWindowSize(window: NSWindow, id: Int) {
        let size = window.frame.size
        UserDefaults.standard.set(size, forKey: "windowSize_\(id)")
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in NSApplication.shared.windows {
                window.makeKeyAndOrderFront(self)
            }
        }
        return true
    }
}

extension UserDefaults {
    func size(forKey key: String) -> NSSize? {
        if let data = data(forKey: key) {
            return NSKeyedUnarchiver.unarchiveObject(with: data) as? NSSize
        }
        return nil
    }
    
    func set(_ size: NSSize, forKey key: String) {
        let data = NSKeyedArchiver.archivedData(withRootObject: size)
        set(data, forKey: key)
    }
}


@main
struct Amazon_Bedrock_Client_for_MacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    @State private var alertIsPresented: Bool = false
    
    var body: some Scene {
        WindowGroup {
            ContentView().frame(idealWidth: 1200, idealHeight: 800)
                .onAppear {
                    if let window = NSApplication.shared.keyWindow {
                        window.delegate = appDelegate
                        let windowID = window.windowNumber
                        appDelegate.restoreWindowSize(window: window, id: windowID)
                    }
                }
        }
        .windowStyle(DefaultWindowStyle())
        .commands {
            SidebarCommands()
            CommandGroup(replacing: .help) {
                Button("Version") {
                    alertIsPresented = true  // Set the alert to be presented
                }
                .alert(isPresented: $alertIsPresented) {  // Attach the alert here
                    Alert(title: Text("Alert Title"), message: Text("Alert Message"), dismissButton: .default(Text("OK")))
                }
            }
            
        }
    }
}

