import Foundation

struct BedrockRegionalModel: Codable, Identifiable, Sendable {
    struct Availability: Codable, Sendable {
        var inferenceTypes: [String]
        var profiles: [String]
    }
    var id: String
    var name: String
    var provider: String
    var inputModalities: [String]
    var outputModalities: [String]
    var streaming: Bool?
    var releasedAt: String?
    var regions: [String: Availability]

    func descriptors(in region: String) -> [BedrockModelDescriptor] {
        guard let availability = regions[region] else { return [] }
        let foundation = BedrockModelDescriptor(id: id, name: name, provider: provider,
            inputModalities: inputModalities, outputModalities: outputModalities,
            inferenceTypes: availability.inferenceTypes, streaming: streaming, lifecycle: "ACTIVE")
        return [foundation] + availability.profiles.map { profile in
            var descriptor = foundation
            descriptor.id = profile
            descriptor.foundationID = id
            descriptor.isProfile = true
            return descriptor
        }
    }
}

enum BedrockMantleCatalog {
    // Mantle-only model cards, checked 2026-09-15. Runtime models are discovered
    // through ListFoundationModels and ListInferenceProfiles, never this list.
    struct Entry: Sendable {
        let id: String
        let name: String
        let regions: Set<String>
        let input: [String]
        var descriptor: BedrockModelDescriptor {
            .init(id: id, name: name, provider: BedrockModelID.providerName(id),
                  inputModalities: input, outputModalities: ["TEXT"],
                  inferenceTypes: ["ON_DEMAND"], streaming: true, lifecycle: "ACTIVE", origin: .mantle)
        }
    }
    static let entries: [Entry] = [
        .init(id: "openai.gpt-5.4", name: "GPT-5.4", regions: ["us-east-1", "us-east-2", "us-west-2"], input: ["TEXT", "IMAGE"]),
        .init(id: "openai.gpt-5.5", name: "GPT-5.5", regions: ["us-east-1", "us-east-2"], input: ["TEXT", "IMAGE"]),
        .init(id: "xai.grok-4.3", name: "Grok 4.3", regions: ["us-east-1", "us-east-2", "us-west-2", "us-gov-west-1"], input: ["TEXT", "IMAGE"]),
        .init(id: "google.gemma-4-26b-a4b", name: "Gemma 4 26B-A4B", regions: ["us-east-1", "us-east-2", "us-west-2", "eu-central-1"], input: ["TEXT", "IMAGE", "VIDEO"]),
        .init(id: "google.gemma-4-31b", name: "Gemma 4 31B", regions: ["us-east-1", "us-east-2", "us-west-2", "eu-central-1"], input: ["TEXT", "IMAGE", "VIDEO"]),
        .init(id: "google.gemma-4-e2b", name: "Gemma 4 E2B", regions: ["us-east-1", "us-east-2", "us-west-2", "eu-central-1"], input: ["TEXT", "IMAGE", "AUDIO", "VIDEO"])
    ]

    static func descriptors(in region: String) -> [BedrockModelDescriptor] {
        entries.filter { $0.regions.contains(region) }.map(\.descriptor)
    }
}
