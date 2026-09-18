import Foundation

struct SoftwareUpdateRelease: Decodable, Sendable {
    static let assetName = "Amazon.Bedrock.Client.for.Mac.dmg"
    static let repository = "aws-samples/amazon-bedrock-client-for-mac"
    static let latestURL = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!

    struct Asset: Decodable, Sendable {
        let name: String
        let browserDownloadURL: URL
        let size: Int64?
        let digest: String?

        enum CodingKeys: String, CodingKey {
            case name, size, digest
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case draft, prerelease, assets
        case tagName = "tag_name"
    }

    var version: String { String(tagName.dropFirst(tagName.hasPrefix("v") ? 1 : 0)) }

    /// A stable release from this repository must never offer a downgrade or an
    /// unrelated asset. The asset name remains compatible with the 1.x updater.
    func update(after currentVersion: String) throws -> Asset? {
        guard !draft, !prerelease, let latest = Self.components(version),
              let current = Self.components(currentVersion) else { return nil }
        guard current.lexicographicallyPrecedes(latest) else { return nil }
        guard let asset = assets.first(where: { $0.name == Self.assetName }),
              Self.isTrustedDownload(asset.browserDownloadURL, tag: tagName) else {
            throw SoftwareUpdateError.invalidRelease
        }
        return asset
    }

    static func components(_ version: String) -> [Int]? {
        let fields = version.split(separator: ".", omittingEmptySubsequences: false)
        guard fields.count == 3, fields.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        let numbers = fields.compactMap { Int($0) }
        return numbers.count == 3 ? numbers : nil
    }

    static func isTrustedDownload(_ url: URL, tag: String) -> Bool {
        url.scheme == "https" && url.host == "github.com" && url.user == nil &&
        url.password == nil && url.port == nil && url.query == nil && url.fragment == nil &&
        url.path == "/\(repository)/releases/download/\(tag)/\(assetName)"
    }

    static func decode(_ data: Data, response: HTTPURLResponse, now: Date) throws -> Self {
        let limited = response.statusCode == 429 || (response.statusCode == 403 &&
            (response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" ||
             response.value(forHTTPHeaderField: "Retry-After") != nil))
        if limited {
            var deadlines: [Date] = []
            if let reset = response.value(forHTTPHeaderField: "X-RateLimit-Reset"),
               let seconds = TimeInterval(reset), seconds.isFinite {
                deadlines.append(Date(timeIntervalSince1970: seconds))
            }
            if let retry = response.value(forHTTPHeaderField: "Retry-After") {
                if let seconds = TimeInterval(retry), seconds.isFinite, seconds >= 0 {
                    deadlines.append(now.addingTimeInterval(seconds))
                } else {
                    let formatter = DateFormatter()
                    formatter.locale = Locale(identifier: "en_US_POSIX")
                    formatter.timeZone = TimeZone(secondsFromGMT: 0)
                    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
                    if let date = formatter.date(from: retry) { deadlines.append(date) }
                }
            }
            let deadline = deadlines.filter { $0 > now }.max() ?? now.addingTimeInterval(60)
            throw SoftwareUpdateError.rateLimited(until: deadline)
        }
        guard response.statusCode == 200 else {
            throw SoftwareUpdateError.metadataUnavailable(statusCode: response.statusCode)
        }
        do { return try JSONDecoder().decode(Self.self, from: data) }
        catch { throw SoftwareUpdateError.invalidMetadata }
    }
}

/// Metadata requests are independent of download and signature validation.
/// Persist the retry deadline so restarting the app cannot hammer a limited API.
@MainActor
final class SoftwareUpdateClient {
    private static let retryKey = "softwareUpdateMetadataRetryAfter"
    private let session: URLSession
    private let preferences: UserDefaults
    private let endpoint: URL
    private let now: () -> Date

    init(session: URLSession = .shared, preferences: UserDefaults = .standard,
         endpoint: URL = SoftwareUpdateRelease.latestURL, now: @escaping () -> Date = Date.init) {
        self.session = session
        self.preferences = preferences
        self.endpoint = endpoint
        self.now = now
    }

    func latestRelease() async throws -> SoftwareUpdateRelease {
        try Task.checkCancellation()
        let date = now()
        if let deadline = preferences.object(forKey: Self.retryKey) as? Date, deadline > date {
            throw SoftwareUpdateError.rateLimited(until: deadline)
        }
        preferences.removeObject(forKey: Self.retryKey)
        var request = URLRequest(url: endpoint, timeoutInterval: 30)
        request.cachePolicy = .useProtocolCachePolicy
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else {
            throw SoftwareUpdateError.invalidMetadata
        }
        do { return try SoftwareUpdateRelease.decode(data, response: response, now: now()) }
        catch let error as SoftwareUpdateError {
            if case .rateLimited(let deadline) = error {
                preferences.set(deadline, forKey: Self.retryKey)
            }
            throw error
        }
    }
}

enum SoftwareUpdateError: LocalizedError {
    case invalidRelease
    case invalidMetadata
    case metadataUnavailable(statusCode: Int)
    case rateLimited(until: Date)
    case invalidDownload
    case manualInstallationRequired(String)
    case verification(String)
    case installation(String)

