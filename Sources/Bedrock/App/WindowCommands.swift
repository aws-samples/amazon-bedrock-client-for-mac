import AppKit
import SwiftUI

@MainActor
enum AppWindows {
    // Keep the scene's OpenWindowAction available after its last window closes.
    static var openMain: (() -> Void)?
    static var newThread: (() -> Void)?

    static var isMainWindowKey: Bool {
        guard let window = NSApp.keyWindow else { return false }
        return window.identifier?.rawValue == "MainWindow" && window.attachedSheet == nil
    }

    static func showMain() {
        if let openMain { openMain() }
        else { NSApp.windows.first { $0.identifier?.rawValue == "MainWindow" }?.makeKeyAndOrderFront(nil) }
        NSApp.activate(ignoringOtherApps: true)
    }

    static func focusComposer() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .focusBedrockComposer, object: nil)
        }
    }
}

extension Notification.Name {
    static let focusBedrockComposer = Notification.Name("focusBedrockComposer")
    static let findBedrockConversation = Notification.Name("findBedrockConversation")
}

struct WindowCommands {
    var canArchive: Bool
    var archive: () -> Void
    var toggleSidebar: () -> Void
    var canGoBack: Bool
    var goBack: () -> Void
    var canFind: Bool
    var find: () -> Void
}

private struct WindowCommandsKey: FocusedValueKey {
    typealias Value = WindowCommands
}

extension FocusedValues {
    var workbenchCommands: WindowCommands? {
        get { self[WindowCommandsKey.self] }
        set { self[WindowCommandsKey.self] = newValue }
    }
}

/// Observe focused command changes in the menu graph, not the App scene.
/// Observing them on App makes a chat update rebuild MainWindowView, which publishes
/// new command closures and invalidates the scene again during input/scrolling.
struct AppCommands: Commands {
    @FocusedValue(\.workbenchCommands) private var windowCommands: WindowCommands?
    @ObservedObject private var updater = UpdateService.shared

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { updater.checkForUpdates(manual: true) }
                .disabled(updater.isBusy)
        }
        CommandGroup(replacing: .newItem) {
            Button("New Thread") {
                NSApp.sendAction(#selector(AppDelegate.newChat(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Archive Thread") {
                guard AppWindows.isMainWindowKey else { return }
                windowCommands?.archive()
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(windowCommands?.canArchive != true)

            Button("Import Thread…", action: AppActions.importThread)
                .keyboardShortcut("o", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .windowArrangement) { }

        CommandGroup(replacing: .help) {
            Button("Bedrock Help") {
                if let url = URL(string: "https://docs.aws.amazon.com/bedrock/latest/userguide/what-is-bedrock.html") {
                    NSWorkspace.shared.open(url)
                }
            }
            .keyboardShortcut("?", modifiers: [.command, .shift])
        }

        CommandGroup(after: .appSettings) {
            Button("Settings") {
                NSApp.sendAction(#selector(AppDelegate.openSettings), to: nil, from: nil)
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()
            Button("Show Quick Access") { QuickAccessWindowController.shared.showWindow() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
        }

        CommandGroup(before: .toolbar) {
            Button("Command Palette") {
                AppWindows.showMain()
                AppStore.shared.showCommandPalette = true
            }
            .keyboardShortcut("k", modifiers: .command)

            Button("Toggle Sidebar") {
                guard AppWindows.isMainWindowKey else { return }
                windowCommands?.toggleSidebar()
            }
            .keyboardShortcut("b", modifiers: .command)
            .disabled(windowCommands == nil)

            Button("Back") { windowCommands?.goBack() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(windowCommands?.canGoBack != true)

            Button("Find in Conversation") { windowCommands?.find() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(windowCommands?.canFind != true)
        }
    }
}
