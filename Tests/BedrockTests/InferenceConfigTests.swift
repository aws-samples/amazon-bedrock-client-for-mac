import XCTest
@testable import Amazon_Bedrock_Client_for_Mac

final class InferenceConfigTests: XCTestCase {
    @MainActor
    func testUnknownModelsUseServiceSamplingDefaultsAndPreserveExplicitOverrides() async throws {
        let preferences = PreferencesStore.shared
        let savedConfigs = preferences.modelInferenceConfigs
        defer {
            preferences.modelInferenceConfigs = savedConfigs
        }
        preferences.modelInferenceConfigs = [:]
        let backend = try BedrockService(region: "us-east-1", profile: "default", endpoint: "", runtimeEndpoint: "")
        for id in ["future.new-model", "us.future.new-model", "global.moonshotai.kimi-k99",
                   "anthropic.claude-next", "xai.grok-future"] {
            let defaults = preferences.getInferenceConfig(for: id)
            XCTAssertNil(defaults.requestTemperature, id)
            XCTAssertNil(defaults.requestTopP, id)
            for thinking in [false, true] {
                let request = try await backend.makeConverseRequest(modelId: id, messages: [], thinkingEnabled: thinking)
                XCTAssertEqual(request.inferenceConfig?.maxTokens, 4096, id)
                XCTAssertNil(request.inferenceConfig?.temperature, id)
                XCTAssertNil(request.inferenceConfig?.topp, id)
                XCTAssertNil(request.additionalModelRequestFields, "Do not guess a reasoning schema for \(id).")
            }
            let custom = ModelInferenceConfig(maxTokens: 1234, temperature: 0.25, topP: 0.85,
                                              overrideDefault: true, enableStreaming: false)
            preferences.setInferenceConfig(custom, for: id)
            let request = try await backend.makeConverseRequest(modelId: id, messages: [], thinkingEnabled: false)
            XCTAssertEqual(request.inferenceConfig?.maxTokens, 1234, id)
            XCTAssertEqual(request.inferenceConfig?.temperature, 0.25, id)
            XCTAssertEqual(request.inferenceConfig?.topp, 0.85, id)
            XCTAssertEqual(preferences.getInferenceConfig(for: id), custom)
            preferences.resetInferenceConfig(for: id)
        }
    }

    @MainActor
    func testKimiK3ConverseNormalizesOldSettingsAndKeepsApplicationProfileIdentity() async throws {
        let region = "us-east-1"
        let arn = "arn:aws:bedrock:us-east-1:123456789012:application-inference-profile/kimi-team"
        let catalog = ModelCatalog.shared.descriptors
        defer { BedrockCapabilityRegistry.shared.replace(region: region, descriptors: catalog) }
        let profile = BedrockModelDescriptor(id: arn, name: "Kimi team", provider: "Moonshot AI",
            inputModalities: ["TEXT", "IMAGE"], outputModalities: ["TEXT"], inferenceTypes: ["INFERENCE_PROFILE"],
            streaming: true, foundationID: "moonshotai.kimi-k3", isProfile: true)
        BedrockCapabilityRegistry.shared.replace(region: region, descriptors: [profile])
        let backend = try BedrockService(region: region, profile: "default", endpoint: "", runtimeEndpoint: "")
        let oldConfig = ModelInferenceConfig(maxTokens: 1024, temperature: 0.7, topP: 0.9,
                                             reasoningEffort: "max", overrideDefault: true)
        for id in ["moonshotai.kimi-k3", "us.moonshotai.kimi-k3", "global.moonshotai.kimi-k3", arn] {
            XCTAssertEqual(backend.getModelType(id), .kimiK3, id)
            XCTAssertTrue(backend.isReasoningSupported(id), id)
            XCTAssertTrue(backend.hasConfigurableReasoning(id), id)
            XCTAssertFalse(backend.hasAlwaysOnReasoning(id), id)
            XCTAssertTrue(backend.isVisionSupported(id), id)
            XCTAssertTrue(backend.isDocumentChatSupported(id), id)
            XCTAssertTrue(backend.isToolUseSupported(id), id)
            XCTAssertFalse(backend.isPromptCachingSupported(id), "K3 Converse must not receive cachePoint.")
            XCTAssertNil(BedrockService.mantleRegions(for: id))
            for thinking in [false, true] {
                let request = try await backend.makeConverseRequest(modelId: id, messages: [],
                    modelParameters: oldConfig, thinkingEnabled: thinking)
                XCTAssertEqual(request.modelId, id)
                XCTAssertEqual(request.inferenceConfig?.maxTokens, 1024)
                XCTAssertNil(request.inferenceConfig?.temperature)
                XCTAssertNil(request.inferenceConfig?.topp)
                let fields = try XCTUnwrap(request.additionalModelRequestFields).asStringMap()
                let reasoning = try XCTUnwrap(fields["reasoning"]).asStringMap()
                XCTAssertEqual(try reasoning["effort"]?.asString(), thinking ? "max" : "none")
                XCTAssertNil(fields["reasoning_effort"])
            }
        }
        XCTAssertTrue(oldConfig.includeTemperature, "Normalize the request without rewriting saved settings.")
        XCTAssertTrue(oldConfig.includeTopP)
        let replay = try await backend.makeConverseRequest(modelId: arn, messages: [
            .init(content: [
                .reasoningcontent(.reasoningtext(.init(signature: "SYNTHETIC_SIGNATURE", text: "Earlier reasoning"))),
                .text("Earlier answer")
            ], role: .assistant),
            .init(content: [.text("Continue")], role: .user)
        ], modelParameters: oldConfig, thinkingEnabled: false)
        XCTAssertEqual(replay.modelId, arn)
        XCTAssertEqual(replay.messages?.count, 2)
        XCTAssertEqual(replay.messages?.first?.content?.count, 1, "Converse must not replay K3 reasoning blocks.")
    }

