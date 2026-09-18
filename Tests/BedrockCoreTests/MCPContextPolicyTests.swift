import XCTest
@testable import BedrockCore

final class MCPContextPolicyTests: XCTestCase {
    func testKeywordsAreOptInLiteralCaseInsensitiveAndWordAware() {
        XCTAssertTrue(MCPContextPolicy.matches("Hello", keywords: nil))
        XCTAssertTrue(MCPContextPolicy.matches("Hello", keywords: [" "]))
        XCTAssertEqual(MCPContextPolicy.keywords([" Git ", "git", " DATABASE"]), ["git", "database"])
        XCTAssertTrue(MCPContextPolicy.matches("Check the GIT diff", keywords: ["git"]))
        XCTAssertFalse(MCPContextPolicy.matches("Create a digital illustration", keywords: ["git"]))
        XCTAssertTrue(MCPContextPolicy.matches("Plan payment\nprocessing", keywords: ["payment processing"]))
        XCTAssertTrue(MCPContextPolicy.matches("Use C++ for this", keywords: ["c++"]))
        XCTAssertFalse(MCPContextPolicy.matches("Use C for this", keywords: ["c++"]))
        XCTAssertTrue(MCPContextPolicy.matches("데이터베이스를 확인해줘", keywords: ["데이터베이스"]))
    }

    func testOnboardingIsBoundedAndDoesNotAddEmptySections() {
        XCTAssertEqual(MCPContextPolicy.onboarding([("Unused", "")]), "")
        let docs = (0..<10).map { ("Server \($0)", String(repeating: "x", count: 32_000)) }
        let result = MCPContextPolicy.onboarding(docs)
        XCTAssertLessThan(result.count, 24_500)
        XCTAssertEqual(result.filter { $0 == "x" }.count, 24_000)
        XCTAssertTrue(result.contains("Server 0"))
        XCTAssertFalse(result.contains("Server 9"))
    }
}
