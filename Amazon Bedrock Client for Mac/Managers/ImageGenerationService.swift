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
        let params = TitanImageModelParameters(inputText: prompt)
        let encodedParams = try JSONEncoder().encode(params)
        
        let request = InvokeModelInput(
            body: encodedParams,
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
        let isSD3 = modelId.contains("sd3")
        let isCore = modelId.contains("stable-image-core")
        let isUltra = modelId.contains("stable-image-ultra") || modelId.contains("sd3-ultra")
        
        let promptData: [String: Any]
        
        if isSD3 || isCore || isUltra {
            // SD3, Core, Ultra formatting
            promptData = ["prompt": prompt]
        } else {
            // Standard Stable Diffusion formatting
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
        
        let response = try await bedrockRuntimeClient.invokeModel(input: request)
        guard let data = response.body else {
            throw ImageGenerationError.invalidResponse
        }
        
        // Try to extract the image from the response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ImageGenerationError.invalidResponse
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
