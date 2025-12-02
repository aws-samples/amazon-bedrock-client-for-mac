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
import AwsCommonRuntimeKit
import Combine
import Foundation
import Logging
import SmithyIdentity
import SmithyIdentityAPI
import SwiftUI
import Smithy

@MainActor
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
            let defaultCredentialProvider: any AWSCredentialIdentityResolver
            if let chain = try? DefaultAWSCredentialIdentityResolverChain() {
                defaultCredentialProvider = chain
            } else {
                defaultCredentialProvider = StaticAWSCredentialIdentityResolver(
                    AWSCredentialIdentity(accessKey: "", secret: "")
                )
            }
            self.backend = Backend(
                region: "us-east-1",
                profile: "default",
                endpoint: "",
                runtimeEndpoint: "",
                awsCredentialIdentityResolver: defaultCredentialProvider
            )
            
            // Extract more detailed error information
            if let commonRuntimeError = error as? AwsCommonRuntimeKit.CommonRunTimeError {
                // Use Mirror to access internal properties of CommonRunTimeError
                let mirror = Mirror(reflecting: commonRuntimeError)
                
                // Try to find the crtError property
                if let crtErrorProperty = mirror.children.first(where: { $0.label == "crtError" }) {
                    let crtError = crtErrorProperty.value
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
            } else if let awsServiceError = error as? AWSClientRuntime.AWSServiceError {
                alertMessage = "AWS service error: \(awsServiceError.message ?? "Unknown error")"
            } else {
                alertMessage = "Error: \(error.localizedDescription)"
            }
            
            self.isLoggedIn = false
        }
        setupObservers()
    }
    
    @MainActor
    private static func createBackend() throws -> Backend {
        let region = SettingManager.shared.selectedRegion.rawValue
        let profile = SettingManager.shared.selectedProfile
        let endpoint = SettingManager.shared.endpoint
        let runtimeEndpoint = SettingManager.shared.runtimeEndpoint
        let profiles = SettingManager.shared.profiles
        
        return try Backend(
            region: region,
            profile: profile,
            endpoint: endpoint,
            runtimeEndpoint: runtimeEndpoint,
            profiles: profiles
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
            .sink { [weak self] _ in
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
        Task { @MainActor in
            let region = SettingManager.shared.selectedRegion.rawValue
            let profile = SettingManager.shared.selectedProfile
            let endpoint = SettingManager.shared.endpoint
            let runtimeEndpoint = SettingManager.shared.runtimeEndpoint
            let profiles = SettingManager.shared.profiles
            
            do {
                let newBackend = try Backend(
                    region: region,
                    profile: profile,
                    endpoint: endpoint,
                    runtimeEndpoint: runtimeEndpoint,
                    profiles: profiles
                )
                self.backend = newBackend
                self.logger.info("Backend refreshed successfully")
            } catch {
                self.logger.error(
                    "Failed to refresh Backend: \(error.localizedDescription). Retaining current Backend."
                )
                self.alertMessage = "Failed to refresh Backend: \(error.localizedDescription)."
            }
        }
    }
}

class Backend: Equatable, @unchecked Sendable {
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
            logger.error("Failed to create Bedrock client: \(error)")
            fatalError("Unable to initialize Bedrock client")
        }
    }()
    
    private(set) lazy var bedrockRuntimeClient: BedrockRuntimeClient = {
        do {
            return try createBedrockRuntimeClient()
        } catch {
            logger.error("Failed to create Bedrock Runtime client: \(error)")
            fatalError("Unable to initialize Bedrock Runtime client")
        }
    }()
    
    /// Initializes Backend with given parameters.
    /// Uses provided profiles to determine if SSO or standard credentials should be used.
    init(region: String, profile: String, endpoint: String, runtimeEndpoint: String, profiles: [ProfileInfo] = []) throws {
        self.region = region
        self.profile = profile
        self.endpoint = endpoint
        self.runtimeEndpoint = runtimeEndpoint
        
        logger.info("Backend init called with \(profiles.count) profiles: \(profiles.map { $0.name }.joined(separator: ", "))")
        logger.info("Looking for profile: \(profile)")
        
        // Try to initialize credentials in order of preference
        do {
            // First try: Use the specified profile from provided profiles
            if let selectedProfile = profiles.first(where: { $0.name == profile }) {
                 switch selectedProfile.type {
                 case .sso:
                     self.awsCredentialIdentityResolver = try SSOAWSCredentialIdentityResolver(profileName: profile)
                     logger.info("Using SSO credentials for profile: \(profile)")
                 case .credentialProcess:
                     // For credential_process profiles, we use ProfileAWSCredentialIdentityResolver
                     // which automatically handles credential_process directives
                     self.awsCredentialIdentityResolver = ProfileAWSCredentialIdentityResolver(profileName: profile)
                     logger.info("Using credential_process for profile: \(profile)")
                 case .credentials:
                     self.awsCredentialIdentityResolver = ProfileAWSCredentialIdentityResolver(profileName: profile)
                     logger.info("Using standard credentials for profile: \(profile)")
                 }
            }
            // Second try: Use default profile if specified profile not found
            else if profile != "default" {
                logger.warning("Profile '\(profile)' not found, falling back to 'default' profile")
                self.awsCredentialIdentityResolver = ProfileAWSCredentialIdentityResolver(profileName: "default")
            }
            // Third try: Use default profile directly
            else {
                logger.info("Using default profile")
                self.awsCredentialIdentityResolver = ProfileAWSCredentialIdentityResolver(profileName: "default")
            }
        } catch {
            // Final try: Use DefaultAWSCredentialIdentityResolverChain as last resort
            logger.warning("Failed to initialize with profile '\(profile)': \(error.localizedDescription)")
            logger.info("Attempting to use DefaultAWSCredentialIdentityResolverChain")
            
            if let chain = try? DefaultAWSCredentialIdentityResolverChain() {
                self.awsCredentialIdentityResolver = chain
                logger.info("Successfully initialized with DefaultAWSCredentialIdentityResolverChain")
            } else {
                // If even the default chain fails, we have no choice but to throw
                logger.error("Failed to initialize with DefaultAWSCredentialIdentityResolverChain")
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

    /// Check if a model supports advanced reasoning capabilities
    func isReasoningSupported(_ modelId: String) -> Bool {
        let modelType = getModelType(modelId)
        switch modelType {
        case .claude37, .claudeSonnet4, .claudeSonnet45, .claudeHaiku45, .claudeOpus4, .claudeOpus41, .claudeOpus45, .deepseekr1, .openaiGptOss120b, .openaiGptOss20b:
            return true
        default:
            return false
        }
    }

    /// Check if a model has configurable reasoning (can be toggled on/off)
    func hasConfigurableReasoning(_ modelId: String) -> Bool {
        let modelType = getModelType(modelId)
        switch modelType {
        case .claude37, .claudeSonnet4, .claudeSonnet45, .claudeHaiku45, .claudeOpus4, .claudeOpus41, .claudeOpus45, .openaiGptOss120b, .openaiGptOss20b:
            return true
        default:
            return false
        }
    }

    /// Check if a model has always-on reasoning (can't be disabled)
    func hasAlwaysOnReasoning(_ modelId: String) -> Bool {
        return getModelType(modelId) == .deepseekr1
    }
    
    /// Check if this is Claude 4.5 or later model (which only supports temperature OR top_p, not both)
    /// This applies to all Anthropic models from version 4.5 onwards
    func isClaude45OrLater(_ modelType: ModelType) -> Bool {
        switch modelType {
        case .claudeSonnet45, .claudeHaiku45, .claudeOpus45:
            return true
        default:
            return false
        }
    }

    /// Check if a model supports prompt caching
    func isPromptCachingSupported(_ modelId: String) -> Bool {
        let modelType = getModelType(modelId)
        switch modelType {
        // Anthropic models that support prompt caching
        case .claude35Haiku, .claude37, .claudeSonnet4, .claudeSonnet45, .claudeHaiku45, .claudeOpus4, .claudeOpus41, .claudeOpus45:
            return true
        // Models that don't support prompt caching (including Nova models due to image caching issues)
        default:
            return false
        }
    }

    /// Check if a model is an embedding model
    func isEmbeddingModel(_ modelId: String) -> Bool {
        let modelType = getModelType(modelId)
        switch modelType {
        case .titanEmbed, .cohereEmbed:
            return true
        default:
            // Fallback to string check for edge cases
            let id = modelId.lowercased()
            return id.contains("embed") || id.contains("titan-e1t")
        }
    }

    /// Check if a model supports document chat
    func isDocumentChatSupported(_ modelId: String) -> Bool {
        let modelType = getModelType(modelId)
        switch modelType {
            // Models that support document chat
        case .claude, .claude3, .claude35, .claude35Haiku, .claude37, .claudeSonnet4, .claudeSonnet45, .claudeHaiku45, .claudeOpus4, .claudeOpus41, .claudeOpus45:
            return true
        case .llama2, .llama3, .llama31, .llama32Small, .llama32Large, .llama33:
            return true
        case .mistral, .mistralLarge, .mistralLarge2407, .mixtral:
            return true
        case .novaPremier, .novaPro, .novaLite:
            return true
        case .titan:
            // Titan Text Premier doesn't support document chat
            return !modelId.contains("text-premier")
        case .cohereCommand:
            return true
        case .cohereCommandLight:
            return false
        case .cohereCommandR, .cohereCommandRPlus:
            return true
        case .jambaLarge, .jambaMini:
            return true
        case .jambaInstruct:
            return false
        case .deepseekr1:
            return true
        case .openaiGptOss120b, .openaiGptOss20b:
            return true
            
        // Models that don't support document chat
        case .mistralSmall, .novaMicro, .titanEmbed, .titanImage, .cohereEmbed,
                .stableDiffusion, .stableImage, .novaCanvas, .rerank, .j2, .cohereRerank,
                .luma, .unknown:
            return false
            
        default:
            return true
        }
    }

    /// Check if a model supports system prompts
    func isSystemPromptSupported(_ modelId: String) -> Bool {
        let modelType = getModelType(modelId)
        switch modelType {
        // Models that support system prompts
        case .claude, .claude3, .claude35, .claude35Haiku, .claude37, .claudeSonnet4, .claudeSonnet45, .claudeHaiku45, .claudeOpus4, .claudeOpus41, .claudeOpus45:
            return true
        case .llama2, .llama3, .llama31, .llama32Small, .llama32Large, .llama33:
            return true
        case .mistralLarge, .mistralLarge2407, .mistralSmall:
            return true
        case .novaPremier, .novaPro, .novaLite, .novaMicro:
            return true
        case .jambaInstruct, .jambaLarge, .jambaMini:
            return true
        case .deepseekr1:
            return true
        case .openaiGptOss120b, .openaiGptOss20b:
            return true
            
        // Models with specific exceptions
        case .mistral, .mistral7b, .mixtral:
            // Mistral Instruct models don't support system prompts
            return !modelId.contains("instruct")
            
        // Models that don't support system prompts
        case .titan, .titanEmbed, .titanImage, .cohereCommand, .cohereCommandLight,
             .cohereCommandR, .cohereCommandRPlus, .cohereEmbed, .cohereRerank,
             .stableDiffusion, .stableImage, .novaCanvas, .rerank, .j2, .luma, .unknown:
            return false
        }
    }

    /// Check if a model supports vision capabilities
    func isVisionSupported(_ modelId: String) -> Bool {
        let modelType = getModelType(modelId)
        switch modelType {
        // Models that fully support vision
        case .claude3, .claude37, .claudeSonnet4, .claudeSonnet45, .claudeHaiku45, .claudeOpus4, .claudeOpus41, .claudeOpus45, .novaPro, .llama32Large:
            return true
            
        // Models with exceptions
        case .claude35:
            // Claude 3.5 Haiku doesn't support vision
            return !modelId.contains("haiku")
        
        // Claude 3.5 Haiku doesn't support vision
        case .claude35Haiku:
            return false
        
        // Models that don't support vision
        default:
            return false
        }
    }

    /// Check if a model supports tool use
    func isToolUseSupported(_ modelId: String) -> Bool {
        let modelType = getModelType(modelId)
        switch modelType {
        // Models that support tool use
        case .claude3, .claude35, .claude35Haiku, .claude37, .claudeSonnet4, .claudeSonnet45, .claudeHaiku45, .claudeOpus4, .claudeOpus41, .claudeOpus45:
            return true
        case .novaPremier, .novaPro, .novaLite, .novaMicro:
            return true
        case .cohereCommandR, .cohereCommandRPlus:
            return true
        case .mistralLarge, .mistralLarge2407:
            return true
        case .llama31, .llama32Large, .llama33:
            return true
        case .jambaLarge, .jambaMini:
            return true
        case .openaiGptOss120b, .openaiGptOss20b:
            return true
            
        // Models that don't support tool use
        default:
            return false
        }
    }

    /// Check if a model supports streaming tool use
    func isStreamingToolUseSupported(_ modelId: String) -> Bool {
        let modelType = getModelType(modelId)
        switch modelType {
        // Models that support streaming tool use
        case .claude3, .claude35, .claude35Haiku, .claude37, .claudeSonnet4, .claudeSonnet45, .claudeHaiku45, .claudeOpus4, .claudeOpus41, .claudeOpus45:
            return true
        case .novaPremier, .novaPro, .novaLite, .novaMicro:
            return true
        case .cohereCommandR, .cohereCommandRPlus:
            return true
        case .openaiGptOss120b, .openaiGptOss20b:
            return true
            
        // Models that don't support streaming tool use
        default:
            return false
        }
    }

    /// Check if a model supports guardrails
    func isGuardrailsSupported(_ modelId: String) -> Bool {
        let modelType = getModelType(modelId)
        switch modelType {
        // Models that don't support guardrails
        case .claude35:
            // Claude 3.5 Haiku doesn't support guardrails
            return !modelId.contains("haiku")
        case .cohereCommandR, .cohereCommandRPlus:
            return false
        case .jambaInstruct:
            return false
            
        // Most models do support guardrails
        default:
            return true
        }
    }
    
    /// Add cache control to messages for prompt caching
    private func addCacheControlToMessages(_ messages: [BedrockRuntimeClientTypes.Message]) -> [BedrockRuntimeClientTypes.Message] {
        guard !messages.isEmpty else { return messages }
        
        var processedMessages = messages
        let lastIndex = messages.count - 1
        var lastMessage = messages[lastIndex]
        
        // Add cache point to the last message to enable caching for conversation history
        if var content = lastMessage.content {
            // Add a cache point at the end of the message content
            let cachePoint = BedrockRuntimeClientTypes.CachePointBlock(
                type: .default
            )
            content.append(.cachepoint(cachePoint))
            
            lastMessage = BedrockRuntimeClientTypes.Message(
                content: content,
                role: lastMessage.role
            )
            processedMessages[lastIndex] = lastMessage
        }
        
        return processedMessages
    }

    /// Helper function to determine the model type based on modelId
    func getModelType(_ modelId: String) -> ModelType {
        // Split by colon first to remove the version number
        let modelIdWithoutVersion = modelId.split(separator: ":").first ?? ""
        
        // Split by dots to handle region prefixes
        let parts = String(modelIdWithoutVersion).split(separator: ".")
        
        // We need at least 2 parts (could be 3 with region prefix)
        guard parts.count >= 2 else {
            print("Error: Invalid modelId format: \(modelId)")
            return .unknown
        }
        
        // Check if we have a region prefix (us, eu, etc.)
        // If we have 3+ parts, the provider is the second element
        let providerIndex = parts.count >= 3 ? 1 : 0
        let provider = String(parts[providerIndex]).lowercased()
        
        // The model name will be the last element or a combination of remaining elements
        let modelNameElements = parts.suffix(from: providerIndex + 1)
        let modelNameAndVersion = modelNameElements.joined(separator: ".")
        
        // Classify by provider first
        switch provider {
        case "anthropic":
            if modelNameAndVersion.contains("claude-sonnet-4-5") {
                return .claudeSonnet45
            } else if modelNameAndVersion.contains("claude-haiku-4-5") {
                return .claudeHaiku45
            } else if modelNameAndVersion.contains("claude-opus-4-5") {
                return .claudeOpus45
            } else if modelNameAndVersion.contains("claude-opus-4-1") {
                return .claudeOpus41
            } else if modelNameAndVersion.contains("claude-sonnet-4") {
                return .claudeSonnet4
            } else if modelNameAndVersion.contains("claude-opus-4") {
                return .claudeOpus4
            } else if modelNameAndVersion.contains("claude-3-7") {
                return .claude37
            } else if modelNameAndVersion.contains("claude-3-5-haiku") {
                return .claude35Haiku
            } else if modelNameAndVersion.contains("claude-3-5") {
                return .claude35
            } else if modelNameAndVersion.contains("claude-3") {
                return .claude3
            } else {
                return .claude
            }
            
        case "ai21":
            if modelNameAndVersion.contains("jamba-1-5-large") {
                return .jambaLarge
            } else if modelNameAndVersion.contains("jamba-1-5-mini") {
                return .jambaMini
            } else if modelNameAndVersion.contains("jamba-instruct") {
                return .jambaInstruct
            } else if modelNameAndVersion.hasPrefix("j2") {
                return .j2
            }
            
        case "amazon":
            if modelNameAndVersion.contains("titan-embed") || modelNameAndVersion.contains("titan-e1t") {
                return .titanEmbed
            } else if modelNameAndVersion.contains("titan-image") {
                return .titanImage
            } else if modelNameAndVersion.contains("titan") {
                return .titan
            } else if modelNameAndVersion.contains("nova-canvas") {
                return .novaCanvas
            } else if modelNameAndVersion.contains("nova") && modelNameAndVersion.contains("premier") {
                return .novaPremier
            } else if modelNameAndVersion.contains("nova") && modelNameAndVersion.contains("pro") {
                return .novaPro
            } else if modelNameAndVersion.contains("nova") && modelNameAndVersion.contains("lite") {
                return .novaLite
            } else if modelNameAndVersion.contains("nova") && modelNameAndVersion.contains("micro") {
                return .novaMicro
            } else if modelNameAndVersion.contains("rerank") {
                return .rerank
            }
            
        case "cohere":
            if modelNameAndVersion.contains("command-r-plus") {
                return .cohereCommandRPlus
            } else if modelNameAndVersion.contains("command-r") {
                return .cohereCommandR
            } else if modelNameAndVersion.contains("command-light") {
                return .cohereCommandLight
            } else if modelNameAndVersion.contains("command") {
                return .cohereCommand
            } else if modelNameAndVersion.contains("embed") {
                return .cohereEmbed
            } else if modelNameAndVersion.contains("rerank") {
                return .cohereRerank
            }
            
        case "meta":
            if modelNameAndVersion.contains("llama3-3") {
                return .llama33
            } else if modelNameAndVersion.contains("llama3-2") {
                // 크기별 분류
                if modelNameAndVersion.contains("11b") || modelNameAndVersion.contains("90b") {
                    return .llama32Large
                } else {
                    return .llama32Small
                }
            } else if modelNameAndVersion.contains("llama3-1") {
                return .llama31
            } else if modelNameAndVersion.contains("llama3") {
                return .llama3
            } else if modelNameAndVersion.contains("llama2") {
                return .llama2
            }
            
        case "mistral":
            if modelNameAndVersion.contains("mistral-large-2407") {
                return .mistralLarge2407
            } else if modelNameAndVersion.contains("mistral-large") {
                return .mistralLarge
            } else if modelNameAndVersion.contains("mistral-small") {
                return .mistralSmall
            } else if modelNameAndVersion.contains("mixtral") {
                return .mixtral
            } else if modelNameAndVersion.contains("mistral-7b") {
                return .mistral7b
            }
            
        case "deepseek":
            if modelNameAndVersion.contains("r1") {
                return .deepseekr1
            }
            
        case "stability":
            if modelNameAndVersion.contains("sd3") || modelNameAndVersion.contains("stable-diffusion") {
                return .stableDiffusion
            } else if modelNameAndVersion.contains("stable-image") {
                return .stableImage
            }
            
        case "luma":
            return .luma
            
        case "openai":
            if modelNameAndVersion.contains("gpt-oss-120b") {
                return .openaiGptOss120b
            } else if modelNameAndVersion.contains("gpt-oss-20b") {
                return .openaiGptOss20b
            }

        default:
            logger.warning("Could not identify model type for modelId: \(modelId)")
            return .unknown
        }
        
        logger.warning("Could not identify model type for modelId: \(modelId)")
        return .unknown
    }
    
    func getDefaultInferenceConfig(for modelType: ModelType, isThinkingEnabled: Bool = false) -> BedrockRuntimeClientTypes.InferenceConfiguration {
        switch modelType {
        case .claudeSonnet45:
            // Claude Sonnet 4.5 only supports temperature OR top_p, not both
            // We prefer temperature as per the issue requirements
            return BedrockRuntimeClientTypes.InferenceConfiguration(
                maxTokens: 8192,
                temperature: 0.9
            )
        case .claudeHaiku45:
            // Claude Haiku 4.5 only supports temperature OR top_p, not both
            
            if isThinkingEnabled {
                return BedrockRuntimeClientTypes.InferenceConfiguration(
                    maxTokens: 32000,
                    temperature: 1.0
                )
            } else {
                return BedrockRuntimeClientTypes.InferenceConfiguration(
                    maxTokens: 32000,
                    temperature: 0.9
                )
            }
        case .claudeOpus45:
            // Claude Opus 4.5 only supports temperature OR top_p, not both
            // Same limitation as Sonnet 4.5 and Haiku 4.5
            if isThinkingEnabled {
                return BedrockRuntimeClientTypes.InferenceConfiguration(
                    maxTokens: 8192,
                    temperature: 1.0
                )
            } else {
                return BedrockRuntimeClientTypes.InferenceConfiguration(
                    maxTokens: 8192,
                    temperature: 0.9
                )
            }
        case .claudeSonnet4:
            if isThinkingEnabled {
                return BedrockRuntimeClientTypes.InferenceConfiguration(
                    maxTokens: 8192,
                    temperature: 1.0
                )
            } else {
                return BedrockRuntimeClientTypes.InferenceConfiguration(
                    maxTokens: 8192,
                    temperature: 0.9,
                    topp: 0.7
                )
            }
        case .claudeOpus4, .claudeOpus41:
            if isThinkingEnabled {
                return BedrockRuntimeClientTypes.InferenceConfiguration(
                    maxTokens: 8192,
                    temperature: 1.0
                )
            } else {
                return BedrockRuntimeClientTypes.InferenceConfiguration(
                    maxTokens: 8192,
                    temperature: 0.9,
                    topp: 0.7
                )
            }
        case .claude37:
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
        case .claude, .claude3, .claude35, .claude35Haiku:
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
        case .novaPremier, .novaPro, .novaLite, .novaMicro:
            return BedrockRuntimeClientTypes.InferenceConfiguration(
                maxTokens: 8192,
                temperature: 0.7,
                topp: 0.9
            )
        case .deepseekr1:
            return BedrockRuntimeClientTypes.InferenceConfiguration(
                maxTokens: 8192,
                temperature: 1
            )
        case .openaiGptOss120b, .openaiGptOss20b:
            return BedrockRuntimeClientTypes.InferenceConfiguration(
                maxTokens: 8192,
                temperature: 0.7,
                topp: 0.9
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
    
    
    // MARK: - Converse Stream API (Unified for Text Models) 부분만 수정

    /// Unified converseStream method for all text generation models
    /// This is the primary method that should be used for all text-based LLMs
    func converseStream(
        withId modelId: String,
        messages: [BedrockRuntimeClientTypes.Message],
        systemContent: [BedrockRuntimeClientTypes.SystemContentBlock]? = nil,
        inferenceConfig: BedrockRuntimeClientTypes.InferenceConfiguration? = nil,
        toolConfig: BedrockRuntimeClientTypes.ToolConfiguration? = nil,
        usageHandler: (@Sendable (UsageInfo) -> Void)? = nil
    ) async throws -> AsyncThrowingStream<BedrockRuntimeClientTypes.ConverseStreamOutput, Error> {
        let modelType = getModelType(modelId)
        
        // Create default inference config if not provided
        // Get model-specific inference config
        let modelConfig = await MainActor.run { SettingManager.shared.getInferenceConfig(for: modelId) }
        let config: BedrockRuntimeClientTypes.InferenceConfiguration
        
        // Check if reasoning is enabled for this model
        let isThinkingEnabled = await MainActor.run { SettingManager.shared.enableModelThinking }
        let isReasoningModel = isReasoningSupported(modelId) && !hasAlwaysOnReasoning(modelId)
        let shouldOverrideForReasoning = isReasoningModel && isThinkingEnabled
        
        // Check if this is Claude 4.5+ model which only supports temperature OR top_p, not both
        // This applies to all Anthropic models from 4.5 onwards
        let isClaude45PlusModel = isClaude45OrLater(modelType)
        
        if modelConfig.overrideDefault {
            // Custom config - but override temperature and topP if reasoning is enabled
            if shouldOverrideForReasoning {
                config = BedrockRuntimeClientTypes.InferenceConfiguration(
                    maxTokens: modelConfig.maxTokens,
                    temperature: 1.0,  // Force temperature to 1.0 for reasoning
                    topp: nil          // Disable topP for reasoning
                )
                logger.info("Using custom inference config for \(modelId) with reasoning override: maxTokens=\(modelConfig.maxTokens), temperature=1.0 (forced), topP=disabled")
            } else if isClaude45PlusModel {
                // Claude 4.5+ models only support temperature, not top_p
                config = BedrockRuntimeClientTypes.InferenceConfiguration(
                    maxTokens: modelConfig.maxTokens,
                    temperature: modelConfig.temperature
                )
                logger.info("Using custom inference config for Claude 4.5+ model \(modelId): maxTokens=\(modelConfig.maxTokens), temperature=\(modelConfig.temperature), topP=disabled (model limitation)")
            } else {
                config = BedrockRuntimeClientTypes.InferenceConfiguration(
                    maxTokens: modelConfig.maxTokens,
                    temperature: modelConfig.temperature,
                    topp: modelConfig.topP
                )
                logger.info("Using custom inference config for \(modelId): maxTokens=\(modelConfig.maxTokens), temperature=\(modelConfig.temperature), topP=\(modelConfig.topP)")
            }
        } else {
            // Default config - but modify for reasoning if needed
            let defaultConfig = getDefaultInferenceConfig(for: modelType)
            
            if shouldOverrideForReasoning {
                // Override default config for reasoning requirements
                config = BedrockRuntimeClientTypes.InferenceConfiguration(
                    maxTokens: defaultConfig.maxTokens,
                    temperature: 1.0,  // Force temperature to 1.0 for reasoning
                    topp: nil          // Disable topP for reasoning
                )
                logger.info("Using default inference config for \(modelType) with reasoning override: temperature=1.0 (forced), topP=disabled")
            } else {
                config = defaultConfig
                logger.info("Using default inference config for model type: \(modelType)")
            }
        }
        
        // Apply prompt caching if supported by the model
        var processedMessages = messages
        
        if isPromptCachingSupported(modelId) && !messages.isEmpty {
            // Add cache control to the last user message to enable caching
            // This allows the conversation history to be cached for subsequent requests
            processedMessages = addCacheControlToMessages(messages)
            logger.info("Prompt caching enabled for model: \(modelId)")
        }
        
        // Create converse stream request
        var request = ConverseStreamInput(
            inferenceConfig: config,
            messages: processedMessages,
            modelId: modelId,
            system: isSystemPromptSupported(modelId) ? systemContent : nil
        )
        
        // Add tool configuration if provided
        if let tools = toolConfig {
            request.toolConfig = tools
        }
        
        // Add reasoning configuration if needed
        if isReasoningModel && isThinkingEnabled {
            do {
                let modelType = getModelType(modelId)
                let reasoningConfig: [String: Any]
                
                // OpenAI GPT-OSS models use different reasoning configuration format
                if modelType == .openaiGptOss120b || modelType == .openaiGptOss20b {
                    // Use user-configured reasoning effort if override is enabled, otherwise use default
                    let effortLevel = modelConfig.overrideDefault ? modelConfig.reasoningEffort : "medium"
                    reasoningConfig = [
                        "reasoning_effort": effortLevel
                    ]
                } else {
                    // Claude and other models use the budget-based format
                    let thinkingBudget = modelConfig.overrideDefault ? modelConfig.thinkingBudget : 2048
                    reasoningConfig = [
                        "reasoning_config": [
                            "type": "enabled",
                            "budget_tokens": thinkingBudget
                        ]
                    ]
                }
                
                request.additionalModelRequestFields = try Document.make(from: reasoningConfig)
                logger.info("Added reasoning configuration for \(modelId)")
            } catch {
                logger.error("Failed to create reasoning config document: \(error)")
            }
        } else if hasAlwaysOnReasoning(modelId) {
            logger.info("Model \(modelId) has built-in reasoning capabilities")
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
                        // Extract usage information from metadata events
                        if case .metadata(let metadataEvent) = event {
                            if let usage = metadataEvent.usage {
                                let usageInfo = UsageInfo(
                                    inputTokens: usage.inputTokens,
                                    outputTokens: usage.outputTokens,
                                    cacheCreationInputTokens: usage.cacheWriteInputTokens,
                                    cacheReadInputTokens: usage.cacheReadInputTokens
                                )
                                logger.info("Usage info - Input: \(usage.inputTokens ?? 0), Output: \(usage.outputTokens ?? 0), Cache Read: \(usage.cacheReadInputTokens ?? 0), Cache Write: \(usage.cacheWriteInputTokens ?? 0)")
                                // Call the usage handler if provided
                                usageHandler?(usageInfo)
                            }
                        }
                        
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

// MARK: - Usage Information for Display

/**
 * Usage information for tracking token consumption and prompt caching metrics
 */
struct UsageInfo {
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheCreationInputTokens: Int?
    let cacheReadInputTokens: Int?
    
    init(inputTokens: Int? = nil, outputTokens: Int? = nil, cacheCreationInputTokens: Int? = nil, cacheReadInputTokens: Int? = nil) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
    }
}

// MARK: - Model Type and Parameter Definitions



enum ModelType {
    // Anthropic models
    case claude, claude3, claude35, claude35Haiku, claude37, claudeSonnet4, claudeSonnet45, claudeHaiku45, claudeOpus4, claudeOpus41, claudeOpus45
    // Meta models
    case llama2, llama3, llama31, llama32Small, llama32Large, llama33
    // Mistral models
    case mistral, mistral7b, mistralLarge, mistralLarge2407, mistralSmall, mixtral
    // Amazon models
    case titan, titanImage, titanEmbed, novaPremier, novaPro, novaLite, novaMicro, novaCanvas, rerank
    // AI21 models
    case j2, jambaInstruct, jambaLarge, jambaMini
    // Cohere models
    case cohereCommand, cohereCommandLight, cohereCommandR, cohereCommandRPlus, cohereEmbed, cohereRerank
    // Stability models
    case stableDiffusion, stableImage
    // OpenAI models
    case openaiGptOss120b, openaiGptOss20b
    // Other models
    case deepseekr1, luma, unknown
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
        
        // Handle SSO/OIDC errors by extracting from error description
        let errorString = String(describing: error)
        let errorType = String(describing: type(of: error))
        
        // Check for InvalidGrantException (SSO token expired/invalid)
        if errorType.contains("InvalidGrantException") || errorString.contains("InvalidGrantException") {
            // Extract error_description from the error
            if let range = errorString.range(of: "error_description: Optional(\""),
               let endRange = errorString.range(of: "\")", range: range.upperBound..<errorString.endIndex) {
                let description = String(errorString[range.upperBound..<endRange.lowerBound])
                self = .expiredToken("SSO session expired: \(description). Please run 'aws sso login' to refresh your credentials.")
                return
            }
            self = .expiredToken("SSO session expired. Please run 'aws sso login --profile <your-profile>' to refresh your credentials.")
            return
        }
        
        // Check for other SSO errors
        if errorType.contains("SSO") || errorString.contains("SSO") || errorString.contains("sso") {
            if errorString.contains("expired") || errorString.contains("invalid") {
                self = .expiredToken("SSO credentials expired. Please run 'aws sso login' to refresh.")
                return
            }
            self = .credentialsError("SSO authentication error. Please check your SSO configuration.")
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
