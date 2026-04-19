//
//  MCPModelsTests.swift
//  Amazon Bedrock Client for Mac
//
//  Tests for MCP model utility functions, particularly tool name namespacing
//

import XCTest
@testable import Amazon_Bedrock_Client_for_Mac

final class MCPModelsTests: XCTestCase {

    // MARK: - Tool Name Namespacing Tests

    /// Test that empty namespace returns original tool name
    func testNamespacedToolName_EmptyNamespace() {
        let toolName = "test_tool"
        let result = namespacedToolName(namespace: "", toolName: toolName)
        XCTAssertEqual(result, toolName, "Empty namespace should return original tool name")
    }

    /// Test normal case where combined length is well under 64 characters
    func testNamespacedToolName_NormalLength() {
        let namespace = "server"
        let toolName = "read_file"
        let result = namespacedToolName(namespace: namespace, toolName: toolName)
        XCTAssertEqual(result, "server__read_file")
        XCTAssertLessThanOrEqual(result.count, 64)
    }

    /// Test case where combined length is exactly 64 characters
    func testNamespacedToolName_ExactlyMaxLength() {
        // 64 chars total: namespace (30) + delimiter (2) + tool (32)
        let namespace = String(repeating: "a", count: 30)
        let toolName = String(repeating: "b", count: 32)
        let result = namespacedToolName(namespace: namespace, toolName: toolName)
        XCTAssertEqual(result.count, 64, "Should be exactly 64 characters")
        XCTAssertTrue(result.contains("__"), "Should contain delimiter")
    }

    /// Test case where combined length is 63 characters (under limit)
    func testNamespacedToolName_OneBelowMaxLength() {
        // 63 chars total: namespace (30) + delimiter (2) + tool (31)
        let namespace = String(repeating: "a", count: 30)
        let toolName = String(repeating: "b", count: 31)
        let result = namespacedToolName(namespace: namespace, toolName: toolName)
        XCTAssertEqual(result.count, 63, "Should be exactly 63 characters")
        XCTAssertTrue(result.hasPrefix(namespace + "__"), "Should start with full namespace and delimiter")
        XCTAssertTrue(result.hasSuffix(toolName), "Should end with full tool name")
    }

    /// Test case where combined length exceeds 64 characters - requires truncation
    func testNamespacedToolName_ExceedsMaxLength() {
        // 70 chars total: namespace (34) + delimiter (2) + tool (34)
        let namespace = String(repeating: "a", count: 34)
        let toolName = String(repeating: "b", count: 34)
        let result = namespacedToolName(namespace: namespace, toolName: toolName)

        XCTAssertLessThanOrEqual(result.count, 64, "Should truncate to 64 characters or less")
        XCTAssertTrue(result.contains("__"), "Should contain delimiter")

        // Verify structure: namespace part + __ + tool part
        let parts = result.split(separator: "_", maxSplits: 2, omittingEmptySubsequences: false)
        XCTAssertGreaterThanOrEqual(parts.count, 3, "Should have namespace__toolname structure")
    }

    /// Test long namespace with short tool name
    func testNamespacedToolName_LongNamespaceShortTool() {
        let namespace = String(repeating: "x", count: 60)  // Very long namespace
        let toolName = "tool"  // Short tool name
        let result = namespacedToolName(namespace: namespace, toolName: toolName)

        XCTAssertLessThanOrEqual(result.count, 64, "Should truncate to 64 characters or less")
        XCTAssertTrue(result.contains("__"), "Should contain delimiter")

        // Tool name should get at least minimum length
        let components = result.components(separatedBy: "__")
        XCTAssertEqual(components.count, 2, "Should have exactly 2 parts")
        XCTAssertGreaterThanOrEqual(components[1].count, 4, "Tool name should be preserved when short")
    }

    /// Test short namespace with long tool name
    func testNamespacedToolName_ShortNamespaceLongTool() {
        let namespace = "srv"  // Short namespace
        let toolName = String(repeating: "y", count: 70)  // Very long tool name
        let result = namespacedToolName(namespace: namespace, toolName: toolName)

        XCTAssertLessThanOrEqual(result.count, 64, "Should truncate to 64 characters or less")
        XCTAssertTrue(result.contains("__"), "Should contain delimiter")

        // Namespace should be preserved when short
        let components = result.components(separatedBy: "__")
        XCTAssertEqual(components.count, 2, "Should have exactly 2 parts")
        XCTAssertEqual(components[0], namespace, "Short namespace should be preserved")
    }

