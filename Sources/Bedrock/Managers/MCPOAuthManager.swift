//
//  MCPOAuthManager.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 12/1/25.
//

import Foundation
import AuthenticationServices
import Logging
import Combine
import CommonCrypto

/**
 * Manages OAuth 2.0 authentication for MCP servers.
 * Handles the OAuth flow including:
 * - Fetching OAuth metadata from servers
 * - Opening browser for user authentication
 * - Handling callback with authorization code
 * - Exchanging code for access token
 * - Token storage and refresh
 */
@MainActor
class MCPOAuthManager: NSObject, ObservableObject {
    static let shared = MCPOAuthManager()
    private var logger = Logger(label: "MCPOAuthManager")
    
    // Published properties
    @Published private(set) var authenticationInProgress: String? = nil
    @Published private(set) var tokenStorage: [String: OAuthTokenInfo] = [:]
    
    // Callback URL scheme for OAuth redirect
    private let callbackScheme = "bedrock"
    private let callbackHost = "oauth-callback"
    
    // Active authentication session
    private var authSession: ASWebAuthenticationSession?
    private var presentationContextProvider: AuthPresentationContextProvider?
    
    private override init() {
        super.init()
        loadTokens()
    }
    
    // MARK: - Public Methods
    
    /**
     * Initiates OAuth authentication for an MCP server.
     *
     * @param serverConfig The MCP server configuration
     * @return Updated server config with OAuth token in headers
     */
    func authenticate(for serverConfig: MCPServerConfig) async throws -> MCPServerConfig {
        guard let urlString = serverConfig.url,
              let serverURL = URL(string: urlString) else {
            throw OAuthError.invalidServerURL
        }
        
        authenticationInProgress = serverConfig.name
        defer { authenticationInProgress = nil }
        
        // Check if we have a valid token
        if let tokenInfo = tokenStorage[serverConfig.name],
           !tokenInfo.isExpired {
            logger.info("Using existing valid token for \(serverConfig.name)")
            return serverConfig.withAuthHeader(token: tokenInfo.accessToken)
        }
        
        // Check if we can refresh the token
        if let tokenInfo = tokenStorage[serverConfig.name],
           let refreshToken = tokenInfo.refreshToken {
            do {
                let newToken = try await refreshAccessToken(
                    serverURL: serverURL,
                    refreshToken: refreshToken,
                    serverName: serverConfig.name
                )
                return serverConfig.withAuthHeader(token: newToken.accessToken)
            } catch {
                logger.warning("Token refresh failed, starting new auth flow: \(error)")
            }
        }
        
        // Start new OAuth flow
        let metadata = try await fetchOAuthMetadata(serverURL: serverURL)
        let tokenInfo = try await performOAuthFlow(serverURL: serverURL, metadata: metadata, serverConfig: serverConfig)
        
        // Store token
        tokenStorage[serverConfig.name] = tokenInfo
        saveTokens()
        
        return serverConfig.withAuthHeader(token: tokenInfo.accessToken)
    }
    
    /**
     * Checks if a server requires OAuth authentication.
     */
    func requiresAuthentication(for serverConfig: MCPServerConfig) async -> Bool {
        guard let urlString = serverConfig.url,
              let serverURL = URL(string: urlString) else {
            return false
        }
        
        // Check if we already have a valid token
        if let tokenInfo = tokenStorage[serverConfig.name], !tokenInfo.isExpired {
            return false
        }
        
        // Try to fetch OAuth metadata
        do {
            _ = try await fetchOAuthMetadata(serverURL: serverURL)
            return true
        } catch {
            return false
        }
    }
    
    /**
     * Clears stored token for a server.
     */
    func clearToken(for serverName: String) {
        tokenStorage.removeValue(forKey: serverName)
        saveTokens()
    }
    
    /**
     * Gets the authorization header value for a server if available.
     */
    func getAuthHeader(for serverName: String) -> String? {
        guard let tokenInfo = tokenStorage[serverName], !tokenInfo.isExpired else {
            return nil
        }
        return "Bearer \(tokenInfo.accessToken)"
    }
    
    // MARK: - OAuth Flow
    
