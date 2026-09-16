import Foundation

struct LocalSkillLibrarySnapshot: Sendable {
    var skills: [SkillDefinition] = []
    var issues: [String] = []
    var unavailable: [String: String] = [:]
}

/// File operations are independent of UI state and run on a worker task.
/// A malformed skill cannot remove the other valid entries in the library.
enum SkillLibrary {
    static let instructionLimit = 1_048_576
    static let libraryLimit = 16_000_000
    static let packageLimit = 50_000_000
    static let entryLimit = 2_000

    static func load(_ directory: URL) throws -> LocalSkillLibrarySnapshot {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let children = try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: .skipsHiddenFiles)
        guard children.count <= entryLimit else { throw LocalOperationError.invalid("The skills folder contains too many entries.") }
        var result = LocalSkillLibrarySnapshot()
        var ids: Set<String> = []
        var bytes = 0
        for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            try Task.checkCancellation()
            do {
                let properties = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard properties.isSymbolicLink != true else {
                    throw LocalOperationError.invalid("Use an original skill file or folder, not a symbolic link.")
                }
                let folder = properties.isDirectory == true
                let url = folder ? child.appendingPathComponent("SKILL.md") : child
                guard url.pathExtension.lowercased() == "md", FileManager.default.fileExists(atPath: url.path) else { continue }
                let id = folder ? child.lastPathComponent : child.deletingPathExtension().lastPathComponent
                try validateID(id)
                guard !ids.contains(id) else { throw LocalOperationError.invalid("Duplicate skill identifier “\(id)”.") }
                let source = try read(url, root: directory)
                bytes += source.utf8.count
                guard bytes <= libraryLimit else { throw LocalOperationError.tooLarge(libraryLimit) }
                let skill = try SkillDefinition.parse(source, id: id, url: url)
                result.skills.append(skill)
                ids.insert(id)
                result.unavailable[id] = skill.unavailableReason()
            } catch is CancellationError { throw CancellationError() }
            catch {
                result.issues.append("\(child.lastPathComponent): \(error.localizedDescription)")
                if bytes > libraryLimit { break }
            }
        }
        return result
    }

    static func read(_ url: URL, root: URL) throws -> String {
        let properties = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
        guard properties.isRegularFile == true, properties.isSymbolicLink != true else {
            throw LocalOperationError.invalid("SKILL.md must be a regular file.")
        }
        let data = try LocalFileTools.readData(root: root, path: url.path, limit: instructionLimit)
        guard let source = String(data: data, encoding: .utf8), !source.contains("\0") else {
            throw LocalOperationError.invalid("SKILL.md must contain UTF-8 text.")
        }
        return source
    }

    static func save(id: String, source: String, existingURL: URL?, directory: URL) throws {
        try validateID(id)
        let url = existingURL ?? directory.appendingPathComponent(id).appendingPathComponent("SKILL.md")
        _ = try SkillDefinition.parse(source, id: id, url: url)
        _ = try LocalPath.resolve(url.path, in: directory, allowRoot: false)
        if existingURL == nil, FileManager.default.fileExists(atPath: url.path) {
            throw LocalOperationError.invalid("This skill already exists. Reload and edit its existing instructions.")
        }
        _ = try LocalFileTools.write(root: directory, path: url.path, content: source, maximumBytes: instructionLimit)
    }

    @discardableResult
    static func importPackage(from source: URL, into directory: URL) throws -> String {
        let properties = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard properties.isSymbolicLink != true else { throw LocalOperationError.invalid("Choose the original skill instead of a symbolic link.") }
        let folder = properties.isDirectory == true
        let file = folder ? source.appendingPathComponent("SKILL.md") : source
        let raw = try read(file, root: source.deletingLastPathComponent())
        var id = (folder ? source.lastPathComponent : source.deletingPathExtension().lastPathComponent).lowercased()
        if id == "skill" { id = source.deletingLastPathComponent().lastPathComponent.lowercased() }
        id = id.replacingOccurrences(of: #"[^a-z0-9_-]"#, with: "-", options: .regularExpression)
        if id.isEmpty { id = "imported-skill" }
        try validateID(id)
        _ = try SkillDefinition.parse(raw, id: id, url: file)
        let target = directory.appendingPathComponent(id)
        guard !FileManager.default.fileExists(atPath: target.path),
              !FileManager.default.fileExists(atPath: directory.appendingPathComponent(id + ".md").path) else {
            throw LocalOperationError.invalid("A skill named “\(id)” already exists. Rename the imported folder or edit the existing skill.")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let staging = directory.appendingPathComponent(".import-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        if folder { try copyPackage(from: source, into: staging) }
        else { try Data(raw.utf8).write(to: staging.appendingPathComponent("SKILL.md"), options: .atomic) }
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: staging, to: target)
        return id
    }

    static func references(for skill: SkillDefinition) throws -> [LocalFileEntry] {
        guard skill.url.lastPathComponent == "SKILL.md" else { return [] }
        return try packageEntries(skill.url.deletingLastPathComponent()).filter { $0.path != "SKILL.md" && !$0.isDirectory }
    }

    static func export(_ skill: SkillDefinition, to destination: URL) throws {
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw LocalOperationError.invalid("Choose a new folder name for this exported skill.")
        }
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".export-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        if skill.url.lastPathComponent == "SKILL.md" {
            try copyPackage(from: skill.url.deletingLastPathComponent(), into: staging)
        } else {
            let raw = try read(skill.url, root: skill.url.deletingLastPathComponent())
            try Data(raw.utf8).write(to: staging.appendingPathComponent("SKILL.md"), options: .atomic)
        }
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: staging, to: destination)
    }

    private static func copyPackage(from source: URL, into destination: URL) throws {
        let entries = try packageEntries(source)
        var bytes = 0
        for entry in entries {
            try Task.checkCancellation()
            let target = destination.appendingPathComponent(entry.path)
            if entry.isDirectory {
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            } else {
                let data = try LocalFileTools.readData(root: source, path: entry.path, limit: max(1, packageLimit - bytes))
                bytes += data.count
                guard bytes <= packageLimit else { throw LocalOperationError.tooLarge(packageLimit) }
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: target, options: .atomic)
                let original = try LocalPath.resolve(entry.path, in: source, allowRoot: false)
                let permissions = try FileManager.default.attributesOfItem(atPath: original.path)[.posixPermissions] as? NSNumber
                if let permissions {
                    try FileManager.default.setAttributes([.posixPermissions: permissions.intValue & 0o777], ofItemAtPath: target.path)
                }
            }
        }
    }

    private static func packageEntries(_ root: URL) throws -> [LocalFileEntry] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
        var enumerationError: Error?
        guard let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys),
            errorHandler: { _, error in enumerationError = error; return false }) else {
            throw LocalOperationError.unavailable("The skill folder cannot be read.")
        }
        let canonicalRoot = try LocalPath.canonicalize(root)
        var result: [LocalFileEntry] = []
        var bytes = 0
        while let url = iterator.nextObject() as? URL {
            try Task.checkCancellation()
            let properties = try url.resourceValues(forKeys: keys)
            guard properties.isSymbolicLink != true,
                  properties.isRegularFile == true || properties.isDirectory == true else {
                throw LocalOperationError.invalid("Skill packages must contain regular files and folders without symbolic links.")
            }
            let checked = try LocalPath.resolve(url.path, in: canonicalRoot, allowRoot: false)
            let count = properties.isDirectory == true ? 0 : properties.fileSize ?? 0
            bytes += count
            guard bytes <= packageLimit, result.count < entryLimit else {
                throw LocalOperationError.invalid("Skill packages must be under 50 MB and contain at most \(entryLimit) entries.")
            }
            result.append(.init(path: String(checked.path.dropFirst(canonicalRoot.path.count + 1)),
                                bytes: count, isDirectory: properties.isDirectory == true))
        }
        if let enumerationError { throw enumerationError }
        return result
    }

    private static func validateID(_ id: String) throws {
        guard id.range(of: #"^[a-zA-Z0-9][a-zA-Z0-9_-]{0,79}$"#, options: .regularExpression) != nil else {
            throw LocalOperationError.invalid("Use a skill identifier of letters, numbers, hyphens, or underscores (up to 80 characters).")
        }
    }
}
