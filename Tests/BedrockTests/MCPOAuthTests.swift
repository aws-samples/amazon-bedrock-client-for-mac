import Foundation
import MCP
import XCTest
@testable import Amazon_Bedrock_Client_for_Mac

final class MCPOAuthTests: XCTestCase {
    @MainActor
    func testLoopbackCallbackRejectsWrongStateAndCompletesOnlyForItsOwnRequest() async throws {
        let redirect = OAuthConfiguration(authentication: .none(clientID: "fixture")).authorizationRedirectURI
        var authorization = URLComponents(string: "https://fixture.example/authorize")!
        authorization.queryItems = [.init(name: "redirect_uri", value: redirect.absoluteString),
                                    .init(name: "state", value: "EXPECTED_STATE")]
        let completed = expectation(description: "Valid callback received")
        completed.assertForOverFulfill = true
        var received: URL?
        let listener = try MCPOAuthCallbackListener(authorizationURL: authorization.url!) { result in
            received = try? result.get()
            completed.fulfill()
        }
        defer { listener.cancel() }
        try await listener.start()
        var callback = URLComponents(url: redirect, resolvingAgainstBaseURL: false)!
        callback.queryItems = [.init(name: "code", value: "FIXTURE_CODE"), .init(name: "state", value: "WRONG")]
        let (_, rejected) = try await URLSession.shared.data(from: callback.url!)
        XCTAssertEqual((rejected as? HTTPURLResponse)?.statusCode, 400)
        XCTAssertNil(received)
        callback.queryItems = [.init(name: "code", value: "FIXTURE_CODE"), .init(name: "state", value: "EXPECTED_STATE")]
        let (_, accepted) = try await URLSession.shared.data(from: callback.url!)
        XCTAssertEqual((accepted as? HTTPURLResponse)?.statusCode, 200)
        await fulfillment(of: [completed], timeout: 3)
        XCTAssertEqual(received, callback.url)
    }

    @MainActor
    func testProtectedHTTPConnectionSignsInRetriesAndReusesTokenAfterReconnect() async throws {
        let fixture = OAuthHTTPFixture()
        defer { fixture.close() }
        let browser = OAuthTestBrowser()
        let (manager, oauth, _) = try manager(browser: browser)
        let server = MCPServerConfig(name: "Protected", transportType: .http, url: fixture.endpoint.absoluteString)
        for _ in 0..<2 {
            let client = Client(name: "fixture-client", version: "1")
            let transport = try manager.makeHTTPTransport(for: server, configuration: fixture.configuration)
            _ = try await client.connect(transport: transport)
            let tools = try await client.listTools()
            XCTAssertEqual(tools.tools.map(\.name), ["fixture_echo"])
            await client.disconnect()
        }
        let browserCount = await browser.count
        XCTAssertEqual(browserCount, 1)
        XCTAssertEqual(fixture.requests(path: "/token").count, 1)
        XCTAssertEqual(oauth.token(for: server)?.value, "FIXTURE_ACCESS")
        let form = try XCTUnwrap(fixture.requests(path: "/token").first?.form)
        XCTAssertEqual(form["resource"], fixture.endpoint.absoluteString)
        XCTAssertEqual(form["grant_type"], "authorization_code")
        XCTAssertFalse(try XCTUnwrap(form["code_verifier"]).isEmpty)
        let registration = try XCTUnwrap(fixture.requests(path: "/register").first?.json)
        let redirects = try XCTUnwrap(registration["redirect_uris"] as? [String])
        let redirect = try XCTUnwrap(redirects.first.flatMap(URL.init(string:)))
        XCTAssertEqual(redirect.scheme, "http")
        XCTAssertEqual(redirect.host, "127.0.0.1")
        XCTAssertGreaterThan(try XCTUnwrap(redirect.port), 0)
        let config = try MCPConfiguration.encode([server])
        XCTAssertFalse(String(decoding: config, as: UTF8.self).contains("FIXTURE_ACCESS"))
    }