    /**
     * Fetches OAuth metadata from the server's well-known endpoint.
     * Supports multiple URL patterns for different OAuth implementations:
     * - Pattern A: /.well-known/oauth-protected-resource → authorization_servers → /.well-known/oauth-authorization-server
     * - Pattern B: /.well-known/oauth-authorization-server directly (Linear style)
     */
    private func fetchOAuthMetadata(serverURL: URL) async throws -> OAuthMetadata {
        // Extract service name from URL path (e.g., "googlecalendar" from "/googlecalendar/mcp")
        let pathComponents = serverURL.pathComponents.filter { $0 != "/" }
        let serviceName = pathComponents.first ?? ""
        
        // Try Pattern A: oauth-protected-resource first
        let protectedResourceURLs = buildProtectedResourceURLs(for: serverURL, serviceName: serviceName)
        
        for metadataURL in protectedResourceURLs {
            logger.info("Trying OAuth protected resource URL: \(metadataURL)")
            
            var request = URLRequest(url: metadataURL)
            request.httpMethod = "GET"
            request.timeoutInterval = 10
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    continue
                }
                
                let resourceMetadata = try JSONDecoder().decode(OAuthProtectedResourceMetadata.self, from: data)
                logger.info("Found OAuth resource metadata: \(resourceMetadata)")
                
                // Fetch authorization server metadata
                if let authServerURL = resourceMetadata.authorizationServers?.first,
                   let authURL = URL(string: authServerURL) {
                    return try await fetchAuthServerMetadata(authServerURL: authURL, serviceName: serviceName)
                }
            } catch {
                logger.debug("Failed to fetch from \(metadataURL): \(error)")
                continue
            }
        }
        
        // Try Pattern B: oauth-authorization-server directly (Linear style)
        let authServerURLs = buildAuthServerURLs(for: serverURL, serviceName: serviceName)
        
        for authURL in authServerURLs {
            logger.info("Trying direct OAuth authorization server URL: \(authURL)")
            
            do {
                let metadata = try await fetchAuthServerMetadata(authServerURL: authURL, serviceName: serviceName)
                // Verify we got valid endpoints
                if metadata.authorizationEndpoint != nil && metadata.tokenEndpoint != nil {
                    return metadata
                }
            } catch {
                logger.debug("Failed to fetch auth server metadata from \(authURL): \(error)")
                continue
            }
        }
        
        throw OAuthError.metadataNotFound
    }
    
    /**
     * Builds list of oauth-protected-resource URLs to try.
     */
    private func buildProtectedResourceURLs(for serverURL: URL, serviceName: String) -> [URL] {
        var urls: [URL] = []
        
        // Pattern 1: Root level without service name (Box style)
        if let rootURL = URL(string: "\(serverURL.scheme!)://\(serverURL.host!)/.well-known/oauth-protected-resource") {
            urls.append(rootURL)
        }
        
        // Pattern 2: With service name in path
        if !serviceName.isEmpty {
            if let serviceURL = URL(string: "\(serverURL.scheme!)://\(serverURL.host!)/.well-known/oauth-protected-resource/\(serviceName)") {
                urls.append(serviceURL)
            }
        }
        
        // Pattern 3: Path-based
        urls.append(serverURL.deletingLastPathComponent()
            .appendingPathComponent(".well-known/oauth-protected-resource"))
        
        return urls
    }
    
    /**
     * Builds list of oauth-authorization-server URLs to try directly.
     */
    private func buildAuthServerURLs(for serverURL: URL, serviceName: String) -> [URL] {
        var urls: [URL] = []
        
        // Pattern 1: Root level (Linear style: https://mcp.linear.app/.well-known/oauth-authorization-server)
        if let rootURL = URL(string: "\(serverURL.scheme!)://\(serverURL.host!)") {
            urls.append(rootURL)
        }
        
        // Pattern 2: With service path
        if !serviceName.isEmpty {
            if let serviceURL = URL(string: "\(serverURL.scheme!)://\(serverURL.host!)/\(serviceName)") {
                urls.append(serviceURL)
            }
        }
        
        return urls
    }
    
    /**
     * Fetches authorization server metadata.
     * Falls back to constructing endpoints from the auth server URL if standard metadata is not available.
     */
    private func fetchAuthServerMetadata(authServerURL: URL, serviceName: String = "") async throws -> OAuthMetadata {
        // Try standard .well-known endpoint first
        let metadataURL = authServerURL.appendingPathComponent(".well-known/oauth-authorization-server")
        
        logger.info("Trying auth server metadata URL: \(metadataURL)")
        
        var request = URLRequest(url: metadataURL)
        request.httpMethod = "GET"
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                return try JSONDecoder().decode(OAuthMetadata.self, from: data)
            }
        } catch {
            logger.debug("Standard metadata not available: \(error)")
        }
        
        // Fallback: construct OAuth endpoints from auth server URL
        // This handles servers that don't expose standard metadata
        logger.info("Using fallback OAuth endpoint construction for: \(authServerURL)")
        
        let baseURL = authServerURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        return OAuthMetadata(
            issuer: baseURL,
            authorizationEndpoint: "\(baseURL)/oauth/authorize",
            tokenEndpoint: "\(baseURL)/oauth/token",
            registrationEndpoint: nil,
            scopesSupported: nil,
            responseTypesSupported: ["code"],
            codeChallengeMethodsSupported: ["S256"]
        )
    }
    
    /**
     * Performs the OAuth authorization flow.
     */
    private func performOAuthFlow(serverURL: URL, metadata: OAuthMetadata, serverConfig: MCPServerConfig) async throws -> OAuthTokenInfo {
        guard let authEndpoint = metadata.authorizationEndpoint,
              let tokenEndpoint = metadata.tokenEndpoint,
              let authURL = URL(string: authEndpoint),
              let tokenURL = URL(string: tokenEndpoint) else {
            throw OAuthError.invalidMetadata
        }
        
        let callbackURL = "\(callbackScheme)://\(callbackHost)"
        
        // Use pre-configured credentials if available (e.g., Box requires pre-registered clients)
        var clientId = serverConfig.clientId ?? "bedrock-client"
        var clientSecret = serverConfig.clientSecret
        
        // If no pre-configured credentials, try Dynamic Client Registration
        if serverConfig.clientId == nil {
            if let registrationEndpoint = metadata.registrationEndpoint,
               let registrationURL = URL(string: registrationEndpoint) {
                logger.info("Attempting Dynamic Client Registration at: \(registrationEndpoint)")
                do {
                    let registration = try await registerClient(
                        registrationURL: registrationURL,
                        redirectURI: callbackURL,
                        serverName: serverConfig.name
                    )
                    clientId = registration.clientId
                    clientSecret = registration.clientSecret
                    logger.info("Successfully registered client: \(clientId)")
                } catch {
                    logger.warning("Dynamic Client Registration failed, using default client_id: \(error)")
                }
            }
        } else {
            logger.info("Using pre-configured OAuth credentials for \(serverConfig.name)")
        }
        
        // Generate PKCE parameters
        let codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier)
        let state = UUID().uuidString
        
        // Build authorization URL
        var authComponents = URLComponents(url: authURL, resolvingAgainstBaseURL: true)!
        authComponents.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: callbackURL),
            URLQueryItem(name: "scope", value: metadata.scopesSupported?.joined(separator: " ") ?? ""),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        
        guard let finalAuthURL = authComponents.url else {
            throw OAuthError.invalidAuthURL
        }
        
        logger.info("Starting OAuth flow with URL: \(finalAuthURL)")
        
        // Perform authentication in browser
        let callbackURLResult = try await performBrowserAuth(url: finalAuthURL)
        
        // Extract authorization code from callback
        guard let components = URLComponents(url: callbackURLResult, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let returnedState = components.queryItems?.first(where: { $0.name == "state" })?.value,
              returnedState == state else {
            throw OAuthError.invalidCallback
        }
        
        // Exchange code for token
        return try await exchangeCodeForToken(
            tokenURL: tokenURL,
            code: code,
            codeVerifier: codeVerifier,
            redirectURI: callbackURL,
            clientId: clientId,
            clientSecret: clientSecret,
            serverName: serverConfig.name
        )
    }
    
    /**
     * Registers a new OAuth client dynamically (RFC 7591).
     */
    private func registerClient(
        registrationURL: URL,
        redirectURI: String,
        serverName: String
    ) async throws -> ClientRegistration {
        var request = URLRequest(url: registrationURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let registrationRequest: [String: Any] = [
            "client_name": "Amazon Bedrock Client for Mac",
            "redirect_uris": [redirectURI],
            "grant_types": ["authorization_code", "refresh_token"],
            "response_types": ["code"],
            "token_endpoint_auth_method": "none"
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: registrationRequest)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            logger.error("Client registration failed with status: \(httpResponse.statusCode)")
            if let responseStr = String(data: data, encoding: .utf8) {
                logger.error("Response: \(responseStr)")
            }
            throw OAuthError.clientRegistrationFailed
        }
        
        let registrationResponse = try JSONDecoder().decode(ClientRegistrationResponse.self, from: data)
        
        return ClientRegistration(
            clientId: registrationResponse.clientId,
            clientSecret: registrationResponse.clientSecret
        )
    }
    
    /**
     * Opens browser for OAuth authentication using ASWebAuthenticationSession.
     * Uses pure callback-based approach following the YJLoginSDK pattern.
     */
    private func performBrowserAuth(url: URL) async throws -> URL {
        let scheme = callbackScheme
        
        logger.info("Starting browser auth with callback scheme: \(scheme)")
        
        // Use nillable completion to prevent double-callback (Auth0/YJLoginSDK pattern)
        var nillableCompletion: ((Result<URL, Error>) -> Void)?
        
        let contextProvider = AuthPresentationContextProvider()
        self.presentationContextProvider = contextProvider
        
        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: scheme
        ) { callbackURL, error in
            // Only process the first callback
            guard let comp = nillableCompletion else { return }
            nillableCompletion = nil
            
            // Handle error cases
            if let error = error {
                if let authError = error as? ASWebAuthenticationSessionError,
                   authError.code == .canceledLogin {
                    comp(.failure(OAuthError.userCancelled))
                } else {
                    comp(.failure(OAuthError.authenticationFailed(error.localizedDescription)))
                }
                return
            }
            
            // Handle success case
            guard let callbackURL = callbackURL else {
                comp(.failure(OAuthError.invalidCallback))
                return
            }
            
            comp(.success(callbackURL))
        }
        
        session.presentationContextProvider = contextProvider
        session.prefersEphemeralWebBrowserSession = false
        self.authSession = session
        
        // Use withCheckedThrowingContinuation but set up completion BEFORE starting
        return try await withCheckedThrowingContinuation { continuation in
            // Set completion handler that will resume the continuation
            nillableCompletion = { result in
                // Clean up on main thread
                Task { @MainActor [weak self] in
                    self?.authSession = nil
                    self?.presentationContextProvider = nil
                }
                
                switch result {
                case .success(let url):
                    continuation.resume(returning: url)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            
            // Now start the session
            let started = session.start()
            
            if !started {
                if let comp = nillableCompletion {
                    nillableCompletion = nil
                    comp(.failure(OAuthError.sessionStartFailed))
                }
            }
        }
    }
    
    /**
     * Exchanges authorization code for access token.
     */
    private func exchangeCodeForToken(
        tokenURL: URL,
        code: String,
        codeVerifier: String,
        redirectURI: String,
        clientId: String,
        clientSecret: String?,
        serverName: String
    ) async throws -> OAuthTokenInfo {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        var bodyParams = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientId,
            "code_verifier": codeVerifier
        ]
        
        // Add client_secret if available
        if let secret = clientSecret {
            bodyParams["client_secret"] = secret
        }
        
        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data) {
                throw OAuthError.tokenExchangeFailed(errorResponse.errorDescription ?? errorResponse.error)
            }
            throw OAuthError.tokenExchangeFailed("HTTP \(httpResponse.statusCode)")
        }
        
        let tokenResponse = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
        
        return OAuthTokenInfo(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn ?? 3600)),
            tokenType: tokenResponse.tokenType ?? "Bearer",
            scope: tokenResponse.scope
        )
    }
    
    /**
     * Refreshes an expired access token.
     */
    private func refreshAccessToken(
        serverURL: URL,
        refreshToken: String,
        serverName: String
    ) async throws -> OAuthTokenInfo {
        let metadata = try await fetchOAuthMetadata(serverURL: serverURL)
        
        guard let tokenEndpoint = metadata.tokenEndpoint,
              let tokenURL = URL(string: tokenEndpoint) else {
            throw OAuthError.invalidMetadata
        }
        
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyParams = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": "bedrock-client"
        ]
        
        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OAuthError.tokenRefreshFailed
        }
        
        let tokenResponse = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
        
        let newTokenInfo = OAuthTokenInfo(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken ?? refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn ?? 3600)),
            tokenType: tokenResponse.tokenType ?? "Bearer",
            scope: tokenResponse.scope
        )
        
        tokenStorage[serverName] = newTokenInfo
        saveTokens()
        
        return newTokenInfo
    }
    
    // MARK: - PKCE Helpers
    
    private func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    private func generateCodeChallenge(from verifier: String) -> String {
        guard let data = verifier.data(using: .utf8) else { return "" }
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    // MARK: - Token Persistence
    
    private func loadTokens() {
        guard let data = UserDefaults.standard.data(forKey: "MCPOAuthTokens"),
              let tokens = try? JSONDecoder().decode([String: OAuthTokenInfo].self, from: data) else {
            return
        }
        tokenStorage = tokens
    }
    
    private func saveTokens() {
        guard let data = try? JSONEncoder().encode(tokenStorage) else { return }
        UserDefaults.standard.set(data, forKey: "MCPOAuthTokens")
    }
}

