// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0

//
//  VideoGenerationService.swift
//  Amazon Bedrock Client for Mac
//
//  Handles asynchronous video generation for Amazon Nova Reel
//  Note: Nova Reel requires the async invoke API which saves videos to S3
//

import AWSBedrockRuntime
import AWSS3
import AWSSDKIdentity
import Foundation
import Logging
import Smithy
import SmithyIdentity
import SmithyIdentityAPI

// MARK: - Video Generation Service

/// Service for invoking video generation models on Amazon Bedrock
/// Nova Reel uses async invoke API - videos are generated asynchronously and saved to S3
final class VideoGenerationService: @unchecked Sendable {
    private let bedrockRuntimeClient: BedrockRuntimeClient
    private let awsCredentialIdentityResolver: (any AWSCredentialIdentityResolver)?
    private let region: String
    private let logger = Logger(label: "VideoGenerationService")
    
    init(bedrockRuntimeClient: BedrockRuntimeClient) {
        self.bedrockRuntimeClient = bedrockRuntimeClient
        self.awsCredentialIdentityResolver = nil
        self.region = "us-east-1"
    }
    
    init(bedrockRuntimeClient: BedrockRuntimeClient, credentialResolver: any AWSCredentialIdentityResolver, region: String) {
        self.bedrockRuntimeClient = bedrockRuntimeClient
        self.awsCredentialIdentityResolver = credentialResolver
        self.region = region
    }
    
    // MARK: - Start Video Generation
    
    /// Start an asynchronous video generation job
    /// - Parameters:
    ///   - request: The Nova Reel request configuration
    ///   - s3OutputUri: S3 URI where the video will be saved (e.g., "s3://my-bucket/videos")
    /// - Returns: The invocation ARN for tracking the job
    func startVideoGeneration(
        request: NovaReelRequest,
        s3OutputUri: String
    ) async throws -> String {
        // Validate S3 URI
        let validation = NovaReelService.validateS3Uri(s3OutputUri)
        guard validation.isValid else {
            throw VideoGenerationError.invalidS3Uri(validation.message ?? "Invalid S3 URI")
        }
        
        // Encode request to JSON
        let encoder = JSONEncoder()
        let requestData = try encoder.encode(request)
        
        guard let requestJson = try? JSONSerialization.jsonObject(with: requestData) as? [String: Any] else {
            throw VideoGenerationError.invalidResponse
        }
        
        // Convert to Smithy Document format
        let modelInput = try Self.convertToDocument(requestJson)
        
        // Create async invoke input
        let input = StartAsyncInvokeInput(
            modelId: NovaReelService.modelId,
            modelInput: modelInput,
            outputDataConfig: .s3outputdataconfig(
                BedrockRuntimeClientTypes.AsyncInvokeS3OutputDataConfig(s3Uri: s3OutputUri)
            )
        )
        
        // Start async invocation
        let response = try await bedrockRuntimeClient.startAsyncInvoke(input: input)
        
        guard let invocationArn = response.invocationArn else {
            throw VideoGenerationError.noInvocationArn
        }
        
        logger.info("Started video generation job: \(invocationArn)")
        return invocationArn
    }
    
    /// Convert dictionary to Smithy Document using SDK's make method
    private static func convertToDocument(_ value: Any) throws -> Smithy.Document {
        return try Smithy.Document.make(from: value)
    }
    
    // MARK: - Check Job Status
    
    /// Get the status of a video generation job
    func getJobStatus(invocationArn: String) async throws -> NovaReelJobInfo {
        let input = GetAsyncInvokeInput(invocationArn: invocationArn)
        let response = try await bedrockRuntimeClient.getAsyncInvoke(input: input)
        
        var s3OutputUri: String? = nil
        if case .s3outputdataconfig(let s3Config) = response.outputDataConfig {
            s3OutputUri = s3Config.s3Uri
        }
        
        return NovaReelJobInfo(
            invocationArn: invocationArn,
            status: response.status?.rawValue ?? "Unknown",
            s3OutputUri: s3OutputUri,
            submitTime: response.submitTime,
            failureMessage: response.failureMessage
        )
    }
    
    // MARK: - List Jobs
    
    /// List video generation jobs
    func listJobs(
        maxResults: Int = 10,
        statusFilter: NovaReelJobStatus? = nil
    ) async throws -> [NovaReelJobInfo] {
        var statusEquals: BedrockRuntimeClientTypes.AsyncInvokeStatus? = nil
        if let filter = statusFilter {
            statusEquals = BedrockRuntimeClientTypes.AsyncInvokeStatus(rawValue: filter.rawValue)
        }
        
        let input = ListAsyncInvokesInput(
            maxResults: maxResults,
            statusEquals: statusEquals
        )
        
        let response = try await bedrockRuntimeClient.listAsyncInvokes(input: input)
        
        return response.asyncInvokeSummaries?.compactMap { summary in
            var s3OutputUri: String? = nil
            if case .s3outputdataconfig(let s3Config) = summary.outputDataConfig {
                s3OutputUri = s3Config.s3Uri
            }
            
            return NovaReelJobInfo(
                invocationArn: summary.invocationArn ?? "",
                status: summary.status?.rawValue ?? "Unknown",
                s3OutputUri: s3OutputUri,
                submitTime: summary.submitTime,
                failureMessage: summary.failureMessage
            )
        } ?? []
    }
    
