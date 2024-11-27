////
////  SSOManager.swift
////  Amazon Bedrock Client for Mac
////
////  Created by Na, Sanghwa on 7/3/24.
////
//
//import Foundation
//import AWSSSOOIDC
//import AWSSSO
//import Logging
//import AWSClientRuntime
//import CryptoKit
//
//// SSOManager is an ObservableObject to manage SSO login state and token handling
//class SSOManager: ObservableObject {
//    static let shared = SSOManager()  // Singleton instance
//
//    private var ssoOIDC: SSOOIDCClient?
//    private var ssoClient: SSOClient?
//    private var logger = Logger(label: "SSOManager")
//    @Published var isLoggedIn = false  // Published property to indicate login state
//    @Published var accessToken: String?  // Published property for the access token
//    private var clientId: String?
//    private var clientSecret: String?
//    private var region: String = "us-east-1"  // Default region
//    private var startUrl: String = ""
//    private var deviceCode: String?
//
//    init() {
//        // Initialization happens during login
//    }
//
//    // Setup the SSOOIDCClient and SSOClient with the specified region
//    private func setupClient() {
//        do {
//            let ssoOIDCConfiguration = try SSOOIDCClient.SSOOIDCClientConfiguration(region: region)
//            ssoOIDC = SSOOIDCClient(config: ssoOIDCConfiguration)
//
//            let ssoConfiguration = try SSOClient.SSOClientConfiguration(region: region)
//            ssoClient = SSOClient(config: ssoConfiguration)
//
//            logger.info("SSOOIDC and SSO clients set up with region: \(region)")
//        } catch {
//            logger.error("Error setting up SSOOIDC or SSO client: \(error)")
//        }
//    }
//
//    // Start the SSO login process and return necessary information for user authentication
//    func startSSOLogin(startUrl: String, region: String) async throws -> (authUrl: String, userCode: String, deviceCode: String, interval: Int) {
//        self.region = region
//        self.startUrl = startUrl
//        setupClient()
//        logger.info("Starting SSO login with startUrl: \(startUrl) and region: \(region)")
//        do {
//            // Register client if clientId and clientSecret are not already set
//            if clientId == nil || clientSecret == nil {
//                let registerClientRequest = RegisterClientInput(
//                    clientName: "AmazonBedrockClient",
//                    clientType: "public",
//                    scopes: ["openid", "sso:account:access"]
//                )
//
//                guard let ssoOIDC = ssoOIDC else {
//                    throw NSError(domain: "SSOManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "SSOOIDC client not initialized"])
//                }
//
//                let registerClientResponse = try await ssoOIDC.registerClient(input: registerClientRequest)
//                clientId = registerClientResponse.clientId
//                clientSecret = registerClientResponse.clientSecret
//                logger.info("Client registered with clientId: \(clientId!)")
//            }
//
//            // Start device authorization flow
//            let startDeviceAuthRequest = StartDeviceAuthorizationInput(
//                clientId: clientId!,
//                clientSecret: clientSecret!,
//                startUrl: startUrl
//            )
//
//            let startDeviceAuthResponse = try await ssoOIDC!.startDeviceAuthorization(input: startDeviceAuthRequest)
//
//            logger.info("Received deviceCode: \(startDeviceAuthResponse.deviceCode ?? "nil")")
//
//            // Store the device code for later use
//            self.deviceCode = startDeviceAuthResponse.deviceCode
//
//            // Return the authorization URL, user code, device code, and polling interval
//            return (
//                authUrl: startDeviceAuthResponse.verificationUriComplete!,
//                userCode: startDeviceAuthResponse.userCode!,
//                deviceCode: startDeviceAuthResponse.deviceCode!,
//                interval: startDeviceAuthResponse.interval ?? 5
//            )
//        } catch let error as InvalidRequestException {
//            logger.error("InvalidRequestException: \(error.message ?? "No message")")
//            throw error
//        } catch {
//            logger.error("SSO Login Error: \(error)")
//            throw error
//        }
//    }
//
//    // Poll for tokens until the user completes authentication
//    func pollForTokens(deviceCode: String, interval: Int) async throws -> CreateTokenOutput {
//        guard let clientId = clientId, let clientSecret = clientSecret else {
//            throw NSError(domain: "SSOManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Client ID or Secret is missing"])
//        }
//
//        logger.info("Using deviceCode: \(deviceCode)")
//
//        let createTokenRequest = CreateTokenInput(
//            clientId: clientId,
//            clientSecret: clientSecret,
//            deviceCode: deviceCode,
//            grantType: "urn:ietf:params:oauth:grant-type:device_code"
//        )
//
//        guard let ssoOIDC = ssoOIDC else {
//            throw NSError(domain: "SSOManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "SSOOIDC client not initialized"])
//        }
//
//        while true {
//            do {
//                // Attempt to create token
//                let tokenResponse = try await ssoOIDC.createToken(input: createTokenRequest)
//                return tokenResponse
//            } catch let error as AuthorizationPendingException {
//                // Authorization is pending; wait for the specified interval and retry
//                logger.info("Authorization pending. Waiting for user to complete authentication.")
//                try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
//            } catch let error as SlowDownException {
//                // Server asks to slow down polling; increase the interval
//                let newInterval = interval + 5
//                logger.info("Slow down requested. Increasing interval to \(newInterval) seconds.")
//                try await Task.sleep(nanoseconds: UInt64(newInterval) * 1_000_000_000)
//            } catch let error as ExpiredTokenException {
//                // Device code has expired
//                logger.error("Device code expired. Please restart the login process.")
//                throw error
//            } catch let error as InvalidGrantException {
//                // Invalid grant; the device code may have expired or is invalid
//                logger.error("Invalid grant. The device code may have expired or is invalid.")
//                throw error
//            } catch {
//                // Other errors
//                logger.error("Token polling error: \(error)")
//                throw error
//            }
//        }
//    }
//
//    // Complete the login process and store the token information
//    func completeLogin(tokenResponse: CreateTokenOutput) {
//        DispatchQueue.main.async {
//            self.accessToken = tokenResponse.accessToken
//            self.isLoggedIn = true
//            SettingManager.shared.isSSOLoggedIn = true
//
//            // Calculate the expiration time based on expiresIn
//            let expiresIn = tokenResponse.expiresIn ?? 0
//            let expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
//
//            // Create SSOTokenInfo with the token details
//            var ssoTokenInfo = SSOTokenInfo(
//                accessToken: tokenResponse.accessToken,
//                expiresIn: Int(expiresIn),
//                refreshToken: tokenResponse.refreshToken,
//                tokenType: tokenResponse.tokenType,
//                startUrl: self.startUrl,
//                region: self.region,
//                expiresAt: expiresAt,
//                clientId: self.clientId,
//                clientSecret: self.clientSecret,
//                registrationExpiresAt: Date().addingTimeInterval(3600),
//                accountId: nil,  // Will be set after account selection
//                roleName: nil    // Will be set after role selection
//            )
//
//            // Store the token information in SettingManager
//            SettingManager.shared.ssoTokenInfo = ssoTokenInfo
//
//            // Save the token to AWS SSO cache
//            do {
//                try self.saveTokenToCache(ssoTokenInfo: ssoTokenInfo)
//                self.logger.info("SSO token saved to cache")
//            } catch {
//                self.logger.error("Failed to save SSO token to cache: \(error)")
//            }
//        }
//    }
//
//    // Function to set accountId and roleName after user selection
//    func setAccountIdAndRoleName(accountId: String, roleName: String) {
//        DispatchQueue.main.async {
//            guard var ssoTokenInfo = SettingManager.shared.ssoTokenInfo else { return }
//            ssoTokenInfo.accountId = accountId
//            ssoTokenInfo.roleName = roleName
//            SettingManager.shared.ssoTokenInfo = ssoTokenInfo
//        }
//    }
//
//    // Save the token to the AWS SSO cache directory
//    private func saveTokenToCache(ssoTokenInfo: SSOTokenInfo) throws {
//        // Compute the SHA1 hash of the start URL to create the token file name
//        guard let startUrl = ssoTokenInfo.startUrl else {
//            throw NSError(domain: "SSOManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Start URL is missing"])
//        }
//        let hashData = startUrl.data(using: .utf8)!
//        let hash = hashData.computeSHA1().encodeToHexString()
//        let tokenFileName = "\(hash).json"
//
//        // Construct the file URL in the user's home directory
//        let homeDir = FileManager.default.homeDirectoryForCurrentUser
//        let tokenFileURL = homeDir.appendingPathComponent(".aws/sso/cache/\(tokenFileName)")
//
//        // Create the token file contents
//        let tokenFile = TokenFile(
//            startUrl: ssoTokenInfo.startUrl ?? "",
//            region: ssoTokenInfo.region ?? "",
//            accessToken: ssoTokenInfo.accessToken ?? "",
//            expiresAt: ssoTokenInfo.expiresAt?.iso8601String ?? "",
//            clientId: ssoTokenInfo.clientId ?? "",
//            clientSecret: ssoTokenInfo.clientSecret ?? "",
//            registrationExpiresAt: ssoTokenInfo.registrationExpiresAt?.iso8601String ?? "",
//            refreshToken: ssoTokenInfo.refreshToken ?? ""
//        )
//
//        // Encode the token file to JSON
//        let encoder = JSONEncoder()
//        encoder.dateEncodingStrategy = .iso8601
//        let data = try encoder.encode(tokenFile)
//
//        // Ensure the directory exists
//        let directoryURL = tokenFileURL.deletingLastPathComponent()
//        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
//
//        // Write the data to the file
//        try data.write(to: tokenFileURL, options: .atomic)
//    }
//
//    // Logout and clear stored credentials
//    func logout() {
//        DispatchQueue.main.async {
//            self.isLoggedIn = false
//            self.accessToken = nil
//            self.clientId = nil
//            self.clientSecret = nil
//            SettingManager.shared.isSSOLoggedIn = false
//            SettingManager.shared.ssoTokenInfo = nil
//        }
//    }
//
//    // Refresh the token if it's expired
//    func refreshTokenIfNeeded() async throws {
//        guard var ssoTokenInfo = SettingManager.shared.ssoTokenInfo else {
//            throw NSError(domain: "SSOManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "SSO token info is missing."])
//        }
//
//        // Check if the token is expired
//        if let expiresAt = ssoTokenInfo.expiresAt, expiresAt <= Date() {
//            // Token is expired; refresh it
//            let tokenRequest = CreateTokenInput(
//                clientId: ssoTokenInfo.clientId!,
//                clientSecret: ssoTokenInfo.clientSecret!,
//                grantType: "refresh_token",
//                refreshToken: ssoTokenInfo.refreshToken!
//            )
//
//            guard let ssoOIDC = ssoOIDC else {
//                throw NSError(domain: "SSOManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "SSOOIDC client not initialized"])
//            }
//
//            let tokenResponse = try await ssoOIDC.createToken(input: tokenRequest)
//
//            // Update the token information
//            let expiresIn = tokenResponse.expiresIn ?? 0
//            let expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
//            ssoTokenInfo.accessToken = tokenResponse.accessToken
//            ssoTokenInfo.expiresIn = Int(expiresIn)
//            ssoTokenInfo.expiresAt = expiresAt
//            ssoTokenInfo.refreshToken = tokenResponse.refreshToken
//
//            // Save the updated token info
//            SettingManager.shared.ssoTokenInfo = ssoTokenInfo
//
//            // Save the token to AWS SSO cache
//            do {
//                try self.saveTokenToCache(ssoTokenInfo: ssoTokenInfo)
//                self.logger.info("SSO token refreshed and saved to cache")
//            } catch {
//                self.logger.error("Failed to save refreshed SSO token to cache: \(error)")
//            }
//        }
//    }
//
//    // List available accounts and roles
//    func listAccountsAndRoles() async throws -> [(accountId: String, roleName: String)] {
//        guard let accessToken = accessToken else {
//            throw NSError(domain: "SSOManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Access token is missing"])
//        }
//        guard let ssoClient = ssoClient else {
//            throw NSError(domain: "SSOManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "SSO client not initialized"])
//        }
//
//        var accounts: [AccountInfo] = []
//        var nextToken: String? = nil
//
//        repeat {
//            let listAccountsInput = ListAccountsInput(
//                accessToken: accessToken,
//                nextToken: nextToken
//            )
//            let response = try await ssoClient.listAccounts(input: listAccountsInput)
//            if let accountList = response.accountList {
//                accounts.append(contentsOf: accountList)
//            }
//            nextToken = response.nextToken
//        } while nextToken != nil
//
//        var accountRoles: [(accountId: String, roleName: String)] = []
//        for account in accounts {
//            var roles: [RoleInfo] = []
//            var roleNextToken: String? = nil
//
//            repeat {
//                let listRolesInput = ListAccountRolesInput(
//                    accessToken: accessToken,
//                    accountId: account.accountId!,
//                    nextToken: roleNextToken
//                )
//                let roleResponse = try await ssoClient.listAccountRoles(input: listRolesInput)
//                if let roleList = roleResponse.roleList {
//                    roles.append(contentsOf: roleList)
//                }
//                roleNextToken = roleResponse.nextToken
//            } while roleNextToken != nil
//
//            for role in roles {
//                accountRoles.append((accountId: account.accountId!, roleName: role.roleName!))
//            }
//        }
//
//        return accountRoles
//    }
//}
//
//// Extension to compute SHA1 hash and encode to hex string
//extension Data {
//    func computeSHA1() -> Data {
//        let digest = Insecure.SHA1.hash(data: self)
//        return Data(digest)
//    }
//
//    func encodeToHexString() -> String {
//        map { String(format: "%02hhx", $0) }.joined()
//    }
//}
//
//// Extension to format Date to ISO8601 string
//extension Date {
//    var iso8601String: String {
//        let formatter = ISO8601DateFormatter()
//        return formatter.string(from: self)
//    }
//}
//
//// Struct to represent the token file format for AWS SSO cache
//private struct TokenFile: Codable {
//    var startUrl: String
//    var region: String
//    var accessToken: String
//    var expiresAt: String
//    var clientId: String
//    var clientSecret: String
//    var registrationExpiresAt: String
//    var refreshToken: String
//}
//
//// SSOTokenInfo struct with added accountId and roleName
//struct SSOTokenInfo: Codable {
//    var accessToken: String?
//    var expiresIn: Int?
//    var refreshToken: String?
//    var tokenType: String?
//    var startUrl: String?
//    var region: String?
//    var expiresAt: Date?
//    var clientId: String?
//    var clientSecret: String?
//    var registrationExpiresAt: Date?
//    var accountId: String?    // Added accountId
//    var roleName: String?     // Added roleName
//}
