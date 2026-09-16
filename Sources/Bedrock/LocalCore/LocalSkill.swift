import Foundation

struct LocalSkill: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var description: String
    var instructions: String
    var raw: String
    var url: URL
    var tags: [String] = []
    var requiredBinaries: [String] = []
    var anyBinaries: [String] = []
    var requiredEnvironment: [String] = []
    var platforms: [String] = []
    var enabledByDefault = true

    func unavailableReason(environment: [String: String] = ProcessInfo.processInfo.environment,
                           executableExists: (String) -> Bool = LocalSkill.executableExists) -> String? {
        if !platforms.isEmpty && !platforms.contains(where: { ["darwin", "macos", "mac"].contains($0.lowercased()) }) {
            return "This skill does not support macOS."
        }
        let missing = requiredBinaries.filter { !executableExists($0) }
        if !missing.isEmpty { return "Install required commands: \(missing.joined(separator: ", "))." }
        if !anyBinaries.isEmpty && !anyBinaries.contains(where: executableExists) {
            return "Install one of: \(anyBinaries.joined(separator: ", "))."
        }
        let missingEnvironment = requiredEnvironment.filter { environment[$0]?.isEmpty != false }
        if !missingEnvironment.isEmpty { return "Missing environment: \(missingEnvironment.joined(separator: ", "))." }
        return nil
    }

    static func executableExists(_ command: String) -> Bool {
        if command.contains("/") { return FileManager.default.isExecutableFile(atPath: command) }
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        return paths.contains { FileManager.default.isExecutableFile(atPath: URL(fileURLWithPath: $0).appendingPathComponent(command).path) }
    }

    static func parse(_ raw: String, id: String, url: URL) throws -> LocalSkill {
        guard raw.utf8.count <= 1_048_576 else { throw LocalWorkbenchError.tooLarge(1_048_576) }
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var fields: [String: String] = [:]
        var body = normalized
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            guard let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
                throw LocalWorkbenchError.invalid("The skill frontmatter is missing its closing --- line.")
            }
            fields = try parseFrontmatter(Array(lines[1..<end]))
            body = lines.dropFirst(end + 1).joined(separator: "\n")
        }
        body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw LocalWorkbenchError.invalid("Add instructions to this skill.") }
        let fallbackName = id.replacingOccurrences(of: "-", with: " ").capitalized
        let name = scalar(fields["name"] ?? fallbackName)
        guard !name.isEmpty else { throw LocalWorkbenchError.invalid("A skill needs a name.") }
        let description = scalar(fields["description"] ?? "")
        func values(_ key: String) -> [String] {
            let value = fields[key] ?? fields.first(where: { $0.key.hasSuffix("." + key) })?.value ?? ""
            return list(value)
        }
        return LocalSkill(
            id: id, name: name, description: description, instructions: body, raw: raw, url: url,
            tags: values("tags"),
            requiredBinaries: values("requires.bins").isEmpty ? values("requires") : values("requires.bins"),
            anyBinaries: values("requires.anyBins"), requiredEnvironment: values("requires.env"),
            platforms: values("platforms"), enabledByDefault: scalar(fields["enabled"] ?? "true").lowercased() != "false"
        )
    }

    /// Supports the scalar/list/multiline frontmatter used by local SKILL.md files.
    /// Nested metadata is flattened so OpenClaw-style `requires.bins` remains useful.
    private static func parseFrontmatter(_ lines: [String]) throws -> [String: String] {
        var fields: [String: String] = [:]
        var parents: [(indent: Int, key: String)] = []
        var lastKey: String?
        var index = 0
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let indent = line.prefix(while: { $0 == " " }).count
            if trimmed.isEmpty || trimmed.hasPrefix("#") { index += 1; continue }
            if trimmed.hasPrefix("- "), let lastKey {
                fields[lastKey, default: ""] += "\n" + String(trimmed.dropFirst(2))
                index += 1
                continue
            }
            guard let colon = trimmed.firstIndex(of: ":") else {
                throw LocalWorkbenchError.invalid("Invalid skill frontmatter near “\(trimmed.prefix(60))”.")
            }
            while let parent = parents.last, parent.indent >= indent { parents.removeLast() }
            let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            let path = (parents.map(\.key) + [key]).joined(separator: ".")
            lastKey = path
            if ["|", "|-", "|+", ">", ">-", ">+"].contains(value) {
                var block: [String] = []
                index += 1
                while index < lines.count {
                    let next = lines[index]
                    if !next.trimmingCharacters(in: .whitespaces).isEmpty &&
                        next.prefix(while: { $0 == " " }).count <= indent { break }
                    block.append(next.trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                fields[path] = block.joined(separator: value.hasPrefix(">") ? " " : "\n")
                continue
            }
            fields[path] = value
            if value.isEmpty { parents.append((indent, key)) }
            index += 1
        }
        return fields
    }

    private static func scalar(_ value: String) -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("\""), let data = value.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(String.self, from: data) { return decoded }
        if value.hasPrefix("'") && value.hasSuffix("'") {
            return String(value.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        return value
    }
    private static func list(_ value: String) -> [String] {
        var value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("[") && value.hasSuffix("]") { value = String(value.dropFirst().dropLast()) }
        return value.components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map(scalar).filter { !$0.isEmpty }
    }

    static func context(for selectedIDs: [String], skills: [LocalSkill], enabled: [String: Bool], limit: Int = 32_000,
                        unavailable: [String: String]? = nil) throws -> String {
        var sections: [String] = []
        for id in selectedIDs {
            guard let skill = skills.first(where: { $0.id == id }),
                  enabled[id] ?? skill.enabledByDefault else { continue }
            let reason = unavailable.map { $0[skill.id] } ?? skill.unavailableReason()
            if let reason { throw LocalWorkbenchError.unavailable("\(skill.name): \(reason)") }
            sections.append("<skill name=\"\(skill.name.replacingOccurrences(of: "\"", with: "'"))\">\n\(skill.instructions)\n</skill>")
        }
        let text = sections.joined(separator: "\n\n")
        guard text.count <= limit else {
            throw LocalWorkbenchError.invalid("The selected skills exceed the \(limit.formatted()) character budget. Select fewer skills or shorten their instructions.")
        }
        return text
    }

    static let bundled: [(id: String, source: String)] = [
        ("bedrock-demo", """
        ---
        name: Bedrock demo guide
        description: Explain a Bedrock capability with a small reproducible example.
        tags: [bedrock, demos]
        ---
        Help the user demonstrate Amazon Bedrock. State the selected model and any capability requirements. Prefer a small, concrete example with an observable result. Distinguish an actual tool result from an explanation. Never claim to have invoked AWS services or inspected files unless the corresponding tool result is available. Keep demo prompts concise and identify prerequisites before suggesting a paid operation.
        """),
        ("code-review", """
        ---
        name: Local code review
        description: Inspect local code and report actionable findings.
        tags: [code, review, local]
        ---
        Inspect the local path supplied by the user with the available read, list, search, and Git tools. Absolute and ~/ paths are supported without selecting a project. Read relevant source before drawing conclusions. Prioritize bugs, data loss, incorrect behavior, and missing validation. For each finding, name the file and line, explain a concrete trigger, and suggest the smallest appropriate fix. Do not modify files unless the user requests it. If the user has not supplied a path, use the working directory.
        """),
        ("document-analysis", """
        ---
        name: Document analysis
        description: Extract useful information grounded in attached documents.
        tags: [documents, analysis]
        ---
        Ground answers in the supplied documents. Cite page numbers or section titles when available. Separate direct observations from inference. Use tables for comparable figures, retain units and dates, and explicitly mark information the documents do not provide. Do not invent sources or summarize documents you have not received.
        """),
        ("skill-author", """
        ---
        name: Skill author
        description: Write a reusable local SKILL.md.
        tags: [skills, productivity]
        ---
        Help create a focused SKILL.md with YAML frontmatter containing name, description, and tags, followed by clear Markdown instructions. Describe when it applies, what inputs it needs, concrete steps, and how success is checked. Keep instructions useful across projects. Do not embed credentials or assume a cloud account integration. Refer to scripts and reference files with relative paths.
        """)
    ]

    /// Upgrade only an exact, unedited bundled file. User-authored workflows
    /// keep their content even when their ID matches a bundled skill.
    static func bundledUpgrade(id: String, source: String) -> String? {
        let original = """
        ---
        name: Local code review
        description: Inspect a local project and report actionable findings.
        tags: [code, review, local]
        ---
        Inspect the selected project with the available read, list, search, and Git tools. Read relevant source before drawing conclusions. Prioritize bugs, data loss, incorrect behavior, and missing validation. For each finding, name the file and line, explain a concrete trigger, and suggest the smallest appropriate fix. Do not modify files unless the user requests it. If no project is selected, ask the user to select a folder.
        """
        guard id == "code-review", source == original else { return nil }
        return bundled.first { $0.id == id }?.source
    }
}
