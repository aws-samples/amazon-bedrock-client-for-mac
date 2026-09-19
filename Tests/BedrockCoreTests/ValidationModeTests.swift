import XCTest
@testable import BedrockCore

final class ValidationModeTests: XCTestCase {
    private let offline = [
        "BEDROCK_TEST_OFFLINE": "1",
        "BEDROCK_WORKBENCH_DATA_DIR": "/tmp/bedrock-fixture",
        "BEDROCK_TEST_RUNTIME_PORT": "51234"
    ]

    func testOrdinaryAppPreservesConfiguredConnection() {
        let endpoint = "https://example.invalid/bedrock"
        XCTAssertFalse(ValidationMode.isOffline(environment: [:]))
        XCTAssertNil(ValidationMode.localRuntimeEndpoint(environment: [:]))
        XCTAssertEqual(ValidationMode.connectionEndpoint(endpoint, environment: [:]), endpoint)
        XCTAssertTrue(ValidationMode.permitsInference(
            modelID: "openai.gpt-6-astra", runtimeEndpoint: endpoint, environment: [:]))
        XCTAssertFalse(ValidationMode.isOffline(environment: ["BEDROCK_TEST_OFFLINE": "1"]))
    }

    func testOfflineSDKEndpointDoesNotRequireASecondLaunchArgument() {
        XCTAssertEqual(ValidationMode.connectionEndpoint("", environment: offline), "http://127.0.0.1:51234")
        XCTAssertEqual(ValidationMode.connectionEndpoint("https://example.invalid", environment: offline),
                       "http://127.0.0.1:51234")
        XCTAssertTrue(ValidationMode.permitsInference(
            modelID: "us.amazon.nova-2-lite-v1:0", runtimeEndpoint: "http://127.0.0.1:51234", environment: offline))
        XCTAssertTrue(ValidationMode.permitsInference(
            modelID: "global.openai.gpt-6-astra", runtimeEndpoint: "http://127.0.0.1:51234", environment: offline))
        XCTAssertTrue(ValidationMode.permitsInference(
            modelID: "us.moonshotai.kimi-k3", runtimeEndpoint: "http://127.0.0.1:51234", environment: offline))
        XCTAssertFalse(ValidationMode.permitsInference(
            modelID: "us.moonshotai.kimi-k3", runtimeEndpoint: "https://bedrock-runtime.us-east-1.amazonaws.com", environment: offline))
    }

    func testIsolationRejectsInvalidPortsAndOtherInferenceRoutes() {
        for port in ["", "80", "65536", "-1", "51234/path", "example.invalid"] {
            var environment = offline
            environment["BEDROCK_TEST_RUNTIME_PORT"] = port
            XCTAssertNil(ValidationMode.localRuntimeEndpoint(environment: environment))
            XCTAssertEqual(ValidationMode.connectionEndpoint("", environment: environment), "http://127.0.0.1:9")
            XCTAssertFalse(ValidationMode.permitsInference(
                modelID: "amazon.nova-2-lite-v1:0", runtimeEndpoint: "http://127.0.0.1:9", environment: environment))
        }
        for model in ["openai.gpt-5.5", "google.gemma-4-e2b", "xai.grok-4.3",
                      "amazon.nova-reel-v1:1", "stability.stable-image-ultra-v1:1",
                      "amazon.nova-2-sonic-v1:0", "cohere.embed-v4:0"] {
            XCTAssertFalse(ValidationMode.permitsInference(
                modelID: model, runtimeEndpoint: "http://127.0.0.1:51234", environment: offline))
        }
        XCTAssertFalse(ValidationMode.permitsInference(
            modelID: "amazon.nova-2-lite-v1:0", runtimeEndpoint: "https://example.invalid", environment: offline))
    }
}
