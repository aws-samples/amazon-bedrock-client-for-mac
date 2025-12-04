// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0

import Foundation

// MARK: - Nova Canvas Task Types

/// All supported Nova Canvas task types
enum NovaCanvasTaskType: String, Codable, CaseIterable {
    case textToImage = "TEXT_IMAGE"
    case colorGuidedGeneration = "COLOR_GUIDED_GENERATION"
    case imageVariation = "IMAGE_VARIATION"
    case inpainting = "INPAINTING"
    case outpainting = "OUTPAINTING"
    case backgroundRemoval = "BACKGROUND_REMOVAL"
    
    var displayName: String {
        switch self {
        case .textToImage: return "Text to Image"
        case .colorGuidedGeneration: return "Color Guided"
        case .imageVariation: return "Image Variation"
        case .inpainting: return "Inpainting"
        case .outpainting: return "Outpainting"
        case .backgroundRemoval: return "Background Removal"
        }
    }
    
    var requiresInputImage: Bool {
        switch self {
        case .textToImage: return false
        case .colorGuidedGeneration: return false // optional
        case .imageVariation, .inpainting, .outpainting, .backgroundRemoval: return true
        }
    }
    
    var supportsMask: Bool {
        switch self {
        case .inpainting, .outpainting: return true
        default: return false
        }
    }
}

/// Control modes for image conditioning
enum NovaCanvasControlMode: String, Codable, CaseIterable {
    case cannyEdge = "CANNY_EDGE"
    case segmentation = "SEGMENTATION"
    
    var displayName: String {
        switch self {
        case .cannyEdge: return "Canny Edge"
        case .segmentation: return "Segmentation"
        }
    }
}

/// Outpainting modes
enum NovaCanvasOutpaintingMode: String, Codable, CaseIterable {
    case defaultMode = "DEFAULT"
    case precise = "PRECISE"
    
    var displayName: String {
        switch self {
        case .defaultMode: return "Default"
        case .precise: return "Precise"
        }
    }
}

// MARK: - Nova Canvas Request Models

/// Base image generation configuration shared across all tasks
struct NovaCanvasImageGenerationConfig: Codable {
    var width: Int
    var height: Int
    var quality: String
    var cfgScale: Float
    var seed: Int
    var numberOfImages: Int
    
    init(
        width: Int = 1024,
        height: Int = 1024,
        quality: String = "standard",
        cfgScale: Float = 8.0,
        seed: Int = 0,
        numberOfImages: Int = 1
    ) {
        // Validate dimensions
        self.width = Self.validateDimension(width)
        self.height = Self.validateDimension(height)
        self.quality = quality
        self.cfgScale = min(max(cfgScale, 1.0), 10.0)
        self.seed = seed
        self.numberOfImages = min(max(numberOfImages, 1), 5)
    }
    
    /// Validates dimension to meet Nova Canvas requirements
    /// - Each side: 320-4096 pixels
    /// - Must be divisible by 16
    /// - Total pixels <= 4,194,304
    private static func validateDimension(_ value: Int) -> Int {
        var result = min(max(value, 320), 4096)
        result = (result / 16) * 16
        return result
    }
}

// MARK: - Text to Image Parameters

struct NovaCanvasTextToImageParams: Codable {
    var text: String
    var negativeText: String?
    var conditionImage: String?  // Base64 encoded image for conditioning
    var controlMode: String?     // CANNY_EDGE or SEGMENTATION
    var controlStrength: Float?  // 0.0 to 1.0
    
    init(
        text: String,
        negativeText: String? = nil,
        conditionImage: String? = nil,
        controlMode: NovaCanvasControlMode? = nil,
        controlStrength: Float? = nil
    ) {
        // Nova Canvas has 1024 character limit for prompts
        self.text = String(text.prefix(1024))
        self.negativeText = negativeText
        self.conditionImage = conditionImage
        self.controlMode = controlMode?.rawValue
        if let strength = controlStrength {
            self.controlStrength = min(max(strength, 0.0), 1.0)
        }
    }
}

