// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0

import Foundation

// MARK: - Nova Reel Task Types

/// Supported Nova Reel task types
enum NovaReelTaskType: String, Codable, CaseIterable, Identifiable {
    case textToVideo = "TEXT_VIDEO"
    case multiShotAutomated = "MULTI_SHOT_AUTOMATED"
    case multiShotManual = "MULTI_SHOT_MANUAL"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .textToVideo: return "Text to Video"
        case .multiShotAutomated: return "Multi-Shot (Auto)"
        case .multiShotManual: return "Multi-Shot (Manual)"
        }
    }
    
    var icon: String {
        switch self {
        case .textToVideo: return "video.badge.plus"
        case .multiShotAutomated: return "film.stack"
        case .multiShotManual: return "film"
        }
    }
    
    var taskDescription: String {
        switch self {
        case .textToVideo: return "Generate 6s video from text/image"
        case .multiShotAutomated: return "Auto-generate multi-shot video"
        case .multiShotManual: return "Manual control per shot"
        }
    }
    
    var maxPromptLength: Int {
        switch self {
        case .textToVideo: return 512
        case .multiShotAutomated: return 4000
        case .multiShotManual: return 512  // per shot
        }
    }
    
    var supportsInputImage: Bool {
        switch self {
        case .textToVideo: return true  // Optional first frame
        case .multiShotAutomated, .multiShotManual: return false
        }
    }
}

// MARK: - Nova Reel Video Generation Config

struct NovaReelVideoGenerationConfig: Codable {
    var durationSeconds: Int  // 6 for single shot, 6-120 (multiples of 6) for multi-shot
    var fps: Int  // Must be 24
    var dimension: String  // Must be "1280x720"
    var seed: Int  // 0-2,147,483,646, default 42
    
    init(
        durationSeconds: Int = 6,
        fps: Int = 24,
        dimension: String = "1280x720",
        seed: Int = 0
    ) {
        // Validate duration (must be multiple of 6, max 120)
        self.durationSeconds = min(max((durationSeconds / 6) * 6, 6), 120)
        self.fps = 24  // Only 24 is supported
        self.dimension = "1280x720"  // Only 1280x720 is supported
        self.seed = min(max(seed, 0), 2_147_483_646)
    }
}

// MARK: - Nova Reel Image Source

struct NovaReelImageSource: Codable {
    var format: String  // "png" or "jpeg"
    var source: NovaReelImageBytes
    
    struct NovaReelImageBytes: Codable {
        var bytes: String  // Base64 encoded image
    }
    
    init(base64Image: String, format: String = "png") {
        self.format = format
        self.source = NovaReelImageBytes(bytes: base64Image)
    }
}

// MARK: - Nova Reel Text to Video Parameters

struct NovaReelTextToVideoParams: Codable {
    var text: String
    var images: [NovaReelImageSource]?  // Optional single image for first frame
    
    init(text: String, firstFrameImage: String? = nil, imageFormat: String = "png") {
        self.text = String(text.prefix(512))
        if let image = firstFrameImage {
            self.images = [NovaReelImageSource(base64Image: image, format: imageFormat)]
        }
    }
}

// MARK: - Nova Reel Multi-Shot Automated Parameters

struct NovaReelMultiShotAutomatedParams: Codable {
    var text: String
    
    init(text: String) {
        self.text = String(text.prefix(4000))
    }
}

// MARK: - Nova Reel Multi-Shot Manual Parameters

struct NovaReelShotDescription: Codable {
    var text: String
    
    init(text: String) {
        self.text = String(text.prefix(512))
    }
}

struct NovaReelMultiShotManualParams: Codable {
    var shots: [NovaReelShotDescription]
    
    init(shots: [String]) {
        self.shots = shots.map { NovaReelShotDescription(text: $0) }
    }
}

// MARK: - Nova Reel Request

struct NovaReelRequest: Codable {
    var taskType: String
    var textToVideoParams: NovaReelTextToVideoParams?
    var multiShotAutomatedParams: NovaReelMultiShotAutomatedParams?
    var multiShotManualParams: NovaReelMultiShotManualParams?
    var videoGenerationConfig: NovaReelVideoGenerationConfig
    
    // MARK: - Factory Methods
    
    /// Create a text-to-video request (single 6s shot)
    static func textToVideo(
        prompt: String,
        firstFrameImage: String? = nil,
        imageFormat: String = "png",
        seed: Int = 0
    ) -> NovaReelRequest {
        NovaReelRequest(
            taskType: NovaReelTaskType.textToVideo.rawValue,
            textToVideoParams: NovaReelTextToVideoParams(
                text: prompt,
                firstFrameImage: firstFrameImage,
                imageFormat: imageFormat
            ),
            videoGenerationConfig: NovaReelVideoGenerationConfig(
                durationSeconds: 6,
                seed: seed
            )
        )
    }
    
