//
//  Bedrockclient.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/08.
//

import Foundation
import Combine
import Logging
import AWSSTS
import AWSSSO
import AWSSSOOIDC
import AWSBedrock
import AWSBedrockRuntime
import AWSClientRuntime
import AwsCommonRuntimeKit
import SmithyIdentity
import AWSSDKIdentity
import SwiftUI

class BackendModel: ObservableObject {
    @Published var backend: Backend
    @Published var alertMessage: String? // Used to trigger alerts in the UI
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
            alertMessage = "Backend initialization failed: \(error.localizedDescription). Using fallback settings."
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
            logger.error("Failed to refresh Backend: \(error.localizedDescription). Retaining current Backend.")
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
            fatalError("Unable to initialize Bedrock client.") // This will rarely trigger now
        }
    }()
    
    private(set) lazy var bedrockRuntimeClient: BedrockRuntimeClient = {
        do {
            return try createBedrockRuntimeClient()
        } catch {
            logger.error("Failed to initialize Bedrock Runtime client: \(error.localizedDescription)")
            fatalError("Unable to initialize Bedrock Runtime client.") // This will rarely trigger now
        }
    }()
    
    init(region: String, profile: String, endpoint: String, runtimeEndpoint: String) throws {
        self.region = region
        self.profile = profile
        self.endpoint = endpoint
        self.runtimeEndpoint = runtimeEndpoint
        
        do {
            self.awsCredentialIdentityResolver = try ProfileAWSCredentialIdentityResolver(profileName: profile)
        } catch {
            logger.error("Failed to create AWS Credential Resolver: \(error.localizedDescription)")
            throw error
        }
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
            fatalError("Fallback Backend failed to initialize. Error: \(error.localizedDescription)")
        }
    }
    
    private func createBedrockClient() throws -> BedrockClient {
        let config = try BedrockClient.BedrockClientConfiguration(
            awsCredentialIdentityResolver: self.awsCredentialIdentityResolver,
            region: self.region,
            signingRegion: self.region,
            endpoint: self.endpoint.isEmpty ? nil : self.endpoint
        )
        logger.info("Bedrock client created with region: \(self.region), endpoint: \(self.endpoint)")
        return BedrockClient(config: config)
    }
    
    private func createBedrockRuntimeClient() throws -> BedrockRuntimeClient {
        let config = try BedrockRuntimeClient.BedrockRuntimeClientConfiguration(
            awsCredentialIdentityResolver: self.awsCredentialIdentityResolver,
            region: self.region,
            signingRegion: self.region,
            endpoint: self.runtimeEndpoint.isEmpty ? nil : self.runtimeEndpoint
        )
        logger.info("Bedrock Runtime client created with region: \(self.region), runtimeEndpoint: \(self.runtimeEndpoint)")
        return BedrockRuntimeClient(config: config)
    }
    
    static func == (lhs: Backend, rhs: Backend) -> Bool {
        return lhs.region == rhs.region &&
        lhs.profile == rhs.profile &&
        lhs.endpoint == rhs.endpoint &&
        lhs.runtimeEndpoint == rhs.runtimeEndpoint
    }
    
    func invokeModel(withId modelId: String, prompt: String) async throws -> Data {
        let modelType = getModelType(modelId)
        let strategy: JSONEncoder.KeyEncodingStrategy = (modelType == .claude || modelType == .mistral || modelType == .llama2 || modelType == .llama3) ? .convertToSnakeCase : .useDefaultKeys
        let params = getModelParameters(modelType: modelType, prompt: prompt)
        let encodedParams = try self.encode(params, strategy: strategy)
        
        let request = InvokeModelInput(body: encodedParams, contentType: "application/json", modelId: modelId)
        
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
    
    func invokeModelStream(withId modelId: String, prompt: String) async throws -> AsyncThrowingStream<BedrockRuntimeClientTypes.ResponseStream, Swift.Error> {
        let modelType = getModelType(modelId)
        let strategy: JSONEncoder.KeyEncodingStrategy = (modelType == .claude || modelType == .claude3 || modelType == .mistral || modelType == .llama2 || modelType == .llama3) ? .convertToSnakeCase : .useDefaultKeys
        let params = getModelParameters(modelType: modelType, prompt: prompt)
        
        let encodedParams = try self.encode(params, strategy: strategy)
        let request = InvokeModelWithResponseStreamInput(body: encodedParams, contentType: "application/json", modelId: modelId)
        
        if let requestJson = String(data: encodedParams, encoding: .utf8) {
            logger.info("Request: \(requestJson)")
        }
        
        let output = try await self.bedrockRuntimeClient.invokeModelWithResponseStream(input: request)
        return output.body ?? AsyncThrowingStream { _ in }
    }
    
    func invokeClaudeModel(withId modelId: String, messages: [ClaudeMessageRequest.Message], systemPrompt: String?) async throws -> Data {
        let requestBody = ClaudeMessageRequest(
            anthropicVersion: "bedrock-2023-05-31",
            maxTokens: 4096,
            system: systemPrompt,
            messages: messages,
            temperature: 0.7,
            topP: 0.9,
            topK: nil,
            stopSequences: nil
        )
        
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let jsonData = try encoder.encode(requestBody)
        
        let request = InvokeModelInput(body: jsonData, contentType: "application/json", modelId: modelId)
        let response = try await self.bedrockRuntimeClient.invokeModel(input: request)
        
        guard response.contentType == "application/json", let data = response.body else {
            logger.error("Invalid Bedrock response: \(response)")
            throw BedrockRuntimeError.invalidResponse(response.body)
        }
        
        return data
    }
    
    func invokeClaudeModelStream(withId modelId: String, messages: [ClaudeMessageRequest.Message], systemPrompt: String?) async throws -> AsyncThrowingStream<BedrockRuntimeClientTypes.ResponseStream, Swift.Error> {
        let requestBody = ClaudeMessageRequest(
            anthropicVersion: "bedrock-2023-05-31",
            maxTokens: 4096,
            system: systemPrompt,
            messages: messages,
            temperature: 0.7,
            topP: 0.9,
            topK: nil,
            stopSequences: nil
        )
        
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let jsonData = try encoder.encode(requestBody)
        
        let request = InvokeModelWithResponseStreamInput(body: jsonData, contentType: "application/json", modelId: modelId)
        let output = try await self.bedrockRuntimeClient.invokeModelWithResponseStream(input: request)
        
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
            // 기존 Stable Diffusion (SDXL 포함)
            promptData = [
                "text_prompts": [["text": prompt]],
                "cfg_scale": 10,
                "seed": 0,
                "steps": 50,
                "samples": 1,
                "style_preset": "photographic"
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
            throw NSError(domain: "BedrockRuntime", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid response: Empty body"])
        }
        
        let json = try JSONSerialization.jsonObject(with: responseBody, options: []) as? [String: Any]
        
        if let images = json?["images"] as? [String], let base64Image = images.first,
           let imageData = Data(base64Encoded: base64Image) {
            
            // Ultra 모델의 경우 추가 정보 처리
            if isUltra, let finishReasons = json?["finish_reasons"] as? [String?] {
                if let finishReason = finishReasons.first, finishReason != nil {
                    throw NSError(domain: "BedrockRuntime", code: 3, userInfo: [NSLocalizedDescriptionKey: "Image generation error: \(finishReason!)"])
                }
            }
            
            return imageData
        } else if let artifacts = json?["artifacts"] as? [[String: Any]],
                  let firstArtifact = artifacts.first,
                  let base64Image = firstArtifact["base64"] as? String,
                  let imageData = Data(base64Encoded: base64Image) {
            
            // 기존 Stable Diffusion (SDXL 포함) 응답 처리
            if let finishReason = firstArtifact["finishReason"] as? String {
                if finishReason == "ERROR" || finishReason == "CONTENT_FILTERED" {
                    throw NSError(domain: "BedrockRuntime", code: 3, userInfo: [NSLocalizedDescriptionKey: "Image generation error: \(finishReason)"])
                }
                print("Stable Diffusion generation - Finish Reason: \(finishReason)")
            }
            
            return imageData
        } else {
            throw NSError(domain: "BedrockRuntime", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to parse model response"])
        }
    }
    
    func listFoundationModels(byCustomizationType: BedrockClientTypes.ModelCustomization? = nil,
                              byInferenceType: BedrockClientTypes.InferenceType? = BedrockClientTypes.InferenceType.onDemand,
                              byOutputModality: BedrockClientTypes.ModelModality? = nil,
                              byProvider: String? = nil) async -> Result<[BedrockClientTypes.FoundationModelSummary], Error> {
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
                return .failure(NSError(domain: "BedrockError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Model summaries are missing"]))
            }
        } catch {
            logger.error("Error occurred: \(error)")
            return .failure(error)
        }
    }
    
    /// Helper function to determine the model type based on modelId
    func getModelType(_ modelId: String) -> ModelType {
        let parts = modelId.split(separator: ".")
        guard let modelName = parts.last else {
            fatalError("Invalid modelId: \(modelId)")
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
            return TitanModelParameters(inputText: "User: \(prompt)\n\nBot:", textGenerationConfig: textGenerationConfig)
        case .titanEmbed:
            return TitanEmbedModelParameters(inputText: prompt)
        case .titanImage:
            return TitanImageModelParameters(inputText: prompt)
        case .j2:
            return AI21ModelParameters(prompt: prompt, temperature: 0.5, topP: 0.5, maxTokens: 200)
        case .cohereCommand:
            return CohereModelParameters(prompt: prompt, temperature: 0.9, p: 0.75, k: 0, maxTokens: 20)
        case .cohereEmbed:
            return CohereEmbedModelParameters(texts: [prompt], inputType: .searchDocument)
        case .mistral:
            return MistralModelParameters(prompt: "<s>[INST] \(prompt)[\\INST]", maxTokens: 4096, temperature: 0.9, topP: 0.9)
        case .llama2:
            return Llama2ModelParameters(prompt: "Prompt: \(prompt)\n\nAnswer:", maxGenLen: 2048, topP: 0.9, temperature: 0.9)
        case .llama3:
            return Llama3ModelParameters(prompt: "Prompt: \(prompt)\n\nAnswer:", maxGenLen: 2048, topP: 0.9, temperature: 0.9)
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
    private func encode<T: Encodable>(_ value: T, strategy: JSONEncoder.KeyEncodingStrategy = .useDefaultKeys) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = strategy  // Use the provided strategy, default to .useDefaultKeys
        return try encoder.encode(value)
    }
    private func encode<T: Encodable>(_ value: T) throws -> String {
        let data : Data =  try self.encode(value)
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
    case claude, claude3, llama2, llama3, mistral, titan, titanImage, titanEmbed, cohereCommand, cohereEmbed, j2, stableDiffusion, jambaInstruct, unknown
}

public protocol ModelParameters: Encodable {
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
    
    init(texts: [String],
         inputType: EmbedInputType,
         truncate: TruncateOption? = nil) {
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
    init(inputText: String, numberOfImages: Int = 1, quality: String = "standard", cfgScale: Double = 8.0, height: Int = 512, width: Int = 512, seed: Int? = nil) {
        self.taskType = "TEXT_IMAGE"
        self.textToImageParams = TextToImageParams(text: inputText)
        self.imageGenerationConfig = ImageGenerationConfig(numberOfImages: numberOfImages, quality: quality, cfgScale: cfgScale, height: height, width: width, seed: seed)
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
    
    public func encodeModel() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }
}

public struct ClaudeMessageRequest: ModelParameters {
    public let anthropicVersion: String
    public let maxTokens: Int
    public let system: String?
    public let messages: [Message]
    public let temperature: Float?
    public let topP: Float?
    public let topK: Int?
    public let stopSequences: [String]?
    
    enum CodingKeys: String, CodingKey {
        case anthropicVersion = "anthropic_version"
        case maxTokens = "max_tokens"
        case system
        case messages
        case temperature
        case topP = "top_p"
        case topK = "top_k"
        case stopSequences = "stop_sequences"
    }
    
    // 메시지 구조체 정의
    public struct Message: Codable {
        let role: String
        let content: [Content]
        
        // 컨텐츠 구조체 정의
        struct Content: Codable {
            var type: String
            var text: String?
            var source: ImageSource?
            
            // 이미지 소스 구조체 정의
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
    
    public init(
        anthropicVersion: String = "bedrock-2023-05-31",
        maxTokens: Int,
        system: String? = nil,
        messages: [Message],
        temperature: Float? = nil,
        topP: Float? = nil,
        topK: Int? = nil,
        stopSequences: [String]? = nil
    ) {
        self.anthropicVersion = anthropicVersion
        self.maxTokens = maxTokens
        self.system = system
        self.messages = messages
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.stopSequences = stopSequences
    }
}

extension ClaudeMessageRequest {
    var dictionaryRepresentation: [String: Any] {
        var dict = [String: Any]()
        dict["anthropic_version"] = anthropicVersion
        dict["max_tokens"] = maxTokens
        if let system = system { dict["system"] = system }
        dict["messages"] = messages.map { $0.dictionaryRepresentation }
        if let temperature = temperature { dict["temperature"] = temperature }
        if let topP = topP { dict["top_p"] = topP }
        if let topK = topK { dict["top_k"] = topK }
        if let stopSequences = stopSequences { dict["stop_sequences"] = stopSequences }
        return dict
    }
}

extension ClaudeMessageRequest.Message {
    var dictionaryRepresentation: [String: Any] {
        var dict = [String: Any]()
        dict["role"] = role
        dict["content"] = content.map { $0.dictionaryRepresentation }
        return dict
    }
}

extension ClaudeMessageRequest.Message.Content {
    var dictionaryRepresentation: [String: Any] {
        var dict = [String: Any]()
        dict["type"] = type
        if let text = text { dict["text"] = text }
        if let source = source { dict["source"] = source.dictionaryRepresentation }
        return dict
    }
}

extension ClaudeMessageRequest.Message.Content.ImageSource {
    var dictionaryRepresentation: [String: Any] {
        return [
            "type": type,
            "media_type": mediaType,
            "data": data
        ]
    }
}

public struct MistralModelParameters: ModelParameters {
    public var prompt: String
    // Updated maxTokens maximum value to 4096.
    public var maxTokens: Int
    public var stop: [String]?
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
    
    public func encodeModel() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }
}

public struct Llama2ModelParameters: ModelParameters {
    public var prompt: String
    public var maxGenLen: Int
    public var topP: Double
    public var temperature: Double
    
    public init(
        prompt: String,
        maxGenLen: Int = 512,
        topP: Double = 0.9,
        temperature: Double = 1.0
    ) {
        self.prompt = prompt
        self.maxGenLen = maxGenLen
        self.topP = topP
        self.temperature = temperature
    }
    
    public func encodeModel() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }
}

public struct Llama3ModelParameters: ModelParameters {
    public var prompt: String
    public var maxGenLen: Int
    public var topP: Double
    public var temperature: Double
    
    public init(
        prompt: String,
        maxGenLen: Int = 2048,
        topP: Double = 0.9,
        temperature: Double = 0.9
    ) {
        self.prompt = prompt
        self.maxGenLen = maxGenLen
        self.topP = topP
        self.temperature = temperature
    }
    
    public func encodeModel() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }
}

// MARK: - TitanModelParameters

public struct TitanModelParameters: ModelParameters {
    public let inputText: String  // Changed from `prompt`
    public let textGenerationConfig: TextGenerationConfig
    
    public func encodeModel() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }
    
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

public struct InvokeTitanResponse: ModelResponse, Decodable {
    public let results: [InvokeTitanResult]
}

public struct InvokeTitanEmbedResponse: ModelResponse, Decodable {
    public let embedding: [Float]
}

public struct InvokeTitanImageResponse: ModelResponse, Decodable {
    public let images: [Data]
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
    public let body: Data // Specify the type here
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
enum STSError: Error  {
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
    case invalidResponse(String?)
    case genericError(String)
    case tokenExpired
}
