import Foundation

enum LocalArguments {
    /// Parse command-line arguments without expansion or shell execution.
    static func parse(_ value: String) throws -> [String] {
        var result: [String] = []
        var token = ""
        var quote: Character?
        var escaped = false
        var started = false
        for character in value {
            guard character != "\0" else { throw LocalOperationError.invalid("Arguments cannot contain NUL characters.") }
            if escaped { token.append(character); escaped = false; started = true; continue }
            if character == "\\", quote != "'" { escaped = true; started = true; continue }
            if let active = quote {
                if character == active { quote = nil } else { token.append(character) }
                continue
            }
            if character == "\"" || character == "'" { quote = character; started = true; continue }
            if character.isWhitespace {
                if started { result.append(token); token = ""; started = false }
            } else { token.append(character); started = true }
        }
        guard quote == nil, !escaped else { throw LocalOperationError.invalid("Close the quote or escape in the server arguments.") }
        if started { result.append(token) }
        return result
    }
    static func display(_ arguments: [String]) -> String {
        arguments.map { argument in
            if !argument.isEmpty, argument.allSatisfy({ $0.isLetter || $0.isNumber || "-_./:@=".contains($0) }) { return argument }
            return "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }.joined(separator: " ")
    }
}

enum LocalDataMigration {
    /// Copy into an empty destination, staging on the same volume for an atomic handoff.
    /// The original directory is kept as a recoverable copy.
    static func copy(from source: URL, to destination: URL) throws {
        let manager = FileManager.default
        let source = source.standardizedFileURL.resolvingSymlinksInPath()
        let destination = destination.standardizedFileURL.resolvingSymlinksInPath()
        guard source != destination, !destination.path.hasPrefix(source.path + "/"), !source.path.hasPrefix(destination.path + "/") else {
            throw LocalOperationError.invalid("Choose a separate empty folder outside the current data folder.")
        }
        if manager.fileExists(atPath: destination.path),
           !(try manager.contentsOfDirectory(atPath: destination.path)).isEmpty {
            throw LocalOperationError.invalid("Choose an empty folder. Existing destination files will not be overwritten.")
        }
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".bedrock-migration-\(UUID().uuidString)")
        defer { try? manager.removeItem(at: staging) }
        if manager.fileExists(atPath: source.path) { try manager.copyItem(at: source, to: staging) }
        else { try manager.createDirectory(at: staging, withIntermediateDirectories: true) }
        if manager.fileExists(atPath: destination.path) { try manager.removeItem(at: destination) }
        try manager.moveItem(at: staging, to: destination)
    }
}