    @MainActor
    func testTitleParametersDoNotChangeTheConversationModelOrSavedInferenceSettings() async throws {
        let preferences = PreferencesStore.shared
        let previous = preferences.modelInferenceConfigs
        let thinking = preferences.enableModelThinking
        let chatModel = preferences.defaultModelId
        defer {
            preferences.modelInferenceConfigs = previous
            preferences.enableModelThinking = thinking
        }
        let id = "us.amazon.nova-pro-v1:0"
        preferences.modelInferenceConfigs[id] = ModelInferenceConfig(maxTokens: 8192, reasoningEffort: "high", overrideDefault: true)
        preferences.enableModelThinking = true
        let saved = preferences.modelInferenceConfigs
        let backend = try BedrockService(region: "us-east-1", profile: "default", endpoint: "", runtimeEndpoint: "")
        let request = try await backend.makeConverseRequest(modelId: id, messages: [],
            modelParameters: ConversationTitle.parameters, thinkingEnabled: false)
        XCTAssertEqual(request.modelId, id)
        XCTAssertEqual(request.inferenceConfig?.maxTokens, ConversationTitle.maxOutputTokens)
        XCTAssertNil(request.inferenceConfig?.temperature)
        XCTAssertNil(request.inferenceConfig?.topp)
        XCTAssertEqual(preferences.modelInferenceConfigs, saved)
        XCTAssertEqual(preferences.defaultModelId, chatModel)
        XCTAssertTrue(preferences.enableModelThinking)
    }

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

    // MARK: - Claude 5.5

