//
//  SSOManager.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 7/3/24.
//

import Foundation
import AWSSSO
import AWSSSOOIDC
import Logging

class SSOManager: ObservableObject {
    private var ssoOIDC: SSOOIDCClient?
    private var sso: SSOClient?
    private var logger = Logger(label: "SSOManager")
    @Published var isLoggedIn = false
    
    init() {
        setupClients()
    }
    
    private func setupClients() {
        do {
            let region = "us-west-2"
            let ssoOIDCConfiguration = try SSOOIDCClient.SSOOIDCClientConfiguration(region: region)
            let ssoConfiguration = try SSOClient.SSOClientConfiguration(region: region)
            
            ssoOIDC = SSOOIDCClient(config: ssoOIDCConfiguration)
            sso = SSOClient(config: ssoConfiguration)
        } catch {
            logger.error("Error setting up clients: \(error)")
        }
    }
    
    func startSSOLogin(startUrl: String, region: String) async throws -> (authUrl: String, userCode: String) {
        do {
            let registerClientRequest = RegisterClientInput(
                clientName: "Amazon Bedrock",
                clientType: "public",
                scopes: ["sso:account:access"]
            )
            
            let registerClientResponse = try await ssoOIDC!.registerClient(input: registerClientRequest)
            
            let startDeviceAuthRequest = StartDeviceAuthorizationInput(
                clientId: registerClientResponse.clientId,
                clientSecret: registerClientResponse.clientSecret,
                startUrl: startUrl
            )
            
            let startDeviceAuthResponse = try await ssoOIDC!.startDeviceAuthorization(input: startDeviceAuthRequest)
            
            return (startDeviceAuthResponse.verificationUriComplete!, startDeviceAuthResponse.userCode!)
        } catch {
            logger.error("SSO Login Error: \(error.localizedDescription)")
            throw error
        }
    }
    
    func pollForTokens(deviceCode: String) async throws -> CreateTokenOutput {
        let createTokenRequest = CreateTokenInput(
            clientId: "clientId", // 실제 클라이언트 ID로 대체해야 함
            clientSecret: "clientSecret", // 실제 클라이언트 시크릿으로 대체해야 함
            deviceCode: deviceCode,
            grantType: "urn:ietf:params:oauth:grant-type:device_code"
        )
        
        while true {
            do {
                let tokenResponse = try await ssoOIDC!.createToken(input: createTokenRequest)
                return tokenResponse
            } catch let error as AuthorizationPendingException {
                try await Task.sleep(nanoseconds: 5_000_000_000) // 5초 대기
            } catch {
                throw error
            }
        }
    }
    
    func refreshToken(currentRefreshToken: String, clientId: String, clientSecret: String) async throws -> CreateTokenOutput {
        let createTokenRequest = CreateTokenInput(
            clientId: clientId,
            clientSecret: clientSecret,
            grantType: "refresh_token",
            refreshToken: currentRefreshToken
        )
        
        do {
            let tokenResponse = try await ssoOIDC!.createToken(input: createTokenRequest)
            return tokenResponse
        } catch {
            logger.error("Token refresh error: \(error.localizedDescription)")
            throw error
        }
    }
    
    func loadTokenFromCache() -> (refreshToken: String, clientId: String, clientSecret: String)? {
        let fileManager = FileManager.default
        let cachePath = NSString(string: "~/.aws/sso/cache").expandingTildeInPath
        
        do {
            let directoryContents = try fileManager.contentsOfDirectory(atPath: cachePath)
            for fileName in directoryContents {
                if fileName.hasSuffix(".json") {
                    let filePath = (cachePath as NSString).appendingPathComponent(fileName)
                    let fileData = try Data(contentsOf: URL(fileURLWithPath: filePath))
                    if let json = try JSONSerialization.jsonObject(with: fileData, options: []) as? [String: Any],
                       let refreshToken = json["refreshToken"] as? String,
                       let clientId = json["clientId"] as? String,
                       let clientSecret = json["clientSecret"] as? String {
                        return (refreshToken, clientId, clientSecret)
                    }
                }
            }
        } catch {
            logger.error("Error loading token from cache: \(error.localizedDescription)")
        }
        
        return nil
    }
    
    func completeLogin(tokenResponse: CreateTokenOutput) async throws {
        // 로그인 완료 로직 구현
        DispatchQueue.main.async {
            self.isLoggedIn = true
        }
    }
    
    func logout() {
        // 로그아웃 로직 구현
        DispatchQueue.main.async {
            self.isLoggedIn = false
        }
    }
}