// MARK: - Presentation Context Provider

private class AuthPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Try keyWindow first, then mainWindow, then first visible window, finally create new window
        if let keyWindow = NSApplication.shared.keyWindow {
            return keyWindow
        }
        if let mainWindow = NSApplication.shared.mainWindow {
            return mainWindow
        }
        if let firstWindow = NSApplication.shared.windows.first(where: { $0.isVisible }) {
            return firstWindow
        }
        if let anyWindow = NSApplication.shared.windows.first {
            return anyWindow
        }
        // Last resort: create a new window (should rarely happen)
        return NSWindow()
    }
}

// MARK: - OAuth Models

struct OAuthProtectedResourceMetadata: Codable {
    let resource: String?
    let authorizationServers: [String]?
    let scopesSupported: [String]?
    
    enum CodingKeys: String, CodingKey {
        case resource
        case authorizationServers = "authorization_servers"
        case scopesSupported = "scopes_supported"
    }
}

struct OAuthMetadata: Codable {
    let issuer: String?
    let authorizationEndpoint: String?
    let tokenEndpoint: String?
    let registrationEndpoint: String?
    let scopesSupported: [String]?
    let responseTypesSupported: [String]?
    let codeChallengeMethodsSupported: [String]?
    
    enum CodingKeys: String, CodingKey {
        case issuer
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case registrationEndpoint = "registration_endpoint"
        case scopesSupported = "scopes_supported"
        case responseTypesSupported = "response_types_supported"
        case codeChallengeMethodsSupported = "code_challenge_methods_supported"
    }
}

