import Foundation

enum DemoModelPolicy {
    /// Image editing services have IMAGE output too, but cannot run a text-only
    /// creation prompt. Keep task compatibility separate from output modality.
    static func createsImagesFromText(_ modelID: String) -> Bool {
        let id = BedrockModelID.base(modelID)
        return [
            "stability.stable-image-core-", "stability.stable-image-ultra-",
            "stability.sd3-", "stability.sd3-5-", "stability.stable-diffusion-",
            "amazon.titan-image-", "amazon.nova-canvas-"
        ].contains { id.hasPrefix($0) }
    }

    static func supports(_ modelID: String, category: DemoCategory) -> Bool {
        guard !BedrockModelID.isLegacy(modelID) else { return false }
        let id = BedrockModelID.base(modelID)
        let route = BedrockModelID.route(id)
        switch category {
        case .text, .reasoning, .documents, .vision, .tools:
            return route == .conversation || route == .responses
        case .images: return createsImagesFromText(id)
        case .video: return route == .video
        case .embeddings:
            return id.hasPrefix("amazon.titan-embed-text-") || id.hasPrefix("amazon.titan-embed-g1-text-") ||
                id.hasPrefix("cohere.embed-")
        }
    }

    static func preference(_ modelID: String, category: DemoCategory) -> Int {
        let id = BedrockModelID.base(modelID)
        let prefixes: [String]
        switch category {
        case .images: prefixes = ["stability.stable-image-core-v1:1", "stability.sd3-5-large", "stability.stable-image-ultra", "amazon.titan-image"]
        case .embeddings: prefixes = ["amazon.titan-embed-text-v2:0", "cohere.embed-v4", "cohere.embed-english"]
        case .video: prefixes = ["luma.ray-v2"]
        default: prefixes = ["amazon.nova-2-lite", "anthropic.claude-sonnet-4-6", "openai.gpt-5.6-luna"]
        }
        return prefixes.firstIndex { id.hasPrefix($0) } ?? prefixes.count
    }
}
