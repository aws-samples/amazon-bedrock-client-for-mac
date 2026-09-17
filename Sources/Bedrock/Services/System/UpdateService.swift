import AppKit
import Combine
import Foundation
import Logging

@MainActor
final class UpdateService: NSObject, ObservableObject {
    static let shared = UpdateService()

    @Published private(set) var isBusy = false
    @Published private(set) var status: String?
    private let logger = Logger(label: "UpdateService")
    private var operation: Task<Void, Never>?
    private var progressWindow: NSWindow?
    private var progressLabel: NSTextField?
    private var installer: Process?

    func checkForUpdates(manual: Bool = false) {
        guard !isBusy, !ValidationMode.isOffline,
              manual || PreferencesStore.shared.checkForUpdates else { return }
        isBusy = true
        status = "Checking for updates…"
        operation = Task { await check(manual: manual) }
    }

    private func check(manual: Bool) async {
        var workspace: URL?
        var prepared: UpdateInstallationPlan?
        var handedOff = false
        var preserveDownload = false
        defer {
            progressWindow?.close()
            progressWindow = nil
            progressLabel = nil
            isBusy = handedOff
            operation = nil
            if !handedOff {
                if let prepared { try? FileManager.default.removeItem(at: prepared.stagingDirectory) }
                if let workspace, !preserveDownload { try? FileManager.default.removeItem(at: workspace) }
            }
        }
        do {
            var request = URLRequest(url: SoftwareUpdateRelease.latestURL, timeoutInterval: 30)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                throw SoftwareUpdateError.invalidRelease
            }
            let release = try JSONDecoder().decode(SoftwareUpdateRelease.self, from: data)
            let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
            guard let asset = try release.update(after: current) else {
                status = "You’re up to date · \(current)"
                if manual { await inform("You’re up to date", "Bedrock \(current) is the latest available version.") }
                return
            }
            try Task.checkCancellation()
            status = "Version \(release.version) is available"
            let alert = NSAlert()
            alert.messageText = "Bedrock \(release.version) is available"
            alert.informativeText = "Download and install the update? Your conversations and settings will stay on this Mac."
            alert.addButton(withTitle: "Update Now")
            alert.addButton(withTitle: "Later")
            alert.addButton(withTitle: "Disable Automatic Checks")
            let choice = await present(alert)
            if choice == .alertThirdButtonReturn { PreferencesStore.shared.checkForUpdates = false }
            guard choice == .alertFirstButtonReturn else { return }
            try Task.checkCancellation()

            let folder = try UpdateInstaller.workspace()
            workspace = folder
            showProgress("Downloading the update…")
            let dmg = try await UpdateInstaller.download(asset, into: folder)
            status = "Verifying the update…"
            progressLabel?.stringValue = "Verifying and preparing the update…"
            do {
                prepared = try await UpdateInstaller.prepare(dmg: dmg, version: release.version,
                                                             currentApp: Bundle.main.bundleURL)
            } catch {
                if error is CancellationError { throw error }
                guard let reason = error as? SoftwareUpdateError,
                      case .manualInstallationRequired = reason else { throw error }
                progressWindow?.close()
                preserveDownload = true
                let alert = NSAlert()
                alert.messageText = "The update is downloaded"
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: "Open Downloaded DMG")
                alert.addButton(withTitle: "Later")
                if await present(alert) == .alertFirstButtonReturn { NSWorkspace.shared.open(dmg) }
                status = "Update downloaded · install from the DMG"
                return
            }
            guard let prepared else { return }
            progressWindow?.close()
            let confirmation = NSAlert()
            confirmation.messageText = "Restart to update Bedrock"
            confirmation.informativeText = "The update has been verified. Bedrock will save your work, install the new version, and reopen."
            confirmation.addButton(withTitle: "Install and Restart")
            confirmation.addButton(withTitle: "Later")
            guard await present(confirmation) == .alertFirstButtonReturn else { return }
            try Task.checkCancellation()
            installer = try await UpdateInstaller.handOff(prepared)
            installer?.terminationHandler = { [weak self] process in
                let succeeded = process.terminationStatus == 0
                Task { @MainActor in
                    // This is reached only if the app stayed open (for example,
                    // its data could not be saved and graceful quit was refused).
                    self?.installer = nil
                    self?.isBusy = false
                    self?.status = succeeded ? "Update installed" : "Update not installed · your previous app was kept"
                }
            }
            handedOff = true
            status = "Restarting to install…"
            NSApp.terminate(nil)
        } catch is CancellationError {
            status = "Update canceled"
        } catch {
            if Task.isCancelled { status = "Update canceled"; return }
            logger.error("Update failed: \(error.localizedDescription)")
            status = "Could not complete the update"
            if manual || workspace != nil { await inform("Unable to update Bedrock", error.localizedDescription) }
        }
    }

    func cleanup() {
        operation?.cancel()
        progressWindow?.close()
        progressWindow = nil
        // The installation helper deliberately outlives this app. It waits for
        // applicationShouldTerminate to finish saving before replacing anything.
    }

    @objc private func cancelUpdate(_ sender: Any?) { operation?.cancel() }

    private func showProgress(_ message: String) {
        status = message
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 140),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Updating Bedrock"
        window.isReleasedWhenClosed = false
        let progress = NSProgressIndicator(frame: NSRect(x: 24, y: 74, width: 332, height: 16))
        progress.style = .bar
        progress.isIndeterminate = true
        progress.startAnimation(nil)
        let label = NSTextField(labelWithString: message)
        label.frame = NSRect(x: 24, y: 98, width: 332, height: 20)
        label.font = .systemFont(ofSize: 13)
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelUpdate))
        cancel.bezelStyle = .rounded
        cancel.frame = NSRect(x: 270, y: 20, width: 88, height: 30)
        window.contentView?.addSubview(label)
        window.contentView?.addSubview(progress)
        window.contentView?.addSubview(cancel)
        progressLabel = label
        progressWindow = window
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func inform(_ title: String, _ message: String) async {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        _ = await present(alert)
    }

    private func present(_ alert: NSAlert) async -> NSApplication.ModalResponse {
        if let window = NSApp.keyWindow ?? NSApp.mainWindow, window.isVisible, window.attachedSheet == nil {
            return await withCheckedContinuation { continuation in
                alert.beginSheetModal(for: window) { continuation.resume(returning: $0) }
            }
        }
        return alert.runModal()
    }
}
