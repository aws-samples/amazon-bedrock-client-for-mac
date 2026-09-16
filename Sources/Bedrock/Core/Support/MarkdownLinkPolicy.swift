import Foundation

enum MarkdownLinkPolicy {
    static func allowsExternalLink(_ url: URL) -> Bool {
        guard url.user == nil, url.password == nil else { return false }
        if url.scheme?.lowercased() == "mailto" { return true }
        return (try? LocalPath.validatedWebURL(url.absoluteString, allowedDomains: "")) != nil
    }
}
