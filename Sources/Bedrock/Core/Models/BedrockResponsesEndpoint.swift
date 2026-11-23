import Foundation

/// The selected profile and source region are part of the connection, not an
/// attachment workaround. Never silently broaden a geographic profile.
struct BedrockResponsesEndpoint: Equatable, Sendable {
    enum Plane: Sendable { case runtime, mantle }
    let plane: Plane
    let region: String
    let modelID: String
    let url: URL
    let signingService = "bedrock"

    // Both endpoints and the runtime profile requirement are documented at:
    // https://docs.aws.amazon.com/bedrock/latest/userguide/bedrock-mantle.html
    static func supportsRuntimeDocuments(_ modelID: String) -> Bool {
        ["openai.gpt-6.2-astra", "openai.gpt-6.2-sol", "openai.gpt-6.1-sol", "openai.gpt-6.1-terra",
         "openai.gpt-6-astra", "openai.gpt-6-sol", "openai.gpt-6-luna",
         "openai.gpt-5.6-sol", "openai.gpt-5.6-terra", "openai.gpt-5.6-luna",
         "xai.grok-4.6", "xai.grok-4.7", "moonshotai.kimi-k3"].contains(BedrockModelID.base(modelID))
    }

    /// GPT-6.2 Astra and Sol read text files on Runtime Responses and reject
    /// PDF input with a 400 (measured 2026-11-23 in us-west-2).
    static func readsPDF(_ modelID: String) -> Bool {
        !["openai.gpt-6.2-astra", "openai.gpt-6.2-sol"].contains(BedrockModelID.base(modelID))
    }

    static func validateDocumentFormats(foundationID: String, formats: [String]) throws {
        if !readsPDF(foundationID) && formats.contains(where: { $0.lowercased() == "pdf" }) {
            throw LocalOperationError.invalid(
                "This model cannot read PDF files. Attach the text as a TXT, Markdown, CSV or HTML file, or choose another model. Your attachment is still saved."
            )
        }
    }

    /// GPT-5.4 and GPT-5.5 keep bedrock-mantle where it serves them. Elsewhere
    /// their system inference profiles are served by Bedrock Runtime Responses.
    static func usesRuntimeOutsideMantle(modelID: String, region: String) -> Bool {
        let baseID = BedrockModelID.base(modelID)
        guard BedrockMantleCatalog.runtimeProfileModels.contains(baseID),
              let regions = BedrockMantleCatalog.regions(for: baseID), !regions.contains(region) else { return false }
        return modelID != baseID || ["us-east-1", "us-east-2", "us-west-2"].contains(region)
    }

    static func usesResponses(_ modelID: String, hasDocuments: Bool, foundationID: String? = nil) -> Bool {
        guard !modelID.contains(":application-inference-profile/") else { return false }
        let foundation = foundationID ?? modelID
        return BedrockModelID.route(foundation) == .responses || hasDocuments && supportsRuntimeDocuments(foundation)
    }

    /// Application profiles retain their billing and IAM scope. Runtime
    /// Responses accepts system profiles, so substituting one is not a retry.
    static func validateDocumentRoute(modelID: String, foundationID: String, hasDocuments: Bool) throws {
        if hasDocuments && modelID.contains(":application-inference-profile/") && supportsRuntimeDocuments(foundationID) {
            throw LocalOperationError.invalid(
                "This model cannot receive documents through an application inference profile. Select its US or Global model profile to send the file. Your attachment is still saved."
            )
        }
    }

    static func resolve(modelID: String, region: String) throws -> Self {
        guard !modelID.contains(":application-inference-profile/") else {
            throw LocalOperationError.invalid("Responses does not support application inference profiles. Select a system inference profile for this request.")
        }
        guard region.range(of: #"^[a-z]{2}(?:-[a-z0-9]+)+-[0-9]+$"#, options: .regularExpression) != nil else {
            throw LocalOperationError.invalid("Choose a valid AWS region.")
        }
        let runtime = supportsRuntimeDocuments(modelID) || usesRuntimeOutsideMantle(modelID: modelID, region: region)
        var wireID = modelID
        if runtime && modelID == BedrockModelID.base(modelID) {
            let supportsUSProfile: Bool
            if BedrockModelID.isKimiK3(modelID) {
                supportsUSProfile = BedrockBundledCatalog.records.first { $0.id == modelID }?
                    .regions[region]?.profiles.contains("us." + modelID) == true
            } else {
                supportsUSProfile = ["us-east-1", "us-east-2", "us-west-2"].contains(region)
            }
            guard supportsUSProfile else {
                throw LocalOperationError.invalid("Choose an inference profile available in \(region) for this model in Settings → Models.")
            }
            wireID = "us." + modelID
        }
        let baseID = BedrockModelID.base(modelID)
        let frontierOpenAI = baseID.hasPrefix("openai.gpt-") && !baseID.hasPrefix("openai.gpt-oss")
        let mantlePath = frontierOpenAI ? "/openai/v1/responses" : "/v1/responses"
        let address = runtime
            ? "https://bedrock-runtime.\(region).amazonaws.com/openai/v1/responses"
            : "https://bedrock-mantle.\(region).api.aws\(mantlePath)"
        guard let url = URL(string: address), url.host != nil, !region.contains("/"), !region.contains(":") else {
            throw LocalOperationError.invalid("Choose a valid AWS region.")
        }
        return Self(plane: runtime ? .runtime : .mantle, region: region,
                    modelID: runtime ? wireID : BedrockModelID.base(modelID), url: url)
    }
}
