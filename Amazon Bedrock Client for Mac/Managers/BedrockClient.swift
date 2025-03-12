//
//  Bedrockclient.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/08.
//

import AWSBedrock
import AWSBedrockRuntime
import AWSClientRuntime
import AWSSDKIdentity
import AWSSSO
import AWSSSOOIDC
import AWSSTS
import AwsCommonRuntimeKit
import Combine
import Foundation
import Logging
import SmithyIdentity
import SmithyIdentityAPI
import SwiftUI

class BackendModel: ObservableObject {
    @Published var backend: Backend
    @Published var alertMessage: String?  // Used to trigger alerts in the UI
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(label: "BackendModel")
    @Published var isLoggedIn = false
    
    init() {
        do {
            self.backend = try BackendModel.createBackend()
            logger.info("Backend initialized successfully")
        } catch {
            logger.error("Failed to initialize Backend: \(error.localizedDescription). Using fallback Backend.")
            self.backend = Backend.fallbackInstance()
            if error.localizedDescription.lowercased().contains("expired") {
                alertMessage = "Your AWS credentials have expired. Please log in again."
            } else {
                alertMessage = "Backend initialization failed: \(error.localizedDescription). Using fallback settings."
            }
        }
        setupObservers()
    }
    
    private static func createBackend() throws -> Backend {
        let region = SettingManager.shared.selectedRegion.rawValue
        let profile = SettingManager.shared.selectedProfile
        let endpoint = SettingManager.shared.endpoint
        let runtimeEndpoint = SettingManager.shared.runtimeEndpoint
        
        return try Backend(
            region: region,
            profile: profile,
            endpoint: endpoint,
            runtimeEndpoint: runtimeEndpoint
        )
    }
    
    private func setupObservers() {
        let regionPublisher = SettingManager.shared.$selectedRegion
        let profilePublisher = SettingManager.shared.$selectedProfile
        let endpointPublisher = SettingManager.shared.$endpoint
        let runtimeEndpointPublisher = SettingManager.shared.$runtimeEndpoint
        
        Publishers.CombineLatest(regionPublisher, profilePublisher)
            .combineLatest(endpointPublisher)
            .combineLatest(runtimeEndpointPublisher)
            .debounce(for: .seconds(0.5), scheduler: DispatchQueue.main)
            .sink { [weak self] combined in
                let (((region, profile), endpoint), runtimeEndpoint) = combined
                self?.refreshBackend()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .awsCredentialsChanged)
            .sink { [weak self] _ in
                self?.refreshBackend()
            }
            .store(in: &cancellables)
    }
    
    private func refreshBackend() {
        let region = SettingManager.shared.selectedRegion.rawValue
        let profile = SettingManager.shared.selectedProfile
        let endpoint = SettingManager.shared.endpoint
        let runtimeEndpoint = SettingManager.shared.runtimeEndpoint
        
        do {
            let newBackend = try Backend(
                region: region,
                profile: profile,
                endpoint: endpoint,
                runtimeEndpoint: runtimeEndpoint
            )
            self.backend = newBackend
            logger.info("Backend refreshed successfully")
        } catch {
            logger.error(
                "Failed to refresh Backend: \(error.localizedDescription). Retaining current Backend."
            )
            alertMessage = "Failed to refresh Backend: \(error.localizedDescription)."
        }
    }
}

class Backend: Equatable {
    let region: String
    let profile: String
    let endpoint: String
    let runtimeEndpoint: String
    private let logger = Logger(label: "Backend")
    public let awsCredentialIdentityResolver: any AWSCredentialIdentityResolver
    
    private(set) lazy var bedrockClient: BedrockClient = {
        do {
            return try createBedrockClient()
        } catch {
            logger.error("Failed to initialize Bedrock client: \(error.localizedDescription)")
            fatalError("Unable to initialize Bedrock client.")
        }
    }()
    
    private(set) lazy var bedrockRuntimeClient: BedrockRuntimeClient = {
        do {
            return try createBedrockRuntimeClient()
        } catch {
            logger.error(
                "Failed to initialize Bedrock Runtime client: \(error.localizedDescription)")
            fatalError("Unable to initialize Bedrock Runtime client.")
        }
    }()
    
    /// Initializes Backend with given parameters.
    /// Uses SettingManager's profiles to determine if SSO or standard credentials should be used.
    init(region: String, profile: String, endpoint: String, runtimeEndpoint: String) throws {
        self.region = region
        self.profile = profile
        self.endpoint = endpoint
        self.runtimeEndpoint = runtimeEndpoint
        
        // Find the selected profile from SettingManager
        if let selectedProfile = SettingManager.shared.profiles.first(where: { $0.name == profile })
        {
            // If the profile type is SSO, use SSOAWSCredentialIdentityResolver
            if selectedProfile.type == .sso {
                self.awsCredentialIdentityResolver = try SSOAWSCredentialIdentityResolver(
                    profileName: profile)
            } else {
                // Otherwise, it's a standard credentials profile
                self.awsCredentialIdentityResolver = try ProfileAWSCredentialIdentityResolver(
                    profileName: profile)
            }
        } else {
            // If profile not found, fallback to default
            self.awsCredentialIdentityResolver = try ProfileAWSCredentialIdentityResolver(
                profileName: "default")
        }
        
        logger.info(
            "Backend initialized with region: \(region), profile: \(profile), endpoint: \(endpoint), runtimeEndpoint: \(runtimeEndpoint)"
        )
    }
    
