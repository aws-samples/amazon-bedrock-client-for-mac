import XCTest
@testable import BedrockCore

final class InferenceProfileTests: XCTestCase {
    private let base = BedrockModelDescriptor(id: "anthropic.claude-haiku-4-5-20251001-v1:0",
        name: "Claude Haiku 4.5", provider: "Anthropic", inputModalities: ["TEXT", "IMAGE"],
        outputModalities: ["TEXT"], inferenceTypes: ["INFERENCE_PROFILE"], streaming: true)
    private let arn = "arn:aws:bedrock:us-east-1:123456789012:application-inference-profile/team-one"

    func testApplicationProfilesKeepNamesFullARNsAndIndependentChoices() throws {
        let first = try profile(arn: arn, name: "Team one")
        let second = try profile(arn: arn.replacingOccurrences(of: "team-one", with: "team-two"), name: "Team two")
        XCTAssertEqual(first.id, arn)
        XCTAssertEqual(first.name, "Team one")
        XCTAssertEqual(first.foundationID, base.id)
        XCTAssertTrue(first.acceptsImages)
        XCTAssertEqual(first.provider, "Anthropic")
        let choices = BedrockModelChoice.make(descriptors: [base, first, second], selectedID: second.id,
                                              favoriteIDs: [first.id], region: "us-east-1")
        XCTAssertEqual(choices.count, 3)
        XCTAssertEqual(Set(choices.map(\.name)), [base.name, "Team one", "Team two"])
        XCTAssertEqual(choices.first?.preferredID, first.id)
        XCTAssertTrue(choices.contains { $0.preferredID == second.id })
    }

    func testApplicationProfileIsNeverAutomaticallyUsedForAnotherModelsBilling() throws {
        let first = try profile(arn: arn, name: "Team one")
        let registry = BedrockCapabilityRegistry()
        registry.replace(region: "us-east-1", descriptors: [base, first])
        XCTAssertEqual(registry.invocationID(base.id, region: "us-east-1"), base.id)
        XCTAssertEqual(registry.invocationID(first.id, region: "us-east-1"), arn)
        XCTAssertEqual(registry.foundationID(first.id, region: "us-east-1"), base.id)
        XCTAssertNil(registry.descriptor(first.id, region: "eu-west-1"))
    }

    func testProfileValidationRejectsWrongRegionsInactiveAndAmbiguousModels() throws {
        XCTAssertEqual(try BedrockInferenceProfile.validateARN(" \(arn)\n", region: "us-east-1"), arn)
        for invalid in [arn.replacingOccurrences(of: "us-east-1", with: "eu-west-1"),
                        arn.replacingOccurrences(of: "bedrock", with: "iam"),
                        arn + "/extra", "team-one", "https://example.com/profile"] {
            XCTAssertThrowsError(try BedrockInferenceProfile.validateARN(invalid, region: "us-east-1"))
        }
        XCTAssertThrowsError(try BedrockInferenceProfile.descriptor(id: "team-one", arn: arn, name: "Team one",
            type: "APPLICATION", status: "CREATING", modelARNs: [base.id], foundations: [base]))
        XCTAssertThrowsError(try BedrockInferenceProfile.descriptor(id: "team-one", arn: arn, name: "Team one",
            type: "APPLICATION", status: "ACTIVE", modelARNs: [base.id, "amazon.nova-pro-v1:0"], foundations: [base]))
        XCTAssertThrowsError(try BedrockInferenceProfile.descriptor(id: "team-one", arn: nil, name: nil,
            type: "APPLICATION", status: "ACTIVE", modelARNs: [base.id], foundations: [base]))
    }

    func testSystemProfilesRetainRegionalGroupingAndImportedMetadataRoundTrips() throws {
        let id = "us." + base.id
        let system = try BedrockInferenceProfile.descriptor(id: id,
            arn: "arn:aws:bedrock:us-east-1:123456789012:inference-profile/" + id, name: "US Haiku",
            type: "SYSTEM_DEFINED", status: "ACTIVE", modelARNs: [base.id], foundations: [base])
        XCTAssertEqual(system.id, id)
        XCTAssertEqual(system.name, base.name)
        XCTAssertEqual(BedrockModelChoice.make(descriptors: [base, system], selectedID: nil,
                                               favoriteIDs: [], region: "us-east-1").count, 1)
        let imported = try profile(arn: arn, name: "Team one")
        let decoded = try JSONDecoder().decode([BedrockModelDescriptor].self, from: JSONEncoder().encode([imported]))
        XCTAssertEqual(decoded, [imported])
    }

    private func profile(arn: String, name: String) throws -> BedrockModelDescriptor {
        try BedrockInferenceProfile.descriptor(id: "opaque-id", arn: arn, name: name,
            type: "APPLICATION", status: "ACTIVE",
            modelARNs: ["arn:aws:bedrock:us-east-1::foundation-model/" + base.id,
                        "arn:aws:bedrock:us-west-2::foundation-model/" + base.id], foundations: [base])
    }
}
