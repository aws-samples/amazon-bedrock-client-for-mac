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
import Smithy

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
            self.isLoggedIn = true
        } catch {
            logger.error("Failed to initialize Backend: \(error)")
            
            // Create Backend with default credentials when an error occurs
            do {
                let defaultCredentialProvider = try DefaultAWSCredentialIdentityResolverChain()
                self.backend = Backend(
                    region: "us-east-1",
                    profile: "default",
                    endpoint: "",
                    runtimeEndpoint: "",
                    awsCredentialIdentityResolver: defaultCredentialProvider
                )
            } catch {
                fatalError("Failed to create even fallback Backend: \(error)")
            }
            
            // Extract more detailed error information
            if let commonRuntimeError = error as? AwsCommonRuntimeKit.CommonRunTimeError {
                // Use Mirror to access internal properties of CommonRunTimeError
                let mirror = Mirror(reflecting: commonRuntimeError)
                
                // Try to find the crtError property
                if let crtErrorProperty = mirror.children.first(where: { $0.label == "crtError" }) {
                    if let crtError = crtErrorProperty.value as? Any {
                        let crtErrorMirror = Mirror(reflecting: crtError)
                        
                        // Extract code, message and name from crtError
                        var errorCode: String = "unknown"
                        var errorMessage: String = "No detailed message available"
                        var errorName: String = "Unknown error"
                        
                        for child in crtErrorMirror.children {
                            if child.label == "code", let code = child.value as? Int {
                                errorCode = String(code)
                            } else if child.label == "message", let message = child.value as? String {
                                errorMessage = message
                            } else if child.label == "name", let name = child.value as? String {
                                errorName = name
                            }
                        }
                        
                        alertMessage = "AWS error (\(errorName)): \(errorMessage) (Code: \(errorCode))"
                    } else {
                        alertMessage = "AWS error: \(commonRuntimeError.localizedDescription)"
                    }
                } else {
                    alertMessage = "AWS error: \(commonRuntimeError.localizedDescription)"
                }
            } else if let awsServiceError = error as? AWSClientRuntime.AWSServiceError {
                alertMessage = "AWS service error: \(awsServiceError.message)"
            } else {
                alertMessage = "Error: \(error.localizedDescription)"
            }
            
            self.isLoggedIn = false
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
    let logger = Logger(label: "Backend")
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
        
        // Try to initialize credentials in order of preference
        do {
            // First try: Use the specified profile from SettingManager
            if let selectedProfile = SettingManager.shared.profiles.first(where: { $0.name == profile }) {
                if selectedProfile.type == .sso {
                    self.awsCredentialIdentityResolver = try SSOAWSCredentialIdentityResolver(profileName: profile)
                    logger.info("Using SSO credentials for profile: \(profile)")
                } else {
                    self.awsCredentialIdentityResolver = try ProfileAWSCredentialIdentityResolver(profileName: profile)
                    logger.info("Using standard credentials for profile: \(profile)")
                }
            }
            // Second try: Use default profile if specified profile not found
            else if profile != "default" {
                logger.warning("Profile '\(profile)' not found, falling back to 'default' profile")
                self.awsCredentialIdentityResolver = try ProfileAWSCredentialIdentityResolver(profileName: "default")
            }
            // Third try: Use default profile directly
            else {
                logger.info("Using default profile")
                self.awsCredentialIdentityResolver = try ProfileAWSCredentialIdentityResolver(profileName: "default")
            }
        } catch {
            // Final try: Use DefaultAWSCredentialIdentityResolverChain as last resort
            logger.warning("Failed to initialize with profile '\(profile)': \(error.localizedDescription)")
            logger.info("Attempting to use DefaultAWSCredentialIdentityResolverChain")
            
            do {
                self.awsCredentialIdentityResolver = try DefaultAWSCredentialIdentityResolverChain()
                logger.info("Successfully initialized with DefaultAWSCredentialIdentityResolverChain")
            } catch {
                // If even the default chain fails, we have no choice but to throw
                logger.error("Failed to initialize with DefaultAWSCredentialIdentityResolverChain: \(error.localizedDescription)")
                throw error
            }
        }
        
        logger.info("Backend initialized with region: \(region), profile: \(profile), endpoint: \(endpoint), runtimeEndpoint: \(runtimeEndpoint)")
    }
    
    /// Initializes Backend with a custom credential resolver
    init(region: String, profile: String, endpoint: String, runtimeEndpoint: String, awsCredentialIdentityResolver: any AWSCredentialIdentityResolver) {
        self.region = region
        self.profile = profile
        self.endpoint = endpoint
        self.runtimeEndpoint = runtimeEndpoint
        self.awsCredentialIdentityResolver = awsCredentialIdentityResolver
        
        logger.info(
            "Backend initialized with custom credential resolver, region: \(region), profile: \(profile)"
        )
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
    
    // MARK: - Core Functionality
    
    /// Check if a model is an image generation model
    func isImageGenerationModel(_ modelId: String) -> Bool {
        let id = modelId.lowercased()
        return id.contains("titan-image") ||
        id.contains("nova-canvas") ||
        id.contains("stable-") ||
        id.contains("sd3-")
    }
    
    func isReasoningSupported(_ modelId: String) -> Bool {
        let modelType = getModelType(modelId)
        switch modelType {
        case .claude37:
            // Claude 3.7 models and DeepSeek R1 support advanced reasoning
            return true
        case .claude, .claude3, .llama2, .llama3, .mistral, .titan, .titanEmbed, .titanImage,
                .cohereCommand, .cohereEmbed, .stableDiffusion, .novaCanvas, .j2,
                .novaPro, .novaLite, .novaMicro, .jambaInstruct, .deepseekr1, .unknown:
            return false
        }
    }
    
    /// Check if a model has configurable reasoning (can be toggled on/off)
    func hasConfigurableReasoning(_ modelId: String) -> Bool {
        // Only Claude 3.7 has configurable reasoning
        return getModelType(modelId) == .claude3 && modelId.contains("claude-3-7")
    }
    
    /// Check if a model has always-on reasoning (can't be disabled)
    func hasAlwaysOnReasoning(_ modelId: String) -> Bool {
        return getModelType(modelId) == .deepseekr1
    }
    
    /// Check if a model is an embedding model
    func isEmbeddingModel(_ modelId: String) -> Bool {
        let id = modelId.lowercased()
        return id.contains("embed") || id.contains("titan-e1t")
    }
    
    /// Check if a model supports document chat
    func isDocumentChatSupported(_ modelId: String) -> Bool {
        let modelType = getModelType(modelId)
        switch modelType {
        case .claude, .claude3, .claude37, .llama2, .llama3, .novaPro, .novaLite, .titan,
                .mistral, .cohereCommand, .deepseekr1, .jambaInstruct:
            // Handle specific exceptions
            if modelType == .titan && modelId.contains("text-premier") {
                return false
            }
            if modelType == .mistral && modelId.contains("small") {
                return false
            }
            if modelType == .cohereCommand && modelId.contains("light") {
                return false
            }
            if modelType == .jambaInstruct {
                return false
            }
            return true
        case .novaMicro, .titanEmbed, .titanImage, .cohereEmbed,
                .stableDiffusion, .novaCanvas, .j2, .unknown:
            return false
        }
    }
    
    /// Check if a model supports system prompts
    func isSystemPromptSupported(_ modelId: String) -> Bool {
        let modelType = getModelType(modelId)
        switch modelType {
        case .claude, .claude3, .claude37, .llama2, .llama3, .novaPro, .novaLite,
                .novaMicro, .jambaInstruct, .deepseekr1, .jambaInstruct, .mistral:
            // Handle specific exceptions
            if modelId.contains("mistral") && modelId.contains("instruct") {
                return false
            }
            return true
        case .titan, .titanEmbed, .titanImage, .cohereEmbed, .cohereCommand,
                .stableDiffusion, .novaCanvas, .j2, .unknown:
            return false
        }
    }
    
    /// Check if a model supports vision capabilities
    func isVisionSupported(_ modelId: String) -> Bool {
        let modelType = getModelType(modelId)
        switch modelType {
        case .claude3, .claude37, .novaPro, .novaLite, .llama3:
            // Only specific Claude 3 models support vision
            if modelId.contains("claude-3") {
                // Claude 3.5 Haiku doesn't support vision
                if modelId.contains("haiku") {
                    return false
                }
                return true
            }
            // Nova Pro supports vision, but Nova Lite doesn't
            if modelId.contains("nova-pro") {
                return true
            }
            // Only Llama 3.2 11b and 90b support vision
            if modelId.contains("llama3") && (modelId.contains("3-2-11b") || modelId.contains("3-2-90b")) {
                return true
            }
            return false
        default:
            return false
        }
    }
    
    /// Check if a model supports tool use
    func isToolUseSupported(_ modelId: String) -> Bool {
        let modelType = getModelType(modelId)
        switch modelType {
        case .claude3, .claude37, .novaPro, .novaLite, .novaMicro, .cohereCommand,
                .mistral, .llama3, .jambaInstruct:
            // Claude 3 models all support tool use
            if modelId.contains("claude-3") {
                return true
            }
            // Nova models all support tool use
            if modelId.contains("nova-") {
                return true
            }
            // Only Command R and R+ support tool use
            if modelId.contains("command-r") {
                return true
            }
            // Mistral Large supports tool use, but not Mistral Instruct
            if modelId.contains("mistral-large") {
                return true
            }
            // Llama 3.1 and 3.2 larger models support tool use
            if (modelId.contains("llama3-1") ||
                modelId.contains("llama3-2-11b") ||
                modelId.contains("llama3-2-90b")) {
                return true
            }
            // Jamba 1.5 Large and Mini support tool use
            if modelId.contains("jamba") &&
                (modelId.contains("large") || modelId.contains("mini")) {
                return true
            }
            return false
        default:
            return false
        }
    }
    
    /// Check if a model supports streaming tool use
    func isStreamingToolUseSupported(_ modelId: String) -> Bool {
        let modelType = getModelType(modelId)
        switch modelType {
        case .claude3, .claude37, .novaPro, .novaLite, .novaMicro, .cohereCommand, .jambaInstruct:
            // Claude 3 models support streaming tool use
            if modelId.contains("claude-3") {
                return true
            }
            // Nova models support streaming tool use
            if modelId.contains("nova-") {
                return true
            }
            // Command R and R+ support streaming tool use
            if modelId.contains("command-r") {
                return true
            }
            // Jamba 1.5 Large and Mini support streaming tool use
            if modelId.contains("jamba") &&
                (modelId.contains("large") || modelId.contains("mini")) {
                return true
            }
            return false
        default:
            return false
        }
    }
    
    /// Check if a model supports guardrails
    func isGuardrailsSupported(_ modelId: String) -> Bool {
        let modelType = getModelType(modelId)
        
        // Models that don't support guardrails
        if modelId.contains("3-5-haiku") {
            return false
        }
        if modelId.contains("command-r") {
            return false
        }
        if modelId.contains("jamba-instruct-v1") {
            return false
        }
        
        return true
    }
    
    /// Helper function to determine the model type based on modelId
    func getModelType(_ modelId: String) -> ModelType {
        let parts = modelId.split(separator: ".")
        guard let modelName = parts.last else {
            print("Error: Invalid modelId: \(modelId)")
            return .unknown
        }
        
        if modelName.hasPrefix("claude-3-7") {
            return .claude37
        } else if modelName.hasPrefix("claude-3") {
            return .claude3
        } else if modelName.hasPrefix("claude") {
            return .claude
        } else if modelName.hasPrefix("titan-embed") || modelName.hasPrefix("titan-e1t") {
            return .titanEmbed
        } else if modelName.hasPrefix("titan-image") {
            return .titanImage
        } else if modelName.hasPrefix("titan") {
            return .titan
        } else if modelName.hasPrefix("nova-pro") {
            return .novaPro
        } else if modelName.hasPrefix("nova-lite") {
            return .novaLite
        } else if modelName.hasPrefix("nova-micro") {
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
    
    func getDefaultInferenceConfig(for modelType: ModelType) -> BedrockRuntimeClientTypes.InferenceConfiguration {
        switch modelType {
        case .claude37:
            let isThinkingEnabled = SettingManager.shared.enableModelThinking
            
            if isThinkingEnabled {
                return BedrockRuntimeClientTypes.InferenceConfiguration(
                    maxTokens: 64000,
                    temperature: 1.0
                )
            } else {
                return BedrockRuntimeClientTypes.InferenceConfiguration(
                    maxTokens: 8192,
                    temperature: 0.9,
                    topp: 0.7
                )
            }
        case .claude, .claude3:
            return BedrockRuntimeClientTypes.InferenceConfiguration(
                maxTokens: 4096,
                temperature: 0.9,
                topp: 0.7
            )
        case .titan:
            return BedrockRuntimeClientTypes.InferenceConfiguration(
                maxTokens: 3072,
                temperature: 0,
                topp: 1.0
            )
        case .novaPro, .novaLite, .novaMicro:
            return BedrockRuntimeClientTypes.InferenceConfiguration(
                maxTokens: 4096,
                temperature: 0.7,
                topp: 0.9
            )
        case .deepseekr1:
            return BedrockRuntimeClientTypes.InferenceConfiguration(
                maxTokens: 8192,
                temperature: 1
            )
        case .mistral, .jambaInstruct:
            return BedrockRuntimeClientTypes.InferenceConfiguration(
                maxTokens: 4096,
                temperature: 0.7,
                topp: 0.9
            )
        case .llama2, .llama3:
            return BedrockRuntimeClientTypes.InferenceConfiguration(
                maxTokens: 2048,
                temperature: 0.7,
                topp: 0.9
            )
        case .cohereCommand:
            return BedrockRuntimeClientTypes.InferenceConfiguration(
                maxTokens: 400,
                temperature: 0.9,
                topp: 0.75
            )
        case .j2:
            return BedrockRuntimeClientTypes.InferenceConfiguration(
                maxTokens: 200,
                temperature: 0.5,
                topp: 0.5
            )
        default:
            return BedrockRuntimeClientTypes.InferenceConfiguration(
                maxTokens: 4096,
                temperature: 0.7,
                topp: 0.9
            )
        }
    }
    
    
    // MARK: - Converse Stream API (Unified for Text Models)
    
    /// Unified converseStream method for all text generation models
    /// This is the primary method that should be used for all text-based LLMs
    func converseStream(
        withId modelId: String,
        messages: [BedrockRuntimeClientTypes.Message],
        systemContent: [BedrockRuntimeClientTypes.SystemContentBlock]? = nil,
        inferenceConfig: BedrockRuntimeClientTypes.InferenceConfiguration? = nil,
        toolConfig: BedrockRuntimeClientTypes.ToolConfiguration? = nil
    ) async throws -> AsyncThrowingStream<BedrockRuntimeClientTypes.ConverseStreamOutput, Error> {
        let modelType = getModelType(modelId)
        
        // Create default inference config if not provided
        let config = inferenceConfig ?? getDefaultInferenceConfig(for: modelType)
        
        // Create converse stream request
        var request = ConverseStreamInput(
            inferenceConfig: config,
            messages: messages,
            modelId: modelId,
            system: isSystemPromptSupported(modelId) ? systemContent : nil
        )
        
        // Add tool configuration if provided
        if let tools = toolConfig {
            request.toolConfig = tools
        }
        
        // Add reasoning configuration only for models that support configurable reasoning
        // Skip models with always-on reasoning like deepseek-r1
        if isReasoningSupported(modelId) && !hasAlwaysOnReasoning(modelId) {
            let isThinkingEnabled = SettingManager.shared.enableModelThinking
            
            if isThinkingEnabled {
                // Create reasoning configuration
                do {
                    let reasoningConfig = [
                        "reasoning_config": [
                            "type": "enabled",
                            "budget_tokens": 2048
                        ]
                    ]
                    
                    request.additionalModelRequestFields = try Document.make(from: reasoningConfig)
                } catch {
                    logger.error("Failed to create reasoning config document: \(error)")
                }
            }
        }
        
        logger.info("Converse API Stream Request for model: \(modelId)")
        
        // Make API call
        let output = try await self.bedrockRuntimeClient.converseStream(input: request)
        
        return AsyncThrowingStream<BedrockRuntimeClientTypes.ConverseStreamOutput, Error> { continuation in
            Task {
                do {
                    guard let stream = output.stream else {
                        continuation.finish()
                        return
                    }
                    
                    for try await event in stream {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    
    
    // MARK: - Image Generation Models
    
    /// Invoke image generation models (which don't use converseStream)
    func invokeImageModel(
        withId modelId: String,
        prompt: String,
        modelType: ModelType
    ) async throws -> Data {
        switch modelType {
        case .titanImage:
            // TitanImage specific parameters
            let params = TitanImageModelParameters(inputText: prompt)
            let encodedParams = try JSONEncoder().encode(params)
            
            let request = InvokeModelInput(
                body: encodedParams,
                contentType: "application/json",
                modelId: modelId
            )
            
            let response = try await self.bedrockRuntimeClient.invokeModel(input: request)
            guard let data = response.body else {
                throw BedrockRuntimeError.invalidResponse(nil)
            }
            
            // Process TitanImage response
            let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            if let images = json?["images"] as? [String], let base64Image = images.first,
               let imageData = Data(base64Encoded: base64Image) {
                return imageData
            } else {
                throw BedrockRuntimeError.invalidResponse(data)
            }
            
        case .novaCanvas:
            // NovaCanvas specific parameters
            let params = NovaCanvasModelParameters(text: prompt)
            let encodedParams = try JSONEncoder().encode(params)
            
            let request = InvokeModelInput(
                body: encodedParams,
                contentType: "application/json",
                modelId: modelId
            )
            
            let response = try await self.bedrockRuntimeClient.invokeModel(input: request)
            guard let data = response.body else {
                throw BedrockRuntimeError.invalidResponse(nil)
            }
            
            // Process NovaCanvas response
            let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            if let images = json?["images"] as? [String], let base64Image = images.first,
               let imageData = Data(base64Encoded: base64Image) {
                return imageData
            } else {
                throw BedrockRuntimeError.invalidResponse(data)
            }
            
        case .stableDiffusion:
            // Stable Diffusion parameters
            let isSD3 = modelId.contains("sd3")
            let isCore = modelId.contains("stable-image-core")
            let isUltra = modelId.contains("stable-image-ultra") || modelId.contains("sd3-ultra")
            
            let promptData: [String: Any]
            
            if isSD3 || isCore || isUltra {
                // SD3, Core, Ultra formatting
                promptData = ["prompt": prompt]
            } else {
                // Standard Stable Diffusion formatting
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
            guard let data = response.body else {
                throw BedrockRuntimeError.invalidResponse(nil)
            }
            
            // Try to extract the image from the response
            let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            
            if let images = json?["images"] as? [String], let base64Image = images.first,
               let imageData = Data(base64Encoded: base64Image) {
                return imageData
            } else if let artifacts = json?["artifacts"] as? [[String: Any]],
                      let firstArtifact = artifacts.first,
                      let base64Image = firstArtifact["base64"] as? String,
                      let imageData = Data(base64Encoded: base64Image) {
                return imageData
            } else {
                throw BedrockRuntimeError.invalidResponse(data)
            }
            
        default:
            throw NSError(
                domain: "BedrockClient",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unsupported image model type"]
            )
        }
    }
    
    // MARK: - Embedding Models
    
    /// Invoke embedding models (which don't use converseStream)
    func invokeEmbeddingModel(
        withId modelId: String,
        text: String
    ) async throws -> Data {
        let modelType = getModelType(modelId)
        
        switch modelType {
        case .titanEmbed:
            let params = TitanEmbedModelParameters(inputText: text)
            let encodedParams = try JSONEncoder().encode(params)
            
            let request = InvokeModelInput(
                body: encodedParams,
                contentType: "application/json",
                modelId: modelId
            )
            
            let response = try await self.bedrockRuntimeClient.invokeModel(input: request)
            guard let data = response.body else {
                throw BedrockRuntimeError.invalidResponse(nil)
            }
            
            return data
            
        case .cohereEmbed:
            let params = CohereEmbedModelParameters(texts: [text], inputType: .searchDocument)
            let encodedParams = try JSONEncoder().encode(params)
            
            let request = InvokeModelInput(
                body: encodedParams,
                contentType: "application/json",
                modelId: modelId
            )
            
            let response = try await self.bedrockRuntimeClient.invokeModel(input: request)
            guard let data = response.body else {
                throw BedrockRuntimeError.invalidResponse(nil)
            }
            
            return data
            
        default:
            throw NSError(
                domain: "BedrockClient",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unsupported embedding model type"]
            )
        }
    }
    
    // MARK: - Foundation Model Information
    
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
    
    // MARK: - Utility Methods
    
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
        encoder.keyEncodingStrategy = strategy
        return try encoder.encode(value)
    }
    
    private func encode<T: Encodable>(_ value: T) throws -> String {
        let data: Data = try self.encode(value)
        return String(data: data, encoding: .utf8) ?? "error when encoding the string"
    }
}

// MARK: - Model Type and Parameter Definitions

enum ModelType {
    case claude, claude3, claude37, llama2, llama3, mistral, titan, titanImage, titanEmbed, cohereCommand, cohereEmbed
    case j2, stableDiffusion, jambaInstruct, novaPro, novaLite, novaMicro, novaCanvas, deepseekr1, unknown
    
    var supportsSystemPrompt: Bool {
        switch self {
        case .claude, .claude3, .claude37, .llama2, .llama3, .mistral, .novaPro, .novaLite, .novaMicro,
                .titan, .cohereCommand, .jambaInstruct, .deepseekr1:
            return true
        case .titanEmbed, .titanImage, .cohereEmbed, .stableDiffusion, .novaCanvas, .j2, .unknown:
            return false
        }
    }
}

// MARK: - Simplified Parameter Structures

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

// Image model parameter definitions
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
    
    init(
        inputText: String,
        numberOfImages: Int = 1,
        quality: String = "standard",
        cfgScale: Double = 8.0,
        height: Int = 512,
        width: Int = 512,
        seed: Int? = nil
    ) {
        self.taskType = "TEXT_IMAGE"
        
        // Titan Image Generator has a 512 character limit for prompts
        let limitedText = inputText.count > 512 ? String(inputText.prefix(512)) : inputText
        self.textToImageParams = TextToImageParams(text: limitedText)
        
        self.imageGenerationConfig = ImageGenerationConfig(
            numberOfImages: numberOfImages,
            quality: quality,
            cfgScale: cfgScale,
            height: height,
            width: width,
            seed: seed
        )
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

// Parameters for embedding models
public struct CohereEmbedModelParameters: ModelParameters {
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
    
    enum CodingKeys: String, CodingKey {
        case texts
        case inputType = "input_type"
        case truncate
    }
}

// MARK: - Error Definitions

enum BedrockRuntimeError: Error {
    case invalidResponse(Data?)
    case invalidURL
    case requestFailed
    case decodingFailed
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

enum BedrockError: Error {
    case invalidResponse(String?)
    case expiredToken(String?)
    case credentialsError(String?)
    case configurationError(String?)
    case permissionError(String?)
    case networkError(String?)
    case unknown(String?)
    
    init(error: Error) {
        // First try to extract detailed information from CommonRunTimeError
        if let commonError = error as? AwsCommonRuntimeKit.CommonRunTimeError {
            // Use reflection to extract detailed error information
            let mirror = Mirror(reflecting: commonError)
            
            if let crtErrorProperty = mirror.children.first(where: { $0.label == "crtError" }) {
                let crtError = crtErrorProperty.value
                let crtErrorMirror = Mirror(reflecting: crtError)
                
                var errorCode: Int = -1
                var errorMessage: String = "Unknown error"
                var errorName: String = "Unknown"
                
                for child in crtErrorMirror.children {
                    if child.label == "code", let code = child.value as? Int {
                        errorCode = code
                    } else if child.label == "message", let message = child.value as? String {
                        errorMessage = message
                    } else if child.label == "name", let name = child.value as? String {
                        errorName = name
                    }
                }
                
                let detailedMessage = "\(errorName): \(errorMessage) (Code: \(errorCode))"
                
                // Categorize based on error message content
                let lowerMessage = errorMessage.lowercased()
                if lowerMessage.contains("credential") || lowerMessage.contains("identity") {
                    self = .credentialsError(detailedMessage)
                } else if lowerMessage.contains("config") || lowerMessage.contains("profile") {
                    self = .configurationError(detailedMessage)
                } else if lowerMessage.contains("permission") || lowerMessage.contains("access") {
                    self = .permissionError(detailedMessage)
                } else if lowerMessage.contains("network") || lowerMessage.contains("connection") {
                    self = .networkError(detailedMessage)
                } else {
                    self = .invalidResponse(detailedMessage)
                }
                return
            }
            
            // If reflection didn't work, use the standard description
            self = .invalidResponse(commonError.localizedDescription)
            return
        }
        
        // Handle AWS service errors
        if let awsError = error as? AWSClientRuntime.AWSServiceError {
            if let typeName = awsError.typeName?.lowercased() {
                if typeName.contains("expiredtoken") {
                    self = .expiredToken(awsError.message)
                } else if typeName.contains("credential") || typeName.contains("auth") {
                    self = .credentialsError(awsError.message)
                } else if typeName.contains("permission") || typeName.contains("access") {
                    self = .permissionError(awsError.message)
                } else {
                    self = .unknown("\(typeName): \(awsError.message ?? "Unknown AWS error")")
                }
            } else {
                self = .unknown(awsError.message)
            }
            return
        }
        
        // Generic error handling
        let errorDescription = error.localizedDescription.lowercased()
        if errorDescription.contains("credential") || errorDescription.contains("identity") {
            self = .credentialsError(error.localizedDescription)
        } else if errorDescription.contains("config") || errorDescription.contains("profile") {
            self = .configurationError(error.localizedDescription)
        } else if errorDescription.contains("permission") || errorDescription.contains("access") {
            self = .permissionError(error.localizedDescription)
        } else if errorDescription.contains("network") || errorDescription.contains("connection") {
            self = .networkError(error.localizedDescription)
        } else if errorDescription.contains("expired") || errorDescription.contains("token") {
            self = .expiredToken(error.localizedDescription)
        } else {
            self = .unknown(error.localizedDescription)
        }
    }
    
    var title: String {
        switch self {
        case .invalidResponse: return "Invalid Response"
        case .expiredToken: return "Expired Token"
        case .credentialsError: return "Credentials Error"
        case .configurationError: return "Configuration Error"
        case .permissionError: return "Permission Error"
        case .networkError: return "Network Error"
        case .unknown: return "Unknown Error"
        }
    }
    
    var message: String {
        switch self {
        case .invalidResponse(let msg),
                .expiredToken(let msg),
                .credentialsError(let msg),
                .configurationError(let msg),
                .permissionError(let msg),
                .networkError(let msg),
                .unknown(let msg):
            return msg ?? "No additional information available"
        }
    }
}
