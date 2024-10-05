//
//  SSOManager.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 7/3/24.
//

import Foundation
import AWSSSOOIDC
import Logging
import AWSClientRuntime

class SSOManager: ObservableObject {
    private var ssoOIDC: SSOOIDCClient?
    private var logger = Logger(label: "SSOManager")
    @Published var isLoggedIn = false
    @Published var accessToken: String?
    private var clientId: String?
    private var clientSecret: String?
    private var region: String = "us-east-1" // Default region

    init() {
        // Initialization happens during login
    }

    private func setupClient() {
        do {
            let ssoOIDCConfiguration = try SSOOIDCClient.SSOOIDCClientConfiguration(region: region)
            ssoOIDC = SSOOIDCClient(config: ssoOIDCConfiguration)
            logger.info("SSOOIDC client set up with region: \(region)")
        } catch {
            logger.error("Error setting up SSOOIDC client: \(error)")
        }
    }

    func startSSOLogin(startUrl: String, region: String) async throws -> (authUrl: String, userCode: String, deviceCode: String, interval: Int) {
        self.region = region
        setupClient()
        logger.info("Starting SSO login with startUrl: \(startUrl) and region: \(region)")
        do {
            // Register client
            if clientId == nil || clientSecret == nil {
                let registerClientRequest = RegisterClientInput(
                    clientName: "AmazonBedrockClient",
                    clientType: "public",
                    scopes: ["openid", "sso:account:access"]
                )

                guard let ssoOIDC = ssoOIDC else {
                    throw NSError(domain: "SSOManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "SSOOIDC client not initialized"])
                }

                let registerClientResponse = try await ssoOIDC.registerClient(input: registerClientRequest)
                clientId = registerClientResponse.clientId
                clientSecret = registerClientResponse.clientSecret
                logger.info("Client registered with clientId: \(clientId!)")
            }

            // Start device authorization
            let startDeviceAuthRequest = StartDeviceAuthorizationInput(
                clientId: clientId!,
                clientSecret: clientSecret!,
                startUrl: startUrl
            )

            let startDeviceAuthResponse = try await ssoOIDC!.startDeviceAuthorization(input: startDeviceAuthRequest)

            logger.info("Received deviceCode: \(startDeviceAuthResponse.deviceCode ?? "nil")")

            return (
                authUrl: startDeviceAuthResponse.verificationUriComplete!,
                userCode: startDeviceAuthResponse.userCode!,
                deviceCode: startDeviceAuthResponse.deviceCode!,
                interval: startDeviceAuthResponse.interval ?? 5
            )
        } catch let error as InvalidRequestException {
            logger.error("InvalidRequestException: \(error.message ?? "No message")")
            throw error
        } catch {
            logger.error("SSO Login Error: \(error)")
            throw error
        }
    }

    func pollForTokens(deviceCode: String, interval: Int) async throws -> CreateTokenOutput {
        guard let clientId = clientId, let clientSecret = clientSecret else {
            throw NSError(domain: "SSOManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Client ID or Secret is missing"])
        }

        logger.info("Using deviceCode: \(deviceCode)")

        let createTokenRequest = CreateTokenInput(
            clientId: clientId,
            clientSecret: clientSecret,
            deviceCode: deviceCode,
            grantType: "urn:ietf:params:oauth:grant-type:device_code"
        )

        guard let ssoOIDC = ssoOIDC else {
            throw NSError(domain: "SSOManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "SSOOIDC client not initialized"])
        }

        while true {
            do {
                let tokenResponse = try await ssoOIDC.createToken(input: createTokenRequest)
                return tokenResponse
            } catch let error as AuthorizationPendingException {
                logger.info("Authorization pending. Waiting for user to complete authentication.")
                try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            } catch let error as SlowDownException {
                let newInterval = interval + 5
                logger.info("Slow down requested. Increasing interval to \(newInterval) seconds.")
                try await Task.sleep(nanoseconds: UInt64(newInterval) * 1_000_000_000)
            } catch let error as InvalidGrantException {
                logger.error("Invalid grant. The device code may have expired or is invalid.")
                throw error
            } catch {
                logger.error("Token polling error: \(error)")
                throw error
            }
        }
    }

    func completeLogin(tokenResponse: CreateTokenOutput) {
        DispatchQueue.main.async {
            self.accessToken = tokenResponse.accessToken
            self.isLoggedIn = true
            SettingManager.shared.isSSOLoggedIn = true
            SettingManager.shared.ssoAccessToken = tokenResponse.accessToken
        }
    }

    func logout() {
        DispatchQueue.main.async {
            self.isLoggedIn = false
            self.accessToken = nil
            self.clientId = nil
            self.clientSecret = nil
            SettingManager.shared.isSSOLoggedIn = false
            SettingManager.shared.ssoAccessToken = nil
        }
    }
}