// MARK: - Color Guided Generation Parameters

struct NovaCanvasColorGuidedGenerationParams: Codable {
    var text: String
    var negativeText: String?
    var colors: [String]  // Hex color codes (1-10)
    var referenceImage: String?  // Optional base64 encoded reference image
    
    init(
        text: String,
        negativeText: String? = nil,
        colors: [String],
        referenceImage: String? = nil
    ) {
        self.text = String(text.prefix(1024))
        self.negativeText = negativeText
        // Limit to 1-10 colors
        self.colors = Array(colors.prefix(10))
        self.referenceImage = referenceImage
    }
}

// MARK: - Image Variation Parameters

struct NovaCanvasImageVariationParams: Codable {
    var text: String?
    var negativeText: String?
    var images: [String]  // 1-5 base64 encoded images
    var similarityStrength: Float  // 0.2 to 1.0
    
    init(
        text: String? = nil,
        negativeText: String? = nil,
        images: [String],
        similarityStrength: Float = 0.7
    ) {
        if let t = text {
            self.text = String(t.prefix(1024))
        }
        self.negativeText = negativeText
        // Limit to 1-5 images
        self.images = Array(images.prefix(5))
        self.similarityStrength = min(max(similarityStrength, 0.2), 1.0)
    }
}

// MARK: - Inpainting Parameters

struct NovaCanvasInpaintingParams: Codable {
    var text: String?
    var negativeText: String?
    var image: String  // Base64 encoded source image
    var maskPrompt: String?  // Natural language mask description
    var maskImage: String?   // Base64 encoded mask image (black = area to change)
    
    init(
        text: String? = nil,
        negativeText: String? = nil,
        image: String,
        maskPrompt: String? = nil,
        maskImage: String? = nil
    ) {
        if let t = text {
            self.text = String(t.prefix(1024))
        }
        self.negativeText = negativeText
        self.image = image
        self.maskPrompt = maskPrompt
        self.maskImage = maskImage
    }
}

// MARK: - Outpainting Parameters

struct NovaCanvasOutpaintingParams: Codable {
    var text: String?
    var negativeText: String?
    var image: String  // Base64 encoded source image
    var maskPrompt: String?
    var maskImage: String?
    var outPaintingMode: String
    
    init(
        text: String? = nil,
        negativeText: String? = nil,
        image: String,
        maskPrompt: String? = nil,
        maskImage: String? = nil,
        outPaintingMode: NovaCanvasOutpaintingMode = .defaultMode
    ) {
        if let t = text {
            self.text = String(t.prefix(1024))
        }
        self.negativeText = negativeText
        self.image = image
        self.maskPrompt = maskPrompt
        self.maskImage = maskImage
        self.outPaintingMode = outPaintingMode.rawValue
    }
}

// MARK: - Background Removal Parameters

struct NovaCanvasBackgroundRemovalParams: Codable {
    var image: String  // Base64 encoded source image
    
    init(image: String) {
        self.image = image
    }
}

// MARK: - Unified Nova Canvas Request

/// Unified request structure for all Nova Canvas operations
struct NovaCanvasRequest: Codable {
    var taskType: String
    var textToImageParams: NovaCanvasTextToImageParams?
    var colorGuidedGenerationParams: NovaCanvasColorGuidedGenerationParams?
    var imageVariationParams: NovaCanvasImageVariationParams?
    var inPaintingParams: NovaCanvasInpaintingParams?
    var outPaintingParams: NovaCanvasOutpaintingParams?
    var backgroundRemovalParams: NovaCanvasBackgroundRemovalParams?
    var imageGenerationConfig: NovaCanvasImageGenerationConfig?
    
    // MARK: - Factory Methods
    
