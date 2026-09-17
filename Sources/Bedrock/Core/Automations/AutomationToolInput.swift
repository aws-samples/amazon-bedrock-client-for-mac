import Foundation

/// Tool requests and the editor share AutomationDefinition's validation and
/// AutomationScheduler's save operation. Updating a schedule preserves its ID,
/// run history and fields omitted by the caller.
enum AutomationToolInput {
    static func apply(_ input: JSONValue, to existing: [AutomationDefinition], defaultModelID: String) throws -> AutomationDefinition {
        guard case .object(let values) = input else { throw LocalOperationError.invalid("Expected an automation object.") }
        let allowed: Set<String> = ["id", "name", "prompt", "model_id", "working_directory", "skill_ids",
            "cadence", "enabled", "time_zone", "run_at", "interval_minutes", "maximum_runtime_seconds",
            "weekdays", "active_start", "active_end"]
        guard Set(values.keys).isSubset(of: allowed) else { throw LocalOperationError.invalid("Unknown automation field.") }
        func string(_ key: String) throws -> String? {
            guard let value = values[key] else { return nil }
            guard case .string(let text) = value else { throw LocalOperationError.invalid("\(key) must be text.") }
            return text
        }
        func integer(_ key: String) throws -> Int? {
            guard let value = values[key] else { return nil }
            guard case .number(let number) = value, let result = Int(exactly: number) else {
                throw LocalOperationError.invalid("\(key) must be an integer.")
            }
            return result
        }
        var result: AutomationDefinition
        if let value = try string("id") {
            guard let id = UUID(uuidString: value), let found = existing.first(where: { $0.id == id }) else {
                throw LocalOperationError.invalid("Use an existing automation ID from local_list_automations.")
            }
            result = found
        } else {
            result = .init(name: "", prompt: "", modelID: defaultModelID)
        }
        if let value = try string("name") { result.name = value }
        if let value = try string("prompt") { result.prompt = value }
        if let value = try string("model_id") { result.modelID = value }
        if let value = try string("working_directory") { result.workingDirectory = value.isEmpty ? nil : value }
        if let value = try string("time_zone") { result.timeZoneIdentifier = value.isEmpty ? nil : value }
        if let value = try string("cadence") {
            guard let cadence = AutomationCadence(rawValue: value) else { throw LocalOperationError.invalid("Cadence must be once, interval, or daily.") }
            result.cadence = cadence
        }
        if let value = values["enabled"] {
            guard case .bool(let enabled) = value else { throw LocalOperationError.invalid("enabled must be true or false.") }
            result.enabled = enabled
        }
        if let value = try string("run_at") {
            guard let date = ISO8601DateFormatter().date(from: value) else { throw LocalOperationError.invalid("run_at must be an ISO-8601 timestamp with a time zone.") }
            result.scheduledAt = date
        }
        if let value = try integer("interval_minutes") { result.intervalMinutes = value }
        if let value = try integer("maximum_runtime_seconds") { result.maximumRuntime = value }
        if let value = values["skill_ids"] {
            guard case .array(let array) = value, array.count <= 100 else { throw LocalOperationError.invalid("skill_ids must be an array of skill IDs.") }
            result.skillIDs = try array.map {
                guard case .string(let id) = $0, !id.isEmpty else { throw LocalOperationError.invalid("Use nonempty skill IDs.") }
                return id
            }
        }
        if let value = values["weekdays"] {
            guard case .array(let array) = value else { throw LocalOperationError.invalid("weekdays must be an array.") }
            result.weekdays = Set(try array.map {
                guard case .number(let number) = $0, let day = Int(exactly: number), (1...7).contains(day) else {
                    throw LocalOperationError.invalid("Use weekday numbers 1 (Sunday) through 7 (Saturday).")
                }
                return day
            })
        }
        func minute(_ key: String) throws -> Int? {
            guard let value = try string(key) else { return nil }
            let pieces = value.split(separator: ":", omittingEmptySubsequences: false)
            guard pieces.count == 2, let hour = Int(pieces[0]), let minute = Int(pieces[1]),
                  (0..<24).contains(hour), (0..<60).contains(minute) else {
                throw LocalOperationError.invalid("\(key) must use HH:mm.")
            }
            return hour * 60 + minute
        }
        if let value = try minute("active_start") { result.activeStartMinute = value }
        if let value = try minute("active_end") { result.activeEndMinute = value }
        guard result.name.count <= 200, result.prompt.utf8.count <= 200_000, result.modelID.count <= 512 else {
            throw LocalOperationError.invalid("The name, prompt, or model ID exceeds the automation limit.")
        }
        if let error = result.validationError { throw LocalOperationError.invalid(error) }
        return result
    }

    static func describe(_ items: [AutomationDefinition]) throws -> String {
        struct Item: Encodable {
            var id: UUID
            var name: String
            var promptPreview: String
            var modelID: String
            var cadence: AutomationCadence
            var enabled: Bool
            var timeZone: String
            var nextRunAt: Date?
            var lastStatus: RunStatus?
        }
        let records = items.map {
            Item(id: $0.id, name: $0.name, promptPreview: String($0.prompt.prefix(300)),
                 modelID: $0.modelID, cadence: $0.cadence, enabled: $0.enabled,
                 timeZone: $0.timeZone.identifier, nextRunAt: $0.nextRunAt, lastStatus: $0.lastStatus)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return String(decoding: try encoder.encode(records), as: UTF8.self)
    }
}
