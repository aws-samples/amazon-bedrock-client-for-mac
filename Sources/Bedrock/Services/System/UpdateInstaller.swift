import CryptoKit
import Foundation

enum UpdateInstaller {
    static let bundleIdentifier = "AWS.Amazon-Bedrock-Client-for-Mac"
    static let appName = "Amazon Bedrock.app"

    static func workspace() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BedrockUpdate-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        return url
    }

    static func download(_ asset: SoftwareUpdateRelease.Asset, into workspace: URL,
                         session: URLSession = .shared) async throws -> URL {
        var request = URLRequest(url: asset.browserDownloadURL, timeoutInterval: 300)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (temporary, response) = try await session.download(for: request)
        // Move the URLSession file before dispatching UI work. Completion-handler
        // temporary files used by the old updater could disappear first.
        let destination = workspace.appendingPathComponent("Update.dmg")
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            try? FileManager.default.removeItem(at: temporary)
            throw SoftwareUpdateError.invalidDownload
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
        try Task.checkCancellation()
        let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0, size <= 2_147_483_648, asset.size == nil || asset.size == size else {
            throw SoftwareUpdateError.invalidDownload
        }
        if let digest = asset.digest {
            guard digest.hasPrefix("sha256:"),
                  String(digest.dropFirst(7)).lowercased() == (try await sha256(destination)) else {
                throw SoftwareUpdateError.invalidDownload
            }
        }
        return destination
    }

    static func sha256(_ file: URL) async throws -> String {
        let worker = Task.detached(priority: .utility) {
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            var hash = SHA256()
            while let bytes = try handle.read(upToCount: 1_048_576), !bytes.isEmpty {
                try Task.checkCancellation()
                hash.update(data: bytes)
            }
            return hash.finalize().map { String(format: "%02x", $0) }.joined()
        }
        return try await withTaskCancellationHandler { try await worker.value }
        onCancel: { worker.cancel() }
    }

    static func prepare(dmg: URL, version: String, currentApp: URL,
                        parentPID: Int32 = ProcessInfo.processInfo.processIdentifier) async throws -> UpdateInstallationPlan {
        let currentApp = currentApp.resolvingSymlinksInPath().standardizedFileURL
        let workspace = dmg.deletingLastPathComponent()
        let parent = currentApp.deletingLastPathComponent()
        let volume = try parent.resourceValues(forKeys: [.volumeIsReadOnlyKey])
        guard FileManager.default.isWritableFile(atPath: parent.path),
              volume.volumeIsReadOnly != true,
              !currentApp.path.contains("/AppTranslocation/") else {
            throw SoftwareUpdateError.manualInstallationRequired(
                "This copy cannot be replaced automatically. Open the downloaded DMG and drag Bedrock into Applications.")
        }
        let signingInfo = try await command("/usr/bin/codesign", ["-dv", "--verbose=4", currentApp.path], in: workspace)
        guard let team = signingInfo.split(separator: "\n").first(where: { $0.hasPrefix("TeamIdentifier=") })
                .map({ String($0.dropFirst("TeamIdentifier=".count)) }),
              team.range(of: #"^[A-Z0-9]{10}$"#, options: .regularExpression) != nil else {
            throw SoftwareUpdateError.manualInstallationRequired(
                "Automatic replacement requires a Developer ID–signed copy. Install the downloaded DMG manually.")
        }
        let stage = parent.appendingPathComponent(".bedrock-update-\(UUID())")
        let mount = workspace.appendingPathComponent("volume")
        let plan = UpdateInstallationPlan(destination: currentApp, stagingDirectory: stage,
                                          workspace: workspace, parentPID: parentPID)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        do {
            try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: false)
            // The mount belongs to this operation. Never guess from /Volumes or
            // use an unrelated recently mounted disk.
            _ = try await command("/usr/bin/hdiutil",
                                  ["attach", "-readonly", "-nobrowse", "-mountpoint", mount.path, dmg.path],
                                  in: workspace, timeout: 90)
            let source = mount.appendingPathComponent(appName)
            try await verifyApp(source, version: version, team: team, in: workspace)
            _ = try await command("/usr/sbin/spctl", ["--assess", "--type", "execute", source.path],
                                  in: workspace, timeout: 60)
            _ = try await command("/usr/bin/ditto", [source.path, plan.stagedApp.path], in: workspace, timeout: 180)
            try await verifyApp(plan.stagedApp, version: version, team: team, in: workspace)
            try Task.checkCancellation()
            try plan.writeHelper()
            await detach(mount, in: workspace)
            return plan
        } catch {
            await detach(mount, in: workspace)
            try? FileManager.default.removeItem(at: stage)
            throw error
        }
    }

    static func verifyApp(_ app: URL, version: String, team: String, in workspace: URL) async throws {
        guard team.range(of: #"^[A-Z0-9]{10}$"#, options: .regularExpression) != nil else {
            throw SoftwareUpdateError.verification("The signing identity is invalid.")
        }
        let data = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        guard info?["CFBundleIdentifier"] as? String == bundleIdentifier,
              info?["CFBundleShortVersionString"] as? String == version,
              info?["CFBundleExecutable"] as? String == "Amazon Bedrock" else {
            throw SoftwareUpdateError.verification("The application identity or version does not match the release.")
        }
        let requirement = #"anchor apple generic and identifier "\#(bundleIdentifier)" and certificate leaf[subject.OU] = "\#(team)""#
        try await verifySignature(app, requirement: requirement, in: workspace)
    }

    static func verifySignature(_ code: URL, requirement: String, in workspace: URL) async throws {
        // codesign treats a requirement without "=" as a filename.
        _ = try await command("/usr/bin/codesign",
                              ["--verify", "--deep", "--strict", "-R", "=" + requirement, code.path], in: workspace)
    }

    @MainActor
    static func handOff(_ plan: UpdateInstallationPlan) async throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = plan.arguments
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": NSHomeDirectory(),
                               "LANG": "en_US.UTF-8", "TMPDIR": NSTemporaryDirectory()]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        do {
            for _ in 0..<200 {
                if !process.isRunning { break }
                if FileManager.default.fileExists(atPath: plan.readyURL.path) { return process }
                try await Task.sleep(for: .milliseconds(50))
            }
        } catch {
            if process.isRunning { process.terminate() }
            throw error
        }
        if process.isRunning { process.terminate() }
        throw SoftwareUpdateError.installation("The update installer could not start. Your current app has not been changed.")
    }

    private static func detach(_ mount: URL, in workspace: URL) async {
        // Cancellation must still unmount our own volume.
        await Task.detached(priority: .utility) {
            _ = try? await LocalProcessRunner.run(executable: "/usr/bin/hdiutil",
                                                  arguments: ["detach", mount.path],
                                                  directory: workspace, timeout: 20)
        }.value
    }

    @discardableResult
    private static func command(_ executable: String, _ arguments: [String], in directory: URL,
                                timeout: TimeInterval = 30) async throws -> String {
        let result = try await LocalProcessRunner.run(executable: executable, arguments: arguments,
                                                      directory: directory, timeout: timeout, outputLimit: 16_000)
        if result.cancelled { throw CancellationError() }
        guard result.succeeded else {
            throw SoftwareUpdateError.verification(
                result.timedOut ? "The verification timed out." : String(result.output.suffix(1_000)))
        }
        return result.output
    }
}
