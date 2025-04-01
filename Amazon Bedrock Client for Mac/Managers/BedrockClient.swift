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
    
    // MARK: - Core Functionality
    
    /// Check if a model is an image generation model
    func isImageGenerationModel(_ modelId: String) -> Bool {
        let id = modelId.lowercased()
        return id.contains("titan-image") ||
               id.contains("nova-canvas") ||
               id.contains("stable-") ||
               id.contains("sd3-")
    }
    
    /// Check if a model is an embedding model
    func isEmbeddingModel(_ modelId: String) -> Bool {
        let id = modelId.lowercased()
        return id.contains("embed") || id.contains("titan-e1t")
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
        case .claude, .claude3:
            return BedrockRuntimeClientTypes.InferenceConfiguration(
                maxTokens: 4096,
                temperature: 1.0,
                topp: 1.0
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
        case .mistral, .llama2, .llama3, .jambaInstruct, .deepseekr1:
            return BedrockRuntimeClientTypes.InferenceConfiguration(
                maxTokens: 4096,
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
            system: systemContent
        )
        
        // Add tool configuration if provided
        if let tools = toolConfig {
            request.toolConfig = tools
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
    case claude, claude3, llama2, llama3, mistral, titan, titanImage, titanEmbed, cohereCommand, cohereEmbed
    case j2, stableDiffusion, jambaInstruct, novaPro, novaLite, novaMicro, novaCanvas, deepseekr1, unknown
    
    var supportsSystemPrompt: Bool {
        switch self {
        case .claude, .claude3, .llama2, .llama3, .mistral, .novaPro, .novaLite, .novaMicro,
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

enum BedrockError: Error {
    case invalidResponse(String?)
    case expiredToken(String?)
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
