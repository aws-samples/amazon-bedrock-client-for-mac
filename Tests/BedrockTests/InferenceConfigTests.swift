import XCTest
@testable import Amazon_Bedrock_Client_for_Mac

final class InferenceConfigTests: XCTestCase {
    @MainActor
    func testApplicationProfileResolvesCapabilitiesAndKeepsItsARNInRequests() async throws {
        let region = "eu-west-3"
        let arn = "arn:aws:bedrock:eu-west-3:123456789012:application-inference-profile/team-model"
        let foundationID = "anthropic.claude-haiku-4-5-20251001-v1:0"
        let profile = BedrockModelDescriptor(id: arn, name: "Team model", provider: "Anthropic",
            inputModalities: ["TEXT", "IMAGE"], outputModalities: ["TEXT"], inferenceTypes: ["INFERENCE_PROFILE"],
            streaming: true, foundationID: foundationID, isProfile: true)
        let catalog = ModelCatalog.shared.descriptors
        BedrockCapabilityRegistry.shared.replace(region: region, descriptors: [profile])
        defer { BedrockCapabilityRegistry.shared.replace(region: region, descriptors: catalog) }
        let backend = try BedrockService(region: region, profile: "default", endpoint: "", runtimeEndpoint: "")
        guard case .claudeHaiku45 = backend.getModelType(arn) else { return XCTFail("Profile capabilities were not resolved.") }
        XCTAssertTrue(backend.isVisionSupported(arn))
        let request = try await backend.makeConverseRequest(modelId: arn, messages: [])
        XCTAssertEqual(request.modelId, arn, "The application ARN must reach Bedrock for billing and IAM enforcement.")
        XCTAssertNotNil(request.inferenceConfig?.maxTokens)
    }

    @MainActor
    func testFrontierApplicationProfilesRetainToolsAndTheirConverseARN() async throws {
        let region = "eu-west-3"
        let catalog = ModelCatalog.shared.descriptors
        defer { BedrockCapabilityRegistry.shared.replace(region: region, descriptors: catalog) }
        let backend = try BedrockService(region: region, profile: "default", endpoint: "", runtimeEndpoint: "")
        for (index, foundationID) in ["openai.gpt-6-astra", "openai.gpt-5.6-luna"].enumerated() {
            let arn = "arn:aws:bedrock:eu-west-3:123456789012:application-inference-profile/team-\(index)"
            let profile = BedrockModelDescriptor(id: arn, name: "Team \(index)", provider: "OpenAI",
                inputModalities: ["TEXT", "IMAGE"], outputModalities: ["TEXT"], inferenceTypes: ["INFERENCE_PROFILE"],
                streaming: true, foundationID: foundationID, isProfile: true)
            BedrockCapabilityRegistry.shared.replace(region: region, descriptors: [profile])
            XCTAssertTrue(backend.isToolUseSupported(arn), foundationID)
            XCTAssertTrue(backend.isStreamingToolUseSupported(arn), foundationID)
            XCTAssertTrue(backend.isReasoningSupported(arn), foundationID)
            XCTAssertTrue(backend.isVisionSupported(arn), foundationID)
            XCTAssertFalse(BedrockResponsesEndpoint.usesResponses(arn, hasDocuments: false),
                           "Application profiles must retain Converse routing and billing.")
            let request = try await backend.makeConverseRequest(modelId: arn, messages: [])
            XCTAssertEqual(request.modelId, arn)
            XCTAssertNil(request.inferenceConfig?.temperature)
            XCTAssertNil(request.inferenceConfig?.topp)
            XCTAssertNotNil(request.additionalModelRequestFields)
        }
    }

