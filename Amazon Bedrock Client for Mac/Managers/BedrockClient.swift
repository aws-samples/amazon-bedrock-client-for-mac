// MARK: - Imports

import Foundation
import Combine
import Logging
import AWSSTS
import AWSBedrock
import AWSBedrockRuntime
import AWSClientRuntime
import AppKit

// MARK: - Backend Class
class BackendModel: ObservableObject {
    @Published var backend: Backend
    
    var cancellables = Set<AnyCancellable>()  // To hold subscription
    
    init() {
        self.backend = Backend(region: AWSRegion.usEast1.rawValue)
        
        updateBackend()
        
        // Assuming SettingManager.shared has a publisher that emits events when AWS region is saved
        SettingManager.shared.awsRegionPublisher
            .sink { [weak self] newRegion in
                self?.updateBackend()
            }
            .store(in: &cancellables)
    }
    
    private func updateBackend() {
        let region: String = SettingManager.shared.getAWSRegion()?.rawValue ?? AWSRegion.usEast1.rawValue // Default to "us-east-1"
        self.backend = Backend(region: region)
    }
}


struct Backend {
    
    // MARK: - Properties
    
    private var logger = Logger(label: "Backend")
    private let credentials: AWSTemporaryCredentials?
    private let region: String
    
    // MARK: - Initializers
    
    init(withCredentials creds: AWSTemporaryCredentials? = nil, region: String) {
        self.credentials = creds
        self.region = region
#if DEBUG
        self.logger.logLevel = .debug
#endif
    }
    
    // MARK: - AWS Methods
    
    func getAWSCredentials(for stsParams: STSParameters, siwaToken token: String) async throws -> AWSTemporaryCredentials {
        let stsClient = try STSClient(region: self.region) // Use injected region
        let sessionDuration = 3600
        let sessionName = "SwiftGenAI"
        let roleArn = "arn:aws:iam::\(stsParams.awsAccountId):role/\(stsParams.roleName)"
        
        let request = AssumeRoleWithWebIdentityInput(
            durationSeconds: sessionDuration,
            roleArn: roleArn,
            roleSessionName: sessionName,
            webIdentityToken: token)
        let response = try await stsClient.assumeRoleWithWebIdentity(input: request)
        
        guard let credentials = response.credentials else {
            logger.error("Invalid credentials (nil)")
            throw STSError.invalidAssumeRoleWithWebIdentityResponse("credentials is nil")
        }
        
        return try AWSTemporaryCredentials(from: credentials)
    }
    
    func invokeModel(withId modelId: String, prompt: String) async throws -> Data {
        // Determine the model type (claude or titan)
        let modelType = getModelType(modelId)
        
        let strategy: JSONEncoder.KeyEncodingStrategy = (modelType == .claude || modelType == .llama2) ? .convertToSnakeCase : .useDefaultKeys
        
        let params = getModelParameters(modelType: modelType, prompt: prompt)
        let encodedParams = try self.encode(params, strategy: strategy)
        
        let request = InvokeModelInput(body: encodedParams,
                                       contentType: "application/json",
                                       modelId: modelId)
        
        // Log the JSON-structured encoded request body
        if let requestJson = String(data: encodedParams, encoding: .utf8) {
            logger.info("Request: \(requestJson)")
        }
        
        let config = try await BedrockRuntimeClient.BedrockRuntimeClientConfiguration(region: self.region)
        
        let client = BedrockRuntimeClient(config: config)
        let response = try await client.invokeModel(input: request)
        
        guard response.contentType == "application/json",
              let data = response.body else {
            logger.error("Invalid Bedrock response: \(response)")
            throw BedrockRuntimeError.invalidResponse(response.body)
        }
        
        return data
    }
    
    // Add or modify this function in your Backend struct
    func invokeModelStream(withId modelId: String, prompt: String) async throws -> AsyncThrowingStream<BedrockRuntimeClientTypes.ResponseStream, Swift.Error> {
        // Determine the model type and parameters
        let modelType = getModelType(modelId)
        
        // Determine the appropriate key encoding strategy for the model type
        let strategy: JSONEncoder.KeyEncodingStrategy = (modelType == .claude || modelType == .llama2) ? .convertToSnakeCase : .useDefaultKeys
        
        let params = getModelParameters(modelType: modelType, prompt: prompt)
        
        do {
            // Encode parameters and create request using the appropriate key encoding strategy
            let encodedParams = try self.encode(params, strategy: strategy)
            let request = InvokeModelWithResponseStreamInput(
                body: encodedParams,
                contentType: "application/json",
                modelId: modelId)
            
            // Log the JSON-structured encoded request body
            if let requestJson = String(data: encodedParams, encoding: .utf8) {
                logger.info("Request: \(requestJson)")
            }
            
            // Create client and make the request
            let config = try await BedrockRuntimeClient.BedrockRuntimeClientConfiguration(region: self.region)
            let client = BedrockRuntimeClient(config: config)
            
            // Invoke the model and get the response stream
            let output = try await client.invokeModelWithResponseStream(input: request)
            
            return output.body ?? AsyncThrowingStream { _ in }
            
        } catch {
            // Log other errors
            logger.error("Error: \(error)")
            throw error
        }
    }
    