    /// Test extremely long namespace with minimal tool name
    func testNamespacedToolName_ExtremelyLongNamespaceMinimalTool() {
        let namespace = String(repeating: "n", count: 100)  // Extremely long
        let toolName = "x"  // Minimal tool name
        let result = namespacedToolName(namespace: namespace, toolName: toolName)

        XCTAssertLessThanOrEqual(result.count, 64, "Should truncate to 64 characters or less")
        XCTAssertTrue(result.contains("__"), "Should contain delimiter")

        let components = result.components(separatedBy: "__")
        XCTAssertEqual(components.count, 2, "Should have exactly 2 parts")
        XCTAssertGreaterThanOrEqual(components[0].count, 8, "Namespace should get at least minimum length")
        XCTAssertGreaterThanOrEqual(components[1].count, 1, "Tool name should be preserved when very short")
    }

    /// Test minimal namespace with extremely long tool name
    func testNamespacedToolName_MinimalNamespaceExtremelyLongTool() {
        let namespace = "s"  // Minimal namespace
        let toolName = String(repeating: "t", count: 100)  // Extremely long
        let result = namespacedToolName(namespace: namespace, toolName: toolName)

        XCTAssertLessThanOrEqual(result.count, 64, "Should truncate to 64 characters or less")
        XCTAssertTrue(result.contains("__"), "Should contain delimiter")

        let components = result.components(separatedBy: "__")
        XCTAssertEqual(components.count, 2, "Should have exactly 2 parts")
        XCTAssertEqual(components[0], namespace, "Short namespace should be preserved")
        XCTAssertGreaterThanOrEqual(components[1].count, 8, "Tool name should get reasonable space")
    }

    /// Test proportional allocation when both are long
    func testNamespacedToolName_ProportionalTruncation() {
        // Both parts equally long - should get roughly equal space
        let namespace = String(repeating: "a", count: 50)
        let toolName = String(repeating: "b", count: 50)
        let result = namespacedToolName(namespace: namespace, toolName: toolName)

        XCTAssertLessThanOrEqual(result.count, 64, "Should truncate to 64 characters or less")

        let components = result.components(separatedBy: "__")
        XCTAssertEqual(components.count, 2, "Should have exactly 2 parts")

        let namespacePart = components[0]
        let toolPart = components[1]

        // With 62 chars available and equal original lengths, allocation should be roughly equal
        // Allow some variance due to integer division
        let lengthDiff = abs(namespacePart.count - toolPart.count)
        XCTAssertLessThanOrEqual(lengthDiff, 2, "Parts should be roughly equal when originals are equal length")
    }

    /// Test with realistic MCP server names and tool names
    func testNamespacedToolName_RealisticNames() {
        let testCases: [(namespace: String, tool: String, shouldTruncate: Bool)] = [
            ("linear_server", "create_issue", false),
            ("github", "create_pull_request", false),
            ("very_long_server_name_with_many_words", "very_long_tool_name_with_descriptive_text", true),
            ("anthropic_claude_mcp_server", "analyze_code_repository_with_context", true),
            ("s", "search_through_documentation_and_return_relevant_results_with_context", true),
        ]

        for (namespace, toolName, shouldTruncate) in testCases {
            let result = namespacedToolName(namespace: namespace, toolName: toolName)
            XCTAssertLessThanOrEqual(result.count, 64, "Result should never exceed 64 characters")
            XCTAssertTrue(result.contains("__"), "Should contain delimiter")

            if !shouldTruncate {
                let expected = "\(namespace)__\(toolName)"
                XCTAssertEqual(result, expected, "Short names should not be truncated")
            }
        }
    }

