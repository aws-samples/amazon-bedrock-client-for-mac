import Darwin
import Foundation

struct AWSSSORegistration: Sendable {
    let clientID: String
    let clientSecret: String
    let expiresAt: Date
}

struct AWSSSOChallenge: Sendable {
    let deviceCode: String
    let userCode: String
    let verificationURL: URL
    let expiresIn: TimeInterval
    let interval: TimeInterval
}

struct AWSSSOSession: Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: TimeInterval
}

enum AWSSSOPollStatus: Error { case pending, slowDown }

protocol AWSSSODeviceProvider: Sendable {
    func register(scopes: [String]) async throws -> AWSSSORegistration
    func authorize(registration: AWSSSORegistration, startURL: String) async throws -> AWSSSOChallenge
    func token(registration: AWSSSORegistration, deviceCode: String) async throws -> AWSSSOSession
}

struct AWSSSOAuthorization: Sendable {
    let registration: AWSSSORegistration
    let session: AWSSSOSession
    let expiresAt: Date
}

struct AWSSSODeviceAuthorization: Sendable {
    var now: @Sendable () -> Date = { Date() }
    var sleep: @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }

    func run(profile: AWSSSOProfile, provider: any AWSSSODeviceProvider,
             present: @Sendable (AWSSSOChallenge) async throws -> Void) async throws -> AWSSSOAuthorization {
        try Task.checkCancellation()
        let registration = try await provider.register(scopes: profile.scopes)
        let challenge = try await provider.authorize(registration: registration, startURL: profile.startURL)
        guard !registration.clientID.isEmpty, !registration.clientSecret.isEmpty,
              !challenge.deviceCode.isEmpty, !challenge.userCode.isEmpty, challenge.expiresIn > 0,
              challenge.verificationURL.scheme == "https", challenge.verificationURL.host?.isEmpty == false,
              challenge.verificationURL.user == nil, challenge.verificationURL.password == nil else {
            throw AWSSSOError.invalidResponse
        }
        let deadline = now().addingTimeInterval(challenge.expiresIn)
        try Task.checkCancellation()
        try await present(challenge)
        var interval = max(1, challenge.interval)
        while now() < deadline {
            try Task.checkCancellation()
            try await sleep(min(interval, deadline.timeIntervalSince(now())))
            try Task.checkCancellation()
            guard now() < deadline else { break }
            do {
                let session = try await provider.token(registration: registration, deviceCode: challenge.deviceCode)
                try Task.checkCancellation()
                guard !session.accessToken.isEmpty, session.expiresIn > 0 else { throw AWSSSOError.invalidResponse }
                return .init(registration: registration, session: session,
                             expiresAt: now().addingTimeInterval(session.expiresIn))
            } catch AWSSSOPollStatus.pending {
                continue
            } catch AWSSSOPollStatus.slowDown {
                interval += 5
            }
        }
        throw AWSSSOError.expired
    }
}

enum AWSSSOCache {
    static func write(_ authorization: AWSSSOAuthorization, profile: AWSSSOProfile, directory: URL) throws {
        let formatter = ISO8601DateFormatter()
        var record: [String: Any] = [
            "startUrl": profile.startURL, "region": profile.region,
            "accessToken": authorization.session.accessToken,
            "expiresAt": formatter.string(from: authorization.expiresAt),
            "clientId": authorization.registration.clientID,
            "clientSecret": authorization.registration.clientSecret,
            "registrationExpiresAt": formatter.string(from: authorization.registration.expiresAt)
        ]
        if let refreshToken = authorization.session.refreshToken { record["refreshToken"] = refreshToken }
        let manager = FileManager.default
        let temporary = directory.appendingPathComponent(".bedrock-\(UUID().uuidString)")
        defer { try? manager.removeItem(at: temporary) }
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
            guard manager.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
                throw AWSSSOError.cacheWrite
            }
            let target = directory.appendingPathComponent(profile.cacheFilename)
            guard rename(temporary.path, target.path) == 0 else { throw AWSSSOError.cacheWrite }
        } catch { throw AWSSSOError.cacheWrite }
    }

    static func expiration(profile: AWSSSOProfile, directory: URL) -> Date? {
        let url = directory.appendingPathComponent(profile.cacheFilename)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber, size.intValue < 131_072,
              let data = try? Data(contentsOf: url),
              let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = record["expiresAt"] as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: value)
    }
}
