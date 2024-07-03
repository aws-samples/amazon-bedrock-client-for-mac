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
            let region = "us-west-2" // 원하는 리전으로 설정
            let ssoOIDCConfiguration = try SSOOIDCClient.SSOOIDCClientConfiguration(region: region)
            let ssoConfiguration = try SSOClient.SSOClientConfiguration(region: region)
            
            ssoOIDC = try SSOOIDCClient(config: ssoOIDCConfiguration)
            sso = try SSOClient(config: ssoConfiguration)
        } catch {
            print("Error setting up clients: \(error)")
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
    
    func getAccountInfo(accessToken: String) async throws -> GetRoleCredentialsOutput {
        let listAccountsRequest = ListAccountsInput(accessToken: accessToken, maxResults: 1)
        let listAccountsResponse = try await sso!.listAccounts(input: listAccountsRequest)
        
        guard let account = listAccountsResponse.accountList?.first else {
            throw NSError(domain: "SSOError", code: 0, userInfo: [NSLocalizedDescriptionKey: "No accounts found"])
        }
        
        let listAccountRolesRequest = ListAccountRolesInput(
            accessToken: accessToken,
            accountId: account.accountId!,
            maxResults: 1
        )
        let listAccountRolesResponse = try await sso!.listAccountRoles(input: listAccountRolesRequest)
        
        guard let role = listAccountRolesResponse.roleList?.first else {
            throw NSError(domain: "SSOError", code: 0, userInfo: [NSLocalizedDescriptionKey: "No roles found"])
        }
        
        let getRoleCredentialsRequest = GetRoleCredentialsInput(
            accessToken: accessToken,
            accountId: account.accountId!,
            roleName: role.roleName!
        )
        return try await sso!.getRoleCredentials(input: getRoleCredentialsRequest)
    }
    
    func completeLogin(tokenResponse: CreateTokenOutput) async throws {
            let roleCredentials = try await getAccountInfo(accessToken: tokenResponse.accessToken!)
            
            // 자격 증명을 안전하게 저장 (Keychain 사용 권장)
            // 여기서는 간단히 로그인 상태만 변경
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