    /// Create a text-to-image request
    static func textToImage(
        prompt: String,
        negativePrompt: String? = nil,
        conditionImage: String? = nil,
        controlMode: NovaCanvasControlMode? = nil,
        controlStrength: Float? = nil,
        config: NovaCanvasImageGenerationConfig = NovaCanvasImageGenerationConfig()
    ) -> NovaCanvasRequest {
        NovaCanvasRequest(
            taskType: NovaCanvasTaskType.textToImage.rawValue,
            textToImageParams: NovaCanvasTextToImageParams(
                text: prompt,
                negativeText: negativePrompt,
                conditionImage: conditionImage,
                controlMode: controlMode,
                controlStrength: controlStrength
            ),
            imageGenerationConfig: config
        )
    }
    
    /// Create a color-guided generation request
    static func colorGuided(
        prompt: String,
        negativePrompt: String? = nil,
        colors: [String],
        referenceImage: String? = nil,
        config: NovaCanvasImageGenerationConfig = NovaCanvasImageGenerationConfig()
    ) -> NovaCanvasRequest {
        NovaCanvasRequest(
            taskType: NovaCanvasTaskType.colorGuidedGeneration.rawValue,
            colorGuidedGenerationParams: NovaCanvasColorGuidedGenerationParams(
                text: prompt,
                negativeText: negativePrompt,
                colors: colors,
                referenceImage: referenceImage
            ),
            imageGenerationConfig: config
        )
    }
    
    /// Create an image variation request
    static func imageVariation(
        images: [String],
        prompt: String? = nil,
        negativePrompt: String? = nil,
        similarityStrength: Float = 0.7,
        config: NovaCanvasImageGenerationConfig = NovaCanvasImageGenerationConfig()
    ) -> NovaCanvasRequest {
        NovaCanvasRequest(
            taskType: NovaCanvasTaskType.imageVariation.rawValue,
            imageVariationParams: NovaCanvasImageVariationParams(
                text: prompt,
                negativeText: negativePrompt,
                images: images,
                similarityStrength: similarityStrength
            ),
            imageGenerationConfig: config
        )
    }
    
    /// Create an inpainting request
    static func inpainting(
        image: String,
        prompt: String? = nil,
        negativePrompt: String? = nil,
        maskPrompt: String? = nil,
        maskImage: String? = nil,
        config: NovaCanvasImageGenerationConfig = NovaCanvasImageGenerationConfig()
    ) -> NovaCanvasRequest {
        NovaCanvasRequest(
            taskType: NovaCanvasTaskType.inpainting.rawValue,
            inPaintingParams: NovaCanvasInpaintingParams(
                text: prompt,
                negativeText: negativePrompt,
                image: image,
                maskPrompt: maskPrompt,
                maskImage: maskImage
            ),
            imageGenerationConfig: config
        )
    }
    
    /// Create an outpainting request
    static func outpainting(
        image: String,
        prompt: String? = nil,
        negativePrompt: String? = nil,
        maskPrompt: String? = nil,
        maskImage: String? = nil,
        outPaintingMode: NovaCanvasOutpaintingMode = .defaultMode,
        config: NovaCanvasImageGenerationConfig = NovaCanvasImageGenerationConfig()
    ) -> NovaCanvasRequest {
        NovaCanvasRequest(
            taskType: NovaCanvasTaskType.outpainting.rawValue,
            outPaintingParams: NovaCanvasOutpaintingParams(
                text: prompt,
                negativeText: negativePrompt,
                image: image,
                maskPrompt: maskPrompt,
                maskImage: maskImage,
                outPaintingMode: outPaintingMode
            ),
            imageGenerationConfig: config
        )
    }
    
    /// Create a background removal request
    static func backgroundRemoval(image: String) -> NovaCanvasRequest {
        NovaCanvasRequest(
            taskType: NovaCanvasTaskType.backgroundRemoval.rawValue,
            backgroundRemovalParams: NovaCanvasBackgroundRemovalParams(image: image)
        )
    }
}

// MARK: - Nova Canvas Config (for Settings persistence)

