// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0

import Foundation

// MARK: - Titan Image Task Types

/// Supported Titan Image Generator task types
enum TitanImageTaskType: String, Codable, CaseIterable, Identifiable {
    case textToImage = "TEXT_IMAGE"
    case inpainting = "INPAINTING"
    case outpainting = "OUTPAINTING"
    case imageVariation = "IMAGE_VARIATION"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .textToImage: return "Text to Image"
        case .inpainting: return "Inpainting"
        case .outpainting: return "Outpainting"
        case .imageVariation: return "Image Variation"
        }
    }
    
    var icon: String {
        switch self {
        case .textToImage: return "text.below.photo"
        case .inpainting: return "paintbrush.pointed"
        case .outpainting: return "arrow.up.left.and.arrow.down.right"
        case .imageVariation: return "photo.on.rectangle"
        }
    }
    
    var taskDescription: String {
        switch self {
        case .textToImage: return "Generate image from text"
        case .inpainting: return "Edit areas within image"
        case .outpainting: return "Extend image borders"
        case .imageVariation: return "Create variations"
        }
    }
    
    var requiresInputImage: Bool {
        switch self {
        case .textToImage: return false
        case .inpainting, .outpainting, .imageVariation: return true
        }
    }
}

// MARK: - Titan Image Request Models

/// Titan Image text-to-image parameters
struct TitanTextToImageParams: Codable {
    var text: String
    var negativeText: String?
    
    init(text: String, negativeText: String? = nil) {
        self.text = String(text.prefix(512))  // Max 512 chars
        self.negativeText = negativeText
    }
}

/// Titan Image inpainting parameters
struct TitanInpaintingParams: Codable {
    var text: String?
    var negativeText: String?
    var image: String  // Base64 encoded
    var maskPrompt: String?
    var maskImage: String?
    
    init(text: String? = nil, negativeText: String? = nil, image: String, maskPrompt: String? = nil, maskImage: String? = nil) {
        if let t = text { self.text = String(t.prefix(512)) }
        self.negativeText = negativeText
        self.image = image
        self.maskPrompt = maskPrompt
        self.maskImage = maskImage
    }
}

/// Titan Image outpainting parameters
struct TitanOutpaintingParams: Codable {
    var text: String?
    var negativeText: String?
    var image: String
    var maskPrompt: String?
    var maskImage: String?
    var outPaintingMode: String
    
    init(text: String? = nil, negativeText: String? = nil, image: String, maskPrompt: String? = nil, maskImage: String? = nil, mode: String = "DEFAULT") {
        if let t = text { self.text = String(t.prefix(512)) }
        self.negativeText = negativeText
        self.image = image
        self.maskPrompt = maskPrompt
        self.maskImage = maskImage
        self.outPaintingMode = mode
    }
}

/// Titan Image variation parameters
struct TitanImageVariationParams: Codable {
    var text: String?
    var negativeText: String?
    var images: [String]  // 1-5 base64 images
    var similarityStrength: Float
    
    init(text: String? = nil, negativeText: String? = nil, images: [String], similarityStrength: Float = 0.7) {
        if let t = text { self.text = String(t.prefix(512)) }
        self.negativeText = negativeText
        self.images = Array(images.prefix(5))
        self.similarityStrength = min(max(similarityStrength, 0.2), 1.0)
    }
}

/// Titan Image generation config
struct TitanImageGenerationConfig: Codable {
    var numberOfImages: Int
    var quality: String
    var height: Int
    var width: Int
    var cfgScale: Float
    var seed: Int
    
    init(
        numberOfImages: Int = 1,
        quality: String = "standard",
        height: Int = 1024,
        width: Int = 1024,
        cfgScale: Float = 8.0,
        seed: Int = 0
    ) {
        self.numberOfImages = min(max(numberOfImages, 1), 5)
        self.quality = quality
        self.height = height
        self.width = width
        self.cfgScale = min(max(cfgScale, 1.1), 10.0)
        self.seed = seed
    }
}

/// Unified Titan Image request
struct TitanImageRequest: Codable {
    var taskType: String
    var textToImageParams: TitanTextToImageParams?
    var inPaintingParams: TitanInpaintingParams?
    var outPaintingParams: TitanOutpaintingParams?
    var imageVariationParams: TitanImageVariationParams?
    var imageGenerationConfig: TitanImageGenerationConfig
    