    // MARK: - Convenience Methods
    
    /// Start a text-to-video generation job
    func startTextToVideo(
        prompt: String,
        firstFrameImage: String? = nil,
        imageFormat: String = "png",
        seed: Int = 0,
        s3OutputUri: String
    ) async throws -> String {
        let request = NovaReelRequest.textToVideo(
            prompt: prompt,
            firstFrameImage: firstFrameImage,
            imageFormat: imageFormat,
            seed: seed
        )
        return try await startVideoGeneration(request: request, s3OutputUri: s3OutputUri)
    }
    
    /// Start a multi-shot automated video generation job
    func startMultiShotAutomated(
        prompt: String,
        durationSeconds: Int,
        seed: Int = 0,
        s3OutputUri: String
    ) async throws -> String {
        let request = NovaReelRequest.multiShotAutomated(
            prompt: prompt,
            durationSeconds: durationSeconds,
            seed: seed
        )
        return try await startVideoGeneration(request: request, s3OutputUri: s3OutputUri)
    }
    
    /// Start a multi-shot manual video generation job
    func startMultiShotManual(
        shots: [String],
        seed: Int = 0,
        s3OutputUri: String
    ) async throws -> String {
        let request = NovaReelRequest.multiShotManual(
            shots: shots,
            seed: seed
        )
        return try await startVideoGeneration(request: request, s3OutputUri: s3OutputUri)
    }
    
    // MARK: - S3 Video Download
    
    /// Parse S3 URI into bucket and key
    static func parseS3Uri(_ uri: String) -> (bucket: String, key: String)? {
        guard uri.hasPrefix("s3://") else { return nil }
        let path = String(uri.dropFirst(5))  // Remove "s3://"
        guard let slashIndex = path.firstIndex(of: "/") else { return nil }
        let bucket = String(path[..<slashIndex])
        let key = String(path[path.index(after: slashIndex)...])
        return (bucket, key)
    }
    
    /// Get local video cache directory (uses same base as ImageStorageManager)
    @MainActor
    static var videoCacheDirectory: URL {
        let baseDir = URL(fileURLWithPath: SettingManager.shared.defaultDirectory)
        let videosDir = baseDir.appendingPathComponent("generated_videos", isDirectory: true)
        
        if !FileManager.default.fileExists(atPath: videosDir.path) {
            try? FileManager.default.createDirectory(at: videosDir, withIntermediateDirectories: true)
        }
        
        return videosDir
    }
    
    /// Generate local filename for video
    static func localVideoFilename(for s3Uri: String) -> String {
        let hash = s3Uri.hashValue
        return "video_\(abs(hash)).mp4"
    }
    
    /// Download video from S3 to local cache
    /// - Parameter s3Uri: Full S3 URI (e.g., "s3://bucket/path/output.mp4")
    /// - Returns: Local file URL where video was downloaded
    func downloadVideoFromS3(s3Uri: String) async throws -> URL {
        guard let resolver = awsCredentialIdentityResolver else {
            throw VideoGenerationError.s3DownloadFailed("Credential resolver not available")
        }
        
        guard let parsed = Self.parseS3Uri(s3Uri) else {
            throw VideoGenerationError.invalidS3Uri("Cannot parse S3 URI: \(s3Uri)")
        }
        
        // Get cache directory on main actor
        let cacheDir = await MainActor.run { Self.videoCacheDirectory }
        
        // Prepare local file path
        let localFilename = Self.localVideoFilename(for: s3Uri)
        let localUrl = cacheDir.appendingPathComponent(localFilename)
        
        // Check if already cached
        if FileManager.default.fileExists(atPath: localUrl.path) {
            logger.info("Video already cached at: \(localUrl.path)")
            return localUrl
        }
        
        // Create S3 client
        let s3Config = try await S3Client.S3ClientConfiguration(
            awsCredentialIdentityResolver: resolver,
            region: region
        )
        let s3Client = S3Client(config: s3Config)
        
        // Download from S3
        let getObjectInput = GetObjectInput(
            bucket: parsed.bucket,
            key: parsed.key
        )
        
        let response = try await s3Client.getObject(input: getObjectInput)
        
        guard let body = response.body else {
            throw VideoGenerationError.s3DownloadFailed("Empty response body")
        }
        
        // Read all data from the stream
        let data = try await body.readData()
        
        guard let videoData = data else {
            throw VideoGenerationError.s3DownloadFailed("Failed to read video data")
        }
        
        // Write to local file
        try videoData.write(to: localUrl)
        
        logger.info("Downloaded video to: \(localUrl.path)")
        return localUrl
    }
}

// MARK: - Video Generation Errors

enum VideoGenerationError: LocalizedError {
    case invalidS3Uri(String)
    case noInvocationArn
    case jobFailed(String)
    case invalidResponse
    case unsupportedModel(String)
    case s3DownloadFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidS3Uri(let message):
            return "Invalid S3 URI: \(message)"
        case .noInvocationArn:
            return "No invocation ARN returned from video generation request"
        case .jobFailed(let message):
            return "Video generation failed: \(message)"
        case .invalidResponse:
            return "Invalid response from video generation service"
        case .unsupportedModel(let modelId):
            return "Unsupported video generation model: \(modelId)"
        case .s3DownloadFailed(let message):
            return "Failed to download video from S3: \(message)"
        }
    }
}
