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
import AppKit
import AwsCommonRuntimeKit
import SmithyIdentity
import AWSSDKIdentity
import AWSClientRuntime

class BackendModel: ObservableObject {
    @Published var backend: Backend
    private var cancellables = Set<AnyCancellable>()
    private var logger = Logger(label: "BackendModel")
    @Published var isLoggedIn = false
    private var ssoOIDC: SSOOIDCClient?
    private var sso: SSOClient?

    init() {
        self.backend = Backend(region: SettingManager.shared.selectedRegion.rawValue,
                               profile: SettingManager.shared.selectedProfile,
                               endpoint: SettingManager.shared.endpoint,
                               runtimeEndpoint: SettingManager.shared.runtimeEndpoint)
        
        setupObservers()
    }

    private func setupObservers() {
        SettingManager.shared.$selectedRegion
            .combineLatest(SettingManager.shared.$selectedProfile,
                           SettingManager.shared.$endpoint,
                           SettingManager.shared.$runtimeEndpoint)
            .sink { [weak self] (region, profile, endpoint, runtimeEndpoint) in
                self?.updateBackend(region: region.rawValue, profile: profile, endpoint: endpoint, runtimeEndpoint: runtimeEndpoint)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .awsCredentialsChanged)
            .sink { [weak self] _ in
                self?.refreshBackend()
            }
            .store(in: &cancellables)
    }

    private func updateBackend(region: String, profile: String, endpoint: String, runtimeEndpoint: String) {
        self.backend = Backend(region: region, profile: profile, endpoint: endpoint, runtimeEndpoint: runtimeEndpoint)
        logger.info("Backend updated, region: \(region), profile: \(profile)")
    }

    private func refreshBackend() {
        updateBackend(region: backend.region,
                      profile: backend.profile,
                      endpoint: backend.endpoint,
                      runtimeEndpoint: backend.runtimeEndpoint)
        logger.info("Backend refreshed due to credentials change")
    }
    
    private func setupClients() { // New function added
        do {
            let region = "us-west-2" // Use desired region
            let ssoOIDCConfiguration = try SSOOIDCClient.SSOOIDCClientConfiguration(region: region)
            let ssoConfiguration = try SSOClient.SSOClientConfiguration(region: region)
            
            ssoOIDC = SSOOIDCClient(config: ssoOIDCConfiguration)
            sso = SSOClient(config: ssoConfiguration)
        } catch {
            print("Error setting up clients: \(error)")
        }
    }
    
    func startSSOLogin(startUrl: String, region: String) async throws -> (authUrl: String, userCode: String) {
        let registerClientRequest = RegisterClientInput(
            clientName: "Amazon Bedrock",
            clientType: "public",
            scopes: ["sso:account:access"]
        )
        
        let registerClientResponse = try await ssoOIDC!.registerClient(input: registerClientRequest)
        
        let startDeviceAuthRequest = StartDeviceAuthorizationInput(
            clientId: registerClientResponse.clientId,
            clientSecret: registerClientResponse.clientSecret,
            startUrl: startUrl
        )
        
        let startDeviceAuthResponse = try await ssoOIDC!.startDeviceAuthorization(input: startDeviceAuthRequest)
        
        return (startDeviceAuthResponse.verificationUriComplete!, startDeviceAuthResponse.userCode!)
    }
    
    func pollForTokens(clientId: String, clientSecret: String, deviceCode: String) async throws -> CreateTokenOutput {
        let createTokenRequest = CreateTokenInput(
            clientId: clientId,
            clientSecret: clientSecret,
            deviceCode: deviceCode,
            grantType: "urn:ietf:params:oauth:grant-type:device_code"
        )
        
        while true {
            do {
                let tokenResponse = try await ssoOIDC!.createToken(input: createTokenRequest)
                return tokenResponse
            } catch let error as AuthorizationPendingException {
                // User hasn't completed the authorization yet, wait and retry
                try await Task.sleep(nanoseconds: 5_000_000_000) // Wait for 5 seconds
            } catch {
                throw error
            }
        }
        
    }
    
    func getAccountInfo(accessToken: String) async throws -> GetRoleCredentialsOutput {
        let listAccountsRequest = ListAccountsInput(accessToken: accessToken, maxResults: 1)
        let listAccountsResponse = try await sso!.listAccounts(input: listAccountsRequest)
        
        guard let account = listAccountsResponse.accountList?.first else {
            throw NSError(domain: "SSOError", code: 0, userInfo: [NSLocalizedDescriptionKey: "No accounts found"])
        }
        
        let listAccountRolesRequest = ListAccountRolesInput(
            accessToken: accessToken,
            accountId: account.accountId!,
            maxResults: 1
        )
        let listAccountRolesResponse = try await sso!.listAccountRoles(input: listAccountRolesRequest)
        
        guard let role = listAccountRolesResponse.roleList?.first else {
            throw NSError(domain: "SSOError", code: 0, userInfo: [NSLocalizedDescriptionKey: "No roles found"])
        }
        
        let getRoleCredentialsRequest = GetRoleCredentialsInput(
            accessToken: accessToken,
            accountId: account.accountId!,
            roleName: role.roleName!
        )
        return try await sso!.getRoleCredentials(input: getRoleCredentialsRequest)
    }
    
    func completeLogin(tokenResponse: CreateTokenOutput) async throws {
        let roleCredentials = try await getAccountInfo(accessToken: tokenResponse.accessToken!)
        
        // Save the credentials securely (you might want to use Keychain for this)
        // For demonstration, we're just setting a flag
        DispatchQueue.main.async {
            self.isLoggedIn = true
        }
    }
}

class Backend: Equatable {
    let region: String
    let profile: String
    let endpoint: String
    let runtimeEndpoint: String
    private var logger = Logger(label: "Backend")
    private var awsCredentialIdentityResolver: any AWSCredentialIdentityResolver
    
