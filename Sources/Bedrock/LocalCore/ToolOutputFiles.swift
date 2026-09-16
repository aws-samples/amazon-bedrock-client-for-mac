import Foundation

enum ToolOutputFiles {
    /// Discover explicit local references only. Merely displaying a tool result
    /// never opens a file or a URL. The same optional file allowlist applies.
    static func find(input: JSONValue, output: String, access: LocalFileAccess) throws -> [URL] {
        var candidates: [String] = []
        func collect(_ value: JSONValue, key: String? = nil, depth: Int = 0) {
            guard depth < 8, candidates.count < 128 else { return }
            switch value {
            case .string(let value):
                if value.hasPrefix("/") || value.hasPrefix("~/") || value.hasPrefix("file:") ||
                    ["path", "file", "filename", "directory", "cwd"].contains(key ?? "") {
                    candidates.append(value)
                }
            case .object(let values):
                for key in values.keys.sorted() where !["command", "content", "text", "data"].contains(key) {
                    if let value = values[key] { collect(value, key: key, depth: depth + 1) }
                }
            case .array(let values): for value in values.prefix(128) { collect(value, key: key, depth: depth + 1) }
            default: break
            }
        }
        collect(input)
        let bounded = String(output.prefix(128_000))
        if let data = bounded.data(using: .utf8), let json = try? JSONDecoder().decode(JSONValue.self, from: data) { collect(json) }
        let pattern = #"(?m)`((?:/|~/|file:)[^`\n]+)`|\]\(((?:/|~/|file:)[^)\n]+)\)|^((?:/|~/|file:)[^\n]+)$|(?:^|[\s:])((?:/|~/|file:)[^\s\"'<>`,)]+)"#
        let regex = try NSRegularExpression(pattern: pattern)
        let text = bounded as NSString
        for match in regex.matches(in: bounded, range: NSRange(location: 0, length: text.length)).prefix(128) {
            for index in 1..<match.numberOfRanges where match.range(at: index).location != NSNotFound {
                candidates.append(text.substring(with: match.range(at: index)))
            }
        }
        var seen: Set<String> = []
        var files: [URL] = []
        for candidate in candidates.prefix(256) {
            try Task.checkCancellation()
            let path: String
            if candidate.hasPrefix("file:") {
                guard let url = URL(string: candidate), url.isFileURL,
                      url.host == nil || url.host == "" || url.host == "localhost" else { continue }
                path = url.path
            } else { path = candidate }
            guard path.utf8.count <= 4_096, !path.contains("\n"),
                  let url = try? access.resolve(path, allowRoot: false).url,
                  FileManager.default.fileExists(atPath: url.path),
                  seen.insert(url.path).inserted else { continue }
            files.append(url)
            if files.count == 8 { break }
        }
        return files
    }
}
