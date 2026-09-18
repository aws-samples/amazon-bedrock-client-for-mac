import Foundation
import XCTest
@testable import BedrockCore

final class AWSSSOTests: XCTestCase {
    private let configuration = """
    [default]
    sso_start_url = https://portal.example/start
    sso_region = us-west-2
    [profile work]
    sso_session = work-session
    sso_account_id = 123456789012
    sso_role_name = Developer
    [sso-session work-session]
    sso_start_url = https://portal.example/start
    sso_region = us-east-1
    sso_registration_scopes = sso:account:access, custom:read
    [profile assumed]
    source_profile = work
    role_arn = arn:aws:iam::123456789012:role/example
    """

    func testModernLegacyAndSourceProfilesUseTheSDKCacheIdentity() throws {
        let legacy = try AWSSSOProfile.parse(configuration: configuration, profileName: "default")
        XCTAssertNil(legacy.sessionName)
        XCTAssertEqual(legacy.region, "us-west-2")
        XCTAssertEqual(legacy.scopes, ["sso:account:access"])
        XCTAssertEqual(legacy.cacheFilename, "5863e3e4b5a9564b6e829cf4aa6724bdbf9788a5.json")
        let modern = try AWSSSOProfile.parse(configuration: configuration, profileName: "work")
        XCTAssertEqual(modern.sessionName, "work-session")
        XCTAssertEqual(modern.region, "us-east-1")
        XCTAssertEqual(modern.scopes, ["sso:account:access", "custom:read"])
        XCTAssertEqual(modern.cacheFilename, "e460ecf101daf4f10acff1ae5e54abb7df6501f8.json")
        XCTAssertNotEqual(modern.cacheFilename, legacy.cacheFilename)
        XCTAssertEqual(modern.cacheFilename.count, 45)
        let assumed = try AWSSSOProfile.parse(configuration: configuration, profileName: "assumed")
        XCTAssertEqual(assumed.profileName, "assumed")
        XCTAssertEqual(assumed.cacheFilename, modern.cacheFilename)
    }

    func testInvalidConfigurationFailsBeforeStartingBrowserOrNetworkRequests() {
        for config in [
            "[profile a]\nsource_profile=b\n[profile b]\nsource_profile=a",
            "[profile a]\nsso_session=missing",
            "[profile a]\nsso_session=missing\nsso_start_url=https://portal.example\nsso_region=us-east-1",
            "[profile a]\nsso_start_url=http://portal.example\nsso_region=us-east-1",
            "[profile a]\nsso_start_url=https://user:secret@portal.example\nsso_region=us-east-1",
            "[profile a]\nsso_start_url=https://portal.example\nsso_region=",
            "[profile a]\nregion=us-east-1"
        ] {
            XCTAssertThrowsError(try AWSSSOProfile.parse(configuration: config, profileName: "a"))
        }
    }

    func testDeviceFlowRespectsPendingSlowDownAndReturnsRefreshableSession() async throws {
        let profile = try AWSSSOProfile.parse(configuration: configuration, profileName: "work")
        let provider = SSOTestProvider(events: [.pending, .slowDown, .success])
        let clock = SSOTestClock()
        let flow = AWSSSODeviceAuthorization(now: { clock.now }, sleep: { clock.advance($0) })
        let result = try await flow.run(profile: profile, provider: provider) { challenge in
            XCTAssertEqual(challenge.userCode, "ABCD-EFGH")
            XCTAssertEqual(challenge.verificationURL.scheme, "https")
        }
        XCTAssertEqual(clock.delays, [2, 2, 7])
        XCTAssertEqual(result.session.refreshToken, "FIXTURE_REFRESH")
        XCTAssertEqual(result.expiresAt, clock.now.addingTimeInterval(600))
        let requests = await provider.requests
        XCTAssertEqual(requests, ["register:sso:account:access,custom:read", "authorize:https://portal.example/start",
                                  "token:DEVICE", "token:DEVICE", "token:DEVICE"])
    }

