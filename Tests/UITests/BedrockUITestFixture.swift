import AppKit
import XCTest

/// A separate loopback server, not a replacement for the app's inference code.
@MainActor
final class BedrockUITestFixture {
    let port: Int
    let requestsURL: URL
    private let directory: URL
    private let process: Process

    init(directory: URL) throws {
        self.directory = directory
        let fixtures = try XCTUnwrap(ProcessInfo.processInfo.environment["BEDROCK_TEST_FIXTURES"])
        let script = URL(fileURLWithPath: fixtures).appendingPathComponent("bedrock_runtime.py")
        XCTAssertTrue(FileManager.default.fileExists(atPath: script.path))
        let ready = directory.appendingPathComponent("runtime-ready.json")
        requestsURL = directory.appendingPathComponent("runtime-requests.jsonl")
        process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", script.path, "--ready", ready.path, "--requests", requestsURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.standardError
        try process.run()
        let deadline = Date().addingTimeInterval(8)
        while !FileManager.default.fileExists(atPath: ready.path), process.isRunning, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        guard let data = try? Data(contentsOf: ready),
              let result = try JSONSerialization.jsonObject(with: data) as? [String: Int],
              let port = result["port"] else {
            process.terminate()
            throw NSError(domain: "BedrockUITestFixture", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "The loopback Bedrock fixture did not start."])
        }
        self.port = port
        try """
        [default]
        aws_access_key_id = TEST_ONLY_ACCESS_KEY
        aws_secret_access_key = TEST_ONLY_SECRET_KEY

        """.write(to: directory.appendingPathComponent("aws-credentials"), atomically: true, encoding: .utf8)
        try "[default]\nregion = us-west-2\n".write(
            to: directory.appendingPathComponent("aws-config"), atomically: true, encoding: .utf8)
    }

    func configure(_ app: XCUIApplication) {
        app.launchEnvironment["BEDROCK_TEST_RUNTIME_PORT"] = String(port)
        app.launchEnvironment["AWS_SHARED_CREDENTIALS_FILE"] = directory.appendingPathComponent("aws-credentials").path
        app.launchEnvironment["AWS_CONFIG_FILE"] = directory.appendingPathComponent("aws-config").path
        app.launchEnvironment["AWS_EC2_METADATA_DISABLED"] = "true"
        app.launchArguments += ["-runtimeEndpoint", "http://127.0.0.1:\(port)"]
    }

    func releaseStream() throws {
        _ = try Data(contentsOf: XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/release")))
    }

    func requests() throws -> [[String: Any]] {
        guard FileManager.default.fileExists(atPath: requestsURL.path) else { return [] }
        return try String(contentsOf: requestsURL, encoding: .utf8).split(separator: "\n").map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
        }
    }

    func stop() {
        if process.isRunning { process.terminate(); process.waitUntilExit() }
    }
}
