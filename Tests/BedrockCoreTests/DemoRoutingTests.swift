import XCTest
@testable import BedrockCore

final class DemoRoutingTests: XCTestCase {
    func testCreateImageExcludesEveryStabilityEditingServiceAndLegacyModels() {
        let services = ["stable-conservative-upscale", "stable-creative-upscale", "stable-fast-upscale",
                        "stable-outpaint", "stable-style-transfer", "stable-image-control-sketch",
                        "stable-image-control-structure", "stable-image-erase-object", "stable-image-inpaint",
                        "stable-image-remove-background", "stable-image-search-recolor",
                        "stable-image-search-replace", "stable-image-style-guide"]
        for service in services {
            for prefix in ["", "us."] {
                let model = "\(prefix)stability.\(service)-v1:0"
                XCTAssertEqual(BedrockModelID.route(model), .image)
                XCTAssertFalse(DemoModelPolicy.supports(model, category: .images), model)
            }
        }
        for model in ["stability.stable-image-core-v1:1", "stability.stable-image-ultra-v1:1", "stability.sd3-5-large-v1:0"] {
            XCTAssertTrue(DemoModelPolicy.supports(model, category: .images))
        }
        XCTAssertFalse(DemoModelPolicy.supports("amazon.nova-canvas-v1:0", category: .images))
        XCTAssertLessThan(DemoModelPolicy.preference("stability.stable-image-core-v1:1", category: .images),
                          DemoModelPolicy.preference("stability.stable-image-ultra-v1:1", category: .images))
    }

    func testConversationDemosExcludeSpeechRerankAndMultimodalEmbeddingEndpoints() {
        for model in ["amazon.nova-2-sonic-v1:0", "cohere.rerank-v3-5:0", "amazon.rerank-v1:0",
                      "twelvelabs.marengo-embed-3-0-v1:0", "amazon.nova-2-multimodal-embeddings-v1:0", "luma.ray-v2:0"] {
            XCTAssertFalse(DemoModelPolicy.supports(model, category: .text), model)
        }
        XCTAssertTrue(DemoModelPolicy.supports("us.openai.gpt-6-astra", category: .text))
        XCTAssertTrue(DemoModelPolicy.supports("openai.gpt-5.5", category: .text))
        XCTAssertTrue(DemoModelPolicy.supports("amazon.titan-embed-text-v2:0", category: .embeddings))
        XCTAssertFalse(DemoModelPolicy.supports("twelvelabs.marengo-embed-3-0-v1:0", category: .embeddings))
    }

    func testImageInvocationResolvesRequiredProfileAndPreservesOnDemandCore() {
        let editing = BedrockModelDescriptor(id: "stability.stable-conservative-upscale-v1:0",
                                             name: "Conservative Upscale", provider: "Stability AI",
                                             inputModalities: ["TEXT", "IMAGE"], outputModalities: ["IMAGE"],
                                             inferenceTypes: ["INFERENCE_PROFILE"])
        var profile = editing
        profile.id = "us." + editing.id; profile.foundationID = editing.id; profile.isProfile = true
        let core = BedrockModelDescriptor(id: "stability.stable-image-core-v1:1", name: "Core", provider: "Stability AI",
                                         inputModalities: ["TEXT"], outputModalities: ["IMAGE"], inferenceTypes: ["ON_DEMAND"])
        let registry = BedrockCapabilityRegistry()
        registry.replace(region: "us-west-2", descriptors: [editing, profile, core])
        XCTAssertEqual(registry.invocationID(editing.id, region: "us-west-2"), profile.id)
        XCTAssertEqual(registry.invocationID(profile.id, region: "us-west-2"), profile.id)
        XCTAssertEqual(registry.invocationID(core.id, region: "us-west-2"), core.id)
        let choices = BedrockModelChoice.make(descriptors: [editing, profile, core], selectedID: nil, favoriteIDs: [], region: "us-west-2")
        XCTAssertEqual(choices.first { $0.id == editing.id }?.preferredID, profile.id)
    }

    func testOldThreadMetadataLoadsWithoutDemoIdentifier() throws {
        let data = Data(#"{"draft":"preserved","skillIDs":["review"],"systemPrompt":"","archived":false}"#.utf8)
        let old = try JSONDecoder().decode(ThreadMetadata.self, from: data)
        XCTAssertNil(old.demoID)
        XCTAssertEqual(old.draft, "preserved")
        XCTAssertEqual(old.skillIDs, ["review"])
        var updated = old
        updated.demoID = "document"
        XCTAssertEqual(try JSONDecoder().decode(ThreadMetadata.self, from: JSONEncoder().encode(updated)), updated)
    }

    func testLegacySDKFailuresDisplayServiceMessageWithoutTransportDump() {
        let source = #"Error invoking the model: ValidationException(properties: AWSBedrockRuntime.ValidationException.Properties(message: Optional("Invocation of model ID stability.stable-conservative-upscale-v1:0 with on-demand throughput isn’t supported. Retry with an inference profile.")), httpResponse: Status Code: HTTP status code 400 x-amzn-requestid: example)"#
        let message = BedrockFailureMessage.readable(source)
        XCTAssertTrue(message.contains("requires an inference profile"))
        XCTAssertFalse(message.contains("httpResponse"))
        XCTAssertEqual(BedrockFailureMessage.readable("Attach a source image."), "Attach a source image.")
        let escaped = #"ValidationException(properties: Properties(message: Optional("Use \"high\" effort.")), httpResponse: details)"#
        XCTAssertEqual(BedrockFailureMessage.readable(escaped), #"Use "high" effort."#)
    }

    func testLumaRequestUsesDocumentedParametersAndKeyframeMediaTypes() throws {
        let config = LumaVideoConfiguration(duration: "9s", loop: true)
        let png = Data([137, 80, 78, 71, 13, 10, 26, 10]).base64EncodedString()
        let jpeg = Data([255, 216, 255, 224]).base64EncodedString()
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: config.request(prompt: "A coastal town.", images: [png, jpeg])) as? [String: Any])
        XCTAssertEqual(body["duration"] as? String, "9s")
        XCTAssertEqual(body["loop"] as? Bool, true)
        XCTAssertNil(body["seed"])
        let frames = try XCTUnwrap(body["keyframes"] as? [String: [String: Any]])
        XCTAssertEqual((frames["frame0"]?["source"] as? [String: String])?["media_type"], "image/png")
        XCTAssertEqual((frames["frame1"]?["source"] as? [String: String])?["media_type"], "image/jpeg")
        XCTAssertThrowsError(try config.request(prompt: ""))
        XCTAssertThrowsError(try config.request(prompt: String(repeating: "a", count: 5_001)))
        XCTAssertThrowsError(try config.request(prompt: "A town.", images: [png, png, png]))
        XCTAssertThrowsError(try LumaVideoConfiguration(duration: "6s").request(prompt: "A town."))
    }
}