    /// Claude 5.5 rejects temperature, top_p and budget thinking. Opus 5.5 cannot turn thinking
    /// off; Sonnet 5.5 uses `between_tools` and Haiku 5.5 `disabled` (Bedrock Converse, 2026-11-23).
    @MainActor
    func testClaude55ModelsUseTheirOwnThinkingControls() async throws {
        let preferences = PreferencesStore.shared
        let saved = preferences.modelInferenceConfigs
        defer { preferences.modelInferenceConfigs = saved }
        preferences.modelInferenceConfigs = [:]
        let backend = try BedrockService(region: "us-east-1", profile: "default", endpoint: "", runtimeEndpoint: "")
        let models: [(base: String, type: ModelType, tokens: Int, effort: String, off: String?)] = [
            ("anthropic.claude-opus-5-5", .claudeOpus55, 32000, "high", nil),
            ("anthropic.claude-sonnet-5-5", .claudeSonnet55, 16000, "high", "between_tools"),
            ("anthropic.claude-haiku-5-5", .claudeHaiku55, 16000, "medium", "disabled")
        ]
        let custom = ModelInferenceConfig(maxTokens: 2048, temperature: 0.7, topP: 0.9,
                                          reasoningEffort: "max", overrideDefault: true)
        for model in models {
            for id in [model.base, "us." + model.base, "global." + model.base] {
                XCTAssertEqual(backend.getModelType(id), model.type, id)
                XCTAssertTrue(backend.isReasoningSupported(id), id)
                XCTAssertEqual(backend.hasAlwaysOnReasoning(id), model.off == nil, id)
                XCTAssertEqual(backend.hasConfigurableReasoning(id), model.off != nil, id)
                XCTAssertTrue(backend.omitsSamplingParameters(model.type), id)
                XCTAssertTrue(backend.isVisionSupported(id), id)
                XCTAssertTrue(backend.isToolUseSupported(id), id)
                XCTAssertTrue(backend.isStreamingToolUseSupported(id), id)
                XCTAssertTrue(backend.isDocumentChatSupported(id), id)
                XCTAssertTrue(backend.isPromptCachingSupported(id), id)
                XCTAssertTrue(backend.isSystemPromptSupported(id), id)
                XCTAssertFalse(BedrockResponsesEndpoint.usesResponses(id, hasDocuments: true), id)
                let range = ModelInferenceRange.getRangeForModel(id)
                XCTAssertEqual(range.maxTokensRange, 1...128000, id)
                XCTAssertEqual(range.defaultMaxTokens, model.tokens, id)
                XCTAssertEqual(range.defaultReasoningEffort, model.effort, id)
                XCTAssertNil(preferences.getInferenceConfig(for: id).requestTemperature, id)
                XCTAssertNil(preferences.getInferenceConfig(for: id).requestTopP, id)

                for thinking in [true, false] {
                    let request = try await backend.makeConverseRequest(modelId: id, messages: [],
                        modelParameters: custom, thinkingEnabled: thinking)
                    XCTAssertEqual(request.inferenceConfig?.maxTokens, 2048, id)
                    XCTAssertNil(request.inferenceConfig?.temperature, id)
                    XCTAssertNil(request.inferenceConfig?.topp, id)
                    let fields = try XCTUnwrap(request.additionalModelRequestFields).asStringMap()
                    let reasoning = try XCTUnwrap(fields["reasoning_config"]).asStringMap()
                    let effort = try XCTUnwrap(fields["output_config"]).asStringMap()["effort"]?.asString()
                    if thinking || model.off == nil {
                        XCTAssertEqual(try reasoning["type"]?.asString(), "adaptive", id)
                        XCTAssertEqual(try reasoning["display"]?.asString(), "summarized", id)
                        XCTAssertEqual(effort, "max", id)
                    } else {
                        XCTAssertEqual(try reasoning["type"]?.asString(), model.off, id)
                        XCTAssertNil(reasoning["display"], "Thinking off takes no display: \(id)")
                        XCTAssertEqual(effort, "high", "Thinking off rejects effort above High: \(id)")
                    }
                }
                let request = try await backend.makeConverseRequest(modelId: id, messages: [], thinkingEnabled: true)
                XCTAssertEqual(request.inferenceConfig?.maxTokens, model.tokens, id)
                XCTAssertNil(request.inferenceConfig?.temperature, id)
                let fields = try XCTUnwrap(request.additionalModelRequestFields).asStringMap()
                XCTAssertEqual(try fields["output_config"]?.asStringMap()["effort"]?.asString(), model.effort, id)
            }
        }
        // Earlier models that share a name prefix keep their own rules.
        XCTAssertEqual(backend.getModelType("us.anthropic.claude-opus-5"), .claudeOpus5)
        XCTAssertEqual(backend.getModelType("global.anthropic.claude-sonnet-5"), .claudeSonnet5)
        XCTAssertEqual(backend.getModelType("us.anthropic.claude-fable-5-2"), .claudeFable5)
        XCTAssertEqual(backend.getModelType("global.anthropic.claude-haiku-4-5-20251001-v1:0"), .claudeHaiku45)
        XCTAssertTrue(backend.hasAlwaysOnReasoning("us.anthropic.claude-fable-5-2"))
    }

    // MARK: - GPT-6.x and Grok

