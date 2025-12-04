// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0

import Foundation

// MARK: - Stability AI Task Types

/// Supported Stability AI task types
enum StabilityAITaskType: String, Codable, CaseIterable, Identifiable {
    case textToImage = "text-to-image"
    case imageToImage = "image-to-image"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .textToImage: return "Text to Image"
        case .imageToImage: return "Image to Image"
        }
    }
    
    var icon: String {
        switch self {
        case .textToImage: return "text.below.photo"
        case .imageToImage: return "photo.on.rectangle"
        }
    }
    
    var taskDescription: String {
        switch self {
        case .textToImage: return "Generate image from text"
        case .imageToImage: return "Transform existing image"
        }
    }
    
    var requiresInputImage: Bool {
        switch self {
        case .textToImage: return false
        case .imageToImage: return true
        }
    }
}

// MARK: - Stability AI Style Presets

enum StabilityAIStylePreset: String, Codable, CaseIterable {
    case none = ""
    case model3d = "3d-model"
    case analogFilm = "analog-film"
    case anime = "anime"
    case cinematic = "cinematic"
    case comicBook = "comic-book"
    case digitalArt = "digital-art"
    case enhance = "enhance"
    case fantasyArt = "fantasy-art"
    case isometric = "isometric"
    case lineArt = "line-art"
    case lowPoly = "low-poly"
    case modelingCompound = "modeling-compound"
    case neonPunk = "neon-punk"
    case origami = "origami"
    case photographic = "photographic"
    case pixelArt = "pixel-art"
    case tileTexture = "tile-texture"
    
    var displayName: String {
        switch self {
        case .none: return "None"
        case .model3d: return "3D Model"
        case .analogFilm: return "Analog Film"
        case .anime: return "Anime"
        case .cinematic: return "Cinematic"
        case .comicBook: return "Comic Book"
        case .digitalArt: return "Digital Art"
        case .enhance: return "Enhance"
        case .fantasyArt: return "Fantasy Art"
        case .isometric: return "Isometric"
        case .lineArt: return "Line Art"
        case .lowPoly: return "Low Poly"
        case .modelingCompound: return "Modeling Compound"
        case .neonPunk: return "Neon Punk"
        case .origami: return "Origami"
        case .photographic: return "Photographic"
        case .pixelArt: return "Pixel Art"
        case .tileTexture: return "Tile Texture"
        }
    }
}

// MARK: - Stability AI Aspect Ratios

enum StabilityAIAspectRatio: String, Codable, CaseIterable {
    case ratio1_1 = "1:1"
    case ratio16_9 = "16:9"
    case ratio9_16 = "9:16"
    case ratio21_9 = "21:9"
    case ratio9_21 = "9:21"
    case ratio2_3 = "2:3"
    case ratio3_2 = "3:2"
    case ratio4_5 = "4:5"
    case ratio5_4 = "5:4"
    
    var displayName: String { rawValue }
}

// MARK: - Stability AI Config (for Settings persistence)

struct StabilityAIConfig: Codable, Equatable {
    var taskType: String
    var aspectRatio: String
    var stylePreset: String
    var negativePrompt: String
    var seed: Int
    var cfgScale: Float
    var steps: Int
    var strength: Float  // For image-to-image (0-1)
    
    static var defaultConfig: StabilityAIConfig {
        StabilityAIConfig(
            taskType: StabilityAITaskType.textToImage.rawValue,
            aspectRatio: StabilityAIAspectRatio.ratio1_1.rawValue,
            stylePreset: "",
            negativePrompt: "",
            seed: 0,
            cfgScale: 10.0,
            steps: 50,
            strength: 0.35
        )
    }
}

// MARK: - Stability AI Request Builders

struct StabilityAIRequestBuilder {
    
    /// Build request for SD3, Ultra, Core models (new format)
    static func buildModernRequest(
        prompt: String,
        negativePrompt: String? = nil,
        aspectRatio: String = "1:1",
        seed: Int = 0,
        image: String? = nil,
        strength: Float = 0.35
    ) -> [String: Any] {
        var request: [String: Any] = ["prompt": prompt]
        
        if let neg = negativePrompt, !neg.isEmpty {
            request["negative_prompt"] = neg
        }
        
        if let img = image {
            // Image-to-image mode
            request["image"] = img
            request["strength"] = strength
            request["mode"] = "image-to-image"
        } else {
            // Text-to-image mode
            request["aspect_ratio"] = aspectRatio
            request["mode"] = "text-to-image"
        }
        
        if seed > 0 {
            request["seed"] = seed
        }
        
        return request
    }
    
    /// Build request for legacy Stable Diffusion models
    static func buildLegacyRequest(
        prompt: String,
        negativePrompt: String? = nil,
        cfgScale: Float = 10.0,
        seed: Int = 0,
        steps: Int = 50,
        stylePreset: String? = nil
    ) -> [String: Any] {
        var textPrompts: [[String: Any]] = [["text": prompt, "weight": 1.0]]
        
        if let neg = negativePrompt, !neg.isEmpty {
            textPrompts.append(["text": neg, "weight": -1.0])
        }
        
        var request: [String: Any] = [
            "text_prompts": textPrompts,
            "cfg_scale": cfgScale,
            "seed": seed,
            "steps": steps,
            "samples": 1
        ]
        
        if let style = stylePreset, !style.isEmpty {
            request["style_preset"] = style
        }
        
        return request
    }
}
