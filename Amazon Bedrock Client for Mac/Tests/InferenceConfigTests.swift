import XCTest
@testable import Amazon_Bedrock_Client_for_Mac

final class InferenceConfigTests: XCTestCase {
    func testLegacyConfigEnablesExistingParameters() throws {
        let json = """
        {
          "maxTokens": 8192,
          "temperature": 0.5,
          "topP": 0.8,
          "thinkingBudget": 2048,
          "reasoningEffort": "medium",
          "overrideDefault": true,
          "enableStreaming": true
        }
        """

        let config = try JSONDecoder().decode(
            ModelInferenceConfig.self,
            from: Data(json.utf8)
        )

        XCTAssertTrue(config.includeMaxTokens)
        XCTAssertTrue(config.includeTemperature)
        XCTAssertTrue(config.includeTopP)
        XCTAssertEqual(config.requestMaxTokens, 8192)
        XCTAssertEqual(config.requestTemperature, 0.5)
        XCTAssertEqual(config.requestTopP, 0.8)
    }

    func testCustomParametersCanBeOmitted() {
        let config = ModelInferenceConfig(
            includeMaxTokens: false,
            includeTemperature: false,
            includeTopP: false,
            overrideDefault: true
        )

        XCTAssertNil(config.requestMaxTokens)
        XCTAssertNil(config.requestTemperature)
        XCTAssertNil(config.requestTopP)
    }

    func testSonnet5DefaultsOmitSamplingParameters() {
        let modelId = "global.anthropic.claude-sonnet-5"
        let range = ModelInferenceRange.getRangeForModel(modelId)
        let parameters = ModelInferenceRange.getParameterDefaultsForModel(modelId)

        XCTAssertEqual(range.maxTokensRange, 1...128000)
        XCTAssertEqual(range.defaultMaxTokens, 4096)
        XCTAssertEqual(range.defaultReasoningEffort, "high")
        XCTAssertTrue(parameters.includeMaxTokens)
        XCTAssertFalse(parameters.includeTemperature)
        XCTAssertFalse(parameters.includeTopP)
    }

    func testSonnet5BackendOmitsSamplingDefaults() throws {
        let modelId = "us.anthropic.claude-sonnet-5"
        let backend = try Backend(
            region: "us-east-1",
            profile: "default",
            endpoint: "",
            runtimeEndpoint: ""
        )

        guard case .claudeSonnet5 = backend.getModelType(modelId) else {
            return XCTFail("Sonnet 5 model ID was not classified correctly")
        }

        let config = backend.getDefaultInferenceConfig(for: .claudeSonnet5)
        XCTAssertEqual(config.maxTokens, 4096)
        XCTAssertNil(config.temperature)
        XCTAssertNil(config.topp)
        XCTAssertTrue(backend.isReasoningSupported(modelId))
    }

    func testClaude45DefaultsUseOnlyTemperature() {
        let parameters = ModelInferenceRange.getParameterDefaultsForModel(
            "us.anthropic.claude-haiku-4-5-20251001-v1:0"
        )

        XCTAssertTrue(parameters.includeMaxTokens)
        XCTAssertTrue(parameters.includeTemperature)
        XCTAssertFalse(parameters.includeTopP)
    }

    func testParameterInclusionRoundTrips() throws {
        let original = ModelInferenceConfig(
            maxTokens: 12000,
            temperature: 0.2,
            topP: 0.75,
            includeMaxTokens: false,
            includeTemperature: false,
            includeTopP: true,
            overrideDefault: true,
            enableStreaming: false
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ModelInferenceConfig.self, from: data)

        XCTAssertFalse(decoded.includeMaxTokens)
        XCTAssertFalse(decoded.includeTemperature)
        XCTAssertTrue(decoded.includeTopP)
        XCTAssertFalse(decoded.enableStreaming)
    }
}
