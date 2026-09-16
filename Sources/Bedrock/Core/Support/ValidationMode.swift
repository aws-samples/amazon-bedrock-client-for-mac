import Foundation

enum ValidationMode {
    /// CI runs a distinct app identity with an isolated data folder. Bundled
    /// models remain browsable; these tests never submit a paid AWS request.
    static var isOffline: Bool {
        isOffline(environment: ProcessInfo.processInfo.environment)
    }

    static func isOffline(environment: [String: String]) -> Bool {
        #if DEBUG || WORKBENCH_TESTING
        environment["BEDROCK_TEST_OFFLINE"] == "1" &&
        environment["BEDROCK_WORKBENCH_DATA_DIR"]?.isEmpty == false
        #else
        false
        #endif
    }

    /// Only test builds can opt into a loopback fixture. The app still uses its
    /// normal AWS SDK, request serialization, streaming parser and tool loop.
    static var localRuntimeEndpoint: String? {
        localRuntimeEndpoint(environment: ProcessInfo.processInfo.environment)
    }

    static func localRuntimeEndpoint(environment: [String: String]) -> String? {
        guard isOffline(environment: environment),
              let value = environment["BEDROCK_TEST_RUNTIME_PORT"],
              let port = Int(value), (1024...65535).contains(port) else { return nil }
        return "http://127.0.0.1:\(port)"
    }

    /// Test connections must not depend on an extra UserDefaults launch
    /// argument. Route both SDK clients locally, even if a stale custom AWS
    /// endpoint was saved. A missing fixture remains closed to all inference.
    static func connectionEndpoint(_ configured: String,
                                   environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        guard isOffline(environment: environment) else { return configured }
        return localRuntimeEndpoint(environment: environment) ?? "http://127.0.0.1:9"
    }

    static func permitsInference(modelID: String, runtimeEndpoint: String,
                                 environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        guard isOffline(environment: environment) else { return true }
        guard let endpoint = localRuntimeEndpoint(environment: environment),
              runtimeEndpoint == endpoint else { return false }
        // Mantle, speech, async media and control-plane clients have separate
        // endpoints. Never allow those to escape the isolated fixture run.
        return BedrockModelID.route(modelID) == .conversation
    }
}
