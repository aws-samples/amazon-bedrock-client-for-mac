import Foundation

enum ValidationMode {
    /// CI runs a distinct app identity with an isolated data folder. Bundled
    /// models remain browsable; these tests never submit a paid AWS request.
    static var isOffline: Bool {
        #if DEBUG || WORKBENCH_TESTING
        ProcessInfo.processInfo.environment["BEDROCK_TEST_OFFLINE"] == "1" &&
        ProcessInfo.processInfo.environment["BEDROCK_WORKBENCH_DATA_DIR"]?.isEmpty == false
        #else
        false
        #endif
    }

    /// Only test builds can opt into a loopback fixture. The app still uses its
    /// normal AWS SDK, request serialization, streaming parser and tool loop.
    static var localRuntimeEndpoint: String? {
        guard isOffline,
              let value = ProcessInfo.processInfo.environment["BEDROCK_TEST_RUNTIME_PORT"],
              let port = Int(value), (1024...65535).contains(port) else { return nil }
        return "http://127.0.0.1:\(port)"
    }

    static func permitsInference(modelID: String, runtimeEndpoint: String) -> Bool {
        guard isOffline else { return true }
        guard let localRuntimeEndpoint, runtimeEndpoint == localRuntimeEndpoint else { return false }
        // Mantle, speech, async media and control-plane clients have separate
        // endpoints. Never allow those to escape the isolated fixture run.
        return BedrockModelID.route(modelID) == .conversation
    }
}
