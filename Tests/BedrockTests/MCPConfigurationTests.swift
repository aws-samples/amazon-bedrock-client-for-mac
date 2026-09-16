import Foundation
import XCTest
@testable import Amazon_Bedrock_Client_for_Mac

final class MCPConfigurationTests: XCTestCase {
    @MainActor
    func testShareableExportOmitsSecretsWithoutChangingPrivateConfiguration() throws {
        let server = MCPServerConfig(name: "private-server", transportType: .http,
            command: "/usr/bin/python3",
            args: ["server.py", "--port", "3000", "--api-key", "argument-secret", "--password=inline-secret"],
            env: ["API_TOKEN": "environment-secret", "PORT": "3000"],
            url: "https://example.com/mcp?api_key=query-secret&mode=stream",
            headers: ["Authorization": "Bearer header-secret", "Accept": "application/json"],
            clientId: "public-client", clientSecret: "oauth-secret")
        let privateData = try MCPConfiguration.encode([server])
        let data = try MCPConfiguration.exportData([server])
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        for secret in ["argument-secret", "inline-secret", "environment-secret", "query-secret", "header-secret", "oauth-secret"] {
            XCTAssertFalse(text.contains(secret), "Export leaked a configured credential.")
            XCTAssertTrue(String(decoding: privateData, as: UTF8.self).contains(secret))
        }
        let exported = try XCTUnwrap(MCPConfiguration.decode(data).first)
        XCTAssertFalse(exported.enabled)
        XCTAssertEqual(exported.command, "/usr/bin/python3")
        XCTAssertEqual(Array(exported.args.prefix(3)), ["server.py", "--port", "3000"])
        XCTAssertEqual(exported.env, ["API_TOKEN": "", "PORT": ""])
        XCTAssertEqual(exported.headers, ["Authorization": "", "Accept": ""])
        XCTAssertNil(exported.clientSecret)
        XCTAssertEqual(exported.clientId, "public-client")
        XCTAssertEqual(exported.url, "https://example.com/mcp?api_key=&mode=stream")
        XCTAssertEqual(try MCPConfiguration.encode([server]), privateData,
                       "The live config must retain its credentials after export.")
    }

    @MainActor
    func testDiagnosticsAndPreviewRemoveEmbeddedCredentialValues() {
        let server = MCPServerConfig(name: "fixture", transportType: .http,
            args: ["--token", "argument-secret"],
            env: ["ACCESS_TOKEN": "env-secret"],
            url: "https://example.com/mcp?token=url-secret",
            headers: ["Authorization": "Bearer header-secret"], clientSecret: "oauth-secret")
        let text = "Connection refused. env-secret argument-secret header-secret oauth-secret url-secret"
        let result = MCPConfiguration.redactedDiagnostic(text, server: server)
        XCTAssertTrue(result.contains("Connection refused."))
        XCTAssertFalse(result.contains("-secret"))
        XCTAssertEqual(MCPConfiguration.previewAddress(server), "https://example.com/mcp?token=")
    }

    @MainActor
    func testImportOnlyReplacesExplicitlySelectedServersAndDoesNotEnableThem() throws {
        let original = MCPServerConfig(name: "existing", command: "/bin/old", env: ["TOKEN": "kept"], enabled: true)
        let other = MCPServerConfig(name: "unrelated", command: "/bin/other", enabled: true)
        let replacement = MCPServerConfig(name: "existing", command: "/bin/new", enabled: true)
        let added = MCPServerConfig(name: "new", command: "/bin/new", enabled: true)
        let current = [original, other]
        let onlyNew = try MCPConfiguration.merging([replacement, added], selected: ["new"], into: current)
        XCTAssertEqual(onlyNew.count, 3)
        XCTAssertEqual(onlyNew[0].command, original.command)
        XCTAssertEqual(onlyNew[0].env, original.env)
        XCTAssertTrue(onlyNew[0].enabled)
        XCTAssertTrue(onlyNew[1].enabled)
        XCTAssertFalse(onlyNew[2].enabled)
        let replaced = try MCPConfiguration.merging([replacement], selected: ["existing"], into: current)
        XCTAssertEqual(replaced[0].command, "/bin/new")
        XCTAssertFalse(replaced[0].enabled)
        XCTAssertEqual(replaced[1].command, other.command)
        XCTAssertTrue(replaced[1].enabled)
    }

    @MainActor
    func testImportRejectsMalformedHeadersEnvironmentAndDuplicateNamesBeforeMutation() throws {
        let current = [MCPServerConfig(name: "kept", command: "/bin/kept")]
        for headers in [["Bad:Header": "value"], ["X-Test": "a\r\nb"], ["X-Test": "a\0b"]] {
            let invalid = MCPServerConfig(name: "invalid", transportType: .http, url: "https://example.com", headers: headers)
            XCTAssertThrowsError(try MCPConfiguration.merging([invalid], selected: ["invalid"], into: current))
        }
        let invalid = MCPServerConfig(name: "invalid", command: "/bin/test", env: ["KEY": "a\0b"])
        XCTAssertThrowsError(try MCPConfiguration.merging([invalid], selected: ["invalid"], into: current))
        XCTAssertThrowsError(try MCPConfiguration.merging(current + current, selected: ["kept"], into: []))
        XCTAssertEqual(current[0].command, "/bin/kept")
        XCTAssertTrue(current[0].enabled)
    }
}
