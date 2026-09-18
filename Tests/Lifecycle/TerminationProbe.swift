import AppKit
import Foundation

/// Runs without XCTest injection: AppKit's real termination loop is the regression.
@MainActor
private final class ProbeDelegate: NSObject, NSApplicationDelegate {
    let root: URL
    let scenario: String
    private var saves = 0
    private var installer: Process?
    private var termination: ApplicationTerminationCoordinator!

    private func configureTermination() {
        termination = ApplicationTerminationCoordinator(
        prepare: { [unowned self] in
            saves += 1
            record("saving \(saves)")
            try? await Task.sleep(for: .milliseconds(80))
            if scenario == "retry", saves == 1 { return false }
            do {
                try "Unsent draft preserved.\n".write(
                    to: root.appendingPathComponent("draft.txt"), atomically: true, encoding: .utf8)
                record("saved \(saves)")
                return true
            } catch {
                record("save-error \(error.localizedDescription)")
                return false
            }
        },
        cancelled: { [unowned self] in
            record("cancelled")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.record("retry-requested")
                NSApp.terminate(nil)
            }
        })
    }

    init(root: URL, scenario: String) {
        self.root = root
        self.scenario = scenario
    }

    func record(_ event: String) {
        let file = root.appendingPathComponent("events.log")
        if !FileManager.default.fileExists(atPath: file.path) {
            FileManager.default.createFile(atPath: file.path, contents: Data())
        }
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data((event + "\n").utf8))
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureTermination()
        record("launched \(scenario)")
        if scenario == "installed" {
            do {
                let draft = try String(contentsOf: root.appendingPathComponent("draft.txt"), encoding: .utf8)
                guard draft == "Unsent draft preserved.\n" else { fatalError("Draft was not saved before replacement") }
                try "2.0.2\n".write(to: root.appendingPathComponent("reopened"),
                                   atomically: true, encoding: .utf8)
            } catch { fatalError("Relaunch validation failed: \(error)") }
            NSApp.terminate(nil)
            return
        }
        Task {
            if scenario == "install" {
                do {
                    let destination = Bundle.main.bundleURL
                    var plan = UpdateInstallationPlan(
                        destination: destination,
                        stagingDirectory: destination.deletingLastPathComponent().appendingPathComponent(".staging"),
                        workspace: root, parentPID: ProcessInfo.processInfo.processIdentifier)
                    plan.quitTimeoutSeconds = 10
                    try plan.writeHelper()
                    installer = try await UpdateInstaller.handOff(plan)
                    record("installer-ready")
                } catch { fatalError("Could not start installation: \(error)") }
            }
            record("quit-requested")
            NSApp.terminate(nil)
            if scenario == "duplicate" { NSApp.terminate(nil) }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if scenario == "installed" { return .terminateNow }
        return termination.shouldTerminate()
    }

    func applicationWillTerminate(_ notification: Notification) {
        record("will-terminate \(scenario)")
    }
}

@main
private struct TerminationProbe {
    @MainActor static func main() {
        let info = Bundle.main.infoDictionary ?? [:]
        let scenario = info["LifecycleScenario"] as? String ?? CommandLine.arguments[1]
        let path = info["LifecycleRoot"] as? String ?? CommandLine.arguments[2]
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let delegate = ProbeDelegate(root: URL(fileURLWithPath: path), scenario: scenario)
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