    /// Bedrock rejects reasoning effort `none` for GPT-6 Astra, GPT-6.1 Sol and GPT-6.2 (measured
    /// 2026-11-23), so turning thinking off sends `none` only where it is accepted.
    @MainActor
    func testGPT6ReasoningTurnsOffOnlyWhereBedrockAcceptsIt() async throws {
        let backend = try BedrockService(region: "us-west-2", profile: "default", endpoint: "", runtimeEndpoint: "")
        let models: [(base: String, type: ModelType, canTurnOff: Bool, tokens: Int)] = [
            ("openai.gpt-6.2-astra", .openaiGpt62Astra, false, 32000),
            ("openai.gpt-6.2-sol", .openaiGpt62Sol, false, 32000),
            ("openai.gpt-6.1-sol", .openaiGpt61Sol, false, 32000),
            ("openai.gpt-6.1-terra", .openaiGpt61Terra, true, 16000),
            ("openai.gpt-6-sol", .openaiGpt6Sol, true, 32000),
            ("openai.gpt-6-luna", .openaiGpt6Luna, true, 8192),
            ("openai.gpt-6-astra", .openaiGpt6Astra, false, 8192)
        ]
        let custom = ModelInferenceConfig(maxTokens: 4000, temperature: 0.7, topP: 0.9,
                                          reasoningEffort: "xhigh", overrideDefault: true)
        for model in models {
            for id in ["us." + model.base, "global." + model.base] {
                XCTAssertEqual(backend.getModelType(id), model.type, id)
                XCTAssertTrue(backend.isFrontierGPT(id), id)
                XCTAssertTrue(backend.isReasoningSupported(id), id)
                XCTAssertEqual(backend.hasAlwaysOnReasoning(id), !model.canTurnOff, id)
                XCTAssertTrue(backend.isDocumentChatSupported(id), id)
                XCTAssertTrue(backend.isStreamingToolUseSupported(id), id)
                XCTAssertFalse(backend.isMantleResponsesModel(id), id)
                let range = ModelInferenceRange.getRangeForModel(id)
                XCTAssertEqual(range.maxTokensRange, 1...128000, id)
                XCTAssertEqual(range.defaultMaxTokens, model.tokens, id)
                let defaults = ModelInferenceRange.getParameterDefaultsForModel(id)
                XCTAssertFalse(defaults.includeTemperature, id)
                XCTAssertFalse(defaults.includeTopP, id)
                for thinking in [true, false] {
                    let request = try await backend.makeConverseRequest(modelId: id, messages: [],
                        modelParameters: custom, thinkingEnabled: thinking)
                    XCTAssertEqual(request.inferenceConfig?.maxTokens, 4000, id)
                    XCTAssertNil(request.inferenceConfig?.temperature, id)
                    XCTAssertNil(request.inferenceConfig?.topp, id)
                    let fields = try XCTUnwrap(request.additionalModelRequestFields).asStringMap()
                    XCTAssertEqual(try fields["reasoning"]?.asStringMap()["effort"]?.asString(),
                                   thinking || !model.canTurnOff ? "xhigh" : "none", id)
                }
            }
        }
        XCTAssertEqual(ModelInferenceRange.getRangeForModel("us.openai.gpt-6-luna").defaultReasoningEffort, "low")
        XCTAssertEqual(ModelInferenceRange.getRangeForModel("us.openai.gpt-6.2-sol").defaultReasoningEffort, "medium")
    }

