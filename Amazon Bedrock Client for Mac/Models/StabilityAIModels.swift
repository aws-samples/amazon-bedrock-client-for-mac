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


// MARK: - Stability AI Image Services

/// Stability AI Image Services - specialized editing tools
enum StabilityAIImageService: String, Codable, CaseIterable, Identifiable {
    // Upscale
    case creativeUpscale = "creative-upscale"
    case conservativeUpscale = "conservative-upscale"
    case fastUpscale = "fast-upscale"
    
    // Edit
    case inpaint = "inpaint"
    case outpaint = "outpaint"
    case searchReplace = "search-replace"
    case searchRecolor = "search-recolor"
    case erase = "erase"
    case removeBackground = "remove-background"
    
    // Control
    case controlSketch = "control-sketch"
    case controlStructure = "control-structure"
    case styleGuide = "style-guide"
    case styleTransfer = "style-transfer"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .creativeUpscale: return "Creative Upscale"
        case .conservativeUpscale: return "Conservative Upscale"
        case .fastUpscale: return "Fast Upscale"
        case .inpaint: return "Inpaint"
        case .outpaint: return "Outpaint"
        case .searchReplace: return "Search & Replace"
        case .searchRecolor: return "Search & Recolor"
        case .erase: return "Erase"
        case .removeBackground: return "Remove Background"
        case .controlSketch: return "Control Sketch"
        case .controlStructure: return "Control Structure"
        case .styleGuide: return "Style Guide"
        case .styleTransfer: return "Style Transfer"
        }
    }
    
    var icon: String {
        switch self {
        case .creativeUpscale: return "arrow.up.left.and.arrow.down.right"
        case .conservativeUpscale: return "arrow.up.forward"
        case .fastUpscale: return "bolt"
        case .inpaint: return "paintbrush.pointed"
        case .outpaint: return "arrow.up.left.and.arrow.down.right"
        case .searchReplace: return "arrow.triangle.2.circlepath"
        case .searchRecolor: return "paintpalette"
        case .erase: return "eraser"
        case .removeBackground: return "person.crop.rectangle"
        case .controlSketch: return "pencil.tip"
        case .controlStructure: return "square.grid.3x3"
        case .styleGuide: return "wand.and.stars"
        case .styleTransfer: return "photo.on.rectangle.angled"
        }
    }
    
    var description: String {
        switch self {
        case .creativeUpscale: return "Upscale 20-40x with reimagining"
        case .conservativeUpscale: return "Upscale preserving details"
        case .fastUpscale: return "Quick 4x upscale"
        case .inpaint: return "Fill masked areas"
        case .outpaint: return "Extend image borders"
        case .searchReplace: return "Replace objects by description"
        case .searchRecolor: return "Recolor objects by description"
        case .erase: return "Remove objects with mask"
        case .removeBackground: return "Isolate subject"
        case .controlSketch: return "Generate from sketch"
        case .controlStructure: return "Maintain structure"
        case .styleGuide: return "Apply style from reference"
        case .styleTransfer: return "Transfer style to image"
        }
    }
    
    var modelId: String {
        switch self {
        case .creativeUpscale: return "us.stability.stable-creative-upscale-v1:0"
        case .conservativeUpscale: return "us.stability.stable-conservative-upscale-v1:0"
        case .fastUpscale: return "us.stability.stable-fast-upscale-v1:0"
        case .inpaint: return "us.stability.stable-image-inpaint-v1:0"
        case .outpaint: return "us.stability.stable-outpaint-v1:0"
        case .searchReplace: return "us.stability.stable-image-search-replace-v1:0"
        case .searchRecolor: return "us.stability.stable-image-search-recolor-v1:0"
        case .erase: return "us.stability.stable-image-erase-object-v1:0"
        case .removeBackground: return "us.stability.stable-image-remove-background-v1:0"
        case .controlSketch: return "us.stability.stable-image-control-sketch-v1:0"
        case .controlStructure: return "us.stability.stable-image-control-structure-v1:0"
        case .styleGuide: return "us.stability.stable-image-style-guide-v1:0"
        case .styleTransfer: return "us.stability.stable-style-transfer-v1:0"
        }
    }
    
    var requiresImage: Bool {
        switch self {
        case .creativeUpscale, .conservativeUpscale, .fastUpscale,
             .inpaint, .outpaint, .searchReplace, .searchRecolor,
             .erase, .removeBackground, .controlSketch, .controlStructure,
             .styleTransfer:
            return true
        case .styleGuide:
            return true  // Requires style reference image
        }
    }
    
    var requiresPrompt: Bool {
        switch self {
        case .fastUpscale, .removeBackground, .erase:
            return false
        default:
            return true
        }
    }
    
    var requiresMask: Bool {
        switch self {
        case .inpaint, .erase:
            return true
        default:
            return false
        }
    }
    
    var category: ServiceCategory {
        switch self {
        case .creativeUpscale, .conservativeUpscale, .fastUpscale:
            return .upscale
        case .inpaint, .outpaint, .searchReplace, .searchRecolor, .erase, .removeBackground:
            return .edit
        case .controlSketch, .controlStructure, .styleGuide, .styleTransfer:
            return .control
        }
    }
    
    enum ServiceCategory: String, CaseIterable {
        case upscale = "Upscale"
        case edit = "Edit"
        case control = "Control"
    }
}