    /// Create a multi-shot automated request
    static func multiShotAutomated(
        prompt: String,
        durationSeconds: Int,
        seed: Int = 0
    ) -> NovaReelRequest {
        NovaReelRequest(
            taskType: NovaReelTaskType.multiShotAutomated.rawValue,
            multiShotAutomatedParams: NovaReelMultiShotAutomatedParams(text: prompt),
            videoGenerationConfig: NovaReelVideoGenerationConfig(
                durationSeconds: durationSeconds,
                seed: seed
            )
        )
    }
    
    /// Create a multi-shot manual request
    static func multiShotManual(
        shots: [String],
        seed: Int = 0
    ) -> NovaReelRequest {
        let durationSeconds = shots.count * 6
        return NovaReelRequest(
            taskType: NovaReelTaskType.multiShotManual.rawValue,
            multiShotManualParams: NovaReelMultiShotManualParams(shots: shots),
            videoGenerationConfig: NovaReelVideoGenerationConfig(
                durationSeconds: durationSeconds,
                seed: seed
            )
        )
    }
}

// MARK: - Nova Reel Config (for Settings persistence)

struct NovaReelConfig: Codable, Equatable {
    var taskType: String
    var durationSeconds: Int
    var seed: Int
    var s3OutputBucket: String  // S3 bucket for video output
    var shots: [String]  // For manual multi-shot mode
    
    static var defaultConfig: NovaReelConfig {
        NovaReelConfig(
            taskType: NovaReelTaskType.textToVideo.rawValue,
            durationSeconds: 6,
            seed: 0,
            s3OutputBucket: "",
            shots: []
        )
    }
}

// MARK: - Nova Reel Job Status

enum NovaReelJobStatus: String, Codable {
    case inProgress = "InProgress"
    case completed = "Completed"
    case failed = "Failed"
    
    var displayName: String {
        switch self {
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }
    
    var icon: String {
        switch self {
        case .inProgress: return "clock.arrow.circlepath"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }
}

// MARK: - Nova Reel Job Info

struct NovaReelJobInfo: Identifiable, Codable {
    var id: String { invocationArn }
    var invocationArn: String
    var status: String
    var s3OutputUri: String?
    var submitTime: Date?
    var failureMessage: String?
    
    var jobStatus: NovaReelJobStatus {
        NovaReelJobStatus(rawValue: status) ?? .inProgress
    }
    
    var videoUri: String? {
        guard let outputUri = s3OutputUri else { return nil }
        return outputUri + "/output.mp4"
    }
}

// MARK: - Nova Reel Video Generation Status (from S3)

struct NovaReelVideoGenerationStatus: Codable {
    var schemaVersion: String?
    var shots: [NovaReelShotStatus]?
    var fullVideo: NovaReelVideoStatus?
    
    struct NovaReelShotStatus: Codable {
        var status: String?
        var location: String?
        var failureType: String?
        var failureMessage: String?
    }
    
    struct NovaReelVideoStatus: Codable {
        var status: String?
        var location: String?
        var failureType: String?
        var failureMessage: String?
    }
}

// MARK: - Nova Reel Service

class NovaReelService {
    static let modelId = "amazon.nova-reel-v1:1"
    static let s3Prefix = "amazon-bedrock-client/videos"
    
    /// Generate S3 output path with prefix
    /// Nova Reel requires trailing slash and creates a subfolder with invocation ID
    static func generateS3OutputPath(bucket: String) -> String {
        let baseBucket = bucket.hasSuffix("/") ? String(bucket.dropLast()) : bucket
        return "\(baseBucket)/\(s3Prefix)/"
    }
    
    /// Extract invocation ID from ARN
    static func extractInvocationId(from arn: String) -> String? {
        // ARN format: arn:aws:bedrock:region:account:async-invoke/invocation-id
        let components = arn.split(separator: "/")
        return components.last.map(String.init)
    }
    
    /// Estimated time for video generation
    static func estimatedTime(durationSeconds: Int) -> String {
        if durationSeconds <= 6 {
            return "~90 seconds"
        } else {
            let minutes = Double(durationSeconds / 6) * 1.5  // Roughly 90s per 6s shot
            if minutes < 2 {
                return "~\(Int(minutes * 60)) seconds"
            } else {
                return "~\(Int(minutes)) minutes"
            }
        }
    }
    
    /// Validate S3 bucket URI
    static func validateS3Uri(_ uri: String) -> (isValid: Bool, message: String?) {
        guard uri.hasPrefix("s3://") else {
            return (false, "S3 URI must start with 's3://'")
        }
        let path = uri.replacingOccurrences(of: "s3://", with: "")
        guard !path.isEmpty else {
            return (false, "S3 bucket name cannot be empty")
        }
        // Extract bucket name (before first /)
        let bucketName = path.split(separator: "/").first.map(String.init) ?? path
        guard !bucketName.isEmpty else {
            return (false, "S3 bucket name cannot be empty")
        }
        // Note: Nova Reel requires S3 bucket in us-east-1 region
        return (true, nil)
    }
    
    /// Get available duration options
    static var durationOptions: [(label: String, seconds: Int)] {
        [
            ("6 seconds", 6),
            ("12 seconds", 12),
            ("18 seconds", 18),
            ("24 seconds", 24),
            ("30 seconds", 30),
            ("1 minute", 60),
            ("2 minutes", 120)
        ]
    }
}
