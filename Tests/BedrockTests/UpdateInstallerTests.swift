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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [fixtureRoot.appendingPathComponent("update_fixture.py").path, port.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer {
            if process.isRunning { process.terminate(); process.waitUntilExit() }
            try? FileManager.default.removeItem(at: directory)
        }
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: port.path) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let number = try String(contentsOf: port, encoding: .utf8)
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