    /// Creates a fallback instance with default values
    static func fallbackInstance() -> Backend {
        do {
            return try Backend(
                region: "us-east-1",
                profile: "default",
                endpoint: "",
                runtimeEndpoint: ""
            )
        } catch {
            fatalError(
                "Fallback Backend failed to initialize. Error: \(error.localizedDescription)")
        }
    }
    
    private func createBedrockClient() throws -> BedrockClient {
        let config = try BedrockClient.BedrockClientConfiguration(
            awsCredentialIdentityResolver: self.awsCredentialIdentityResolver,
            region: self.region,
            signingRegion: self.region,
            endpoint: self.endpoint.isEmpty ? nil : self.endpoint
        )
        logger.info(
            "Bedrock client created with region: \(self.region), endpoint: \(self.endpoint)")
        return BedrockClient(config: config)
    }
    
    private func createBedrockRuntimeClient() throws -> BedrockRuntimeClient {
        let config = try BedrockRuntimeClient.BedrockRuntimeClientConfiguration(
            awsCredentialIdentityResolver: self.awsCredentialIdentityResolver,
            region: self.region,
            signingRegion: self.region,
            endpoint: self.runtimeEndpoint.isEmpty ? nil : self.runtimeEndpoint
        )
        logger.info(
            "Bedrock Runtime client created with region: \(self.region), runtimeEndpoint: \(self.runtimeEndpoint)"
        )
        return BedrockRuntimeClient(config: config)
    }
    
    static func == (lhs: Backend, rhs: Backend) -> Bool {
        return lhs.region == rhs.region && lhs.profile == rhs.profile
        && lhs.endpoint == rhs.endpoint && lhs.runtimeEndpoint == rhs.runtimeEndpoint
    }
    
    func invokeModel(withId modelId: String, prompt: String) async throws -> Data {
        let modelType = getModelType(modelId)
        
        // Use Converse API for supported models
        if modelType.usesConverseAPI {
            return try await converse(withId: modelId, prompt: prompt)
        }
        
        let strategy: JSONEncoder.KeyEncodingStrategy = (
            modelType == .claude ||
            modelType == .claude3 ||
            modelType == .novaPro ||
            modelType == .novaLite ||
            modelType == .novaMicro
        ) ? .convertToSnakeCase : .useDefaultKeys
        
        let params = getModelParameters(modelType: modelType, prompt: prompt)
        let encodedParams = try self.encode(params, strategy: strategy)
        
        let request = InvokeModelInput(
            body: encodedParams, contentType: "application/json", modelId: modelId)
        
        if let requestJson = String(data: encodedParams, encoding: .utf8) {
            logger.info("Request: \(requestJson)")
        }
        
        let response = try await self.bedrockRuntimeClient.invokeModel(input: request)
        
        guard response.contentType == "application/json", let data = response.body else {
            logger.error("Invalid Bedrock response: \(response)")
            throw BedrockRuntimeError.invalidResponse(response.body)
        }
        
        return data
    }
    
    /// Invokes a model using the Converse API (non-streaming)
    /// For Llama and Mistral models
    func converse(withId modelId: String, prompt: String) async throws -> Data {
        let modelType = getModelType(modelId)
        
        // ContentBlock은 enum 케이스 사용
        let contentBlock = BedrockRuntimeClientTypes.ContentBlock.text(prompt)
        
        // userMessage는 var로 선언하여 수정 가능하게 함
        var userMessage = BedrockRuntimeClientTypes.Message(role: .user)
        userMessage.content = [contentBlock]
        
        let inferenceConfig = BedrockRuntimeClientTypes.InferenceConfiguration(
            maxTokens: 2048,
            temperature: 0.7,
            topp: 0.9
        )
        
        let systemPrompt = SettingManager.shared.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        var systemBlocks: [BedrockRuntimeClientTypes.SystemContentBlock]? = nil
        if !systemPrompt.isEmpty && modelType.supportsSystemPrompt {
            // SystemContentBlock도 enum 케이스 사용
            let systemBlock = BedrockRuntimeClientTypes.SystemContentBlock.text(systemPrompt)
            systemBlocks = [systemBlock]
        }
        
        let request = ConverseInput(
            inferenceConfig: inferenceConfig,
            messages: [userMessage],
            modelId: modelId,
            system: systemBlocks
        )
        
        logger.info("Converse API Request for model: \(modelId)")
        
        let response = try await self.bedrockRuntimeClient.converse(input: request)
        
        // 수정: output.message를 안전하게 추출
        var standardResponse: [String: Any] = [:]
        if case let .message(convMessage) = response.output,
           convMessage.role == .assistant,
           let content = convMessage.content {
            var contentItems: [[String: String]] = []
            for item in content {
                if case let BedrockRuntimeClientTypes.ContentBlock.text(text) = item {
                    contentItems.append(["type": "text", "text": text])
                }
            }
            standardResponse["message"] = [
                "role": "assistant",
                "content": contentItems
            ]
        } else {
            standardResponse["message"] = [
                "role": "assistant",
                "content": [
                    ["type": "text", "text": "No valid response from model"]
                ]
            ]
        }
        
        let processedData = try JSONSerialization.data(withJSONObject: standardResponse)
        return processedData
    }
    
