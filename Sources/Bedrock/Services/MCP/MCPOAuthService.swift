import AppKit
import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import MCP
import Security

/// Uses the SDK's OAuth discovery, PKCE, resource binding, refresh and challenge handling.
/// Each transport gets its own authorizer; tokens are scoped to a saved server and endpoint.
@MainActor
final class MCPOAuthService: ObservableObject {
    static let shared = MCPOAuthService()
    @Published private(set) var authenticationInProgress: String?
    @Published private(set) var revision = 0
    @Published private(set) var persistenceError: String?
    private var waiting: Set<String> = []
    private var stores: [String: any TokenStorage] = [:]
    private let preferences: UserDefaults
    private let storeFactory: ((String) -> any TokenStorage)?
    private let authorizationDelegate: (any OAuthAuthorizationDelegate)?
    private var session: ASWebAuthenticationSession?
    private var presentationContext: MCPAuthPresentationContext?
    private var continuation: CheckedContinuation<URL, Error>?
    private var sessionID: UUID?
    private var callbackListener: MCPOAuthCallbackListener?

    init(preferences: UserDefaults = .standard,
         storeFactory: ((String) -> any TokenStorage)? = nil,
         authorizationDelegate: (any OAuthAuthorizationDelegate)? = nil) {
        self.preferences = preferences
        self.storeFactory = storeFactory
        self.authorizationDelegate = authorizationDelegate
    }

    nonisolated static func storageKey(for server: MCPServerConfig) -> String {
        let identity = "\(server.name)|\(server.url ?? "")|\(server.clientId ?? "")"
        return SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func token(for server: MCPServerConfig) -> OAuthAccessToken? { storage(for: server).load() }
    func isAuthenticating(_ name: String) -> Bool { waiting.contains(name) }
    func clearToken(for server: MCPServerConfig) {
        storage(for: server).clear()
        revision &+= 1
    }

    func makeAuthorizer(for server: MCPServerConfig) -> OAuthAuthorizer {
        let storage = storage(for: server)
        let clientID = server.clientId ?? storage.load()?.clientID ?? ""
        let authentication: OAuthConfiguration.TokenEndpointAuthentication
        if let secret = server.clientSecret, !secret.isEmpty {
            authentication = .clientSecretPost(clientID: clientID, clientSecret: secret)
        } else { authentication = .none(clientID: clientID) }
        let configuration = OAuthConfiguration(grantType: .authorizationCode,
            authentication: authentication,
            clientName: "Bedrock for Mac",
            authorizationDelegate: authorizationDelegate ?? MCPBrowserAuthorization(service: self, serverName: server.name))
        return OAuthAuthorizer(configuration: configuration, tokenStorage: storage)
    }

    func authenticate(for server: MCPServerConfig) async throws {
        let url = try LocalPath.validatedWebURL(server.url ?? "", allowedDomains: "")
        let authorizer = makeAuthorizer(for: server)
        _ = try await authorizer.handleChallenge(statusCode: 401, headers: ["WWW-Authenticate": "Bearer"],
                                                  endpoint: url, operationKey: "sign-in", session: .shared)
    }

    /// Bind the previous name-keyed records to the configurations present at upgrade time.
    /// No OAuth token is copied into mcp_config.json or an HTTP header setting.
    func migrateLegacyTokens(for servers: [MCPServerConfig]) {
        guard let data = preferences.data(forKey: "MCPOAuthTokens"),
              let legacy = try? JSONDecoder().decode([String: LegacyToken].self, from: data) else { return }
        var persisted = true
        for server in servers where server.transportType == .http {
            guard let token = legacy[server.name] else { continue }
            let store = storage(for: server)
            if store.load() == nil {
                store.save(OAuthAccessToken(value: token.accessToken, tokenType: token.tokenType,
                    expiresAt: token.expiresAt, scopes: Set((token.scope ?? "").split(separator: " ").map(String.init)),
                    authorizationServer: nil, refreshToken: token.refreshToken, clientID: server.clientId))
            }
            if let keychain = store as? MCPKeychainTokenStorage, keychain.persistenceFailed { persisted = false }
        }
        if persisted { preferences.removeObject(forKey: "MCPOAuthTokens") }
        revision &+= 1
    }

    private func storage(for server: MCPServerConfig) -> any TokenStorage {
        let key = Self.storageKey(for: server)
        if let existing = stores[key] { return existing }
        let store: any TokenStorage = storeFactory?(key) ?? MCPKeychainTokenStorage(account: key,
            changed: { [weak self] error in
                Task { @MainActor in
                    self?.persistenceError = error
                    self?.revision &+= 1
                }
            })
        stores[key] = store
        return store
    }

    fileprivate func present(_ url: URL, serverName: String) async throws -> URL {
        waiting.insert(serverName)
        defer { waiting.remove(serverName) }
        // macOS presents one sign-in sheet at a time. Queued sign-ins remain cancellable.
        while sessionID != nil { try await Task.sleep(for: .milliseconds(100)) }
        try Task.checkCancellation()
        let id = UUID()
        sessionID = id
        authenticationInProgress = serverName
        defer {
            if sessionID == id { finish(id, result: .failure(CancellationError())) }
        }
        return try await withTaskCancellationHandler {
            let callback = try MCPOAuthCallbackListener(authorizationURL: url) { [weak self] result in
                self?.finish(id, result: result)
            }
            callbackListener = callback
            try await callback.start()
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let context = MCPAuthPresentationContext()
                self.presentationContext = context
                let session = ASWebAuthenticationSession(url: url, callbackURLScheme: nil) { [weak self] callback, error in
                    Task { @MainActor in
                        if let error { self?.finish(id, result: .failure(error)) }
                        else if let callback { self?.finish(id, result: .success(callback)) }
                        else { self?.finish(id, result: .failure(LocalOperationError.invalid("Sign-in returned no callback."))) }
                    }
                }
                session.presentationContextProvider = context
                session.prefersEphemeralWebBrowserSession = false
                self.session = session
                if !session.start() {
                    finish(id, result: .failure(LocalOperationError.unavailable("The sign-in window could not open.")))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.sessionID == id else { return }
                self?.session?.cancel()
                self?.finish(id, result: .failure(CancellationError()))
            }
        }
    }

    private func finish(_ id: UUID, result: Result<URL, Error>) {
        guard sessionID == id else { return }
        let pending = continuation
        let browser = session
        let callback = callbackListener
        continuation = nil
        session = nil
        sessionID = nil
        callbackListener = nil
        presentationContext = nil
        authenticationInProgress = nil
        callback?.cancel()
        browser?.cancel()
        pending?.resume(with: result)
    }

    private struct LegacyToken: Codable {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Date
        let tokenType: String
        let scope: String?
    }
}

private struct MCPBrowserAuthorization: OAuthAuthorizationDelegate {
    let service: MCPOAuthService
    let serverName: String
    func presentAuthorizationURL(_ url: URL) async throws -> URL {
        try await service.present(url, serverName: serverName)
    }
}

@MainActor
private final class MCPAuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
    }
}