    /// Test that delimiter is always preserved
    func testNamespacedToolName_DelimiterAlwaysPresent() {
        let testCases = [
            (String(repeating: "a", count: 40), String(repeating: "b", count: 40)),
            (String(repeating: "x", count: 100), String(repeating: "y", count: 100)),
            ("short", "name"),
        ]

        for (namespace, toolName) in testCases where !namespace.isEmpty {
            let result = namespacedToolName(namespace: namespace, toolName: toolName)
            XCTAssertTrue(result.contains("__"), "Delimiter should always be present for non-empty namespace")

            let delimiterCount = result.components(separatedBy: "__").count - 1
            XCTAssertEqual(delimiterCount, 1, "Should have exactly one delimiter")
        }
    }

    /// Test minimum length guarantees
    func testNamespacedToolName_MinimumLengthGuarantees() {
        // Very long namespace, very short tool - both should get minimum space
        let namespace = String(repeating: "n", count: 80)
        let toolName = "t"
        let result = namespacedToolName(namespace: namespace, toolName: toolName)

        let components = result.components(separatedBy: "__")
        XCTAssertEqual(components.count, 2, "Should have exactly 2 parts")

        // Both parts should get at least 8 chars (or original length if shorter)
        XCTAssertGreaterThanOrEqual(components[0].count, 8, "Namespace should get minimum 8 chars")
        XCTAssertGreaterThanOrEqual(components[1].count, 1, "Tool name should be preserved when very short")
    }

    // MARK: - Sanitize Server Name Tests

    func testSanitizeServerName_BasicAlphanumeric() {
        XCTAssertEqual(sanitizeServerNameToNamespace("myserver"), "myserver")
        XCTAssertEqual(sanitizeServerNameToNamespace("MyServer123"), "myserver123")
    }

    func testSanitizeServerName_WithHyphens() {
        XCTAssertEqual(sanitizeServerNameToNamespace("my-server"), "my_server")
        XCTAssertEqual(sanitizeServerNameToNamespace("server-with-many-hyphens"), "server_with_many_hyphens")
    }

    func testSanitizeServerName_WithUnderscores() {
        XCTAssertEqual(sanitizeServerNameToNamespace("my_server"), "my_server")
        XCTAssertEqual(sanitizeServerNameToNamespace("my__server"), "my_server")
    }

    func testSanitizeServerName_SpecialCharacters() {
        XCTAssertEqual(sanitizeServerNameToNamespace("my@server!"), "my_server")
        XCTAssertEqual(sanitizeServerNameToNamespace("server#123$"), "server_123")
    }

    func testSanitizeServerName_MultipleConsecutiveSpecialChars() {
        XCTAssertEqual(sanitizeServerNameToNamespace("my---server"), "my_server")
        XCTAssertEqual(sanitizeServerNameToNamespace("server___test"), "server_test")
    }

    // MARK: - Edge Case Tests (from PR review feedback)

    func testSanitizeServerName_EmptyString() {
        let result = sanitizeServerNameToNamespace("")
        XCTAssertEqual(result, "", "Empty string should return empty string")
    }

    func testSanitizeServerName_StartsWithDigit() {
        // Critical: Bedrock requires tool names to start with a letter, not a digit
        XCTAssertEqual(sanitizeServerNameToNamespace("123service"), "s_123service")
        XCTAssertEqual(sanitizeServerNameToNamespace("1server"), "s_1server")
        XCTAssertEqual(sanitizeServerNameToNamespace("99_bottles"), "s_99_bottles")
    }

    func testSanitizeServerName_AllDigits() {
        XCTAssertEqual(sanitizeServerNameToNamespace("12345"), "s_12345")
    }

    func testSanitizeServerName_Unicode() {
        // Unicode characters should be replaced with underscores
        XCTAssertEqual(sanitizeServerNameToNamespace("server🚀"), "server_")
        XCTAssertEqual(sanitizeServerNameToNamespace("日本語"), "___")
        XCTAssertEqual(sanitizeServerNameToNamespace("café"), "caf_")
    }

    func testSanitizeServerName_VeryLongName() {
        let longName = String(repeating: "a", count: 200)
        let result = sanitizeServerNameToNamespace(longName)
        XCTAssertEqual(result.count, 200, "Should preserve full length (truncation happens in namespacedToolName)")
        XCTAssertEqual(result, longName, "Should be unchanged since it's all alphanumeric")
    }