    static func textToImage(prompt: String, negativePrompt: String? = nil, config: TitanImageGenerationConfig) -> TitanImageRequest {
        TitanImageRequest(
            taskType: TitanImageTaskType.textToImage.rawValue,
            textToImageParams: TitanTextToImageParams(text: prompt, negativeText: negativePrompt),
            imageGenerationConfig: config
        )
    }
    
    static func inpainting(image: String, prompt: String? = nil, negativePrompt: String? = nil, maskPrompt: String? = nil, maskImage: String? = nil, config: TitanImageGenerationConfig) -> TitanImageRequest {
        TitanImageRequest(
            taskType: TitanImageTaskType.inpainting.rawValue,
            inPaintingParams: TitanInpaintingParams(text: prompt, negativeText: negativePrompt, image: image, maskPrompt: maskPrompt, maskImage: maskImage),
            imageGenerationConfig: config
        )
    }
    
    static func outpainting(image: String, prompt: String? = nil, negativePrompt: String? = nil, maskPrompt: String? = nil, maskImage: String? = nil, mode: String = "DEFAULT", config: TitanImageGenerationConfig) -> TitanImageRequest {
        TitanImageRequest(
            taskType: TitanImageTaskType.outpainting.rawValue,
            outPaintingParams: TitanOutpaintingParams(text: prompt, negativeText: negativePrompt, image: image, maskPrompt: maskPrompt, maskImage: maskImage, mode: mode),
            imageGenerationConfig: config
        )
    }
    
    static func imageVariation(images: [String], prompt: String? = nil, negativePrompt: String? = nil, similarityStrength: Float = 0.7, config: TitanImageGenerationConfig) -> TitanImageRequest {
        TitanImageRequest(
            taskType: TitanImageTaskType.imageVariation.rawValue,
            imageVariationParams: TitanImageVariationParams(text: prompt, negativeText: negativePrompt, images: images, similarityStrength: similarityStrength),
            imageGenerationConfig: config
        )
    }
}

// MARK: - Titan Image Config (for Settings persistence)

struct TitanImageConfig: Codable, Equatable {
    var taskType: String
    var width: Int
    var height: Int
    var quality: String
    var cfgScale: Float
    var numberOfImages: Int
    var negativePrompt: String
    var similarityStrength: Float
    var outpaintingMode: String
    var maskPrompt: String
    var seed: Int
    
    static var defaultConfig: TitanImageConfig {
        TitanImageConfig(
            taskType: TitanImageTaskType.textToImage.rawValue,
            width: 1024,
            height: 1024,
            quality: "standard",
            cfgScale: 8.0,
            numberOfImages: 1,
            negativePrompt: "",
            similarityStrength: 0.7,
            outpaintingMode: "DEFAULT",
            maskPrompt: "",
            seed: 0
        )
    }
    
    func toImageGenerationConfig() -> TitanImageGenerationConfig {
        TitanImageGenerationConfig(
            numberOfImages: numberOfImages,
            quality: quality,
            height: height,
            width: width,
            cfgScale: cfgScale,
            seed: seed
        )
    }
}

// MARK: - Titan Image Supported Sizes

struct TitanImageSize: Identifiable, Equatable {
    let id = UUID()
    let width: Int
    let height: Int
    let label: String
    
    static let supportedSizes: [TitanImageSize] = [
        TitanImageSize(width: 1024, height: 1024, label: "1:1"),
        TitanImageSize(width: 768, height: 768, label: "1:1 Small"),
        TitanImageSize(width: 512, height: 512, label: "1:1 Tiny"),
        TitanImageSize(width: 768, height: 1152, label: "2:3"),
        TitanImageSize(width: 1152, height: 768, label: "3:2"),
        TitanImageSize(width: 768, height: 1280, label: "3:5"),
        TitanImageSize(width: 1280, height: 768, label: "5:3"),
        TitanImageSize(width: 896, height: 1152, label: "7:9"),
        TitanImageSize(width: 1152, height: 896, label: "9:7"),
        TitanImageSize(width: 768, height: 1408, label: "6:11"),
        TitanImageSize(width: 1408, height: 768, label: "11:6"),
        TitanImageSize(width: 640, height: 1408, label: "5:11"),
        TitanImageSize(width: 1408, height: 640, label: "11:5"),
        TitanImageSize(width: 1152, height: 640, label: "9:5"),
        TitanImageSize(width: 1173, height: 640, label: "16:9"),
    ]
}
