// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0

//
//  ImageGenerationService.swift
//  Amazon Bedrock Client for Mac
//
//  Handles image generation for Titan Image, Nova Canvas, and Stability AI models
//

import AWSBedrockRuntime
import Foundation

// MARK: - Image Generation Service

/// Service for invoking image generation models on Amazon Bedrock
class ImageGenerationService {
    private let bedrockRuntimeClient: BedrockRuntimeClient
    
    init(bedrockRuntimeClient: BedrockRuntimeClient) {
        self.bedrockRuntimeClient = bedrockRuntimeClient
    }
    
    // MARK: - Main Entry Point
    
    /// Invoke an image generation model
    func invokeImageModel(
        withId modelId: String,
        prompt: String,
        modelType: ModelType
    ) async throws -> Data {
        switch modelType {
        case .titanImage:
            return try await invokeTitanImage(modelId: modelId, prompt: prompt)
            
        case .novaCanvas:
            let request = NovaCanvasRequest.textToImage(
                prompt: prompt,
                config: NovaCanvasImageGenerationConfig()
            )
            return try await invokeNovaCanvas(request: request)
            
        case .stableDiffusion, .stableImage:
            return try await invokeStabilityAI(modelId: modelId, prompt: prompt)
            
        default:
            throw ImageGenerationError.unsupportedModel(modelId)
        }
    }
    
    // MARK: - Titan Image
    