    /// Grok 4.6 and 4.7 always reason and accept Low through Very high; `none` and `max` return 400.
    @MainActor
    func testGrokReasoningEffortStaysWithinWhatBedrockAccepts() async throws {
        let backend = try BedrockService(region: "us-west-2", profile: "default", endpoint: "", runtimeEndpoint: "")
        for id in ["us.xai.grok-4.7", "global.xai.grok-4.7", "xai.grok-4.6", "us.xai.grok-4.6"] {
            XCTAssertEqual(backend.getModelType(id), .xaiGrok4, id)
            XCTAssertTrue(backend.hasAlwaysOnReasoning(id), id)
            XCTAssertTrue(backend.isDocumentChatSupported(id), id)
            XCTAssertTrue(backend.isStreamingToolUseSupported(id), id)
            XCTAssertEqual(ModelInferenceRange.getRangeForModel(id).maxTokensRange, 1...128000, id)
            for (saved, sent) in [("xhigh", "xhigh"), ("low", "low"), ("max", "medium"), ("none", "medium"), ("", "medium")] {
                let config = ModelInferenceConfig(maxTokens: 1000, temperature: 0.7, reasoningEffort: saved, overrideDefault: true)
                for thinking in [true, false] {
                    let request = try await backend.makeConverseRequest(modelId: id, messages: [],
                        modelParameters: config, thinkingEnabled: thinking)
                    XCTAssertEqual(request.inferenceConfig?.maxTokens, 1000, id)
                    XCTAssertNil(request.inferenceConfig?.temperature, id)
                    let fields = try XCTUnwrap(request.additionalModelRequestFields).asStringMap()
                    XCTAssertEqual(try fields["reasoning"]?.asStringMap()["effort"]?.asString(), sent, "\(id) \(saved)")
                }
            }
        }
        XCTAssertEqual(backend.getModelType("xai.grok-4.3"), .unknown, "Mantle's Grok 4.3 keeps its existing request.")
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

    /// GPT-5.5 is not on bedrock-mantle in Oregon, where its Runtime profiles serve it.
    /// Dated Mantle-only IDs and Regions without those profiles stay gated.
    func testMantleRegionGateRejectsUnservedRegion() throws {
        let oregon = try BedrockService(
            region: "us-west-2",
            profile: "default",
            endpoint: "",
            runtimeEndpoint: ""
        )
        XCTAssertTrue(oregon.isMantleModelAvailableInRegion("openai.gpt-5.5"))
        XCTAssertTrue(oregon.isMantleModelAvailableInRegion("us.openai.gpt-5.5"))
        XCTAssertFalse(oregon.isMantleModelAvailableInRegion("openai.gpt-5.5-2026-04-23"))
        let frankfurt = try BedrockService(region: "eu-central-1", profile: "default", endpoint: "", runtimeEndpoint: "")
        XCTAssertFalse(frankfurt.isMantleModelAvailableInRegion("openai.gpt-5.5"))
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

    @MainActor
    func testSonnet46RequestsUseOnlyOneSamplingParameterAcrossProfileForms() async throws {
        let preferences = PreferencesStore.shared
        let savedConfigs = preferences.modelInferenceConfigs
        let savedThinking = preferences.enableModelThinking
        defer {
            preferences.modelInferenceConfigs = savedConfigs
            preferences.enableModelThinking = savedThinking
        }
        preferences.modelInferenceConfigs = [:]
        preferences.enableModelThinking = false
        let backend = try BedrockService(region: "us-east-1", profile: "default", endpoint: "", runtimeEndpoint: "")
        let identifiers = [
            "anthropic.claude-sonnet-4-6",
            "us.anthropic.claude-sonnet-4-6",
            "global.anthropic.claude-sonnet-4-6",
            "arn:aws:bedrock:us-east-1:123456789012:inference-profile/us.anthropic.claude-sonnet-4-6"
        ]
        for id in identifiers {
            XCTAssertEqual(backend.getModelType(id), .claudeSonnet46, id)
            let defaults = ModelInferenceRange.getParameterDefaultsForModel(id)
            XCTAssertTrue(defaults.includeTemperature, id)
            XCTAssertFalse(defaults.includeTopP, id)
            let request = try await backend.makeConverseRequest(modelId: id, messages: [])
            XCTAssertEqual(request.inferenceConfig?.temperature, 0.9, id)
            XCTAssertNil(request.inferenceConfig?.topp, id)
            XCTAssertTrue(backend.isVisionSupported(id), id)
            XCTAssertTrue(backend.isToolUseSupported(id), id)
        }
    }

    @MainActor
    func testSonnet46CustomSamplingAndThinkingAreNormalizedInTheRequest() async throws {
        let preferences = PreferencesStore.shared
        let savedConfigs = preferences.modelInferenceConfigs
        let savedThinking = preferences.enableModelThinking
        defer {
            preferences.modelInferenceConfigs = savedConfigs
            preferences.enableModelThinking = savedThinking
        }
        let id = "us.anthropic.claude-sonnet-4-6"
        let backend = try BedrockService(region: "us-east-1", profile: "default", endpoint: "", runtimeEndpoint: "")
        preferences.enableModelThinking = false

        // Old saved settings can still have both fields enabled.
        preferences.setInferenceConfig(.init(temperature: 0.3, topP: 0.8, overrideDefault: true), for: id)
        var request = try await backend.makeConverseRequest(modelId: id, messages: [])
        XCTAssertEqual(request.inferenceConfig?.temperature, 0.3)
        XCTAssertNil(request.inferenceConfig?.topp)

        preferences.setInferenceConfig(.init(topP: 0.8, includeTemperature: false, overrideDefault: true), for: id)
        request = try await backend.makeConverseRequest(modelId: id, messages: [])
        XCTAssertNil(request.inferenceConfig?.temperature)
        XCTAssertEqual(request.inferenceConfig?.topp, 0.8)

        preferences.setInferenceConfig(.init(includeTemperature: false, includeTopP: false, overrideDefault: true), for: id)
        request = try await backend.makeConverseRequest(modelId: id, messages: [])
        XCTAssertNil(request.inferenceConfig?.temperature)
        XCTAssertNil(request.inferenceConfig?.topp)

        preferences.setInferenceConfig(.init(temperature: 0.3, topP: 0.8, overrideDefault: true), for: id)
        preferences.enableModelThinking = true
        request = try await backend.makeConverseRequest(modelId: id, messages: [])
        XCTAssertEqual(request.inferenceConfig?.temperature, 1.0)
        XCTAssertNil(request.inferenceConfig?.topp)
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