    func invokeModelStream(withId modelId: String, prompt: String) async throws
    -> AsyncThrowingStream<BedrockRuntimeClientTypes.ResponseStream, Swift.Error>
    {
        let modelType = getModelType(modelId)
        
        let strategy: JSONEncoder.KeyEncodingStrategy = (
            modelType == .claude ||
            modelType == .claude3 ||
            modelType == .novaPro ||
            modelType == .novaLite ||
            modelType == .novaMicro
        ) ? .convertToSnakeCase : .useDefaultKeys
        
        let params = getModelParameters(modelType: modelType, prompt: prompt)
        
        let encodedParams = try self.encode(params, strategy: strategy)
        let request = InvokeModelWithResponseStreamInput(
            body: encodedParams, contentType: "application/json", modelId: modelId)
        
        if let requestJson = String(data: encodedParams, encoding: .utf8) {
            logger.info("Request: \(requestJson)")
        }
        
        let output = try await self.bedrockRuntimeClient.invokeModelWithResponseStream(
            input: request)
        return output.body ?? AsyncThrowingStream { _ in }
    }
    
    /// Invokes a model using the Converse API (streaming)
    /// For Llama and Mistral models
    func converseStream(withId modelId: String, prompt: String) async throws
    -> AsyncThrowingStream<BedrockRuntimeClientTypes.ConverseStreamOutput, Swift.Error> {
        let modelType = getModelType(modelId)
        
        // userMessage 생성
        var userMessage = BedrockRuntimeClientTypes.Message(role: .user)
        let contentBlock = BedrockRuntimeClientTypes.ContentBlock.text(prompt)
        userMessage.content = [contentBlock]
        
        let inferenceConfig = BedrockRuntimeClientTypes.InferenceConfiguration(
            maxTokens: 2048,
            temperature: 0.7,
            topp: 0.9
        )
        
        let systemPrompt = SettingManager.shared.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        var systemBlocks: [BedrockRuntimeClientTypes.SystemContentBlock]? = nil
        if !systemPrompt.isEmpty && modelType.supportsSystemPrompt {
            let systemBlock = BedrockRuntimeClientTypes.SystemContentBlock.text(systemPrompt)
            systemBlocks = [systemBlock]
        }
        
        let request = ConverseStreamInput(
            inferenceConfig: inferenceConfig,
            messages: [userMessage],
            modelId: modelId,
            system: systemBlocks
        )
        
        logger.info("Converse API Stream Request for model: \(modelId)")
        
        let output = try await self.bedrockRuntimeClient.converseStream(input: request)
        
        return AsyncThrowingStream<BedrockRuntimeClientTypes.ConverseStreamOutput, Error> { continuation in
            Task {
                do {
                    guard let stream = output.stream else {
                        continuation.finish()
                        return
                    }
                    
                    for try await event in stream {
                        // 이미 event는 ResponseStream 타입이므로 그대로 전달합니다.
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    func buildClaudeMessageRequest(
        modelId: String,
        systemPrompt: String?,
        messages: [ClaudeMessageRequest.Message]
    ) -> ClaudeMessageRequest {
        let thinking = SettingManager.shared.enableModelThinking && modelId.contains("3-7") ? ClaudeMessageRequest.Thinking(budgetTokens: 2048, type: "enabled") : nil
        
        return ClaudeMessageRequest(
            maxTokens: 8192,
            thinking: thinking,
            system: systemPrompt,
            messages: messages,
            temperature: 1,
            topP: nil,
            topK: nil,
            stopSequences: nil
        )
    }
    
    func invokeClaudeModel(
        withId modelId: String, messages: [ClaudeMessageRequest.Message], systemPrompt: String?
    ) async throws -> Data {
        let requestBody = buildClaudeMessageRequest(modelId: modelId, systemPrompt: systemPrompt, messages: messages)
        
        let jsonData = try requestBody.encode(strategy: .convertToSnakeCase)
        
        let request = InvokeModelInput(
            body: jsonData, contentType: "application/json", modelId: modelId)
        let response = try await self.bedrockRuntimeClient.invokeModel(input: request)
        
        guard response.contentType == "application/json", let data = response.body else {
            logger.error("Invalid Bedrock response: \(response)")
            throw BedrockRuntimeError.invalidResponse(response.body)
        }
        
        return data
    }
    
    func invokeClaudeModelStream(
        withId modelId: String, messages: [ClaudeMessageRequest.Message], systemPrompt: String?
    ) async throws -> AsyncThrowingStream<BedrockRuntimeClientTypes.ResponseStream, Swift.Error> {
        let requestBody = buildClaudeMessageRequest(modelId: modelId, systemPrompt: systemPrompt, messages: messages)
        
        let jsonData = try requestBody.encode(strategy: .convertToSnakeCase)
        
        let request = InvokeModelWithResponseStreamInput(body: jsonData, contentType: "application/json", modelId: modelId)
        let output = try await self.bedrockRuntimeClient.invokeModelWithResponseStream(input: request)
        
        return output.body ?? AsyncThrowingStream { _ in }
    }
    
    //    MARK: -- Invoke Nova Model
    func invokeNovaModel(withId modelId: String, messages: [NovaModelParameters.Message], systemPrompt: String?) async throws -> Data {
        let requestBody = NovaModelParameters(
            system: systemPrompt.map { [NovaModelParameters.SystemMessage(text: $0)] },
            messages: messages
        )
        
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let jsonData = try encoder.encode(requestBody)
        
        let request = InvokeModelInput(
            body: jsonData,
            contentType: "application/json",
            modelId: modelId
        )
        
        if let requestJson = String(data: jsonData, encoding: .utf8) {
            logger.info("[BedrockClient] Nova Request: \(requestJson)")
        }
        
        let response = try await self.bedrockRuntimeClient.invokeModel(input: request)
        
        guard response.contentType == "application/json", let data = response.body else {
            logger.error("Invalid Bedrock response: \(response)")
            throw BedrockRuntimeError.invalidResponse(response.body)
        }
        
        return data
    }
    
    func invokeNovaModelStream(withId modelId: String, messages: [NovaModelParameters.Message], systemPrompt: String?) async throws -> AsyncThrowingStream<BedrockRuntimeClientTypes.ResponseStream, Error> {
        let requestBody = NovaModelParameters(
            system: systemPrompt.map { [NovaModelParameters.SystemMessage(text: $0)] },
            messages: messages
        )
        
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let jsonData = try encoder.encode(requestBody)
        
        let request = InvokeModelWithResponseStreamInput(
            body: jsonData, contentType: "application/json", modelId: modelId)
        let output = try await self.bedrockRuntimeClient.invokeModelWithResponseStream(
            input: request)
        
        return output.body ?? AsyncThrowingStream { _ in }
    }
    
    func invokeStableDiffusionModel(withId modelId: String, prompt: String) async throws -> Data {
        let isSD3 = modelId.contains("sd3")
        let isCore = modelId.contains("stable-image-core")
        let isUltra = modelId.contains("stable-image-ultra") || modelId.contains("sd3-ultra")
        
        let promptData: [String: Any]
        
        if isSD3 || isCore || isUltra {
            // SD3, Core, Ultra
            promptData = ["prompt": prompt]
        } else {
            // Standard Stable Diffusion (including SDXL)
            promptData = [
                "text_prompts": [["text": prompt]],
                "cfg_scale": 10,
                "seed": 0,
                "steps": 50,
                "samples": 1,
                "style_preset": "photographic",
            ]
        }
        
        let jsonData = try JSONSerialization.data(withJSONObject: promptData)
        
        let request = InvokeModelInput(
            body: jsonData,
            contentType: "application/json",
            modelId: modelId
        )
        
        let response = try await self.bedrockRuntimeClient.invokeModel(input: request)
        
        guard let responseBody = response.body else {
            throw NSError(
                domain: "BedrockRuntime", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Invalid response: Empty body"])
        }
        
        let json =
        try JSONSerialization.jsonObject(with: responseBody, options: []) as? [String: Any]
        
        if let images = json?["images"] as? [String], let base64Image = images.first,
           let imageData = Data(base64Encoded: base64Image)
        {
            
            // Process additional information for Ultra model
            if isUltra, let finishReasons = json?["finish_reasons"] as? [String?] {
                if let finishReason = finishReasons.first, finishReason != nil {
                    throw NSError(
                        domain: "BedrockRuntime", code: 3,
                        userInfo: [
                            NSLocalizedDescriptionKey: "Image generation error: \(finishReason!)"
                        ])
                }
            }
            
            return imageData
        } else if let artifacts = json?["artifacts"] as? [[String: Any]],
                  let firstArtifact = artifacts.first,
                  let base64Image = firstArtifact["base64"] as? String,
                  let imageData = Data(base64Encoded: base64Image)
        {
            
            // Process response for standard Stable Diffusion (including SDXL)
            if let finishReason = firstArtifact["finishReason"] as? String {
                if finishReason == "ERROR" || finishReason == "CONTENT_FILTERED" {
                    throw NSError(
                        domain: "BedrockRuntime", code: 3,
                        userInfo: [
                            NSLocalizedDescriptionKey: "Image generation error: \(finishReason)"
                        ])
                }
                print("Stable Diffusion generation - Finish Reason: \(finishReason)")
            }
            
            return imageData
        } else {
            throw NSError(
                domain: "BedrockRuntime", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to parse model response"])
        }
    }
    
    func listFoundationModels(
        byCustomizationType: BedrockClientTypes.ModelCustomization? = nil,
        byInferenceType: BedrockClientTypes.InferenceType? = BedrockClientTypes.InferenceType
            .onDemand,
        byOutputModality: BedrockClientTypes.ModelModality? = nil,
        byProvider: String? = nil
    ) async -> Result<[BedrockClientTypes.FoundationModelSummary], Error> {
        do {
            let request = ListFoundationModelsInput(
                byCustomizationType: byCustomizationType,
                byInferenceType: byInferenceType,
                byOutputModality: byOutputModality,
                byProvider: byProvider)
            
            let response = try await self.bedrockClient.listFoundationModels(input: request)
            
            if let modelSummaries = response.modelSummaries {
                return .success(modelSummaries)
            } else {
                logger.error("Invalid Bedrock response: \(response)")
                return .failure(
                    NSError(
                        domain: "BedrockError", code: 0,
                        userInfo: [NSLocalizedDescriptionKey: "Model summaries are missing"]))
            }
        } catch {
            logger.error("Error occurred: \(error)")
            return .failure(error)
        }
    }
    
    func listInferenceProfiles(
        maxResults: Int? = nil,
        nextToken: String? = nil,
        typeEquals: BedrockClientTypes.InferenceProfileType? = nil
    ) async -> [BedrockClientTypes.InferenceProfileSummary] {
        do {
            let input = AWSBedrock.ListInferenceProfilesInput(
                maxResults: maxResults,
                nextToken: nextToken,
                typeEquals: typeEquals
            )
            let response = try await self.bedrockClient.listInferenceProfiles(input: input)
            guard let summaries = response.inferenceProfileSummaries else {
                logger.warning("No inference profiles found in the response.")
                return []
            }
            logger.info("Fetched \(summaries.count) inference profiles.")
            return summaries
        } catch {
            logger.error("Failed to fetch inference profiles: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Helper function to determine the model type based on modelId
    func getModelType(_ modelId: String) -> ModelType {
        let parts = modelId.split(separator: ".")
        guard let modelName = parts.last else {
            print("Error: Invalid modelId: \(modelId)")
            return .unknown
        }
        
        if modelName.hasPrefix("claude") {
            return .claude
        } else if modelName.hasPrefix("titan-embed") {
            return .titanEmbed
        } else if modelName.hasPrefix("titan-e1t") {
            return .titanEmbed
        } else if modelName.hasPrefix("titan-image") {
            return .titanImage
        } else if modelName.hasPrefix("titan") {
            return .titan
        } else if modelName.hasPrefix("nova-pro"){
            return .novaPro
        } else if modelName.hasPrefix("nova-lite"){
            return .novaLite
        } else if modelName.hasPrefix("nova-micro"){
            return .novaMicro
        } else if modelName.hasPrefix("nova-canvas") {
            return .novaCanvas
        } else if modelName.hasPrefix("j2") {
            return .j2
        } else if modelName.hasPrefix("command") {
            return .cohereCommand
        } else if modelName.hasPrefix("embed") {
            return .cohereEmbed
        } else if modelName.hasPrefix("stable-") || modelName.hasPrefix("sd3-") {
            return .stableDiffusion
        } else if modelName.hasPrefix("llama2") {
            return .llama2
        } else if modelName.hasPrefix("llama3") {
            return .llama3
        } else if modelName.hasPrefix("mistral") || modelName.hasPrefix("mixtral") {
            return .mistral
        } else if modelName.hasPrefix("jamba-instruct") {
            return .jambaInstruct
        } else if modelName.hasPrefix("r1") {
            return .deepseekr1
        } else {
            return .unknown
        }
    }
    
    /// Function to get model parameters
    func getModelParameters(modelType: ModelType, prompt: String) -> ModelParameters {
        switch modelType {
        case .claude:
            return ClaudeModelParameters(prompt: "Human: \(prompt)\n\nAssistant:")
        case .titan:
            let textGenerationConfig = TitanModelParameters.TextGenerationConfig(
                temperature: 0,
                topP: 1.0,
                maxTokenCount: 3072,
                stopSequences: []
            )
            return TitanModelParameters(
                inputText: "User: \(prompt)\n\nBot:", textGenerationConfig: textGenerationConfig)
        case .titanEmbed:
            // No system prompt for embedding models
            return TitanEmbedModelParameters(inputText: prompt)
        case .titanImage:
            // No system prompt for image generation models
            // Create TitanImageModelParameters with prompt length validation
            if prompt.count > 512 {
                logger.info("Titan image prompt truncated from \(prompt.count) to 512 characters")
            }
            return TitanImageModelParameters(inputText: prompt)
        case .novaPro, .novaLite, .novaMicro:
            // ADDED Amazon Nova ModelParameters. https://docs.aws.amazon.com/nova/latest/userguide/invoke.html
            let message = NovaModelParameters.Message(role: "user", content: [NovaModelParameters.Message.MessageContent(text: prompt)])
            let systemMessage = NovaModelParameters.SystemMessage(text: "You are a helpful AI assistant.") // Optional: Add system message if needed
            return NovaModelParameters(system: [systemMessage], messages: [message])
        case .novaCanvas:
            // No system prompt for image generation models
            return NovaCanvasModelParameters(
                taskType: "TEXT_IMAGE",
                text: prompt
            )
        case .j2:
            return AI21ModelParameters(prompt: prompt, temperature: 0.5, topP: 0.5, maxTokens: 200)
        case .cohereCommand:
            return CohereModelParameters(
                prompt: prompt, temperature: 0.9, p: 0.75, k: 0, maxTokens: 20)
        case .cohereEmbed:
            // No system prompt for embedding models
            return CohereEmbedModelParameters(texts: [prompt], inputType: .searchDocument)
        case .mistral, .llama2, .llama3:
            // These models now use the Converse API instead
            // Handled in separate methods: invokeConverseModel and invokeConverseModelStream
            return ClaudeModelParameters(prompt: "Placeholder - should not be used")  // This won't actually be used
        case .jambaInstruct:
            return JambaInstructModelParameters(
                messages: [
                    JambaInstructModelParameters.Message(role: "user", content: prompt)
                ],
                max_tokens: 4096,
                temperature: 0.7,
                top_p: 0.9
            )
        default:
            return ClaudeModelParameters(prompt: "Human: \(prompt)\n\nAssistant:")
        }
    }
    
    public func decode<T: Decodable>(_ data: Data) throws -> T {
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }
    public func decode<T: Decodable>(json: String) throws -> T {
        let data = json.data(using: .utf8)!
        return try self.decode(data)
    }
    private func encode<T: Encodable>(
        _ value: T, strategy: JSONEncoder.KeyEncodingStrategy = .useDefaultKeys
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = strategy  // Use the provided strategy, default to .useDefaultKeys
        return try encoder.encode(value)
    }
    private func encode<T: Encodable>(_ value: T) throws -> String {
        let data: Data = try self.encode(value)
        return String(data: data, encoding: .utf8) ?? "error when encoding the string"
    }
}

// MARK: - NSAlert Extension for Error Handling

extension NSAlert {
    static func presentErrorAlert(title: String, message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = title
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}

enum ModelType {
    case claude, claude3, llama2, llama3, mistral, titan, titanImage, titanEmbed, cohereCommand, cohereEmbed, j2, stableDiffusion, jambaInstruct, novaPro, novaLite, novaMicro, novaCanvas, deepseekr1, unknown
    
    var usesConverseAPI: Bool {
        switch self {
        case .llama2, .llama3, .mistral, .deepseekr1:
            return true
        default:
            return false
        }
    }
    
    var supportsSystemPrompt: Bool {
        switch self {
        case .claude, .claude3, .llama2, .llama3, .mistral, .novaPro, .novaLite, .novaMicro, .titan, .cohereCommand, .jambaInstruct, .deepseekr1:
            return true
        case .titanEmbed, .titanImage, .cohereEmbed, .stableDiffusion, .novaCanvas, .j2, .unknown:
            return false
        }
    }
}

public protocol ModelParameters: Encodable {
    func encode(strategy: JSONEncoder.KeyEncodingStrategy?) throws -> Data
}

extension ModelParameters {
    public func encode(strategy: JSONEncoder.KeyEncodingStrategy? = nil) throws -> Data {
        let encoder = JSONEncoder()
        if let strategy {
            encoder.keyEncodingStrategy = strategy
        }
        return try encoder.encode(self)
    }
}

// Extend structs to include AI21 and Cohere model parameters
public struct AI21ModelParameters: ModelParameters {
    let prompt: String
    let temperature: Float
    let topP: Float
    let maxTokens: Int
    // Add additional parameters like penalties if needed
}

public struct JambaInstructModelParameters: ModelParameters {
    public var messages: [Message]
    public var max_tokens: Int
    public var temperature: Double
    public var top_p: Double
    
    public struct Message: Codable {
        public let role: String
        public let content: String
    }
    
    public init(
        messages: [Message],
        max_tokens: Int = 4096,
        temperature: Double = 0.7,
        top_p: Double = 0.9
    ) {
        self.messages = messages
        self.max_tokens = max_tokens
        self.temperature = temperature
        self.top_p = top_p
    }
}

public enum ReturnLikelihoods: String, Codable {
    case generation = "GENERATION"
    case all = "ALL"
    case none = "NONE"
}

public struct CohereModelParameters: ModelParameters {
    let prompt: String
    let temperature: Float
    let p: Float
    let k: Float
    let maxTokens: Int
    let stopSequences: [String]
    let returnLikelihoods: ReturnLikelihoods
    
    // Initialize all the parameters with default values, so you can omit them when you don't need to set them
    init(prompt: String,
         temperature: Float = 0.7,
         p: Float = 0.9,
         k: Float = 0,
         maxTokens: Int = 400,
         stopSequences: [String] = [],
         returnLikelihoods: ReturnLikelihoods = .none)
    {
        self.prompt = prompt
        self.temperature = temperature
        self.p = p
        self.k = k
        self.maxTokens = maxTokens
        self.stopSequences = stopSequences
        self.returnLikelihoods = returnLikelihoods
    }
    
    // Define the CodingKeys enum for custom JSON key names
    enum CodingKeys: String, CodingKey {
        case prompt
        case temperature
        case p
        case k
        case maxTokens = "max_tokens"
        case stopSequences = "stop_sequences"
        case returnLikelihoods = "return_likelihoods"
    }
}

public struct CohereEmbedModelParameters: ModelParameters, Encodable {
    let texts: [String]
    let inputType: EmbedInputType
    let truncate: TruncateOption?
    
    init(
        texts: [String],
        inputType: EmbedInputType,
        truncate: TruncateOption? = nil
    ) {
        self.texts = texts
        self.inputType = inputType
        self.truncate = truncate
    }
    
    enum EmbedInputType: String, Codable {
        case searchDocument = "search_document"
        case searchQuery = "search_query"
        case classification = "classification"
        case clustering = "clustering"
    }
    
    enum TruncateOption: String, Codable {
        case none = "NONE"
        case left = "LEFT"
        case right = "RIGHT"
    }
    
    // Define the CodingKeys enum for custom JSON key names
    enum CodingKeys: String, CodingKey {
        case texts
        case inputType = "input_type"
        case truncate
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(texts, forKey: .texts)
        try container.encode(inputType, forKey: .inputType)
        try container.encodeIfPresent(truncate, forKey: .truncate)
    }
}

public struct TitanEmbedModelParameters: ModelParameters {
    let inputText: String
}

struct TitanImageModelParameters: ModelParameters {
    var taskType: String
    var textToImageParams: TextToImageParams
    var imageGenerationConfig: ImageGenerationConfig
    
    struct TextToImageParams: Codable {
        var text: String
    }
    
    struct ImageGenerationConfig: Codable {
        var numberOfImages: Int
        var quality: String
        var cfgScale: Double
        var height: Int
        var width: Int
        var seed: Int?
    }
    
    // Initialize with default values and the input text
    init(
        inputText: String, numberOfImages: Int = 1, quality: String = "standard",
        cfgScale: Double = 8.0, height: Int = 512, width: Int = 512, seed: Int? = nil
    ) {
        self.taskType = "TEXT_IMAGE"
        
        // Titan Image Generator has a 512 character limit for prompts
        let limitedText = inputText.count > 512 ? String(inputText.prefix(512)) : inputText
        self.textToImageParams = TextToImageParams(text: limitedText)
        
        self.imageGenerationConfig = ImageGenerationConfig(
            numberOfImages: numberOfImages, quality: quality, cfgScale: cfgScale, height: height,
            width: width, seed: seed)
        
        if limitedText.count < inputText.count {
            print("Warning: Titan image prompt truncated to 512 characters (original: \(inputText.count) characters)")
        }
    }
}

struct NovaCanvasModelParameters: ModelParameters {
    var taskType: String
    var textToImageParams: TextToImageParams
    var imageGenerationConfig: ImageGenerationConfig
    
    struct TextToImageParams: Codable {
        var text: String
        var negativeText: String?
    }
    
    struct ImageGenerationConfig: Codable {
        var width: Int
        var height: Int
        var quality: String
        var cfgScale: Float
        var seed: Int
        var numberOfImages: Int
    }
    
    init(
        taskType: String = "TEXT_IMAGE",
        text: String,
        negativeText: String? = nil,
        width: Int = 1024,
        height: Int = 1024,
        quality: String = "premium",
        cfgScale: Float = 8.0,
        seed: Int = 0,
        numberOfImages: Int = 1
    ) {
        self.taskType = taskType
        self.textToImageParams = TextToImageParams(text: text, negativeText: negativeText)
        self.imageGenerationConfig = ImageGenerationConfig(
            width: width,
            height: height,
            quality: quality,
            cfgScale: cfgScale,
            seed: seed,
            numberOfImages: numberOfImages
        )
    }
}

public struct ClaudeModelParameters: ModelParameters {
    public var prompt: String
    public var temperature: Double
    public var topP: Double
    public var topK: Int
    public var maxTokensToSample: Int
    public var stopSequences: [String]
    
    public init(
        prompt: String,
        temperature: Double = 1.0,
        topP: Double = 1.0,
        topK: Int = 250,
        maxTokensToSample: Int = 8191,
        stopSequences: [String] = ["\n\nHuman:"]
    ) {
        self.prompt = prompt
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.maxTokensToSample = maxTokensToSample
        self.stopSequences = stopSequences
    }
}

public struct ClaudeMessageRequest: ModelParameters {
    public struct Thinking: ModelParameters {
        public let budgetTokens: Int
        public let type: String
    }
    
    public let anthropicVersion: String = "bedrock-2023-05-31"
    public let maxTokens: Int
    public let thinking: Thinking?
    public let system: String?
    public let messages: [Message]
    public let temperature: Float?
    public let topP: Float?
    public let topK: Int?
    public let stopSequences: [String]?
    
    // Message structure definition
    public struct Message: Codable {
        let role: String
        let content: [Content]
        
        // Content structure definition
        struct Content: Codable {
            var type: String
            var text: String?
            var source: ImageSource?
            
            // Image source structure definition
            struct ImageSource: Codable {
                let type: String = "base64"
                let mediaType: String
                let data: String
                
                enum CodingKeys: String, CodingKey {
                    case type
                    case mediaType = "media_type"
                    case data
                }
            }
        }
    }
}

public struct LLamaMistralModelParameters: ModelParameters {
    public var prompt: String
    public var maxTokens: Int
    public var temperature: Double
    public var topP: Double
    public var topK: Double?
    
    // Included default values for stop and topK to align with the rest of the structure
    public init(
        prompt: String,
        maxTokens: Int = 4096,
        temperature: Double = 1.0,
        topP: Double = 0.9,
        topK: Double? = nil
    ) {
        self.prompt = prompt
        // Ensured maxTokens cannot exceed 4096.
        self.maxTokens = min(maxTokens, 4096)
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
    }
}

// MARK: - Amazon Nova Model Parameters
public struct NovaModelParameters: ModelParameters {
    public let system: [SystemMessage]?
    public let messages: [Message]
    public let inferenceConfig: InferenceConfig?
    
    public struct SystemMessage: Codable {
        public let text: String
        
        public init(text: String) {
            self.text = text
        }
    }
    
    public struct Message: Codable {
        public let role: String
        public let content: [MessageContent]
        
        public init(role: String, content: [MessageContent]) {
            self.role = role
            self.content = content
        }
        
        public struct MessageContent: Codable {
            public var text: String?
            public var image: ImageContent?
            
            public init(text: String? = nil, image: ImageContent? = nil) {
                self.text = text
                self.image = image
            }
            
            public struct ImageContent: Codable {
                public let format: ImageFormat
                public let source: ImageSource
                
                public init(format: ImageFormat, source: ImageSource) {
                    self.format = format
                    self.source = source
                }
                
                public enum ImageFormat: String, Codable {
                    case jpeg, png, gif, webp
                }
                
                public struct ImageSource: Codable {
                    public let bytes: String
                    
                    public init(bytes: String) {
                        self.bytes = bytes
                    }
                }
            }
        }
    }
    
    public struct InferenceConfig: Codable {
        public let maxNewTokens: Int?
        public let temperature: Float?
        public let topP: Float?
        public let topK: Int?
        public let stopSequences: [String]?
        
        enum CodingKeys: String, CodingKey {
            case maxNewTokens = "max_new_tokens"
            case temperature
            case topP = "top_p"
            case topK = "top_k"
            case stopSequences = "stop_sequences"
        }
        
        public init(
            maxNewTokens: Int? = nil,
            temperature: Float? = nil,
            topP: Float? = nil,
            topK: Int? = nil,
            stopSequences: [String]? = nil
        ) {
            self.maxNewTokens = maxNewTokens
            self.temperature = temperature
            self.topP = topP
            self.topK = topK
            self.stopSequences = stopSequences
        }
    }
    
    public init(
        system: [SystemMessage]? = nil,
        messages: [Message],
        inferenceConfig: InferenceConfig? = nil
    ) {
        self.system = system
        self.messages = messages
        self.inferenceConfig = inferenceConfig
    }
}

// MARK: - TitanModelParameters

public struct TitanModelParameters: ModelParameters {
    public let inputText: String  // Changed from `prompt`
    public let textGenerationConfig: TextGenerationConfig
    
    public struct TextGenerationConfig: Encodable {
        let temperature: Double
        let topP: Double
        let maxTokenCount: Int  // Ensure this doesn't exceed 8000
        let stopSequences: [String]
    }
}

// MARK: - ModelType Enumeration

// Model response protocols
protocol ModelResponse {}

public struct InvokeClaudeResponse: ModelResponse, Decodable {
    public let completion: String
    public let stop_reason: String
}

// 응답 모델 정의
struct ClaudeMessageResponse: Codable {
    let id: String
    let model: String
    let type: String
    let role: String
    let content: [Content]
    let stopReason: String
    let stopSequence: String?
    let usage: Usage
    
    struct Content: Codable {
        let type: String
        let text: String?
    }
    
    struct Usage: Codable {
        let inputTokens: Int
        let outputTokens: Int
        
        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case id, model, type, role, content
        case stopReason = "stop_reason"
        case stopSequence = "stop_sequence"
        case usage
    }
}

public struct InvokeNovaResponse: ModelResponse, Decodable {
    public let output: Output
    public let stopReason: String
    public let usage: Usage
    
    public struct Output: Decodable {
        public let message: Message
    }
    
    public struct Message: Decodable {
        public let content: [Content]
        public let role: String
        
        public struct Content: Decodable {
            public let text: String
        }
    }
    
    public struct Usage: Decodable {
        public let inputTokens: Int
        public let outputTokens: Int
        public let totalTokens: Int
    }
    
    enum CodingKeys: String, CodingKey {
        case output
        case stopReason = "stopReason"
        case usage
    }
}

public struct InvokeTitanResponse: ModelResponse, Decodable {
    public let results: [InvokeTitanResult]
}

public struct InvokeTitanEmbedResponse: ModelResponse, Decodable {
    public let embedding: [Float]
}

public struct InvokeTitanImageResponse: ModelResponse, Decodable {
    public let images: [Data]
}

public struct InvokeNovaCanvasResponse: ModelResponse, Decodable {
    public let images: [Data]
    public let error: String?
    
    enum CodingKeys: String, CodingKey {
        case images
        case error
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode base64-encoded images and convert them to Data
        let base64Images = try container.decode([String].self, forKey: .images)
        self.images = try base64Images.map { base64Str in
            guard let imageData = Data(base64Encoded: base64Str) else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: container.codingPath,
                        debugDescription: "Invalid base64 image string."
                    )
                )
            }
            return imageData
        }
        
        // Decode optional error field
        self.error = try container.decodeIfPresent(String.self, forKey: .error)
    }
}

public struct InvokeTitanResult: Decodable {
    public let outputText: String
    // Add any other properties you need from the Titan response
}

public struct InvokeAI21Response: ModelResponse, Decodable {
    public let completions: [AI21Completion]
}

public struct InvokeJambaInstructResponse: ModelResponse, Decodable {
    public let id: String
    public let choices: [Choice]
    public let usage: Usage
    
    public struct Choice: Decodable {
        public let index: Int
        public let message: Message
        public let finishReason: String?
        
        public struct Message: Decodable {
            public let role: String
            public let content: String
        }
    }
    
    public struct Usage: Decodable {
        public let promptTokens: Int?
        public let completionTokens: Int?
        public let totalTokens: Int?
    }
}

public struct AI21Completion: Decodable {
    public let data: AI21Data
}

public struct AI21Data: Decodable {
    public let text: String
    // Add any other properties you need from the AI21 response
}

public struct InvokeCommandResponse: ModelResponse, Decodable {
    public let generations: [AI21Data]
}

public struct InvokeCohereEmbedResponse: ModelResponse, Decodable {
    public let embeddings: [[Float]]
}

public struct InvokeStableDiffusionResponse: ModelResponse, Decodable {
    public let body: Data  // Specify the type here
}

public struct MistralData: Decodable {
    public let text: String
    public let stop_reason: String?
}

public struct InvokeMistralResponse: ModelResponse, Decodable {
    public let outputs: [MistralData]
}

public struct InvokeLlama2Response: ModelResponse, Decodable {
    public let generation: String
}

public struct InvokeLlama3Response: ModelResponse, Decodable {
    public let generation: String
}

// MARK: - Errors
enum STSError: Error {
    case invalidCredentialsResponse(String)
    case invalidAssumeRoleWithWebIdentityResponse(String)
}
enum BedrockRuntimeError: Error {
    case invalidResponse(Data?)
    case invalidURL
    case requestFailed
    case decodingFailed
}
enum BedrockError: Error {
    /// The response from Bedrock was invalid.
    case invalidResponse(String?)
    /// The AWS credentials have expired.
    case expiredToken(String?)
    /// An unknown error occurred.
    case unknown(String?)
    
    init(error: Error) {
        if let awsError = error as? AWSClientRuntime.AWSServiceError {
            if let typeName = awsError.typeName?.lowercased(), typeName.contains("expiredtoken") {
                self = .expiredToken(awsError.message)
            } else {
                self = .unknown(awsError.message)
            }
        } else if let commonError = error as? AwsCommonRuntimeKit.CommonRunTimeError {
            self = .invalidResponse(commonError.localizedDescription)
        } else {
            self = .unknown(error.localizedDescription)
        }
    }
}