    func invokeStableDiffusionModel(withId modelId: String, prompt: String) async throws -> Data {
        let promptData = [
            "text_prompts": [["text": prompt]],
            "cfg_scale": 6,
            "seed": Int.random(in: 0..<100),
            "steps": 50
        ] as [String : Any]
        
        let jsonData: Data
        do {
            jsonData = try JSONSerialization.data(withJSONObject: promptData)
        } catch {
            logger.error("Error serializing JSON: \(error)")
            throw BedrockRuntimeError.requestFailed
        }
        
        if let jsonString = String(data: jsonData, encoding: .utf8) {
            logger.info("Serialized JSON: \(jsonString)")
        }
        
        let contentType = "application/json"
        let accept = "image/png"
        
        // Prepare the request
        let request = InvokeModelInput(
            accept: accept,
            body: jsonData,
            contentType: contentType,
            modelId: modelId
        )
        
        // Create client and make the request
        let config = try await BedrockRuntimeClient.BedrockRuntimeClientConfiguration(region: self.region)
        let client = BedrockRuntimeClient(config: config)
        
        let response = try await client.invokeModel(input: request)
        
        guard response.contentType == "image/png", let data = response.body else {
            logger.error("Invalid Bedrock response: \(response)")
            throw BedrockRuntimeError.invalidResponse(response.body)
        }
        
        return data
    }
    
