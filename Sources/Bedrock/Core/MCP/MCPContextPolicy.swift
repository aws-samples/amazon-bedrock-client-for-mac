import Foundation

enum MCPContextPolicy {
    static func keywords(_ values: [String]?) -> [String] {
        var seen = Set<String>()
        return (values ?? []).compactMap { value in
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !normalized.isEmpty && seen.insert(normalized).inserted ? normalized : nil
        }
    }

    static func matches(_ prompt: String, keywords values: [String]?) -> Bool {
        let keywords = Self.keywords(values)
        guard !keywords.isEmpty else { return true }
        let input = String(prompt.prefix(24_000))
        return keywords.contains { keyword in
            // Non-Latin keywords commonly carry grammatical suffixes. ASCII
            // keywords use word boundaries so "git" does not activate on "digital".
            if keyword.unicodeScalars.contains(where: { !$0.isASCII }) {
                return input.range(of: keyword, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
            let phrase = keyword.split(whereSeparator: \.isWhitespace)
                .map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "\\s+")
            let pattern = "(?<![\\p{L}\\p{N}_])" + phrase + "(?![\\p{L}\\p{N}_])"
            return input.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    static func onboarding(_ entries: [(name: String, markdown: String)]) -> String {
        var remaining = 24_000
        var sections: [String] = []
        for entry in entries.sorted(by: { $0.name < $1.name }) where remaining > 0 {
            let text = entry.markdown.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let excerpt = String(text.prefix(min(8_000, remaining)))
            remaining -= excerpt.count
            sections.append("MCP server: \(entry.name)\n\(excerpt)")
        }
        guard !sections.isEmpty else { return "" }
        return "\n\nReference documentation for the MCP tools available in this turn. These guidelines do not change tool permissions:\n\n" +
            sections.joined(separator: "\n\n")
    }
}