// MARK: - Stability AI Image Services Config

struct StabilityAIServicesConfig: Codable, Equatable {
    var selectedService: String
    var creativity: Float  // For upscale (0.1-0.5), outpaint (0.1-1.0)
    var controlStrength: Float  // For control services (0-1)
    var fidelity: Float  // For style guide (0-1)
    var styleStrength: Float  // For style transfer (0-1)
    var compositionFidelity: Float  // For style transfer (0-1)
    var changeStrength: Float  // For style transfer (0.1-1)
    var growMask: Int  // For inpaint/erase/search (0-20)
    var outpaintLeft: Int
    var outpaintRight: Int
    var outpaintUp: Int
    var outpaintDown: Int
    var searchPrompt: String  // For search & replace/recolor
    var negativePrompt: String  // Common to most services
    var stylePreset: String  // For upscale, inpaint, control services
    var aspectRatio: String  // For style guide
    var seed: Int
    
    static var defaultConfig: StabilityAIServicesConfig {
        StabilityAIServicesConfig(
            selectedService: StabilityAIImageService.removeBackground.rawValue,
            creativity: 0.3,
            controlStrength: 0.7,
            fidelity: 0.5,
            styleStrength: 0.5,
            compositionFidelity: 0.9,
            changeStrength: 0.9,
            growMask: 5,
            outpaintLeft: 0,
            outpaintRight: 0,
            outpaintUp: 0,
            outpaintDown: 0,
            searchPrompt: "",
            negativePrompt: "",
            stylePreset: "",
            aspectRatio: "1:1",
            seed: 0
        )
    }
}

// MARK: - Stability AI Services Request Builder

struct StabilityAIServicesRequestBuilder {
    
    /// Build request for Creative/Conservative Upscale
    static func buildUpscaleRequest(
        image: String,
        prompt: String,
        creativity: Float = 0.3,
        negativePrompt: String? = nil,
        seed: Int = 0,
        stylePreset: String? = nil
    ) -> [String: Any] {
        var request: [String: Any] = [
            "image": image,
            "prompt": prompt,
            "creativity": creativity
        ]
        if let neg = negativePrompt, !neg.isEmpty { request["negative_prompt"] = neg }
        if seed > 0 { request["seed"] = seed }
        if let style = stylePreset, !style.isEmpty { request["style_preset"] = style }
        return request
    }
    
    /// Build request for Fast Upscale (minimal params)
    static func buildFastUpscaleRequest(image: String) -> [String: Any] {
        return ["image": image]
    }
    
    /// Build request for Inpaint
    static func buildInpaintRequest(
        image: String,
        prompt: String,
        mask: String? = nil,
        growMask: Int = 5,
        negativePrompt: String? = nil,
        seed: Int = 0,
        stylePreset: String? = nil
    ) -> [String: Any] {
        var request: [String: Any] = [
            "image": image,
            "prompt": prompt,
            "grow_mask": growMask
        ]
        if let m = mask { request["mask"] = m }
        if let neg = negativePrompt, !neg.isEmpty { request["negative_prompt"] = neg }
        if seed > 0 { request["seed"] = seed }
        if let style = stylePreset, !style.isEmpty { request["style_preset"] = style }
        return request
    }
    