    private lazy var bedrockClient: BedrockClient = createBedrockClient()
    private lazy var bedrockRuntimeClient: BedrockRuntimeClient = createBedrockRuntimeClient()
    
    init(region: String, profile: String, endpoint: String, runtimeEndpoint: String) {
        self.region = region
        self.profile = profile
        self.endpoint = endpoint
        self.runtimeEndpoint = runtimeEndpoint
        
        do {
            if let selectedProfile = SettingManager.shared.profiles.first(where: { $0.name == profile }) {
                if selectedProfile.type == .sso {
                    self.awsCredentialIdentityResolver = try SSOAWSCredentialIdentityResolver(profileName: profile)
                } else {
                    self.awsCredentialIdentityResolver = try ProfileAWSCredentialIdentityResolver(profileName: profile)
                }
            } else {
                self.awsCredentialIdentityResolver = try ProfileAWSCredentialIdentityResolver(profileName: profile)
            }
        } catch {
            logger.error("Failed to create credentials resolver: \(error). Using default credentials.")
            self.awsCredentialIdentityResolver = try! ProfileAWSCredentialIdentityResolver(profileName: "default")
        }
        
        logger.info("Backend initialized with region: \(region), profile: \(profile), endpoint: \(endpoint), runtimeEndpoint: \(runtimeEndpoint)")
    }

    func loginWithSSO(profileName: String? = nil) async throws {
        do {
            let ssoResolver = try SSOAWSCredentialIdentityResolver(
                profileName: profileName,
                configFilePath: nil,
                credentialsFilePath: nil
            )
            self.awsCredentialIdentityResolver = ssoResolver
            // Bedrock 클라이언트들을 새로운 자격 증명으로 재생성
            self.bedrockClient = createBedrockClient()
            self.bedrockRuntimeClient = createBedrockRuntimeClient()
            logger.info("Successfully logged in with SSO")
        } catch {
            logger.error("Failed to login with SSO: \(error)")
            throw error
        }
    }
    
    func isLoggedInWithSSO() -> Bool {
        return awsCredentialIdentityResolver is SSOAWSCredentialIdentityResolver
    }
    
    func logoutSSO() {
        do {
            self.awsCredentialIdentityResolver = try ProfileAWSCredentialIdentityResolver(profileName: profile)
            self.bedrockClient = createBedrockClient()
            self.bedrockRuntimeClient = createBedrockRuntimeClient()
            logger.info("Logged out from SSO and reverted to profile credentials")
        } catch {
            logger.error("Failed to revert to profile credentials after SSO logout: \(error)")
        }
    }
    
    private func createBedrockClient() -> BedrockClient {
        do {
            let config = try BedrockClient.BedrockClientConfiguration(
                awsCredentialIdentityResolver: self.awsCredentialIdentityResolver,
                region: self.region,
                signingRegion: self.region,
                endpoint: self.endpoint.isEmpty ? nil : self.endpoint
            )
            logger.info("Bedrock client created with region: \(self.region), profile: \(self.profile), endpoint: \(self.endpoint)")
            return BedrockClient(config: config)
        } catch {
            logger.error("Failed to create Bedrock client: \(error.localizedDescription)")
            fatalError("Unable to create Bedrock client: \(error.localizedDescription)")
        }
    }
    
    private func createBedrockRuntimeClient() -> BedrockRuntimeClient {
        do {
            let config = try BedrockRuntimeClient.BedrockRuntimeClientConfiguration(
                awsCredentialIdentityResolver: self.awsCredentialIdentityResolver,
                region: self.region,
                signingRegion: self.region,
                endpoint: self.runtimeEndpoint.isEmpty ? nil : self.runtimeEndpoint
            )
            logger.info("BedrockRuntime client created with region: \(self.region), profile: \(self.profile), runtimeEndpoint: \(self.runtimeEndpoint)")
            return BedrockRuntimeClient(config: config)
        } catch {
            logger.error("Failed to create Bedrock Runtime client: \(error.localizedDescription)")
            fatalError("Unable to create Bedrock Runtime client: \(error.localizedDescription)")
        }
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
    
    func invokeClaudeModel(withId modelId: String, messages: [ClaudeMessageRequest.Message]) async throws -> Data {
        let requestBody = ClaudeMessageRequest(
            anthropicVersion: "bedrock-2023-05-31",
            maxTokens: 4096,
            system: nil,
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
    
    func invokeClaudeModelStream(withId modelId: String, messages: [ClaudeMessageRequest.Message]) async throws -> AsyncThrowingStream<BedrockRuntimeClientTypes.ResponseStream, Swift.Error> {
        let requestBody = ClaudeMessageRequest(
            anthropicVersion: "bedrock-2023-05-31",
            maxTokens: 4096,
            system: nil,
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
        let promptData = [
            "text_prompts": [["text": prompt]],
            "cfg_scale": 6,
            "seed": Int.random(in: 0..<100),
            "steps": 50
        ] as [String : Any]
        
        let jsonData = try JSONSerialization.data(withJSONObject: promptData)
        
        if let jsonString = String(data: jsonData, encoding: .utf8) {
            logger.info("Serialized JSON: \(jsonString)")
        }
        
        let request = InvokeModelInput(
            accept: "image/png",
            body: jsonData,
            contentType: "application/json",
            modelId: modelId
        )
        
        let response = try await self.bedrockRuntimeClient.invokeModel(input: request)
        
        guard response.contentType == "image/png", let data = response.body else {
            logger.error("Invalid Bedrock response: \(response)")
            throw BedrockRuntimeError.invalidResponse(response.body)
        }
        
        return data
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
        } else if modelName.hasPrefix("stable-diffusion") {
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