/// The SDK's synchronous token-store interface can be called from its transport actor.
/// Cache reads are cheap; a lock serializes persistence and explicit sign-out.
final class MCPKeychainTokenStorage: TokenStorage, @unchecked Sendable {
    private let lock = NSLock()
    private let account: String
    private let service: String
    private let changed: @Sendable (String?) -> Void
    private var token: OAuthAccessToken?
    private var failed = false
    var persistenceFailed: Bool { lock.lock(); defer { lock.unlock() }; return failed }

    init(account: String, changed: @escaping @Sendable (String?) -> Void) {
        self.account = account
        self.changed = changed
        self.service = (Bundle.main.bundleIdentifier ?? "amazon-bedrock-client") + ".mcp-oauth"
        var query = self.query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            token = try? JSONDecoder().decode(OAuthAccessToken.self, from: data)
        }
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    func load() -> OAuthAccessToken? { lock.lock(); defer { lock.unlock() }; return token }
    func save(_ token: OAuthAccessToken) {
        lock.lock()
        self.token = token
        let status: OSStatus
        if let data = try? JSONEncoder().encode(token) {
            let attributes = [kSecValueData as String: data]
            let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if update == errSecItemNotFound {
                var entry = query.merging(attributes) { _, new in new }
                entry[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                status = SecItemAdd(entry as CFDictionary, nil)
            } else { status = update }
        } else { status = errSecParam }
        failed = status != errSecSuccess
        lock.unlock()
        changed(status == errSecSuccess ? nil : "The OAuth token could not be saved in Keychain. Sign in again after restarting the app.")
    }
    func clear() {
        lock.lock()
        token = nil
        let status = SecItemDelete(query as CFDictionary)
        failed = status != errSecSuccess && status != errSecItemNotFound
        lock.unlock()
        changed(status == errSecSuccess || status == errSecItemNotFound ? nil : "The OAuth token could not be removed from Keychain.")
    }
}