/// Configuration for Nova Canvas image generation settings
struct NovaCanvasConfig: Codable, Equatable {
    var taskType: String
    var width: Int
    var height: Int
    var quality: String
    var cfgScale: Float
    var numberOfImages: Int
    var negativePrompt: String
    var similarityStrength: Float
    var outpaintingMode: String
    
    static var defaultConfig: NovaCanvasConfig {
        NovaCanvasConfig(
            taskType: NovaCanvasTaskType.textToImage.rawValue,
            width: 1024,
            height: 1024,
            quality: "standard",
            cfgScale: 8.0,
            numberOfImages: 1,
            negativePrompt: "",
            similarityStrength: 0.7,
            outpaintingMode: NovaCanvasOutpaintingMode.defaultMode.rawValue
        )
    }
    
    /// Convert to NovaCanvasImageGenerationConfig
    func toImageGenerationConfig() -> NovaCanvasImageGenerationConfig {
        NovaCanvasImageGenerationConfig(
            width: width,
            height: height,
            quality: quality,
            cfgScale: cfgScale,
            numberOfImages: numberOfImages
        )
    }
}

// MARK: - Nova Canvas Response

struct NovaCanvasResponse: Codable {
    var images: [String]?  // Base64 encoded images
    var error: String?
    
    /// Decode the first image from base64
    func getFirstImageData() -> Data? {
        guard let base64Image = images?.first else { return nil }
        return Data(base64Encoded: base64Image)
    }
    
    /// Decode all images from base64
    func getAllImageData() -> [Data] {
        return images?.compactMap { Data(base64Encoded: $0) } ?? []
    }
}

// MARK: - Nova Canvas Service

/// Service class for Nova Canvas image generation operations
class NovaCanvasService {
    static let modelId = "amazon.nova-canvas-v1:0"
    
