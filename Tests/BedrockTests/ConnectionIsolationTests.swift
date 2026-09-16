import XCTest
@testable import Amazon_Bedrock_Client_for_Mac

final class ConnectionIsolationTests: XCTestCase {
    func testTestHostNeverResolvesRealCredentialsOrUsesAnAWSFallbackEndpoint() async throws {
        XCTAssertTrue(ValidationMode.isOffline, "Run this suite with the isolated test scheme.")
        guard ValidationMode.isOffline else { return }
        let service = try BedrockService(region: "us-west-2", profile: "must-not-resolve",
                                         endpoint: "https://example.invalid", runtimeEndpoint: "")
        let endpoint = ValidationMode.localRuntimeEndpoint ?? "http://127.0.0.1:9"
        XCTAssertEqual(service.endpoint, endpoint)
        XCTAssertEqual(service.runtimeEndpoint, endpoint)
        let identity = try await service.awsCredentialIdentityResolver.getIdentity(identityProperties: nil)
        XCTAssertEqual(identity.accessKey, "BEDROCK_UI_TEST")
    }

    func testProfileDiscoveryUsesEnvironmentOverridesAndMergesTypes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let credentials = directory.appendingPathComponent("custom-credentials")
        let config = directory.appendingPathComponent("custom-configuration")
        try "[default]\n[fixture]\n".write(to: credentials, atomically: true, encoding: .utf8)
        try "[profile fixture]\nsso_session = fixture\n[sso-session ignored]\n".write(
            to: config, atomically: true, encoding: .utf8)
        let environment = ["AWS_SHARED_CREDENTIALS_FILE": credentials.path, "AWS_CONFIG_FILE": config.path]
        let profiles = PreferencesStore.readAWSProfilesSync(environment: environment)
        XCTAssertEqual(Set(profiles.map(\.name)), ["default", "fixture"])
        XCTAssertEqual(profiles.first { $0.name == "fixture" }?.type, .sso)
    }

    func testOfflineProfileDiscoveryCannotFallBackToHomeDirectory() {
        let environment = ["BEDROCK_TEST_OFFLINE": "1", "BEDROCK_WORKBENCH_DATA_DIR": "/tmp/isolated-profile-test"]
        let files = PreferencesStore.configurationFileURLs(environment: environment)
        XCTAssertEqual(files.credentials.path, "/tmp/isolated-profile-test/aws/credentials")
        XCTAssertEqual(files.config.path, "/tmp/isolated-profile-test/aws/config")
    }
}