// MARK: - Dynamic Client Registration Models

struct ClientRegistration {
    let clientId: String
    let clientSecret: String?
}

struct ClientRegistrationResponse: Codable {
    let clientId: String
    let clientSecret: String?
    let clientIdIssuedAt: Int?
    let clientSecretExpiresAt: Int?
    
    enum CodingKeys: String, CodingKey {
        case clientId = "client_id"
        case clientSecret = "client_secret"
        case clientIdIssuedAt = "client_id_issued_at"
        case clientSecretExpiresAt = "client_secret_expires_at"
    }
}

struct OAuthTokenResponse: Codable {
    let accessToken: String
    let tokenType: String?
    let expiresIn: Int?
    let refreshToken: String?
    let scope: String?
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
}

struct OAuthErrorResponse: Codable {
    let error: String
    let errorDescription: String?
    
    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

struct OAuthTokenInfo: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date
    let tokenType: String
    let scope: String?
    
    var isExpired: Bool {
        return Date() >= expiresAt.addingTimeInterval(-60) // 1 minute buffer
    }
}

enum OAuthError: LocalizedError {
    case invalidServerURL
    case invalidResponse
    case metadataNotFound
    case invalidMetadata
    case invalidAuthURL
    case invalidCallback
    case userCancelled
    case sessionStartFailed
    case authenticationFailed(String)
    case tokenExchangeFailed(String)
    case tokenRefreshFailed
    case clientRegistrationFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "Invalid server URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .metadataNotFound:
            return "OAuth metadata not found"
        case .invalidMetadata:
            return "Invalid OAuth metadata"
        case .clientRegistrationFailed:
            return "Failed to register OAuth client"
        case .invalidAuthURL:
            return "Invalid authorization URL"
        case .invalidCallback:
            return "Invalid callback from authentication"
        case .userCancelled:
            return "Authentication cancelled by user"
        case .sessionStartFailed:
            return "Failed to start authentication session"
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        case .tokenExchangeFailed(let message):
            return "Token exchange failed: \(message)"
        case .tokenRefreshFailed:
            return "Failed to refresh token"
        }
    }
}

// MARK: - MCPServerConfig Extension

extension MCPServerConfig {
    func withAuthHeader(token: String) -> MCPServerConfig {
        var config = self
        var newHeaders = config.headers ?? [:]
        newHeaders["Authorization"] = "Bearer \(token)"
        config.headers = newHeaders
        return config
    }
}
