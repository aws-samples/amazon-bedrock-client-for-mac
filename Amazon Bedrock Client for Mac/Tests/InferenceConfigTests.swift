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

    func testOpus5DefaultsOmitSamplingParameters() {
        let modelId = "global.anthropic.claude-opus-5"
        let range = ModelInferenceRange.getRangeForModel(modelId)
        let parameters = ModelInferenceRange.getParameterDefaultsForModel(modelId)

        XCTAssertEqual(range.maxTokensRange, 1...128000)
        XCTAssertEqual(range.defaultMaxTokens, 32000)
        XCTAssertEqual(range.defaultReasoningEffort, "xhigh")
        XCTAssertTrue(parameters.includeMaxTokens)
        XCTAssertFalse(parameters.includeTemperature)
        XCTAssertFalse(parameters.includeTopP)
    }

    func testOpus5BackendOmitsSamplingDefaults() throws {
        let modelId = "us.anthropic.claude-opus-5"
        let backend = try Backend(
            region: "us-east-1",
            profile: "default",
            endpoint: "",
            runtimeEndpoint: ""
        )

        guard case .claudeOpus5 = backend.getModelType(modelId) else {
            return XCTFail("Opus 5 model ID was not classified correctly")
        }

        let config = backend.getDefaultInferenceConfig(for: .claudeOpus5)
        XCTAssertEqual(config.maxTokens, 32000)
        XCTAssertNil(config.temperature)
        XCTAssertNil(config.topp)
        XCTAssertTrue(backend.isReasoningSupported(modelId))
        XCTAssertTrue(backend.isVisionSupported(modelId))
        XCTAssertTrue(backend.isToolUseSupported(modelId))
        XCTAssertTrue(backend.isPromptCachingSupported(modelId))
    }

    /// Opus 5 rejects `reasoning_config: disabled` at xhigh/max effort, so those clamp to high.
    func testOpus5ClampsEffortWhenThinkingDisabled() throws {
        let backend = try Backend(
            region: "us-east-1",
            profile: "default",
            endpoint: "",
            runtimeEndpoint: ""
        )

        XCTAssertEqual(backend.effortForDisabledThinking("xhigh"), "high")
        XCTAssertEqual(backend.effortForDisabledThinking("max"), "high")
        XCTAssertEqual(backend.effortForDisabledThinking("high"), "high")
        XCTAssertEqual(backend.effortForDisabledThinking("medium"), "medium")
        XCTAssertEqual(backend.effortForDisabledThinking("low"), "low")
    }

    /// The bare `anthropic.claude-opus-5` form (Bedrock Mantle / Messages API) must not
    /// fall through to the legacy `.claude` case, which would send sampling params.
    func testOpus5BareModelIdIsClassified() throws {
        let backend = try Backend(
            region: "us-east-1",
            profile: "default",
            endpoint: "",
            runtimeEndpoint: ""
        )

        guard case .claudeOpus5 = backend.getModelType("anthropic.claude-opus-5") else {
            return XCTFail("Bare Opus 5 model ID was not classified correctly")
        }
        XCTAssertTrue(backend.omitsSamplingParameters(.claudeOpus5))
    }

    // MARK: - GPT-5.6 (Sol / Terra / Luna)

    func testGpt56TiersAreClassified() throws {
        let backend = try Backend(
            region: "us-east-1",
            profile: "default",
            endpoint: "",
            runtimeEndpoint: ""
        )

        guard case .openaiGpt56Sol = backend.getModelType("openai.gpt-5.6-sol") else {
            return XCTFail("GPT-5.6 Sol was not classified correctly")
        }
        guard case .openaiGpt56Terra = backend.getModelType("openai.gpt-5.6-terra") else {
            return XCTFail("GPT-5.6 Terra was not classified correctly")
        }
        guard case .openaiGpt56Luna = backend.getModelType("openai.gpt-5.6-luna") else {
            return XCTFail("GPT-5.6 Luna was not classified correctly")
        }

        // All three are served only through the bedrock-mantle Responses API
        XCTAssertTrue(backend.isMantleResponsesModel("openai.gpt-5.6-sol"))
        XCTAssertTrue(backend.isMantleResponsesModel("openai.gpt-5.6-terra"))
        XCTAssertTrue(backend.isMantleResponsesModel("openai.gpt-5.6-luna"))
        XCTAssertTrue(backend.isReasoningSupported("openai.gpt-5.6-sol"))
    }

    /// Each tier gets its own token budget and effort baseline rather than a shared default.
    func testGpt56TierDefaultsDiffer() {
        let sol = ModelInferenceRange.getRangeForModel("openai.gpt-5.6-sol")
        let terra = ModelInferenceRange.getRangeForModel("openai.gpt-5.6-terra")
        let luna = ModelInferenceRange.getRangeForModel("openai.gpt-5.6-luna")

        XCTAssertEqual(sol.defaultMaxTokens, 32000)
        XCTAssertEqual(sol.defaultReasoningEffort, "high")
        XCTAssertEqual(terra.defaultMaxTokens, 16000)
        XCTAssertEqual(terra.defaultReasoningEffort, "medium")
        XCTAssertEqual(luna.defaultMaxTokens, 8192)
        XCTAssertEqual(luna.defaultReasoningEffort, "low")

        // The Responses API path takes max_output_tokens + effort only
        for modelId in ["openai.gpt-5.6-sol", "openai.gpt-5.6-terra", "openai.gpt-5.6-luna"] {
            let parameters = ModelInferenceRange.getParameterDefaultsForModel(modelId)
            XCTAssertTrue(parameters.includeMaxTokens, "\(modelId) should send max tokens")
            XCTAssertFalse(parameters.includeTemperature, "\(modelId) must not send temperature")
            XCTAssertFalse(parameters.includeTopP, "\(modelId) must not send top_p")
        }
    }

    /// Region availability matches what the bedrock-mantle endpoints actually serve.
    /// No CRIS at launch, so a model must not be offered outside these regions.
    func testMantleRegionAvailability() {
        XCTAssertEqual(Backend.mantleRegions(for: "openai.gpt-5.6-sol"), ["us-east-1", "us-east-2"])
        XCTAssertEqual(Backend.mantleRegions(for: "openai.gpt-5.6-terra"), ["us-east-1", "us-east-2", "us-west-2"])
        XCTAssertEqual(Backend.mantleRegions(for: "openai.gpt-5.6-luna"), ["us-east-1", "us-east-2", "us-west-2"])
        XCTAssertEqual(Backend.mantleRegions(for: "openai.gpt-5.5"), ["us-east-1", "us-east-2"])
        XCTAssertEqual(Backend.mantleRegions(for: "openai.gpt-5.4"), ["us-east-1", "us-east-2", "us-west-2"])

        // Non-Mantle models are not region-gated by this table
        XCTAssertNil(Backend.mantleRegions(for: "us.anthropic.claude-opus-5"))
        XCTAssertNil(Backend.mantleRegions(for: "openai.gpt-oss-120b"))
    }

    /// Sol is not served in Oregon, so a chat saved against it must be rejected there
    /// rather than sent to an endpoint that cannot serve it.
    func testMantleRegionGateRejectsUnservedRegion() throws {
        let oregon = try Backend(
            region: "us-west-2",
            profile: "default",
            endpoint: "",
            runtimeEndpoint: ""
        )
        XCTAssertFalse(oregon.isMantleModelAvailableInRegion("openai.gpt-5.6-sol"))
        XCTAssertTrue(oregon.isMantleModelAvailableInRegion("openai.gpt-5.6-terra"))
        XCTAssertTrue(oregon.isMantleModelAvailableInRegion("openai.gpt-5.6-luna"))
        // Non-Mantle models are never gated by region here
        XCTAssertTrue(oregon.isMantleModelAvailableInRegion("us.anthropic.claude-opus-5"))

        let virginia = try Backend(
            region: "us-east-1",
            profile: "default",
            endpoint: "",
            runtimeEndpoint: ""
        )
        XCTAssertTrue(virginia.isMantleModelAvailableInRegion("openai.gpt-5.6-sol"))
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