    private func invokeTitanImage(modelId: String, prompt: String) async throws -> Data {
        // Use saved config from SettingManager
        let config = await MainActor.run { SettingManager.shared.titanImageConfig }
        let genConfig = config.toImageGenerationConfig()
        
        let request = TitanImageRequest.textToImage(
            prompt: prompt,
            negativePrompt: config.negativePrompt.isEmpty ? nil : config.negativePrompt,
            config: genConfig
        )
        
        let encodedParams = try JSONEncoder().encode(request)
        
        let invokeRequest = InvokeModelInput(
            body: encodedParams,
            contentType: "application/json",
            modelId: modelId
        )
        
        let response = try await bedrockRuntimeClient.invokeModel(input: invokeRequest)
        guard let data = response.body else {
            throw ImageGenerationError.invalidResponse
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let images = json["images"] as? [String],
              let base64Image = images.first,
              let imageData = Data(base64Encoded: base64Image) else {
            throw ImageGenerationError.invalidResponse
        }
        
        return imageData
    }
    
    /// Invoke Titan Image with full request (for advanced tasks)
    func invokeTitanImage(modelId: String, request: TitanImageRequest) async throws -> Data {
        let encodedParams = try JSONEncoder().encode(request)
        
        let invokeRequest = InvokeModelInput(
            body: encodedParams,
            contentType: "application/json",
            modelId: modelId
        )
        
        let response = try await bedrockRuntimeClient.invokeModel(input: invokeRequest)
        guard let data = response.body else {
            throw ImageGenerationError.invalidResponse
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let images = json["images"] as? [String],
              let base64Image = images.first,
              let imageData = Data(base64Encoded: base64Image) else {
            throw ImageGenerationError.invalidResponse
        }
        
        return imageData
    }
    
    // MARK: - Nova Canvas
    
    /// Invoke Nova Canvas with a unified request structure
    /// Supports: TEXT_IMAGE, COLOR_GUIDED_GENERATION, IMAGE_VARIATION, INPAINTING, OUTPAINTING, BACKGROUND_REMOVAL
    func invokeNovaCanvas(request: NovaCanvasRequest) async throws -> Data {
        let encodedParams = try JSONEncoder().encode(request)
        
        let invokeRequest = InvokeModelInput(
            body: encodedParams,
            contentType: "application/json",
            modelId: NovaCanvasService.modelId
        )
        
        let response = try await bedrockRuntimeClient.invokeModel(input: invokeRequest)
        guard let data = response.body else {
            throw ImageGenerationError.invalidResponse
        }
        
        let novaResponse = try JSONDecoder().decode(NovaCanvasResponse.self, from: data)
        
        if let error = novaResponse.error {
            throw ImageGenerationError.modelError(error)
        }
        
        guard let imageData = novaResponse.getFirstImageData() else {
            throw ImageGenerationError.invalidResponse
        }
        
        return imageData
    }
    
    /// Invoke Nova Canvas and return all generated images
    func invokeNovaCanvasMultiple(request: NovaCanvasRequest) async throws -> [Data] {
        let encodedParams = try JSONEncoder().encode(request)
        
        let invokeRequest = InvokeModelInput(
            body: encodedParams,
            contentType: "application/json",
            modelId: NovaCanvasService.modelId
        )
        
        let response = try await bedrockRuntimeClient.invokeModel(input: invokeRequest)
        guard let data = response.body else {
            throw ImageGenerationError.invalidResponse
        }
        
        let novaResponse = try JSONDecoder().decode(NovaCanvasResponse.self, from: data)
        
        if let error = novaResponse.error {
            throw ImageGenerationError.modelError(error)
        }
        
        let images = novaResponse.getAllImageData()
        guard !images.isEmpty else {
            throw ImageGenerationError.invalidResponse
        }
        
        return images
    }
    
    // MARK: - Stability AI
    
    private func invokeStabilityAI(modelId: String, prompt: String) async throws -> Data {
        // Use saved config from SettingManager
        let config = await MainActor.run { SettingManager.shared.stabilityAIConfig }
        
        let isSD3 = modelId.contains("sd3")
        let isCore = modelId.contains("stable-image-core")
        let isUltra = modelId.contains("stable-image-ultra") || modelId.contains("sd3-ultra")
        
        let promptData: [String: Any]
        
        if isSD3 || isCore || isUltra {
            // SD3, Core, Ultra formatting - use modern request builder
            promptData = StabilityAIRequestBuilder.buildModernRequest(
                prompt: prompt,
                negativePrompt: config.negativePrompt.isEmpty ? nil : config.negativePrompt,
                aspectRatio: config.aspectRatio,
                seed: config.seed
            )
        } else {
            // Standard Stable Diffusion formatting - use legacy request builder
            promptData = StabilityAIRequestBuilder.buildLegacyRequest(
                prompt: prompt,
                negativePrompt: config.negativePrompt.isEmpty ? nil : config.negativePrompt,
                cfgScale: config.cfgScale,
                seed: config.seed,
                steps: config.steps,
                stylePreset: config.stylePreset.isEmpty ? nil : config.stylePreset
            )
        }
        
        let jsonData = try JSONSerialization.data(withJSONObject: promptData)
        
        let request = InvokeModelInput(
            body: jsonData,
            contentType: "application/json",
            modelId: modelId
        )
        
        let response = try await bedrockRuntimeClient.invokeModel(input: request)
        guard let data = response.body else {
            throw ImageGenerationError.invalidResponse
        }
        
        // Try to extract the image from the response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ImageGenerationError.invalidResponse
        }
        
        // Check for content filter
        if let finishReasons = json["finish_reasons"] as? [String?],
           let reason = finishReasons.first, let filterReason = reason {
            throw ImageGenerationError.contentFiltered(filterReason)
        }
        
        // New format (SD3, Ultra, Core)
        if let images = json["images"] as? [String],
           let base64Image = images.first,
           let imageData = Data(base64Encoded: base64Image) {
            return imageData
        }
        
        // Legacy format (older Stable Diffusion)
        if let artifacts = json["artifacts"] as? [[String: Any]],
           let firstArtifact = artifacts.first,
           let base64Image = firstArtifact["base64"] as? String,
           let imageData = Data(base64Encoded: base64Image) {
            return imageData
        }
        
        throw ImageGenerationError.invalidResponse
    }
    
    /// Invoke Stability AI with image-to-image
    func invokeStabilityAIImageToImage(modelId: String, prompt: String, inputImage: String) async throws -> Data {
        let config = await MainActor.run { SettingManager.shared.stabilityAIConfig }
        
        let promptData = StabilityAIRequestBuilder.buildModernRequest(
            prompt: prompt,
            negativePrompt: config.negativePrompt.isEmpty ? nil : config.negativePrompt,
            aspectRatio: config.aspectRatio,
            seed: config.seed,
            image: inputImage,
            strength: config.strength
        )
        
        let jsonData = try JSONSerialization.data(withJSONObject: promptData)
        
        let request = InvokeModelInput(
            body: jsonData,
            contentType: "application/json",
            modelId: modelId
        )
        
        let response = try await bedrockRuntimeClient.invokeModel(input: request)
        guard let data = response.body else {
            throw ImageGenerationError.invalidResponse
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let images = json["images"] as? [String],
              let base64Image = images.first,
              let imageData = Data(base64Encoded: base64Image) else {
            throw ImageGenerationError.invalidResponse
        }
        
        return imageData
    }
    
    // MARK: - Stability AI Image Services
    
    /// Invoke Stability AI Image Service
    func invokeStabilityAIService(
        service: StabilityAIImageService,
        prompt: String,
        inputImage: String,
        maskImage: String? = nil,
        styleImage: String? = nil  // For style transfer
    ) async throws -> Data {
        let config = await MainActor.run { SettingManager.shared.stabilityAIServicesConfig }
        
        let requestData: [String: Any]
        
        switch service {
        case .creativeUpscale, .conservativeUpscale:
            requestData = StabilityAIServicesRequestBuilder.buildUpscaleRequest(
                image: inputImage,
                prompt: prompt,
                creativity: config.creativity,
                negativePrompt: config.negativePrompt.isEmpty ? nil : config.negativePrompt,
                seed: config.seed,
                stylePreset: config.stylePreset.isEmpty ? nil : config.stylePreset
            )
            
        case .fastUpscale:
            requestData = StabilityAIServicesRequestBuilder.buildFastUpscaleRequest(image: inputImage)
            
        case .inpaint:
            requestData = StabilityAIServicesRequestBuilder.buildInpaintRequest(
                image: inputImage,
                prompt: prompt,
                mask: maskImage,
                growMask: config.growMask,
                negativePrompt: config.negativePrompt.isEmpty ? nil : config.negativePrompt,
                seed: config.seed,
                stylePreset: config.stylePreset.isEmpty ? nil : config.stylePreset
            )
            
        case .outpaint:
            requestData = StabilityAIServicesRequestBuilder.buildOutpaintRequest(
                image: inputImage,
                left: config.outpaintLeft,
                right: config.outpaintRight,
                up: config.outpaintUp,
                down: config.outpaintDown,
                prompt: prompt.isEmpty ? nil : prompt,
                creativity: config.creativity,
                seed: config.seed
            )
            
        case .searchReplace:
            requestData = StabilityAIServicesRequestBuilder.buildSearchReplaceRequest(
                image: inputImage,
                prompt: prompt,
                searchPrompt: config.searchPrompt,
                growMask: config.growMask,
                negativePrompt: config.negativePrompt.isEmpty ? nil : config.negativePrompt,
                seed: config.seed,
                stylePreset: config.stylePreset.isEmpty ? nil : config.stylePreset
            )
            
        case .searchRecolor:
            requestData = StabilityAIServicesRequestBuilder.buildSearchRecolorRequest(
                image: inputImage,
                prompt: prompt,
                selectPrompt: config.searchPrompt,
                growMask: config.growMask,
                negativePrompt: config.negativePrompt.isEmpty ? nil : config.negativePrompt,
                seed: config.seed,
                stylePreset: config.stylePreset.isEmpty ? nil : config.stylePreset
            )
            
        case .erase:
            requestData = StabilityAIServicesRequestBuilder.buildEraseRequest(
                image: inputImage,
                mask: maskImage,
                growMask: config.growMask,
                seed: config.seed
            )
            
        case .removeBackground:
            requestData = StabilityAIServicesRequestBuilder.buildRemoveBackgroundRequest(image: inputImage)
            
        case .controlSketch, .controlStructure:
            requestData = StabilityAIServicesRequestBuilder.buildControlRequest(
                image: inputImage,
                prompt: prompt,
                controlStrength: config.controlStrength,
                negativePrompt: config.negativePrompt.isEmpty ? nil : config.negativePrompt,
                seed: config.seed,
                stylePreset: config.stylePreset.isEmpty ? nil : config.stylePreset
            )
            
        case .styleGuide:
            requestData = StabilityAIServicesRequestBuilder.buildStyleGuideRequest(
                image: inputImage,
                prompt: prompt,
                fidelity: config.fidelity,
                aspectRatio: config.aspectRatio,
                negativePrompt: config.negativePrompt.isEmpty ? nil : config.negativePrompt,
                seed: config.seed
            )
            
        case .styleTransfer:
            guard let styleImg = styleImage else {
                throw ImageGenerationError.modelError("Style Transfer requires both init_image and style_image")
            }
            requestData = StabilityAIServicesRequestBuilder.buildStyleTransferRequest(
                initImage: inputImage,
                styleImage: styleImg,
                prompt: prompt.isEmpty ? nil : prompt,
                styleStrength: config.styleStrength,
                compositionFidelity: config.compositionFidelity,
                changeStrength: config.changeStrength,
                negativePrompt: config.negativePrompt.isEmpty ? nil : config.negativePrompt,
                seed: config.seed
            )
        }
        
        let jsonData = try JSONSerialization.data(withJSONObject: requestData)
        
        let request = InvokeModelInput(
            body: jsonData,
            contentType: "application/json",
            modelId: service.modelId
        )
        
        let response = try await bedrockRuntimeClient.invokeModel(input: request)
        guard let data = response.body else {
            throw ImageGenerationError.invalidResponse
        }
        
        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ImageGenerationError.invalidResponse
        }
        
        // Check for content filter
        if let finishReasons = json["finish_reasons"] as? [String?],
           let reason = finishReasons.first, let filterReason = reason {
            throw ImageGenerationError.contentFiltered(filterReason)
        }
        
        // Extract image
        guard let images = json["images"] as? [String],
              let base64Image = images.first,
              let imageData = Data(base64Encoded: base64Image) else {
            throw ImageGenerationError.invalidResponse
        }
        
        return imageData
    }
}

// MARK: - Image Generation Errors

enum ImageGenerationError: LocalizedError {
    case unsupportedModel(String)
    case invalidResponse
    case modelError(String)
    case contentFiltered(String)
    
    var errorDescription: String? {
        switch self {
        case .unsupportedModel(let modelId):
            return "Unsupported image generation model: \(modelId)"
        case .invalidResponse:
            return "Invalid response from image generation model"
        case .modelError(let message):
            return "Image generation error: \(message)"
        case .contentFiltered(let reason):
            return "Content filtered: \(reason)"
        }
    }
}

// NOTE: TitanImageModelParameters is defined in BedrockClient.swift
