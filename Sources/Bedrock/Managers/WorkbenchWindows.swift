import AppKit
import SwiftUI

@MainActor
enum WorkbenchWindows {
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

struct WorkbenchWindowCommands {
    var canTrash: Bool
    var trash: () -> Void
    var toggleSidebar: () -> Void
    var canGoBack: Bool
    var goBack: () -> Void
    var canFind: Bool
    var find: () -> Void
}

private struct WorkbenchWindowCommandsKey: FocusedValueKey {
    typealias Value = WorkbenchWindowCommands
}

extension FocusedValues {
    var workbenchCommands: WorkbenchWindowCommands? {
        get { self[WorkbenchWindowCommandsKey.self] }
        set { self[WorkbenchWindowCommandsKey.self] = newValue }
    }
}

/// Observe focused command changes in the menu graph, not the App scene.
/// Observing them on App makes a chat update rebuild MainView, which publishes
/// new command closures and invalidates the scene again during input/scrolling.
struct WorkbenchAppCommands: Commands {
    @FocusedValue(\.workbenchCommands) private var windowCommands: WorkbenchWindowCommands?

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Thread") {
                NSApp.sendAction(#selector(AppDelegate.newChat(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Move Thread to Trash") {
                guard WorkbenchWindows.isMainWindowKey else { return }
                windowCommands?.trash()
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(windowCommands?.canTrash != true)

            Button("Import Thread…", action: WorkbenchActions.importThread)
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
            Button("Show Quick Access") { QuickAccessWindowManager.shared.showWindow() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
        }

        CommandGroup(before: .toolbar) {
            Button("Command Palette") {
                WorkbenchWindows.showMain()
                WorkbenchStore.shared.showCommandPalette = true
            }
            .keyboardShortcut("k", modifiers: .command)

            Button("Toggle Sidebar") {
                guard WorkbenchWindows.isMainWindowKey else { return }
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