    func testExpiredAndDeniedSignInsStopPolling() async throws {
        let profile = try AWSSSOProfile.parse(configuration: configuration, profileName: "work")
        for (events, expiry, expected) in [([SSOTestProvider.Event.pending], 2.0, AWSSSOError.expired),
                                          ([.denied], 600.0, .denied)] {
            let provider = SSOTestProvider(events: events, expiresIn: expiry)
            let clock = SSOTestClock()
            let flow = AWSSSODeviceAuthorization(now: { clock.now }, sleep: { clock.advance($0) })
            do {
                _ = try await flow.run(profile: profile, provider: provider) { _ in }
                XCTFail("Sign-in must not complete")
            } catch let error as AWSSSOError { XCTAssertEqual(error, expected) }
        }
    }

    func testCancellingBrowserDoesNotExchangeOrPersistAToken() async throws {
        let profile = try AWSSSOProfile.parse(configuration: configuration, profileName: "work")
        let provider = SSOTestProvider(events: [.success])
        do {
            _ = try await AWSSSODeviceAuthorization().run(profile: profile, provider: provider) { _ in throw CancellationError() }
            XCTFail("Cancellation must propagate")
        } catch is CancellationError { }
        let requests = await provider.requests
        XCTAssertFalse(requests.contains(where: { $0.hasPrefix("token:") }))
    }

    func testCacheWritesCompatibleJSONWithPrivatePermissionsAndAtomicReplacement() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sso-cache-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let profile = try AWSSSOProfile.parse(configuration: configuration, profileName: "work")
        let expires = Date(timeIntervalSince1970: 2_000_000_000)
        let authorization = AWSSSOAuthorization(
            registration: .init(clientID: "CLIENT", clientSecret: "SECRET", expiresAt: expires.addingTimeInterval(3600)),
            session: .init(accessToken: "ACCESS", refreshToken: "REFRESH", expiresIn: 600), expiresAt: expires)
        try AWSSSOCache.write(authorization, profile: profile, directory: root)
        let file = root.appendingPathComponent(profile.cacheFilename)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        try AWSSSOCache.write(authorization, profile: profile, directory: root)
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o600)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: String])
        XCTAssertEqual(json["accessToken"], "ACCESS")
        XCTAssertEqual(json["refreshToken"], "REFRESH")
        XCTAssertEqual(json["clientId"], "CLIENT")
        XCTAssertEqual(json["clientSecret"], "SECRET")
        XCTAssertEqual(json["region"], "us-east-1")
        XCTAssertEqual(AWSSSOCache.expiration(profile: profile, directory: root), expires)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [profile.cacheFilename])
    }
}

private actor SSOTestProvider: AWSSSODeviceProvider {
    enum Event { case pending, slowDown, success, denied }
    var events: [Event]
    let expiresIn: TimeInterval
    private(set) var requests: [String] = []
    init(events: [Event], expiresIn: TimeInterval = 600) { self.events = events; self.expiresIn = expiresIn }
    func register(scopes: [String]) async throws -> AWSSSORegistration {
        requests.append("register:\(scopes.joined(separator: ","))")
        return .init(clientID: "CLIENT", clientSecret: "SECRET", expiresAt: Date().addingTimeInterval(3600))
    }
    func authorize(registration: AWSSSORegistration, startURL: String) async throws -> AWSSSOChallenge {
        requests.append("authorize:\(startURL)")
        return .init(deviceCode: "DEVICE", userCode: "ABCD-EFGH",
            verificationURL: URL(string: "https://portal.example/verify")!, expiresIn: expiresIn, interval: 2)
    }
    func token(registration: AWSSSORegistration, deviceCode: String) async throws -> AWSSSOSession {
        requests.append("token:\(deviceCode)")
        switch events.isEmpty ? .pending : events.removeFirst() {
        case .pending: throw AWSSSOPollStatus.pending
        case .slowDown: throw AWSSSOPollStatus.slowDown
        case .denied: throw AWSSSOError.denied
        case .success: return .init(accessToken: "FIXTURE_ACCESS", refreshToken: "FIXTURE_REFRESH", expiresIn: 600)
        }
    }
}

private final class SSOTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_800_000_000)
    private(set) var delays: [TimeInterval] = []
    var now: Date { lock.lock(); defer { lock.unlock() }; return date }
    func advance(_ seconds: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        delays.append(seconds)
        date = date.addingTimeInterval(seconds)
    }
}