    func testSanitizeServerName_NoDoubleUnderscore() {
        // Critical invariant: output must never contain "__" (the delimiter)
        let testCases = [
            "my--server",
            "server___name",
            "test____service",
            "a@@@b",
        ]

        for testCase in testCases {
            let result = sanitizeServerNameToNamespace(testCase)
            XCTAssertFalse(result.contains("__"), "Sanitized namespace '\(result)' must not contain '__' delimiter")
        }
    }

    func testAssignUniqueNamespaces_EmptyServerName() {
        let servers = ["", "server1"]
        let result = assignUniqueNamespaces(serverNames: servers)

        XCTAssertEqual(result[""], "server", "Empty server name should default to 'server'")
        XCTAssertEqual(result["server1"], "server1")
    }

    func testAssignUniqueNamespaces_DigitStartingServers() {
        let servers = ["123service", "456service"]
        let result = assignUniqueNamespaces(serverNames: servers)

        // Both should get s_ prefix and remain unique
        XCTAssertEqual(result["123service"], "s_123service")
        XCTAssertEqual(result["456service"], "s_456service")
        XCTAssertNotEqual(result["123service"], result["456service"])
    }

    func testAssignUniqueNamespaces_DigitStartingCollision() {
        // Edge case: "123server" and "s_123server" both sanitize to "s_123server"
        let servers = ["123server", "s_123server"]
        let result = assignUniqueNamespaces(serverNames: servers)

        let namespaces = Set(result.values)
        XCTAssertEqual(namespaces.count, 2, "Should resolve collision with suffix")
    }

    // MARK: - Unique Namespace Assignment Tests

    func testAssignUniqueNamespaces_NoCollisions() {
        let servers = ["server1", "server2", "server3"]
        let result = assignUniqueNamespaces(serverNames: servers)

        XCTAssertEqual(result["server1"], "server1")
        XCTAssertEqual(result["server2"], "server2")
        XCTAssertEqual(result["server3"], "server3")
    }

    func testAssignUniqueNamespaces_WithCollisions() {
        let servers = ["my-server", "my_server", "my@server"]
        let result = assignUniqueNamespaces(serverNames: servers)

        // All sanitize to "my_server", so should get suffixes
        let namespaces = Set(result.values)
        XCTAssertEqual(namespaces.count, 3, "Should have 3 unique namespaces")
        XCTAssertTrue(namespaces.contains("my_server"))
        XCTAssertTrue(namespaces.contains("my_server_2") || namespaces.contains("my_server_3"))
    }

    func testAssignUniqueNamespaces_Deterministic() {
        let servers = ["server-a", "server_a", "serverA"]
        let result1 = assignUniqueNamespaces(serverNames: servers)
        let result2 = assignUniqueNamespaces(serverNames: servers)

        XCTAssertEqual(result1, result2, "Should produce deterministic results")
    }

    // MARK: - Parse Namespaced Tool Name Tests

    func testParseNamespacedToolName_ValidFormat() {
        let namespaceMap = ["server": "my-server"]
        let result = parseNamespacedToolName("server__tool_name", namespaceToServer: namespaceMap)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.serverName, "my-server")
        XCTAssertEqual(result?.toolName, "tool_name")
    }

    func testParseNamespacedToolName_NoDelimiter() {
        let namespaceMap = ["server": "my-server"]
        let result = parseNamespacedToolName("toolname", namespaceToServer: namespaceMap)

        XCTAssertNil(result, "Should return nil when no delimiter present")
    }

    func testParseNamespacedToolName_UnknownNamespace() {
        let namespaceMap = ["server": "my-server"]
        let result = parseNamespacedToolName("unknown__tool_name", namespaceToServer: namespaceMap)

        XCTAssertNil(result, "Should return nil for unknown namespace")
    }

    func testParseNamespacedToolName_EmptyParts() {
        let namespaceMap = ["server": "my-server"]

        XCTAssertNil(parseNamespacedToolName("__tool", namespaceToServer: namespaceMap))
        XCTAssertNil(parseNamespacedToolName("server__", namespaceToServer: namespaceMap))
    }
}
