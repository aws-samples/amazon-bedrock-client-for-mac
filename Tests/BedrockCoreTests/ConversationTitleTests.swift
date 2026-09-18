import XCTest
@testable import BedrockCore

final class ConversationTitleTests: XCTestCase {
    func testAutomaticChoosesAnAvailableTextModelAndExplicitSelectionWins() throws {
        let models = [
            model("stability.stable-image-ultra-v1:1", output: ["IMAGE"]),
            model("us.anthropic.claude-haiku-4-5-20251001-v1:0"),
            model("openai.gpt-5.5")
        ]
        XCTAssertEqual(try ConversationTitle.modelID(preferred: nil, available: models), models[1].id)
        XCTAssertEqual(try ConversationTitle.modelID(preferred: models[2].id, available: models), models[2].id)
        XCTAssertEqual(try ConversationTitle.modelID(preferred: nil, available: [models[2]]), models[2].id)
        XCTAssertThrowsError(try ConversationTitle.modelID(preferred: "missing", available: models))
        XCTAssertThrowsError(try ConversationTitle.modelID(preferred: models[0].id, available: models))
        XCTAssertThrowsError(try ConversationTitle.modelID(preferred: nil, available: [models[0]]))
    }

    func testNonTextRetiredAndProvisionedModelsCannotBeUsedForTitles() {
        var provisioned = model("amazon.nova-pro-v1:0")
        provisioned.inferenceTypes = ["PROVISIONED"]
        var retired = model("anthropic.claude-haiku-4-5-20251001-v1:0")
        retired.lifecycle = "LEGACY"
        for item in [provisioned, retired, model("amazon.nova-2-sonic-v1:0"),
                     model("amazon.titan-embed-text-v2:0"), model("amazon.nova-2-pro-preview-20251202-v1:0")] {
            XCTAssertFalse(ConversationTitle.supports(item), item.id)
        }
    }

    func testTitlePreferenceRoundTripsAndOlderPreferencesRetainAutomaticSelection() throws {
        var preferences = AppPreferences()
        preferences.automaticTitles = true
        preferences.titleGenerationModelID = "openai.gpt-5.5"
        let encoded = try JSONEncoder().encode(preferences)
        XCTAssertEqual(try JSONDecoder().decode(AppPreferences.self, from: encoded), preferences)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "titleGenerationModelID")
        let restored = try JSONDecoder().decode(AppPreferences.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(restored.titleGenerationModelID)
        XCTAssertTrue(restored.automaticTitles)
        XCTAssertEqual(restored.contextCharacterBudget, preferences.contextCharacterBudget)
    }

    func testTitleRequestsAndSidebarResultsAreBounded() {
        let input = String(repeating: "long input ", count: 10_000)
        XCTAssertLessThan(ConversationTitle.prompt(input).count, 6500)
        XCTAssertEqual(ConversationTitle.clean("\n“Local file search”\nExplanation"), "Local file search")
        XCTAssertEqual(ConversationTitle.clean(String(repeating: "가", count: 200)).count, 120)
        XCTAssertEqual(ConversationTitle.clean(" \n "), "")
    }

    private func model(_ id: String, output: [String] = ["TEXT"]) -> BedrockModelDescriptor {
        .init(id: id, name: id, provider: BedrockModelID.providerName(id),
              inputModalities: ["TEXT"], outputModalities: output, inferenceTypes: ["ON_DEMAND"], streaming: true)
    }
}