    @MainActor
    func testOpaqueProfileCapabilitiesMatchFoundationCapabilities() throws {
        let region = "eu-west-3"
        let catalog = ModelCatalog.shared.descriptors
        defer { BedrockCapabilityRegistry.shared.replace(region: region, descriptors: catalog) }
        let backend = try BedrockService(region: region, profile: "default", endpoint: "", runtimeEndpoint: "")
        let models = ["xai.grok-4.6", "mistral.mistral-7b-instruct-v0:2",
                      "amazon.titan-text-premier-v1:0", "stability.stable-image-ultra-v1:1"]
        for (index, foundationID) in models.enumerated() {
            let arn = "arn:aws:bedrock:eu-west-3:123456789012:application-inference-profile/opaque-\(index)"
            let profile = BedrockModelDescriptor(id: arn, name: "Team \(index)", provider: "",
                inputModalities: [], outputModalities: [], inferenceTypes: ["INFERENCE_PROFILE"],
                foundationID: foundationID, isProfile: true)
            let foundation = BedrockModelDescriptor(id: foundationID, name: "Foundation \(index)", provider: "",
                inputModalities: [], outputModalities: [], inferenceTypes: ["INFERENCE_PROFILE"])
            BedrockCapabilityRegistry.shared.replace(region: region, descriptors: [foundation, profile])
            XCTAssertEqual(backend.isReasoningSupported(arn), backend.isReasoningSupported(foundationID), foundationID)
            XCTAssertEqual(backend.isToolUseSupported(arn), backend.isToolUseSupported(foundationID), foundationID)
            XCTAssertEqual(backend.isStreamingToolUseSupported(arn), backend.isStreamingToolUseSupported(foundationID), foundationID)
            XCTAssertEqual(backend.isImageGenerationModel(arn), backend.isImageGenerationModel(foundationID), foundationID)
            XCTAssertEqual(backend.isSystemPromptSupported(arn), backend.isSystemPromptSupported(foundationID), foundationID)
            XCTAssertEqual(backend.isDocumentChatSupported(arn), backend.isDocumentChatSupported(foundationID), foundationID)
        }
    }

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
        let backend = try BedrockService(
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
        let backend = try BedrockService(
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
        let backend = try BedrockService(
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
        let backend = try BedrockService(
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
        let backend = try BedrockService(
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

        // The current catalog serves these models through Converse profiles.
        // Saved bare IDs must be promoted to a real profile at invocation time.
        for modelID in ["openai.gpt-5.6-sol", "openai.gpt-5.6-terra", "openai.gpt-5.6-luna", "openai.gpt-6-astra"] {
            XCTAssertFalse(backend.isMantleResponsesModel(modelID))
            let record = try XCTUnwrap(BedrockBundledCatalog.records.first { $0.id == modelID })
            XCTAssertTrue(record.regions["us-west-2"]?.profiles.contains("us." + modelID) == true)
        }
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

        // Frontier GPT models omit unsupported sampling parameters.
        for modelId in ["openai.gpt-5.6-sol", "openai.gpt-5.6-terra", "openai.gpt-5.6-luna"] {
            let parameters = ModelInferenceRange.getParameterDefaultsForModel(modelId)
            XCTAssertTrue(parameters.includeMaxTokens, "\(modelId) should send max tokens")
            XCTAssertFalse(parameters.includeTemperature, "\(modelId) must not send temperature")
            XCTAssertFalse(parameters.includeTopP, "\(modelId) must not send top_p")
        }
    }

    /// Mantle-only gates do not accidentally restrict models with Converse profiles.
    func testMantleRegionAvailability() {
        XCTAssertNil(BedrockService.mantleRegions(for: "openai.gpt-5.6-sol"))
        XCTAssertNil(BedrockService.mantleRegions(for: "openai.gpt-5.6-terra"))
        XCTAssertNil(BedrockService.mantleRegions(for: "openai.gpt-5.6-luna"))
        XCTAssertNil(BedrockService.mantleRegions(for: "openai.gpt-6-astra"))
        XCTAssertEqual(BedrockService.mantleRegions(for: "openai.gpt-5.5"), ["us-east-1", "us-east-2"])
        XCTAssertEqual(BedrockService.mantleRegions(for: "openai.gpt-5.4"), ["us-east-1", "us-east-2", "us-west-2"])

        // Non-Mantle models are not region-gated by this table
        XCTAssertNil(BedrockService.mantleRegions(for: "us.anthropic.claude-opus-5"))
        XCTAssertNil(BedrockService.mantleRegions(for: "openai.gpt-oss-120b"))
    }

    /// GPT-5.5 is Mantle-only and unavailable in Oregon; Sol has Converse profiles.
    func testMantleRegionGateRejectsUnservedRegion() throws {
        let oregon = try BedrockService(
            region: "us-west-2",
            profile: "default",
            endpoint: "",
            runtimeEndpoint: ""
        )
        XCTAssertFalse(oregon.isMantleModelAvailableInRegion("openai.gpt-5.5"))
        XCTAssertTrue(oregon.isMantleModelAvailableInRegion("openai.gpt-5.6-sol"))
        XCTAssertTrue(oregon.isMantleModelAvailableInRegion("openai.gpt-5.6-terra"))
        XCTAssertTrue(oregon.isMantleModelAvailableInRegion("openai.gpt-5.6-luna"))
        // Non-Mantle models are never gated by region here
        XCTAssertTrue(oregon.isMantleModelAvailableInRegion("us.anthropic.claude-opus-5"))

        let virginia = try BedrockService(
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