    var errorDescription: String? {
        switch self {
        case .invalidRelease: "The release does not contain a valid Bedrock update."
        case .invalidMetadata: "GitHub returned unreadable update information. Please try again."
        case .metadataUnavailable(let statusCode):
            "GitHub could not provide update information (HTTP \(statusCode)). Please try again."
        case .rateLimited(let deadline):
            "GitHub temporarily limited update checks. Try again after \(DateFormatter.localizedString(from: deadline, dateStyle: .short, timeStyle: .short))."
        case .invalidDownload: "The update download is incomplete or could not be verified. Please try again."
        case .manualInstallationRequired(let detail): detail
        case .verification(let detail): "The update could not be verified. \(detail)"
        case .installation(let detail): detail
        }
    }
}

/// Paths are arguments, never interpolated shell source. The helper waits for
/// this exact process to finish saving, then renames on the same volume. It
/// retains/restores the old app if replacement or relaunch fails.
struct UpdateInstallationPlan: Sendable {
    let destination: URL
    let stagingDirectory: URL
    let workspace: URL
    let parentPID: Int32
    var relaunch = true
    var quitTimeoutSeconds = 120

    var stagedApp: URL { stagingDirectory.appendingPathComponent("New.app") }
    var previousApp: URL { stagingDirectory.appendingPathComponent("Previous.app") }
    var scriptURL: URL { workspace.appendingPathComponent("finish-update.sh") }
    var readyURL: URL { workspace.appendingPathComponent("ready") }
    var resultURL: URL { workspace.appendingPathComponent("result") }

    func writeHelper() throws {
        guard parentPID > 0, (1...600).contains(quitTimeoutSeconds),
              [destination, stagingDirectory, workspace].allSatisfy(\.isFileURL),
              destination.pathExtension == "app",
              destination.deletingLastPathComponent().standardizedFileURL ==
                stagingDirectory.deletingLastPathComponent().standardizedFileURL,
              destination.standardizedFileURL != stagedApp.standardizedFileURL,
              destination.standardizedFileURL != previousApp.standardizedFileURL else {
            throw SoftwareUpdateError.installation("The update destination is invalid.")
        }
        try Self.helper.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
    }

    var arguments: [String] {
        [scriptURL.path, String(parentPID), destination.path, stagedApp.path, previousApp.path,
         workspace.path, relaunch ? "1" : "0", String(quitTimeoutSeconds)]
    }

    static let helper = #"""
    #!/bin/sh
    set -eu
    PATH=/usr/bin:/bin:/usr/sbin:/sbin
    export PATH
    umask 077
    PARENT_PID=$1
    DESTINATION=$2
    STAGED=$3
    PREVIOUS=$4
    WORKSPACE=$5
    RELAUNCH=$6
    TIMEOUT=$7
    exec >> "$WORKSPACE/update.log" 2>&1
    MOVED_OLD=0
    INSTALLED_NEW=0
    COMPLETED=0

    finish() {
        status=$?
        trap - EXIT HUP INT TERM
        if [ "$COMPLETED" -ne 1 ]; then
            if [ "$INSTALLED_NEW" -eq 1 ] && [ -d "$DESTINATION" ]; then
                /bin/mv "$DESTINATION" "$STAGED" || true
            fi
            if [ "$MOVED_OLD" -eq 1 ] && [ ! -e "$DESTINATION" ]; then
                /bin/mv "$PREVIOUS" "$DESTINATION" || true
            fi
            printf 'failed\n' > "$WORKSPACE/result"
            if [ "$RELAUNCH" -eq 1 ]; then
                /usr/bin/osascript -e 'display alert "Bedrock update could not finish" message "Your previous app has been kept. Open Bedrock and try again, or download the update from GitHub." as warning' || true
                if [ "$MOVED_OLD" -eq 1 ] && [ -d "$DESTINATION" ]; then
                    /usr/bin/open -n "$DESTINATION" || true
                fi
            fi
        fi
        exit "$status"
    }
    trap finish EXIT
    trap 'exit 1' HUP INT TERM

    test -d "$DESTINATION" && test ! -L "$DESTINATION"
    test -d "$STAGED" && test ! -L "$STAGED"
    test ! -e "$PREVIOUS"
    /usr/bin/codesign --verify --deep --strict "$STAGED"
    printf 'ready\n' > "$WORKSPACE/ready"
    elapsed=0
    while /bin/kill -0 "$PARENT_PID" 2>/dev/null; do
        if [ "$elapsed" -ge "$TIMEOUT" ]; then exit 1; fi
        /bin/sleep 1
        elapsed=$((elapsed + 1))
    done

    /bin/mv "$DESTINATION" "$PREVIOUS"
    MOVED_OLD=1
    /bin/mv "$STAGED" "$DESTINATION"
    INSTALLED_NEW=1
    /usr/bin/codesign --verify --deep --strict "$DESTINATION"
    if [ "$RELAUNCH" -eq 1 ]; then /usr/bin/open -n "$DESTINATION"; fi
    COMPLETED=1
    printf 'installed\n' > "$WORKSPACE/result"
    /bin/rm -rf "$PREVIOUS"
    /bin/rmdir "$(dirname "$STAGED")" || true
    """#
}
