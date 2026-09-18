import XCTest
@testable import BedrockCore

final class BedrockResponsesEndpointTests: XCTestCase {
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
        for id in ["openai.gpt-5.5", "openai.gpt-5.4", "openai.gpt-5.4-2026-03-05",
                   "openai.gpt-5.5-2026-04-23", "xai.grok-4.3", "google.gemma-4-31b"] {
            XCTAssertTrue(BedrockResponsesEndpoint.usesResponses(id, hasDocuments: false))
            let endpoint = try BedrockResponsesEndpoint.resolve(modelID: id, region: "us-east-2")
            XCTAssertEqual(endpoint.plane, .mantle)
            XCTAssertEqual(endpoint.modelID, id)
            let path = id.hasPrefix("openai.gpt-5.") ? "/openai/v1/responses" : "/v1/responses"
            XCTAssertEqual(endpoint.url.absoluteString, "https://bedrock-mantle.us-east-2.api.aws" + path)
            XCTAssertEqual(endpoint.signingService, "bedrock")
        }
        XCTAssertEqual(try BedrockResponsesEndpoint.resolve(modelID: "openai.gpt-oss-120b", region: "us-east-1").url.path,
                       "/v1/responses", "GPT OSS keeps the standard Mantle API path.")
    }
}
