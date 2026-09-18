import Darwin
import Foundation
import XCTest
@testable import Amazon_Bedrock_Client_for_Mac

final class UpdateInstallerTests: XCTestCase {
    func testSignatureRequirementAcceptsTrustedCodeAndRejectsWrongIdentity() async throws {
        let root = try UpdateInstaller.workspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = URL(fileURLWithPath: "/usr/bin/true")
        try await UpdateInstaller.verifySignature(executable, requirement: "anchor apple", in: root)
        do {
            try await UpdateInstaller.verifySignature(executable, requirement: #"identifier "org.example.WrongApp""#, in: root)
            XCTFail("The same signed executable must fail an unrelated identity requirement.")
        } catch { }
    }

    private func withDownloadServer(_ body: (URL, URL) async throws -> Void) async throws {
        let directory = URL(fileURLWithPath: "/private/tmp/bedrock-ui-fixtures")
            .appendingPathComponent("updater-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let port = directory.appendingPathComponent("port")
        let environment = ProcessInfo.processInfo.environment
        let fixtureRoot = environment["BEDROCK_TEST_FIXTURES"].map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent("Fixtures")
        let python = try XCTUnwrap(Bundle(for: UpdateInstallerTests.self)
            .object(forInfoDictionaryKey: "BedrockTestPython") as? String)
        XCTAssertTrue(python.hasPrefix("/") && !python.contains("$("), "Use the real Python interpreter, not xcrun's shim.")
        let script = fixtureRoot.appendingPathComponent("update_fixture.py")
        XCTAssertTrue(FileManager.default.fileExists(atPath: script.path), "Missing download fixture: \(script.path)")
        let errorLog = directory.appendingPathComponent("server.log")
        FileManager.default.createFile(atPath: errorLog.path, contents: nil)
        let errors = try FileHandle(forWritingTo: errorLog)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [script.path, port.path]
        // Keep XCTest/DYLD instrumentation and unrelated app environment
        // variables out of the standalone Python fixture.
        process.environment = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": NSHomeDirectory(),
            "TMPDIR": directory.path, "LANG": "en_US.UTF-8",
            "PYTHONUNBUFFERED": "1", "PYTHONDONTWRITEBYTECODE": "1"
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        addTeardownBlock {
            defer {
                try? errors.close()
                try? FileManager.default.removeItem(at: directory)
            }
            guard process.isRunning else { return }
            process.terminate()
            for _ in 0..<50 where process.isRunning {
                try? await Task.sleep(for: .milliseconds(20))
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                for _ in 0..<50 where process.isRunning {
                    try? await Task.sleep(for: .milliseconds(20))
                }
            }
            XCTAssertFalse(process.isRunning, "The owned download fixture must stop within two seconds.")
        }
        try process.run()
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        var readyPort: Int?
        while process.isRunning, ContinuousClock.now < deadline {
            if let text = try? String(contentsOf: port, encoding: .utf8),
               let number = Int(text), (1...65535).contains(number) {
                readyPort = number
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        guard let number = readyPort else {
            let details = (try? String(contentsOf: errorLog, encoding: .utf8)) ?? ""
            throw NSError(domain: "UpdateDownloadFixture", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "The download fixture did not start. \(details.suffix(2_000))"
            ])
        }
        let base = try XCTUnwrap(URL(string: "http://127.0.0.1:\(number)"))
        try await body(base, directory)
    }

    func testDownloadedTemporaryFileSurvivesAsyncUIWorkAndRetainsExactBytes() async throws {
        try await withDownloadServer { base, directory in
            let asset = SoftwareUpdateRelease.Asset(name: SoftwareUpdateRelease.assetName,
                                                     browserDownloadURL: base.appendingPathComponent("update.dmg"),
                                                     size: 23,
                                                     digest: "sha256:3b552b2dd63632d713c494b0772759ba7854a8d6fcf6f0d4018fbec5d12c16cd")
            let downloaded = try await UpdateInstaller.download(asset, into: directory)
            try await Task.sleep(for: .milliseconds(200))
            XCTAssertEqual(try Data(contentsOf: downloaded), Data("verified update payload".utf8))
            XCTAssertEqual(downloaded.deletingLastPathComponent().path, directory.path)
        }
    }

    func testHTTPErrorPageCannotBeUsedAsAnUpdate() async throws {
        try await withDownloadServer { base, directory in
            let asset = SoftwareUpdateRelease.Asset(name: SoftwareUpdateRelease.assetName,
                                                     browserDownloadURL: base.appendingPathComponent("missing.dmg"),
                                                     size: nil, digest: nil)
            do {
                _ = try await UpdateInstaller.download(asset, into: directory)
                XCTFail("An HTTP error must never produce an installable update.")
            } catch {
                XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("Update.dmg").path))
            }
        }
    }

    func testIncorrectAssetSizeAndDigestAreRejected() async throws {
        try await withDownloadServer { base, directory in
            for (size, digest) in [(Int64(1), Optional<String>.none), (Int64(23), "sha256:" + String(repeating: "0", count: 64))] {
                let folder = directory.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
                let asset = SoftwareUpdateRelease.Asset(name: SoftwareUpdateRelease.assetName,
                                                         browserDownloadURL: base.appendingPathComponent("update.dmg"),
                                                         size: size, digest: digest)
                do {
                    _ = try await UpdateInstaller.download(asset, into: folder)
                    XCTFail("A mismatched size or digest must reject the update.")
                } catch let error as SoftwareUpdateError {
                    guard case .invalidDownload = error else { return XCTFail("Unexpected error: \(error)") }
                }
            }
        }
    }

    func testWrongApplicationIdentityAndUnsignedUpdatesAreRejectedBeforeInstallation() async throws {
        let root = try UpdateInstaller.workspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Amazon Bedrock.app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        for (identity, version) in [("org.example.Unrelated", "2.0.0"),
                                    (UpdateInstaller.bundleIdentifier, "1.4.10"),
                                    (UpdateInstaller.bundleIdentifier, "2.0.0")] {
            let info = ["CFBundleIdentifier": identity, "CFBundleShortVersionString": version,
                        "CFBundleExecutable": "Amazon Bedrock"]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
            do {
                try await UpdateInstaller.verifyApp(app, version: "2.0.0", team: "ABCDEFGHIJ", in: root)
                XCTFail("Wrong identity, version, or missing signature must fail verification.")
            } catch { }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.path))
    }
}
