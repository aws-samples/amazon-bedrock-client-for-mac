import XCTest
@testable import BedrockCore

final class BedrockResponsesEndpointTests: XCTestCase {
    func testAstraApplicationProfileDoesNotSilentlyChangeBillingForFiles() throws {
        let arn = "arn:aws:bedrock:us-east-1:123456789012:application-inference-profile/team"
        let foundation = "openai.gpt-6-astra"
        XCTAssertNoThrow(try BedrockResponsesEndpoint.validateDocumentRoute(
            modelID: arn, foundationID: foundation, hasDocuments: false))
        XCTAssertThrowsError(try BedrockResponsesEndpoint.validateDocumentRoute(
            modelID: arn, foundationID: foundation, hasDocuments: true)) { error in
            XCTAssertTrue(error.localizedDescription.contains("application inference profile"))
            XCTAssertTrue(error.localizedDescription.contains("attachment is still saved"))
        }
        XCTAssertFalse(BedrockResponsesEndpoint.usesResponses(arn, hasDocuments: true, foundationID: foundation))
        XCTAssertThrowsError(try BedrockResponsesEndpoint.resolve(modelID: arn, region: "us-east-1"))
        XCTAssertNoThrow(try BedrockResponsesEndpoint.validateDocumentRoute(
            modelID: arn, foundationID: "anthropic.claude-haiku-4-5-20251001-v1:0", hasDocuments: true))
    }

    func testAstraFileRoutingPreservesExplicitProfilesAndRejectsMalformedRegions() throws {
        for profile in ["us.openai.gpt-6-astra", "global.openai.gpt-6-astra"] {
            XCTAssertTrue(BedrockResponsesEndpoint.usesResponses(profile, hasDocuments: true))
            let endpoint = try BedrockResponsesEndpoint.resolve(modelID: profile, region: "us-east-1")
            XCTAssertEqual(endpoint.modelID, profile)
            XCTAssertEqual(endpoint.url.path, "/openai/v1/responses")
        }
        for region in ["", "us-east-1.example.com", "us-east-1/extra", "us-east-1?redirect=true"] {
            XCTAssertThrowsError(try BedrockResponsesEndpoint.resolve(modelID: "us.openai.gpt-6-astra", region: region))
        }
    }

    func testDocumentRouteUsesResponsesWhileExistingTextAndToolsKeepConverse() throws {
        for model in ["openai.gpt-6-astra", "openai.gpt-5.6-luna", "openai.gpt-5.6-sol",
                      "openai.gpt-5.6-terra", "xai.grok-4.6"] {
            XCTAssertFalse(BedrockResponsesEndpoint.usesResponses("us." + model, hasDocuments: false))
            XCTAssertTrue(BedrockResponsesEndpoint.usesResponses("us." + model, hasDocuments: true))
            let endpoint = try BedrockResponsesEndpoint.resolve(modelID: "us." + model, region: "us-west-2")
            XCTAssertEqual(endpoint.plane, .runtime)
            XCTAssertEqual(endpoint.modelID, "us." + model)
            XCTAssertEqual(endpoint.signingService, "bedrock")
            XCTAssertEqual(endpoint.url.absoluteString, "https://bedrock-runtime.us-west-2.amazonaws.com/openai/v1/responses")
        }
        XCTAssertFalse(BedrockResponsesEndpoint.usesResponses("us.anthropic.claude-sonnet-4-6", hasDocuments: true))
        XCTAssertFalse(BedrockResponsesEndpoint.usesResponses("us.amazon.nova-2-lite-v1:0", hasDocuments: true))
    }

    func testSelectedGlobalProfileAndSourceRegionStayExplicit() throws {
        let endpoint = try BedrockResponsesEndpoint.resolve(modelID: "global.openai.gpt-5.6-luna", region: "eu-central-1")
        XCTAssertEqual(endpoint.modelID, "global.openai.gpt-5.6-luna")
        XCTAssertEqual(endpoint.region, "eu-central-1")
        XCTAssertEqual(endpoint.url.host, "bedrock-runtime.eu-central-1.amazonaws.com")
        let us = try BedrockResponsesEndpoint.resolve(modelID: "openai.gpt-5.6-luna", region: "us-east-2")
        XCTAssertEqual(us.modelID, "us.openai.gpt-5.6-luna")
        XCTAssertThrowsError(try BedrockResponsesEndpoint.resolve(modelID: "openai.gpt-5.6-luna", region: "eu-central-1"),
                             "A bare ID must not silently opt into global inference or switch the user's AWS region.")
    }

    func testMantleOnlyModelsKeepTheirExistingEndpointAndBareID() throws {
        for id in ["openai.gpt-5.5", "openai.gpt-5.4", "xai.grok-4.3", "google.gemma-4-31b"] {
            XCTAssertTrue(BedrockResponsesEndpoint.usesResponses(id, hasDocuments: false))
            let endpoint = try BedrockResponsesEndpoint.resolve(modelID: id, region: "us-east-2")
            XCTAssertEqual(endpoint.plane, .mantle)
            XCTAssertEqual(endpoint.modelID, id)
            XCTAssertEqual(endpoint.url.absoluteString, "https://bedrock-mantle.us-east-2.api.aws/v1/responses")
            XCTAssertEqual(endpoint.signingService, "bedrock")
        }
    }
}
