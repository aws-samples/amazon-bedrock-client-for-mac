import Foundation
import Darwin
import XCTest
@testable import BedrockCore

final class SoftwareUpdateTests: XCTestCase {
    private func release(tag: String = "v2.0.0", draft: Bool = false, prerelease: Bool = false,
                         url: String? = nil) throws -> SoftwareUpdateRelease {
        let value: [String: Any] = [
            "tag_name": tag, "draft": draft, "prerelease": prerelease,
            "assets": [["name": SoftwareUpdateRelease.assetName,
                        "browser_download_url": url ??
                        "https://github.com/\(SoftwareUpdateRelease.repository)/releases/download/\(tag)/\(SoftwareUpdateRelease.assetName)"]]
        ]
        return try JSONDecoder().decode(SoftwareUpdateRelease.self, from: JSONSerialization.data(withJSONObject: value))
    }

    func testExistingVersionDiscoversTheCompatibleReleaseAssetWithoutOfferingDowngrades() throws {
        let update = try release()
        XCTAssertEqual(try update.update(after: "1.4.10")?.name, SoftwareUpdateRelease.assetName)
        XCTAssertNil(try update.update(after: "2.0.0"))
        XCTAssertNil(try update.update(after: "2.0.1"))
        XCTAssertNotNil(try release(tag: "v2.0.10").update(after: "2.0.9"))
        XCTAssertNil(try release(tag: "v2.0.9").update(after: "2.0.10"))
    }

    func testDraftPrereleaseAndMalformedVersionsCannotTriggerAnInstall() throws {
        XCTAssertNil(try release(draft: true).update(after: "1.4.10"))
        XCTAssertNil(try release(prerelease: true).update(after: "1.4.10"))
        for version in ["v2.0.0-beta", "vv2.0.0", "v2..0", "v2.0", "v2.0.0;open"] {
            XCTAssertNil(try release(tag: version).update(after: "1.4.10"), version)
        }
        XCTAssertNil(try release().update(after: "unknown"))
    }

    func testUnexpectedRepositoryHostOrAssetCannotBecomeAnUpdate() throws {
        let path = "/\(SoftwareUpdateRelease.repository)/releases/download/v2.0.0/\(SoftwareUpdateRelease.assetName)"
        for url in ["http://github.com\(path)", "https://example.com\(path)",
                    "https://github.com.evil.example\(path)", "https://user@github.com\(path)",
                    "https://github.com\(path)?other=1", "https://github.com\(path)#other",
                    "https://github.com/other/repository/releases/download/v2.0.0/App.dmg"] {
            XCTAssertThrowsError(try release(url: url).update(after: "1.4.10"), url)
        }
    }

    func testMetadataHTTPFailuresAreNotReportedAsInvalidReleaseAssets() throws {
        for status in [401, 403, 404, 500, 502, 503] {
            let response = try XCTUnwrap(HTTPURLResponse(url: SoftwareUpdateRelease.latestURL,
                statusCode: status, httpVersion: nil, headerFields: nil))
            XCTAssertThrowsError(try SoftwareUpdateRelease.decode(Data(), response: response, now: Date())) { error in
                guard case SoftwareUpdateError.metadataUnavailable(let code) = error else {
                    return XCTFail("Unexpected error for HTTP \(status): \(error)")
                }
                XCTAssertEqual(code, status)
                XCTAssertFalse(error.localizedDescription.contains("valid Bedrock update"))
            }
        }
    }