    @MainActor
    func testExpiredTokenRefreshesBeforeToolRequestsWithoutOpeningBrowser() async throws {
        let fixture = OAuthHTTPFixture()
        defer { fixture.close() }
        let browser = OAuthTestBrowser()
        let (manager, oauth, stores) = try manager(browser: browser)
        let server = MCPServerConfig(name: "Refresh", transportType: .http, url: fixture.endpoint.absoluteString,
                                     clientId: "fixture-client")
        stores.store(MCPOAuthService.storageKey(for: server)).save(.init(value: "EXPIRED",
            tokenType: "Bearer", expiresAt: Date().addingTimeInterval(-60), scopes: ["tools:read"],
            authorizationServer: fixture.origin, refreshToken: "FIXTURE_REFRESH", clientID: "fixture-client"))
        let client = Client(name: "fixture-client", version: "1")
        _ = try await client.connect(transport: manager.makeHTTPTransport(for: server, configuration: fixture.configuration))
        _ = try await client.listTools()
        await client.disconnect()
        let browserCount = await browser.count
        XCTAssertEqual(browserCount, 0)
        XCTAssertEqual(fixture.requests(path: "/token").first?.form["grant_type"], "refresh_token")
        XCTAssertEqual(oauth.token(for: server)?.value, "FIXTURE_ACCESS")
        XCTAssertFalse(fixture.requests(path: "/mcp").contains { $0.authorization == "Bearer EXPIRED" })
    }

    @MainActor
    func testPublicServersAndExplicitAuthorizationHeadersDoNotTriggerOAuth() async throws {
        for requiresAuth in [false, true] {
            let fixture = OAuthHTTPFixture(requiresAuth: requiresAuth, acceptedAuthorization: "Bearer MANUAL")
            defer { fixture.close() }
            let browser = OAuthTestBrowser()
            let (manager, _, _) = try manager(browser: browser)
            let server = MCPServerConfig(name: "Manual", transportType: .http, url: fixture.endpoint.absoluteString,
                                         headers: requiresAuth ? ["authorization": "Bearer MANUAL"] : nil)
            let client = Client(name: "fixture-client", version: "1")
            _ = try await client.connect(transport: manager.makeHTTPTransport(for: server, configuration: fixture.configuration))
            _ = try await client.listTools()
            await client.disconnect()
            let browserCount = await browser.count
            XCTAssertEqual(browserCount, 0)
            XCTAssertTrue(fixture.requests(path: "/token").isEmpty)
        }
    }

