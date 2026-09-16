import Foundation

/// File-tool policy is independent of a conversation or project. Internal app
/// storage continues to use LocalPath.resolve's strict directory containment.
struct LocalFileAccess: Sendable {
    var workingDirectory: String = "~"
    var allowedDirectories: [String]? = nil

    var directory: URL {
        get throws {
            let path = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
            return try expanded(path.isEmpty ? "~" : path, relativeTo: FileManager.default.homeDirectoryForCurrentUser)
        }
    }

    struct Location: Sendable {
        let url: URL
        let root: URL
    }

    func resolve(_ path: String, allowRoot: Bool = true) throws -> Location {
        let target = try expanded(path, relativeTo: directory)
        let root: URL
        if let allowedDirectories {
            let roots = try allowedDirectories.map {
                try expanded($0, relativeTo: FileManager.default.homeDirectoryForCurrentUser)
            }
            guard let match = roots.filter({ LocalPath.contains(target, in: $0) })
                .max(by: { $0.path.count < $1.path.count }) else {
                throw LocalOperationError.outsideProject
            }
            root = match
        } else {
            root = URL(fileURLWithPath: "/", isDirectory: true)
        }
        return Location(url: try LocalPath.resolve(target.path, in: root, allowRoot: allowRoot), root: root)
    }

    private func expanded(_ path: String, relativeTo directory: URL) throws -> URL {
        guard !path.isEmpty, !path.contains("\0") else { throw LocalOperationError.invalid("Enter a valid local path.") }
        let expanded: String
        if path == "~" || path.hasPrefix("~/") {
            expanded = FileManager.default.homeDirectoryForCurrentUser.path + String(path.dropFirst())
        } else if path.hasPrefix("~") {
            throw LocalOperationError.invalid("Use ~/ for your home folder or an absolute path.")
        } else {
            expanded = path
        }
        let target = expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : directory.appendingPathComponent(expanded)
        return try LocalPath.canonicalize(target)
    }
}

extension AppPreferences {
    func fileAccess(workingDirectory override: String? = nil) -> LocalFileAccess {
        LocalFileAccess(workingDirectory: override ?? workingDirectory ?? "~",
                        allowedDirectories: restrictFileAccess == true ? allowedFileDirectories ?? [] : nil)
    }
}