    func testRateLimitsHonorResetSecondsAndHTTPDateWithoutImmediateRetry() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        let cases: [(Int, [String: String], TimeInterval)] = [
            (403, ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1800000120"], 120),
            (429, ["Retry-After": "90"], 90),
            (403, ["Retry-After": formatter.string(from: now.addingTimeInterval(180))], 180),
            (429, [:], 60),
            (429, ["Retry-After": "-10", "X-RateLimit-Reset": "invalid"], 60),
            (403, ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1"], 60)
        ]
        for (status, headers, expected) in cases {
            let response = try XCTUnwrap(HTTPURLResponse(url: SoftwareUpdateRelease.latestURL,
                statusCode: status, httpVersion: nil, headerFields: headers))
            XCTAssertThrowsError(try SoftwareUpdateRelease.decode(Data(), response: response, now: now)) { error in
                guard case SoftwareUpdateError.rateLimited(let deadline) = error else {
                    return XCTFail("Expected a rate limit, got \(error)")
                }
                XCTAssertEqual(deadline.timeIntervalSince(now), expected, accuracy: 0.01)
            }
        }
    }

    func testUnreadableMetadataIsSeparateFromAMissingOrUntrustedAsset() throws {
        let response = try XCTUnwrap(HTTPURLResponse(url: SoftwareUpdateRelease.latestURL,
            statusCode: 200, httpVersion: nil, headerFields: nil))
        XCTAssertThrowsError(try SoftwareUpdateRelease.decode(Data("not JSON".utf8), response: response, now: Date())) { error in
            guard case SoftwareUpdateError.invalidMetadata = error else {
                return XCTFail("Expected invalid metadata, got \(error)")
            }
        }
        let data = Data(#"{"tag_name":"v2.0.2","draft":false,"prerelease":false,"assets":[]}"#.utf8)
        let decoded = try SoftwareUpdateRelease.decode(data, response: response, now: Date())
        XCTAssertThrowsError(try decoded.update(after: "2.0.1")) { error in
            guard case SoftwareUpdateError.invalidRelease = error else {
                return XCTFail("Asset validation must still reject a missing DMG")
            }
        }
    }

    @MainActor
    func testMetadataClientPersistsCooldownAcrossInstancesAndRecoversAfterReset() async throws {
        let suite = "UpdateMetadataTests.\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        let endpoint = try XCTUnwrap(URL(string: "https://updates.test/\(UUID())"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateMetadataURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer {
            session.invalidateAndCancel()
            preferences.removePersistentDomain(forName: suite)
            UpdateMetadataURLProtocol.fixtures.remove(endpoint)
        }
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        UpdateMetadataURLProtocol.fixtures.set(endpoint, status: 403,
            headers: ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1800000120"])
        let client = SoftwareUpdateClient(session: session, preferences: preferences, endpoint: endpoint, now: { now })
        do {
            _ = try await client.latestRelease()
            XCTFail("The rate-limited response must fail")
        } catch {
            guard case SoftwareUpdateError.rateLimited = error else { return XCTFail("\(error)") }
        }
        let restarted = SoftwareUpdateClient(session: session, preferences: preferences, endpoint: endpoint, now: { now })
        do {
            _ = try await restarted.latestRelease()
            XCTFail("A restarted client must respect the persisted deadline")
        } catch {
            guard case SoftwareUpdateError.rateLimited = error else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(UpdateMetadataURLProtocol.fixtures.count(endpoint), 1)

        now = now.addingTimeInterval(121)
        let body = try JSONSerialization.data(withJSONObject: [
            "tag_name": "v2.0.2", "draft": false, "prerelease": false,
            "assets": [["name": SoftwareUpdateRelease.assetName,
                        "browser_download_url": "https://github.com/\(SoftwareUpdateRelease.repository)/releases/download/v2.0.2/\(SoftwareUpdateRelease.assetName)"]]
        ])
        UpdateMetadataURLProtocol.fixtures.set(endpoint, status: 200, body: body)
        let recovered = try await restarted.latestRelease()
        XCTAssertNotNil(try recovered.update(after: "2.0.1"))
        XCTAssertEqual(UpdateMetadataURLProtocol.fixtures.count(endpoint), 2)
    }

    func testInstallerWaitsForTheExactOldProcessAndDoesNotDeleteItsAppOnTimeout() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sleeper = try startSleeper()
        var ownsSleeper = true
        defer {
            // Reap our fixture PID directly so cleanup across an await does
            // not depend on Foundation run-loop exit notifications.
            if ownsSleeper {
                _ = kill(sleeper, SIGKILL)
                var status: Int32 = 0
                while waitpid(sleeper, &status, 0) < 0 && errno == EINTR {}
            }
        }
        var plan = try makePlan(in: root, pid: sleeper)
        plan.quitTimeoutSeconds = 1
        try plan.writeHelper()
        let result = try await execute(plan)
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(try marker(plan.destination), "old")
        XCTAssertEqual(try marker(plan.stagedApp), "new")
        XCTAssertFalse(FileManager.default.fileExists(atPath: plan.previousApp.path))
        XCTAssertEqual(try String(contentsOf: plan.resultURL, encoding: .utf8), "failed\n")
        var status: Int32 = 0
        let exited = waitpid(sleeper, &status, WNOHANG)
        if exited == sleeper || (exited < 0 && errno == ECHILD) { ownsSleeper = false }
        XCTAssertEqual(exited, 0, "An updater must never force-kill the running app.")
    }

    func testInstallerReplacesOnlyTheStagedAppAndKeepsAdjacentDataWithLiteralPaths() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let plan = try makePlan(in: root)
        let data = root.appendingPathComponent("Conversations.json")
        try Data("Keep every conversation and preference.".utf8).write(to: data)
        try plan.writeHelper()
        let result = try await execute(plan)
        XCTAssertTrue(result.succeeded, result.output)
        XCTAssertEqual(try marker(plan.destination), "new")
        XCTAssertEqual(try String(contentsOf: data, encoding: .utf8), "Keep every conversation and preference.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("NEVER").path))
        XCTAssertEqual(try String(contentsOf: plan.resultURL, encoding: .utf8), "installed\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: plan.previousApp.path))
    }

    func testAlteredStagedSignatureIsRejectedBeforeMovingTheCurrentApp() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let plan = try makePlan(in: root)
        try Data("tampered".utf8).write(to: plan.stagedApp.appendingPathComponent("Contents/Resources/marker"))
        try plan.writeHelper()
        let result = try await execute(plan)
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(try marker(plan.destination), "old")
        XCTAssertFalse(FileManager.default.fileExists(atPath: plan.previousApp.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: plan.readyURL.path))
    }

    func testFailedSecondRenameRestoresTheOriginalApp() async throws {
        let root = try temporaryDirectory()
        let plan = try makePlan(in: root)
        defer {
            _ = chflags(plan.stagedApp.path, 0)
            try? FileManager.default.removeItem(at: root)
        }
        // An immutable staged directory forces the second atomic rename to
        // fail after the old app has already moved into the backup location.
        XCTAssertEqual(chflags(plan.stagedApp.path, UInt32(UF_IMMUTABLE)), 0)
        try plan.writeHelper()
        let result = try await execute(plan)
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(try marker(plan.destination), "old")
        XCTAssertEqual(try marker(plan.stagedApp), "new")
        XCTAssertFalse(FileManager.default.fileExists(atPath: plan.previousApp.path))
    }

    func testInstallerRefusesAStageOnADifferentParentOrProcessGroupPID() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var plan = try makePlan(in: root)
        plan = UpdateInstallationPlan(destination: plan.destination, stagingDirectory: plan.stagingDirectory,
                                      workspace: plan.workspace, parentPID: 0, relaunch: false)
        XCTAssertThrowsError(try plan.writeHelper())
        let other = UpdateInstallationPlan(destination: root.appendingPathComponent("App.app"),
                                            stagingDirectory: root.appendingPathComponent("Elsewhere/stage"),
                                            workspace: root, parentPID: 1, relaunch: false)
        XCTAssertThrowsError(try other.writeHelper())
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Update's $(touch NEVER) \(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        return root
    }

    private func startSleeper() throws -> pid_t {
        var arguments = [strdup("/bin/sleep"), strdup("30"), nil]
        var environment = [strdup("PATH=/usr/bin:/bin"), nil]
        defer {
            arguments.forEach { free($0) }
            environment.forEach { free($0) }
        }
        var pid: pid_t = 0
        let result = posix_spawn(&pid, "/bin/sleep", nil, nil, &arguments, &environment)
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: result) ?? .EIO) }
        return pid
    }

    private func makePlan(in root: URL, pid: Int32 = Int32.max) throws -> UpdateInstallationPlan {
        let stage = root.appendingPathComponent(".staging")
        let workspace = root.appendingPathComponent("download")
        for folder in [stage, workspace] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        }
        let plan = UpdateInstallationPlan(destination: root.appendingPathComponent("Bedrock's $(touch NEVER).app"),
                                          stagingDirectory: stage, workspace: workspace, parentPID: pid, relaunch: false)
        try app(at: plan.destination, marker: "old")
        try app(at: plan.stagedApp, marker: "new")
        return plan
    }

    private func app(at url: URL, marker: String) throws {
        let contents = url.appendingPathComponent("Contents")
        for name in ["MacOS", "Resources"] {
            try FileManager.default.createDirectory(at: contents.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"),
                                         to: contents.appendingPathComponent("MacOS/Fixture"))
        let info = ["CFBundleIdentifier": "org.example.BedrockUpdateFixture", "CFBundleExecutable": "Fixture",
                    "CFBundlePackageType": "APPL", "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0.0"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        try Data(marker.utf8).write(to: contents.appendingPathComponent("Resources/marker"))
        try run("/usr/bin/codesign", ["--force", "--sign", "-", url.path])
    }

    private func marker(_ app: URL) throws -> String {
        try String(contentsOf: app.appendingPathComponent("Contents/Resources/marker"), encoding: .utf8)
    }

    private func execute(_ plan: UpdateInstallationPlan) async throws -> LocalProcessResult {
        try await LocalProcessRunner.run(executable: "/bin/sh", arguments: plan.arguments,
                                          directory: plan.workspace, timeout: 10)
    }

    @discardableResult
    private func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "UpdateFixture", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: output])
        }
        return output
    }
}

private final class UpdateMetadataURLProtocol: URLProtocol, @unchecked Sendable {
    static let fixtures = FixtureStore()
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "updates.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, let fixture = Self.fixtures.take(url),
              let response = HTTPURLResponse(url: url, statusCode: fixture.status,
                                             httpVersion: nil, headerFields: fixture.headers) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: fixture.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    struct Fixture {
        let status: Int
        let headers: [String: String]
        let body: Data
    }
    final class FixtureStore: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [URL: Fixture] = [:]
        private var requests: [URL: Int] = [:]
        func set(_ url: URL, status: Int, headers: [String: String] = [:], body: Data = Data()) {
            lock.lock(); defer { lock.unlock() }
            values[url] = Fixture(status: status, headers: headers, body: body)
        }
        func take(_ url: URL) -> Fixture? {
            lock.lock(); defer { lock.unlock() }
            requests[url, default: 0] += 1
            return values[url]
        }
        func count(_ url: URL) -> Int {
            lock.lock(); defer { lock.unlock() }
            return requests[url, default: 0]
        }
        func remove(_ url: URL) {
            lock.lock(); defer { lock.unlock() }
            values.removeValue(forKey: url)
            requests.removeValue(forKey: url)
        }
    }
}