    /// Build request for Outpaint
    static func buildOutpaintRequest(
        image: String,
        left: Int = 0,
        right: Int = 0,
        up: Int = 0,
        down: Int = 0,
        prompt: String? = nil,
        creativity: Float = 0.5,
        seed: Int = 0
    ) -> [String: Any] {
        var request: [String: Any] = ["image": image]
        if left > 0 { request["left"] = left }
        if right > 0 { request["right"] = right }
        if up > 0 { request["up"] = up }
        if down > 0 { request["down"] = down }
        if let p = prompt, !p.isEmpty { request["prompt"] = p }
        request["creativity"] = creativity
        if seed > 0 { request["seed"] = seed }
        return request
    }
    
    /// Build request for Search & Replace
    static func buildSearchReplaceRequest(
        image: String,
        prompt: String,
        searchPrompt: String,
        growMask: Int = 5,
        negativePrompt: String? = nil,
        seed: Int = 0,
        stylePreset: String? = nil
    ) -> [String: Any] {
        var request: [String: Any] = [
            "image": image,
            "prompt": prompt,
            "search_prompt": searchPrompt,
            "grow_mask": growMask
        ]
        if let neg = negativePrompt, !neg.isEmpty { request["negative_prompt"] = neg }
        if seed > 0 { request["seed"] = seed }
        if let style = stylePreset, !style.isEmpty { request["style_preset"] = style }
        return request
    }
    
    /// Build request for Search & Recolor
    static func buildSearchRecolorRequest(
        image: String,
        prompt: String,
        selectPrompt: String,
        growMask: Int = 5,
        negativePrompt: String? = nil,
        seed: Int = 0,
        stylePreset: String? = nil
    ) -> [String: Any] {
        var request: [String: Any] = [
            "image": image,
            "prompt": prompt,
            "select_prompt": selectPrompt,
            "grow_mask": growMask
        ]
        if let neg = negativePrompt, !neg.isEmpty { request["negative_prompt"] = neg }
        if seed > 0 { request["seed"] = seed }
        if let style = stylePreset, !style.isEmpty { request["style_preset"] = style }
        return request
    }
    
    /// Build request for Erase
    static func buildEraseRequest(
        image: String,
        mask: String? = nil,
        growMask: Int = 5,
        seed: Int = 0
    ) -> [String: Any] {
        var request: [String: Any] = [
            "image": image,
            "grow_mask": growMask
        ]
        if let m = mask { request["mask"] = m }
        if seed > 0 { request["seed"] = seed }
        return request
    }
    
    /// Build request for Remove Background
    static func buildRemoveBackgroundRequest(image: String) -> [String: Any] {
        return ["image": image]
    }
    
    /// Build request for Control Sketch/Structure
    static func buildControlRequest(
        image: String,
        prompt: String,
        controlStrength: Float = 0.7,
        negativePrompt: String? = nil,
        seed: Int = 0,
        stylePreset: String? = nil
    ) -> [String: Any] {
        var request: [String: Any] = [
            "image": image,
            "prompt": prompt,
            "control_strength": controlStrength
        ]
        if let neg = negativePrompt, !neg.isEmpty { request["negative_prompt"] = neg }
        if seed > 0 { request["seed"] = seed }
        if let style = stylePreset, !style.isEmpty { request["style_preset"] = style }
        return request
    }
    
    /// Build request for Style Guide
    static func buildStyleGuideRequest(
        image: String,
        prompt: String,
        fidelity: Float = 0.5,
        aspectRatio: String = "1:1",
        negativePrompt: String? = nil,
        seed: Int = 0
    ) -> [String: Any] {
        var request: [String: Any] = [
            "image": image,
            "prompt": prompt,
            "fidelity": fidelity,
            "aspect_ratio": aspectRatio
        ]
        if let neg = negativePrompt, !neg.isEmpty { request["negative_prompt"] = neg }
        if seed > 0 { request["seed"] = seed }
        return request
    }
    
    /// Build request for Style Transfer (requires two images)
    static func buildStyleTransferRequest(
        initImage: String,
        styleImage: String,
        prompt: String? = nil,
        styleStrength: Float = 0.5,
        compositionFidelity: Float = 0.9,
        changeStrength: Float = 0.9,
        negativePrompt: String? = nil,
        seed: Int = 0
    ) -> [String: Any] {
        var request: [String: Any] = [
            "init_image": initImage,
            "style_image": styleImage,
            "style_strength": styleStrength,
            "composition_fidelity": compositionFidelity,
            "change_strength": changeStrength
        ]
        if let p = prompt, !p.isEmpty { request["prompt"] = p }
        if let neg = negativePrompt, !neg.isEmpty { request["negative_prompt"] = neg }
        if seed > 0 { request["seed"] = seed }
        return request
    }
}