    // Helper function to determine the model type based on modelId
    func getModelType(_ modelId: String) -> FoundationModelType {
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
        } else if modelName.hasPrefix("stable-diffusion") {
            return .stableDiffusion
        } else if modelName.hasPrefix("llama2") {
            return .llama2
        } else {
            return .unknown
        }
    }
    
    // Function to get model parameters
    func getModelParameters(modelType: FoundationModelType, prompt: String) -> ModelParameters {
        switch modelType {
        case .claude:
            return ClaudeModelParameters(prompt: "Human: \(prompt)\n\nAssistant:")
        case .titan:
            let textGenerationConfig = TitanModelParameters.TextGenerationConfig(
                temperature: 0,
                topP: 1.0,
                maxTokenCount: 4086,
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
        case .llama2:
            return Llama2ModelParameters(prompt: "Prompt: \(prompt)\n\nAnswer:", maxGenLen: 2048, topP: 0.9, temperature: 0.9)
        default:
            return ClaudeModelParameters(prompt: "Human: \(prompt)\n\nAssistant:")
        }
    }
    
    func listFoundationModels(byCustomizationType: BedrockClientTypes.ModelCustomization? = nil,
                              byInferenceType: BedrockClientTypes.InferenceType? = nil,
                              byOutputModality: BedrockClientTypes.ModelModality? = nil,
                              byProvider: String? = nil) async -> Result<[BedrockClientTypes.FoundationModelSummary], BedrockError> {
        
        do {
            let request = ListFoundationModelsInput(
                byCustomizationType: byCustomizationType,
                byInferenceType: byInferenceType,
                byOutputModality: byOutputModality,
                byProvider: byProvider)
            
            let config = try await BedrockClient.BedrockClientConfiguration(
                region: self.region)
            
            let client = BedrockClient(config: config)
            
            let response = try await client.listFoundationModels(input: request)
            
            if let modelSummaries = response.modelSummaries {
                return .success(modelSummaries)
            } else {
                logger.error("Invalid Bedrock response: \(response)")
                return .failure(BedrockError.invalidResponse("Model summaries are missing"))
            }
            
        } catch {
            if let awsError = error as? AWSClientRuntime.UnknownAWSHTTPServiceError {
                if awsError.typeName == "ExpiredTokenException" {
                    logger.error("Token has expired")
                    return .failure(BedrockError.tokenExpired)
                } else if awsError.typeName == "UnrecognizedClientException" {
                    logger.error("The security token included in the request is invalid.")
                    return .failure(BedrockError.genericError("The security token included in the request is invalid."))
                }
            } else {
                logger.error("General error occurred: \(error)")
                return .failure(BedrockError.genericError(error.localizedDescription))
            }
        }
        
        return .failure(BedrockError.genericError("An unexpected error occurred"))
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
// MARK: - Data structures
/**
 The required parameters for Sign In WIth Apple.  All these are coming from Apple's developer portal and
 Sign In With Apple configuration
 */
struct STSParameters {
    init(awsAccountId: String, roleName: String) {
        self.awsAccountId = awsAccountId
        self.roleName = roleName
    }
    let awsAccountId : String
    let roleName : String
}
/**
 SDK agnostic represnetation of AWS Credentials
 */
struct AWSTemporaryCredentials: Codable {
    let accessKey: String
    let secretAccessKey: String
    let expiration: Date?
    let sessionToken: String
    
    init(accessKey: String, secretAccessKey: String, expiration: Date? = nil, sessionToken: String) {
        self.accessKey = accessKey
        self.secretAccessKey = secretAccessKey
        self.expiration = expiration
        self.sessionToken = sessionToken
    }
    init(from credentials: STSClientTypes.Credentials) throws {
        guard let accessKeyId = credentials.accessKeyId,
              let secretAccessKey = credentials.secretAccessKey,
              let sessionToken = credentials.sessionToken,
              let expiration = credentials.expiration
        else {
            throw STSError.invalidAssumeRoleWithWebIdentityResponse("one of the access key or secret is nil")
        }
        self.init(
            accessKey: accessKeyId,
            secretAccessKey: secretAccessKey,
            expiration: expiration,
            sessionToken: sessionToken)
    }
}
extension AWSTemporaryCredentials: CredentialsProviding {
    func getCredentials() async throws -> Credentials {
        return Credentials(accessKey: self.accessKey,
                           secret: self.secretAccessKey,
                           expirationTimeout: self.expiration,
                           sessionToken: self.sessionToken)
    }
}
extension AWSTemporaryCredentials {
    
    /*
     
     Generated by Claude v2.
     
     I modified the generated code to return Static Credentials and
     to provide a default value
     
     Prompt :
     
     Write a swift function that takes one parameter as input
     (profile) and returns two values, an AWS access key and AWS secret key.
     The function will read a files in ~/.aws/credentials. The file might
     have multiple profiles identified as [profile_name]. For each profile,
     there are two values to return aws_access_key_id is the aws access key
     and aws_secret_access_key contains the AWS secret key.  Here is an
     exemple of the file format :
     [default]
     aws_access_key_id=AKIA12344567890EYFQT
     aws_secret_access_key=Us412344567890gtNW
     
     [seb]
     aws_access_key_id=AKIA12344567890PQ
     aws_secret_access_key=4Oa12344567890MRy
     
     */
    
    static func getEnvironmentVariable(named: String) -> String? {
        return ProcessInfo.processInfo.environment[named]
    }
    
    static func fromConfigurationFile(forProfile profile: String = "default",
                                      filePath path: String = "~/.aws/credentials") -> AWSTemporaryCredentials {
        
        let credentialsURL = URL(fileURLWithPath: resolveFilePath(path))
        
        guard let credentialsString = try? String(contentsOf: credentialsURL) else {
            fatalError("Unable to load AWS credentials file")
        }
        
        var accessKey = ""
        var secretKey = ""
        var sessionToken = ""
        
        let profileLines = credentialsString.components(separatedBy: "\n")
        
        var inProfile = false
        
        for line in profileLines {
            if line.hasPrefix("[") && line.hasSuffix("]") {
                let currentProfile = line.trimmingCharacters(in: .init(charactersIn: "[]"))
                inProfile = (currentProfile == profile)
            } else if inProfile {
                if line.hasPrefix("aws_access_key_id") {
                    accessKey = line.components(separatedBy: " = ").last!.trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("aws_secret_access_key") {
                    secretKey = line.components(separatedBy: " = ").last!.trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("aws_session_token") {
                    sessionToken = line.components(separatedBy: " = ").last!.trimmingCharacters(in: .whitespaces)
                }
            }
        }
        
        accessKey = getEnvironmentVariable(named: "AWS_ACCESS_KEY_ID") ?? accessKey
        secretKey = getEnvironmentVariable(named: "AWS_SECRET_ACCESS_KEY") ?? secretKey
        sessionToken = getEnvironmentVariable(named: "AWS_SESSION_TOKEN") ?? sessionToken
        
        guard !accessKey.isEmpty && !secretKey.isEmpty else {
            fatalError("Unable to load AWS credentials file")
        }
        
        return AWSTemporaryCredentials(accessKey: accessKey, secretAccessKey: secretKey, sessionToken: sessionToken)
    }
    
    private static func resolveFilePath(_ path: String) -> String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        
        if path.starts(with: "~") {
            let filePath = path.replacingOccurrences(of: "~", with: homeDir)
            return filePath
        }
        
        return path
    }
}
public enum BedrockModelProvider : String {
    case titan = "Amazon"
    case claude = "Anthropic"
    case stabledifusion = "Stability AI"
    case j2 = "AI21 Labs"
}

enum FoundationModelType {
    case titan
    case titanEmbed
    case titanImage
    case claude
    case j2
    case cohereCommand
    case stableDiffusion
    case llama2
    case unknown
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

public enum ModelType {
    case claude
    case titan
}

// Model response protocols
protocol ModelResponse {}

public struct InvokeClaudeResponse: ModelResponse, Decodable {
    public let completion: String
    public let stop_reason: String
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

public struct InvokeStableDiffusionResponse: ModelResponse, Decodable {
    public let body: Data // Specify the type here
}

public struct InvokeLlama2Response: ModelResponse, Decodable {
    public let generation: String
}

struct ListFoundationModelsResponse: Decodable {
    public var modelSummaries: [BedrockClientTypes.FoundationModelSummary]?
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
