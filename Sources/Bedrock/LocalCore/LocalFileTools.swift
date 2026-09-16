import Foundation

enum LocalPath {
    static func resolve(_ path: String, in root: URL, allowRoot: Bool = true) throws -> URL {
        guard !path.contains("\0"), !path.hasPrefix("~") else { throw LocalWorkbenchError.outsideProject }
        let canonicalRoot = try canonicalize(root)
        let candidate = path.hasPrefix("/") ? URL(fileURLWithPath: path) : canonicalRoot.appendingPathComponent(path)
        let resolved = try canonicalize(candidate)
        guard contains(resolved, in: canonicalRoot),
              allowRoot || resolved.path != canonicalRoot.path else { throw LocalWorkbenchError.outsideProject }
        return resolved
    }

    static func contains(_ url: URL, in root: URL) -> Bool {
        root.path == "/" || url.path == root.path || url.path.hasPrefix(root.path + "/")
    }

    /// Foundation leaves symlinks unresolved when the final file does not exist.
    /// Resolve each parent (including dangling links) before accepting a new file.
    static func canonicalize(_ url: URL) throws -> URL {
        var pending = url.pathComponents.filter { $0 != "/" }
        var current = URL(fileURLWithPath: "/", isDirectory: true)
        var followedLinks = 0
        while !pending.isEmpty {
            let component = pending.removeFirst()
            if component == "." { continue }
            if component == ".." { current.deleteLastPathComponent(); continue }
            let candidate = current.appendingPathComponent(component)
            if let link = try? FileManager.default.destinationOfSymbolicLink(atPath: candidate.path) {
                followedLinks += 1
                guard followedLinks <= 40 else { throw LocalWorkbenchError.invalid("The path contains a symbolic-link loop.") }
                if link.hasPrefix("/") { current = URL(fileURLWithPath: "/", isDirectory: true) }
                pending = (link as NSString).pathComponents.filter { $0 != "/" } + pending
            } else {
                current = candidate
            }
        }
        return current
    }

    static func validatedWebURL(_ value: String, allowedDomains: String) throws -> URL {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme), let host = url.host?.lowercased(),
              !host.isEmpty, url.user == nil, url.password == nil else {
            throw LocalWorkbenchError.invalid("Use an HTTP or HTTPS URL without embedded credentials.")
        }
        let domains = allowedDomains.split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }
        if !domains.isEmpty && !domains.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
            throw LocalWorkbenchError.invalid("“\(host)” is not in the allowed web domains.")
        }
        return url
    }
}

struct LocalFileEntry: Identifiable, Equatable, Sendable {
    var path: String
    var bytes: Int
    var isDirectory = false
    var id: String { path }
}

enum LocalFileTools {
    static let excludedDirectories: Set<String> = [".git", ".build", "node_modules", "DerivedData", "build", "dist", ".next", "vendor"]
    static func list(root: URL, directory: String = ".", limit: Int = 1_000,
                     recursive: Bool = true, includeHidden: Bool = false) throws -> [LocalFileEntry] {
        let target = try LocalPath.resolve(directory, in: root)
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory), isDirectory.boolValue,
              FileManager.default.isReadableFile(atPath: target.path) else {
            throw LocalWorkbenchError.unavailable("This folder is unavailable or macOS has not granted access to it.")
        }
        guard let enumerator = FileManager.default.enumerator(at: target, includingPropertiesForKeys: Array(keys),
                                                              options: includeHidden ? [] : [.skipsHiddenFiles],
                                                              errorHandler: { _, _ in true }) else {
            throw LocalWorkbenchError.unavailable("This folder could not be opened.")
        }
        let canonicalRoot = try LocalPath.resolve(".", in: root)
        let prefixCount = canonicalRoot.path == "/" ? 1 : canonicalRoot.path.count + 1
        var entries: [LocalFileEntry] = []
        var visited = 0
        while let url = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            visited += 1
            if visited > 20_000 { break }
            guard let values = try? url.resourceValues(forKeys: keys) else { enumerator.skipDescendants(); continue }
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            if values.isDirectory == true && !recursive { enumerator.skipDescendants() }
            if recursive && values.isDirectory == true && excludedDirectories.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            guard values.isRegularFile == true || (!recursive && values.isDirectory == true) else { continue }
            let resolved = try LocalPath.resolve(url.path, in: root)
            entries.append(.init(path: String(resolved.path.dropFirst(prefixCount)), bytes: values.fileSize ?? 0,
                                 isDirectory: values.isDirectory == true))
            if entries.count >= max(1, limit) { break }
        }
        return entries.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    static func read(root: URL, path: String, maximumBytes: Int = 1_048_576, startLine: Int = 1, lineCount: Int = 300) throws -> String {
        let data = try readData(root: root, path: path, limit: maximumBytes)
        guard let text = String(data: data, encoding: .utf8), !text.contains("\0") else {
            throw LocalWorkbenchError.invalid("This file is not UTF-8 text. Use the native preview to open it.")
        }
        let lines = text.components(separatedBy: "\n")
        let start = max(1, startLine) - 1
        guard start < lines.count else { return "" }
        let end = min(lines.count, start + min(5_000, max(1, lineCount)))
        return lines[start..<end].enumerated().map { "\(start + $0.offset + 1): \($0.element)" }.joined(separator: "\n")
    }

    static func readData(root: URL, path: String, limit: Int) throws -> Data {
        try Task.checkCancellation()
        guard limit > 0 else { throw LocalWorkbenchError.invalid("The file size limit must be positive.") }
        let url = try LocalPath.resolve(path, in: root, allowRoot: false)
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw LocalWorkbenchError.invalid("Select a regular file.") }
        guard (values.fileSize ?? 0) <= limit else { throw LocalWorkbenchError.tooLarge(limit) }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw LocalWorkbenchError.tooLarge(limit) }
        try Task.checkCancellation()
        return data
    }

    static func search(root: URL, query: String, maximumResults: Int = 100) throws -> String {
        guard !query.isEmpty else { throw LocalWorkbenchError.invalid("Enter text to search for.") }
        var results: [String] = []
        for entry in try list(root: root, limit: 5_000) where entry.bytes <= 512_000 {
            try Task.checkCancellation()
            guard let data = try? readData(root: root, path: entry.path, limit: 512_000),
                  let text = String(data: data, encoding: .utf8), !text.contains("\0") else { continue }
            for (index, line) in text.components(separatedBy: "\n").enumerated() where line.localizedStandardContains(query) {
                results.append("\(entry.path):\(index + 1): \(line.prefix(1_000))")
                if results.count >= maximumResults { return results.joined(separator: "\n") + "\n[Result limit reached]" }
            }
        }
        return results.isEmpty ? "No matches." : results.joined(separator: "\n")
    }

    static func write(root: URL, path: String, content: String, maximumBytes: Int = 1_048_576) throws -> String {
        try Task.checkCancellation()
        guard content.utf8.count <= maximumBytes else { throw LocalWorkbenchError.tooLarge(maximumBytes) }
        let url = try LocalPath.resolve(path, in: root, allowRoot: false)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Recheck after creating parents; never follow a link out of the allowed root.
        let checkedURL = try LocalPath.resolve(url.path, in: root, allowRoot: false)
        try Task.checkCancellation()
        try Data(content.utf8).write(to: checkedURL, options: .atomic)
        return "Wrote \(content.utf8.count) bytes to \(path)."
    }

    static func bounded(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let marker = "\n[Output truncated; \(text.count) characters total]\n"
        let room = max(0, limit - marker.count)
        return String(text.prefix(room * 3 / 4)) + marker + String(text.suffix(room / 4))
    }
}
