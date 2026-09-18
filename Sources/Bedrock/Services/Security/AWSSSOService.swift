import AppKit
import AWSSSOOIDC
import Combine
import Foundation

@MainActor
final class AWSSSOService: ObservableObject {
    @Published private(set) var isSigningIn = false
    @Published private(set) var challenge: AWSSSOChallenge?
    @Published private(set) var expiresAt: Date?
    @Published private(set) var message: String?
    @Published private(set) var profile: AWSSSOProfile?
    private var task: Task<Void, Never>?
    private var generation = UUID()

    private var cacheDirectory: URL {
        let environment = ProcessInfo.processInfo.environment
        if ValidationMode.isOffline(environment: environment),
           let root = environment["BEDROCK_WORKBENCH_DATA_DIR"] {
            return URL(fileURLWithPath: root).appendingPathComponent("aws/sso/cache")
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".aws/sso/cache")
    }

    func selectProfile(_ name: String) {
        cancel()
        profile = nil
        expiresAt = nil
        let config = PreferencesStore.configurationFileURLs().config
        let directory = cacheDirectory
        let id = generation
        task = Task {
            let result = await Task.detached {
                Result { try AWSSSOProfile.parse(configuration: String(contentsOf: config, encoding: .utf8), profileName: name) }
            }.value
            guard generation == id, !Task.isCancelled else { return }
            profile = try? result.get()
            if let profile { expiresAt = AWSSSOCache.expiration(profile: profile, directory: directory) }
        }
    }

    func signIn() {
        guard let profile, !isSigningIn else { return }
        cancel()
        let id = generation
        let directory = cacheDirectory
        isSigningIn = true
        task = Task {
            defer { if generation == id { isSigningIn = false; challenge = nil; task = nil } }
            do {
                guard !ValidationMode.isOffline(environment: ProcessInfo.processInfo.environment) else {
                    throw LocalOperationError.unavailable("SSO sign-in is disabled in isolated UI tests.")
                }
                let provider = try await AWSSSOOIDCProvider(region: profile.region)
                let result = try await AWSSSODeviceAuthorization().run(profile: profile, provider: provider) { [weak self] challenge in
                    try await self?.present(challenge, generation: id)
                }
                try Task.checkCancellation()
                guard generation == id else { return }
                try await Task.detached { try AWSSSOCache.write(result, profile: profile, directory: directory) }.value
                guard generation == id, !Task.isCancelled else { return }
                expiresAt = result.expiresAt
                message = "Signed in. The AWS connection is ready to refresh."
                NotificationCenter.default.post(name: .awsCredentialsChanged, object: nil)
            } catch is CancellationError {
                // Cancelling leaves the previous cached session intact.
            } catch {
                guard generation == id else { return }
                message = (error as? AWSSSOError)?.localizedDescription
                    ?? "SSO sign-in could not finish. Check your connection and retry."
            }
        }
    }

    private func present(_ challenge: AWSSSOChallenge, generation id: UUID) throws {
        try Task.checkCancellation()
        guard generation == id else { throw CancellationError() }
        self.challenge = challenge
        message = "Approve sign-in in your browser using the code below."
        openBrowser()
    }

    func openBrowser() {
        guard let url = challenge?.verificationURL else { return }
        if !NSWorkspace.shared.open(url) { message = "Open the verification link in your browser to continue." }
    }

    func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
        isSigningIn = false
        challenge = nil
        message = nil
    }
}

private struct AWSSSOOIDCProvider: AWSSSODeviceProvider {
    let client: SSOOIDCClient

    init(region: String) async throws {
        client = try SSOOIDCClient(region: region)
    }

    func register(scopes: [String]) async throws -> AWSSSORegistration {
        let output = try await client.registerClient(input: .init(clientName: "Bedrock for Mac", clientType: "public",
            grantTypes: ["urn:ietf:params:oauth:grant-type:device_code", "refresh_token"], scopes: scopes))
        guard let id = output.clientId, let secret = output.clientSecret, output.clientSecretExpiresAt > 0 else {
            throw AWSSSOError.invalidResponse
        }
        return .init(clientID: id, clientSecret: secret, expiresAt: Date(timeIntervalSince1970: Double(output.clientSecretExpiresAt)))
    }

    func authorize(registration: AWSSSORegistration, startURL: String) async throws -> AWSSSOChallenge {
        let output = try await client.startDeviceAuthorization(input: .init(clientId: registration.clientID,
            clientSecret: registration.clientSecret, startUrl: startURL))
        guard let deviceCode = output.deviceCode, let userCode = output.userCode,
              let link = output.verificationUriComplete ?? output.verificationUri, let url = URL(string: link) else {
            throw AWSSSOError.invalidResponse
        }
        return .init(deviceCode: deviceCode, userCode: userCode, verificationURL: url,
                     expiresIn: Double(output.expiresIn), interval: Double(output.interval))
    }

    func token(registration: AWSSSORegistration, deviceCode: String) async throws -> AWSSSOSession {
        do {
            let output = try await client.createToken(input: .init(clientId: registration.clientID,
                clientSecret: registration.clientSecret, deviceCode: deviceCode,
                grantType: "urn:ietf:params:oauth:grant-type:device_code"))
            guard let token = output.accessToken else { throw AWSSSOError.invalidResponse }
            return .init(accessToken: token, refreshToken: output.refreshToken, expiresIn: Double(output.expiresIn))
        } catch is AuthorizationPendingException { throw AWSSSOPollStatus.pending }
        catch is SlowDownException { throw AWSSSOPollStatus.slowDown }
        catch is ExpiredTokenException { throw AWSSSOError.expired }
        catch is AccessDeniedException { throw AWSSSOError.denied }
    }
}
