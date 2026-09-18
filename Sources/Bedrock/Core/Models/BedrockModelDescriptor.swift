import Foundation

enum BedrockModelRoute: String, Codable, Sendable, CaseIterable {
    case conversation, responses, image, video, embedding, asyncEmbedding, rerank, speech, videoAnalysis
    var title: String {
        switch self {
        case .conversation: "Conversation"
        case .responses: "Responses"
        case .image: "Image generation"
        case .video: "Video generation"
        case .embedding: "Embeddings"
        case .asyncEmbedding: "Multimodal embeddings"
        case .rerank: "Reranking"
        case .speech: "Speech"
        case .videoAnalysis: "Video analysis"
        }
    }
    var symbol: String {
        switch self {
        case .conversation, .responses: "bubble.left.and.bubble.right"
        case .image: "photo"
        case .video, .videoAnalysis: "film"
        case .embedding, .asyncEmbedding: "point.3.filled.connected.trianglepath.dotted"
        case .rerank: "list.number"
        case .speech: "waveform"
        }
    }
}

enum BedrockModelID {
    static let geographicPrefixes: Set<String> = ["us", "us-gov", "eu", "apac", "global", "au", "jp"]
    static func base(_ value: String) -> String {
        // An ARN may contain colons and slashes; a model version may contain dots.
        let value = value.split(separator: "/").last.map(String.init) ?? value
        guard let dot = value.firstIndex(of: "."), geographicPrefixes.contains(String(value[..<dot])) else { return value }
        return String(value[value.index(after: dot)...])
    }
    static func provider(_ value: String) -> String { String(base(value).split(separator: ".").first ?? "") }
    static func route(_ value: String, output: [String] = []) -> BedrockModelRoute {
        let id = base(value).lowercased()
        if id.contains("sonic") { return .speech }
        if id.contains("pegasus") { return .videoAnalysis }
        if id.contains("marengo") { return .asyncEmbedding }
        if id.contains("rerank") { return .rerank }
        if output.contains("EMBEDDING") || id.contains("embed") || id.contains("titan-e1t") { return .embedding }
        if output.contains("VIDEO") || id.contains("nova-reel") || id.hasPrefix("luma.") { return .video }
        if output.contains("IMAGE") || id.hasPrefix("stability.") || id.contains("nova-canvas") || id.contains("titan-image") { return .image }
        // GPT-6 and GPT-5.6 have Converse cross-region profiles. The models below
        // are still Mantle-only and use its OpenAI-compatible Responses endpoint.
        if ["openai.gpt-5.4", "openai.gpt-5.5", "xai.grok-4.3"].contains(id) || id.hasPrefix("google.gemma-4-") { return .responses }
        return .conversation
    }

    static func providerName(_ value: String) -> String {
        let provider = provider(value)
        return [
            "ai21": "AI21 Labs", "amazon": "Amazon", "anthropic": "Anthropic",
            "cohere": "Cohere", "deepseek": "DeepSeek", "google": "Google",
            "luma": "Luma AI", "meta": "Meta", "minimax": "MiniMax",
            "mistral": "Mistral AI", "moonshot": "Moonshot AI", "moonshotai": "Moonshot AI",
            "nvidia": "NVIDIA", "openai": "OpenAI", "qwen": "Qwen",
            "stability": "Stability AI", "twelvelabs": "TwelveLabs",
            "writer": "Writer", "xai": "xAI", "zai": "Z.AI"
        ][provider] ?? provider.capitalized
    }

    /// Retired entries from the requested catalog also stay hidden when a cached
    /// profile lacks lifecycle metadata. The exact version matters: Nova 2 Sonic
    /// and Sonnet 4.5/4.6 remain available.
    static func isLegacy(_ value: String, lifecycle: String? = nil) -> Bool {
        if let lifecycle, !["ACTIVE", "UNKNOWN", ""].contains(lifecycle.uppercased()) { return true }
        let id = base(value).lowercased()
        return [
            "anthropic.claude-opus-4-1-", "anthropic.claude-sonnet-4-20250514-",
            "twelvelabs.marengo-embed-2-7-", "amazon.nova-sonic-",
            "amazon.nova-premier-", "amazon.nova-reel-", "amazon.nova-canvas-",
            "ai21.jamba-1-5-large-", "ai21.jamba-1-5-mini-"
        ].contains { id.hasPrefix($0) }
    }

