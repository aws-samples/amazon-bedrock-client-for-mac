import CryptoKit
import Foundation

struct AWSSSOProfile: Equatable, Sendable {
    let profileName: String
    let sessionName: String?
    let startURL: String
    let region: String
    let scopes: [String]

    /// The CRT and AWS CLI key modern caches by session name and legacy caches by start URL.
    var cacheFilename: String {
        Insecure.SHA1.hash(data: Data((sessionName ?? startURL).utf8))
            .map { String(format: "%02x", $0) }.joined() + ".json"
    }

    static func parse(configuration: String, profileName: String) throws -> Self {
        var sections: [String: [String: String]] = [:]
        var section: String?
        for line in configuration.split(whereSeparator: \.isNewline) {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.isEmpty || text.hasPrefix("#") || text.hasPrefix(";") { continue }
            if text.hasPrefix("["), let end = text.firstIndex(of: "]") {
                section = String(text[text.index(after: text.startIndex)..<end]).trimmingCharacters(in: .whitespaces)
            } else if let section, let equal = text.firstIndex(of: "=") {
                let key = text[..<equal].trimmingCharacters(in: .whitespaces).lowercased()
                var value = text[text.index(after: equal)...].trimmingCharacters(in: .whitespaces)
                if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                    value = String(value.dropFirst().dropLast())
                }
                sections[section, default: [:]][key] = value
            }
        }
        var name = profileName
        var visited = Set<String>()
        while visited.insert(name).inserted, visited.count <= 8 {
            guard let profile = sections[name == "default" ? name : "profile \(name)"] else {
                throw AWSSSOError.configuration("The selected profile was not found in the AWS config file.")
            }
            let session = profile["sso_session"].flatMap { $0.isEmpty ? nil : $0 }
            if let session, sections["sso-session \(session)"] == nil {
                throw AWSSSOError.configuration("The profile’s sso-session section is missing from the AWS config file.")
            }
            let settings = session.flatMap { sections["sso-session \($0)"] } ?? profile
            if let start = settings["sso_start_url"], let region = settings["sso_region"],
               let url = URL(string: start), url.scheme == "https", url.host?.isEmpty == false,
               url.user == nil, url.password == nil, !region.isEmpty,
               region.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) {
                let scopes = (settings["sso_registration_scopes"] ?? "sso:account:access")
                    .split { $0 == "," || $0.isWhitespace }.map(String.init)
                return .init(profileName: profileName, sessionName: session, startURL: start,
                             region: region, scopes: scopes.isEmpty ? ["sso:account:access"] : scopes)
            }
            if session != nil || profile.keys.contains(where: { $0.hasPrefix("sso_") }) {
                throw AWSSSOError.configuration("Configure sso_start_url and sso_region for this profile or its sso-session.")
            }
            guard let source = profile["source_profile"], !source.isEmpty else {
                throw AWSSSOError.configuration("This AWS profile does not use IAM Identity Center SSO.")
            }
            name = source
        }
        throw AWSSSOError.configuration("The AWS source_profile chain contains a cycle or is too long.")
    }
}

enum AWSSSOError: LocalizedError, Equatable {
    case configuration(String)
    case expired
    case denied
    case invalidResponse
    case cacheWrite

    var errorDescription: String? {
        switch self {
        case .configuration(let message): return message
        case .expired: return "The sign-in code expired. Start sign-in again."
        case .denied: return "Sign-in was not approved. You can try again."
        case .invalidResponse: return "AWS returned an incomplete sign-in response. Try again."
        case .cacheWrite: return "The AWS SSO session could not be saved. Check access to the local SSO cache."
        }
    }
}