    @MainActor
    func testCancelledAndInvalidCallbacksDoNotSaveTokensOrRetryAuthenticatedRequests() async throws {
        for mode in [OAuthTestBrowser.Mode.cancel, .wrongState] {
            let fixture = OAuthHTTPFixture()
            defer { fixture.close() }
            let browser = OAuthTestBrowser(mode: mode)
            let (manager, oauth, _) = try manager(browser: browser)
            let server = MCPServerConfig(name: "Cancelled", transportType: .http, url: fixture.endpoint.absoluteString)
            let transport = try manager.makeHTTPTransport(for: server, configuration: fixture.configuration)
            try await transport.connect()
            do {
                try await transport.send(Data(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#.utf8))
                XCTFail("Invalid authorization must fail")
            } catch { }
            await transport.disconnect()
            XCTAssertNil(oauth.token(for: server))
            XCTAssertTrue(fixture.requests(path: "/token").isEmpty)
        }
    }

    @MainActor
    func testLegacyTokensMigrateOnceAndNeverCrossEndpoints() throws {
        let browser = OAuthTestBrowser()
        let (_, oauth, _) = try manager(browser: browser)
        let server = MCPServerConfig(name: "Saved", transportType: .http, url: "https://saved.oauth.test/mcp")
        // Test migration with the same isolated preference suite used by this service.
        let suite = "bedrock.oauth.migration.\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let stores = OAuthTestStores()
        let migrating = MCPOAuthService(preferences: preferences, storeFactory: { stores.store($0) }, authorizationDelegate: browser)
        let data = try JSONSerialization.data(withJSONObject: ["Saved": [
            "accessToken": "LEGACY_ONLY", "refreshToken": "OLD_REFRESH", "tokenType": "Bearer",
            "expiresAt": Date().addingTimeInterval(3600).timeIntervalSinceReferenceDate, "scope": "tools:read"
        ]])
        preferences.set(data, forKey: "MCPOAuthTokens")
        migrating.migrateLegacyTokens(for: [server])
        XCTAssertNil(preferences.data(forKey: "MCPOAuthTokens"))
        XCTAssertEqual(migrating.token(for: server)?.value, "LEGACY_ONLY")
        var changed = server
        changed.url = "https://another.oauth.test/mcp"
        XCTAssertNil(migrating.token(for: changed), "A saved name must not send a token to a changed endpoint.")
        XCTAssertNil(oauth.token(for: server))
        migrating.clearToken(for: server)
        XCTAssertNil(migrating.token(for: server))
    }

    @MainActor
    private func manager(browser: OAuthTestBrowser) throws -> (MCPClientManager, MCPOAuthService, OAuthTestStores) {
        let suite = "bedrock.oauth.tests.\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let stores = OAuthTestStores()
        let oauth = MCPOAuthService(preferences: preferences, storeFactory: { stores.store($0) }, authorizationDelegate: browser)
        let manager = MCPClientManager(configurationDirectory: root, preferences: preferences, autoStart: false, oauth: oauth)
        addTeardownBlock { @MainActor in
            await manager.shutdown()
            preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        return (manager, oauth, stores)
    }
}

@MainActor
private final class OAuthTestStores {
    var values: [String: OAuthTestTokenStorage] = [:]
    func store(_ key: String) -> OAuthTestTokenStorage {
        if let value = values[key] { return value }
        let value = OAuthTestTokenStorage(); values[key] = value; return value
    }
}
private final class OAuthTestTokenStorage: TokenStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var token: OAuthAccessToken?
    func save(_ token: OAuthAccessToken) { lock.lock(); defer { lock.unlock() }; self.token = token }
    func load() -> OAuthAccessToken? { lock.lock(); defer { lock.unlock() }; return token }
    func clear() { lock.lock(); defer { lock.unlock() }; token = nil }
}
private actor OAuthTestBrowser: OAuthAuthorizationDelegate {
    enum Mode { case normal, cancel, wrongState }
    private let mode: Mode
    private(set) var count = 0
    init(mode: Mode = .normal) { self.mode = mode }
    func presentAuthorizationURL(_ url: URL) async throws -> URL {
        count += 1
        if mode == .cancel { throw CancellationError() }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let state = items.first(where: { $0.name == "state" })?.value,
              items.contains(where: { $0.name == "code_challenge_method" && $0.value == "S256" }) else {
            throw URLError(.badURL)
        }
        let redirect = items.first(where: { $0.name == "redirect_uri" })!.value!
        var callback = URLComponents(string: redirect)!
        callback.queryItems = [.init(name: "code", value: "FIXTURE_CODE"),
                               .init(name: "state", value: mode == .wrongState ? "wrong-state" : state)]
        return callback.url!
    }
}
private final class OAuthHTTPFixture: @unchecked Sendable {
    struct Request {
        let path: String
        let authorization: String?
        let body: Data
        var json: [String: Any]? { try? JSONSerialization.jsonObject(with: body) as? [String: Any] }
        var form: [String: String] {
            var components = URLComponents(); components.percentEncodedQuery = String(decoding: body, as: UTF8.self)
            return Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
        }
    }
    let origin: URL
    var endpoint: URL { origin.appendingPathComponent("mcp") }
    let requiresAuth: Bool
    let acceptedAuthorization: String
    private let lock = NSLock()
    private var recorded: [Request] = []
    var configuration: URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OAuthFixtureURLProtocol.self]
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 10
        return config
    }
    init(requiresAuth: Bool = true, acceptedAuthorization: String = "Bearer FIXTURE_ACCESS") {
        // A public literal passes the SDK's independent DNS/SSRF checks.
        // URLProtocol intercepts every request; no connection to this address is made.
        origin = URL(string: "https://93.184.215.14")!
        self.requiresAuth = requiresAuth; self.acceptedAuthorization = acceptedAuthorization
        OAuthFixtureURLProtocol.register(self)
    }
    func close() { OAuthFixtureURLProtocol.remove(self) }
    func requests(path: String) -> [Request] { lock.lock(); defer { lock.unlock() }; return recorded.filter { $0.path == path } }
    func respond(_ request: URLRequest) -> (Int, [String: String], Data) {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(contentsOf: buffer.prefix(count))
            }
        }
        let record = Request(path: request.url!.path, authorization: request.value(forHTTPHeaderField: "Authorization"), body: body)
        lock.lock(); recorded.append(record); lock.unlock()
        func json(_ value: [String: Any], status: Int = 200, headers: [String: String] = [:]) -> (Int, [String: String], Data) {
            (status, headers.merging(["Content-Type": "application/json"]) { _, new in new }, try! JSONSerialization.data(withJSONObject: value))
        }
        if record.path.hasPrefix("/.well-known/oauth-protected-resource") {
            return json(["resource": endpoint.absoluteString, "authorization_servers": [origin.absoluteString], "scopes_supported": ["tools:read"]])
        }
        if record.path == "/.well-known/oauth-authorization-server" {
            return json(["issuer": origin.absoluteString, "authorization_endpoint": origin.appendingPathComponent("authorize").absoluteString,
                         "token_endpoint": origin.appendingPathComponent("token").absoluteString,
                         "registration_endpoint": origin.appendingPathComponent("register").absoluteString,
                         "code_challenge_methods_supported": ["S256"], "token_endpoint_auth_methods_supported": ["none"]])
        }
        if record.path == "/register" { return json(["client_id": "fixture-client", "token_endpoint_auth_method": "none"]) }
        if record.path == "/token" {
            return json(["access_token": "FIXTURE_ACCESS", "token_type": "Bearer", "refresh_token": "FIXTURE_REFRESH", "expires_in": 3600, "scope": "tools:read"])
        }
        if record.path == "/mcp" {
            if requiresAuth && record.authorization != acceptedAuthorization {
                return json([:], status: 401, headers: ["WWW-Authenticate": "Bearer resource_metadata=\"\(origin.absoluteString)/.well-known/oauth-protected-resource\""])
            }
            if request.httpMethod == "GET" { return json([:], status: 405) }
            guard let payload = record.json, let id = payload["id"] else { return (202, [:], Data()) }
            let result: [String: Any]
            if payload["method"] as? String == "initialize" {
                result = ["protocolVersion": "2025-11-25", "capabilities": ["tools": [:]], "serverInfo": ["name": "fixture", "version": "1"]]
            } else { result = ["tools": [["name": "fixture_echo", "inputSchema": ["type": "object", "properties": [:]]]]] }
            return json(["jsonrpc": "2.0", "id": id, "result": result])
        }
        return json([:], status: 404)
    }
}
private final class OAuthFixtureURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var fixtures: [String: OAuthHTTPFixture] = [:]
    static func register(_ fixture: OAuthHTTPFixture) { lock.lock(); defer { lock.unlock() }; fixtures[fixture.origin.host!] = fixture }
    static func remove(_ fixture: OAuthHTTPFixture) { lock.lock(); defer { lock.unlock() }; fixtures.removeValue(forKey: fixture.origin.host!) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); let fixture = Self.fixtures[request.url?.host ?? ""]; Self.lock.unlock()
        guard let fixture else { client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return }
        let (status, headers, data) = fixture.respond(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