    /// Product exclusions apply to bundled, cached, and live model choices.
    /// Keep the model metadata and invocation support for existing conversations.
    static func isExcludedFromSelection(_ value: String) -> Bool {
        let id = base(value).lowercased()
        return id == "amazon.nova-2-pro-preview" || id.hasPrefix("amazon.nova-2-pro-preview-")
    }
}

enum BedrockModelOrigin: String, Codable, Sendable { case runtime, mantle, custom }

struct BedrockModelDescriptor: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var provider: String
    var inputModalities: [String]
    var outputModalities: [String]
    var inferenceTypes: [String]
    var streaming: Bool?
    var foundationID: String?
    var isProfile = false
    var lifecycle: String? = nil
    var origin: BedrockModelOrigin = .runtime
    var route: BedrockModelRoute { BedrockModelID.route(foundationID ?? id, output: outputModalities) }
    var isApplicationProfile: Bool { isProfile && id.contains(":application-inference-profile/") }
    var isLegacy: Bool { BedrockModelID.isLegacy(foundationID ?? id, lifecycle: lifecycle) }
    var isHiddenFromSelection: Bool {
        isLegacy || BedrockModelID.isExcludedFromSelection(id)
            || BedrockModelID.isExcludedFromSelection(foundationID ?? id)
    }
    var isConversation: Bool { route == .conversation || route == .responses || route == .videoAnalysis }
    var acceptsImages: Bool { inputModalities.contains("IMAGE") }
    var acceptsAudio: Bool { inputModalities.contains("SPEECH") || inputModalities.contains("AUDIO") }
    var acceptsVideo: Bool { inputModalities.contains("VIDEO") }
    var needsProvisionedThroughput: Bool { !isProfile && !inferenceTypes.isEmpty && Set(inferenceTypes).isSubset(of: ["PROVISIONED"]) }
}

/// The runtime consults the same metadata as the UI without touching SwiftUI state.
final class BedrockCapabilityRegistry: @unchecked Sendable {
    static let shared = BedrockCapabilityRegistry()
    private let lock = NSLock()
    private var byRegion: [String: [String: BedrockModelDescriptor]] = [:]
    func replace(region: String, descriptors: [BedrockModelDescriptor]) {
        lock.lock(); defer { lock.unlock() }
        byRegion[region] = Dictionary(descriptors.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    }
    func descriptor(_ id: String, region: String) -> BedrockModelDescriptor? {
        lock.lock(); defer { lock.unlock() }
        return byRegion[region]?[id] ?? byRegion[region]?[BedrockModelID.base(id)]
    }
    func foundationID(_ id: String, region: String) -> String {
        descriptor(id, region: region)?.foundationID ?? BedrockModelID.base(id)
    }
    func invocationID(_ id: String, region: String) -> String {
        lock.lock(); defer { lock.unlock() }
        guard let catalog = byRegion[region], let entry = catalog[id], !entry.isProfile,
              !entry.inferenceTypes.contains("ON_DEMAND"), entry.inferenceTypes.contains("INFERENCE_PROFILE") else { return id }
        let prefix = region.hasPrefix("us-gov-") ? "us-gov." : region.hasPrefix("eu-") ? "eu." : region.hasPrefix("ap-") ? "apac." : "us."
        return catalog.values.filter { $0.isProfile && !$0.isApplicationProfile &&
            BedrockModelID.base($0.foundationID ?? $0.id) == BedrockModelID.base(id) }
            .sorted {
                func rank(_ item: BedrockModelDescriptor) -> Int { item.id.hasPrefix(prefix) ? 0 : item.id.hasPrefix("global.") ? 1 : 2 }
                if rank($0) != rank($1) { return rank($0) < rank($1) }
                return $0.id < $1.id
            }.first?.id ?? id
    }
}