    /// Parse a user prompt to detect Nova Canvas task type and parameters
    static func parsePrompt(_ prompt: String) -> (taskType: NovaCanvasTaskType, cleanPrompt: String, parameters: [String: Any]) {
        let lowercased = prompt.lowercased()
        var parameters: [String: Any] = [:]
        var cleanPrompt = prompt
        
        // Detect task type from prompt keywords
        if lowercased.contains("/inpaint") || lowercased.contains("[inpaint]") {
            cleanPrompt = prompt
                .replacingOccurrences(of: "/inpaint", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "[inpaint]", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (.inpainting, cleanPrompt, parameters)
        }
        
        if lowercased.contains("/outpaint") || lowercased.contains("[outpaint]") {
            cleanPrompt = prompt
                .replacingOccurrences(of: "/outpaint", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "[outpaint]", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (.outpainting, cleanPrompt, parameters)
        }
        
        if lowercased.contains("/variation") || lowercased.contains("[variation]") {
            cleanPrompt = prompt
                .replacingOccurrences(of: "/variation", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "[variation]", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (.imageVariation, cleanPrompt, parameters)
        }
        
        if lowercased.contains("/remove-bg") || lowercased.contains("[remove-bg]") || 
           lowercased.contains("/background-removal") || lowercased.contains("[background-removal]") {
            return (.backgroundRemoval, "", parameters)
        }
        
        // Detect color-guided generation (hex colors in prompt)
        let hexPattern = "#[0-9A-Fa-f]{6}"
        if let regex = try? NSRegularExpression(pattern: hexPattern),
           regex.numberOfMatches(in: prompt, range: NSRange(prompt.startIndex..., in: prompt)) > 0 {
            let matches = regex.matches(in: prompt, range: NSRange(prompt.startIndex..., in: prompt))
            let colors = matches.compactMap { match -> String? in
                guard let range = Range(match.range, in: prompt) else { return nil }
                return String(prompt[range])
            }
            if !colors.isEmpty {
                parameters["colors"] = colors
                // Remove color codes from prompt
                cleanPrompt = prompt
                for color in colors {
                    cleanPrompt = cleanPrompt.replacingOccurrences(of: color, with: "")
                }
                cleanPrompt = cleanPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                return (.colorGuidedGeneration, cleanPrompt, parameters)
            }
        }
        
        // Default to text-to-image
        return (.textToImage, cleanPrompt, parameters)
    }
    
    /// Extract negative prompt from text (format: "prompt --no negative terms")
    static func extractNegativePrompt(from prompt: String) -> (prompt: String, negativePrompt: String?) {
        let parts = prompt.components(separatedBy: "--no ")
        if parts.count > 1 {
            let mainPrompt = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let negativePrompt = parts.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            return (mainPrompt, negativePrompt.isEmpty ? nil : negativePrompt)
        }
        return (prompt, nil)
    }
    
    /// Build a Nova Canvas request from parsed parameters
    static func buildRequest(
        taskType: NovaCanvasTaskType,
        prompt: String,
        negativePrompt: String? = nil,
        inputImages: [String] = [],
        maskPrompt: String? = nil,
        maskImage: String? = nil,
        colors: [String] = [],
        config: NovaCanvasImageGenerationConfig = NovaCanvasImageGenerationConfig()
    ) -> NovaCanvasRequest {
        switch taskType {
        case .textToImage:
            return .textToImage(
                prompt: prompt,
                negativePrompt: negativePrompt,
                conditionImage: inputImages.first,
                config: config
            )
            
        case .colorGuidedGeneration:
            return .colorGuided(
                prompt: prompt,
                negativePrompt: negativePrompt,
                colors: colors,
                referenceImage: inputImages.first,
                config: config
            )
            
        case .imageVariation:
            return .imageVariation(
                images: inputImages,
                prompt: prompt.isEmpty ? nil : prompt,
                negativePrompt: negativePrompt,
                config: config
            )
            
        case .inpainting:
            guard let image = inputImages.first else {
                // Return empty request - will fail validation
                return NovaCanvasRequest(taskType: taskType.rawValue)
            }
            return .inpainting(
                image: image,
                prompt: prompt.isEmpty ? nil : prompt,
                negativePrompt: negativePrompt,
                maskPrompt: maskPrompt,
                maskImage: maskImage,
                config: config
            )
            
        case .outpainting:
            guard let image = inputImages.first else {
                return NovaCanvasRequest(taskType: taskType.rawValue)
            }
            return .outpainting(
                image: image,
                prompt: prompt.isEmpty ? nil : prompt,
                negativePrompt: negativePrompt,
                maskPrompt: maskPrompt,
                maskImage: maskImage,
                config: config
            )
            
        case .backgroundRemoval:
            guard let image = inputImages.first else {
                return NovaCanvasRequest(taskType: taskType.rawValue)
            }
            return .backgroundRemoval(image: image)
        }
    }
}

// MARK: - Image Utilities

extension NovaCanvasService {
    /// Encode image data to base64 string
    static func encodeImage(_ data: Data) -> String {
        return data.base64EncodedString()
    }
    
    /// Decode base64 string to image data
    static func decodeImage(_ base64String: String) -> Data? {
        return Data(base64Encoded: base64String)
    }
    
    /// Validate image dimensions for Nova Canvas
    static func validateImageDimensions(width: Int, height: Int) -> (isValid: Bool, message: String?) {
        // Check minimum/maximum dimensions
        guard width >= 320 && width <= 4096 else {
            return (false, "Width must be between 320 and 4096 pixels")
        }
        guard height >= 320 && height <= 4096 else {
            return (false, "Height must be between 320 and 4096 pixels")
        }
        
        // Check aspect ratio (1:4 to 4:1)
        let aspectRatio = Float(width) / Float(height)
        guard aspectRatio >= 0.25 && aspectRatio <= 4.0 else {
            return (false, "Aspect ratio must be between 1:4 and 4:1")
        }
        
        // Check total pixel count
        let totalPixels = width * height
        guard totalPixels <= 4_194_304 else {
            return (false, "Total pixel count must not exceed 4,194,304")
        }
        
        return (true, nil)
    }
}
