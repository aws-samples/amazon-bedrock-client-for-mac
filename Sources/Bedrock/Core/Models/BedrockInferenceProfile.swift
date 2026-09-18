import Foundation

enum BedrockInferenceProfile {
    static func validateARN(_ value: String, region: String) throws -> String {
        let arn = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = arn.split(separator: ":", maxSplits: 5, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 6, parts[0] == "arn", ["aws", "aws-us-gov", "aws-cn"].contains(parts[1]),
              parts[2] == "bedrock", parts[3] == region,
              parts[4].count == 12, parts[4].allSatisfy(\.isNumber),
              ["inference-profile/", "application-inference-profile/"].contains(where: parts[5].hasPrefix),
              let identifier = parts[5].split(separator: "/").last,
              parts[5].split(separator: "/").count == 2, !identifier.isEmpty,
              !arn.contains(where: \.isWhitespace) else {
            throw LocalOperationError.invalid("Enter a Bedrock inference profile ARN for \(region).")
        }
        return arn
    }

    static func descriptor(id: String?, arn: String?, name: String?, type: String?,
                           status: String?, modelARNs: [String],
                           foundations: [BedrockModelDescriptor]) throws -> BedrockModelDescriptor {
        guard status == "ACTIVE" else {
            throw LocalOperationError.invalid("The inference profile is not active.")
        }
        let modelIDs = Set(modelARNs.map(BedrockModelID.base).filter { !$0.isEmpty })
        guard modelIDs.count == 1, let foundationID = modelIDs.first else {
            throw LocalOperationError.invalid("The inference profile does not identify a single supported foundation model.")
        }
        let application = type == "APPLICATION" || arn?.contains(":application-inference-profile/") == true
        guard let identifier = application ? arn : (id ?? arn), !identifier.isEmpty else {
            throw LocalOperationError.invalid("The inference profile is missing its identifier.")
        }
        let foundation = foundations.first { BedrockModelID.base($0.id) == foundationID && !$0.isProfile }
        return BedrockModelDescriptor(id: identifier,
            name: application ? (name ?? identifier) : (foundation?.name ?? name ?? identifier),
            provider: foundation?.provider ?? BedrockModelID.providerName(foundationID),
            inputModalities: foundation?.inputModalities ?? [],
            outputModalities: foundation?.outputModalities ?? [],
            inferenceTypes: ["INFERENCE_PROFILE"], streaming: foundation?.streaming,
            foundationID: foundationID, isProfile: true, lifecycle: foundation?.lifecycle)
    }
}
