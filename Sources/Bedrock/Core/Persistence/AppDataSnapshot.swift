import Foundation

struct AppDataSnapshot: Codable, Sendable {
    var version = 1
    var projects: [LegacyProject] = []
    var threads: [String: ThreadMetadata] = [:]
    var preferences = AppPreferences()
    var skillEnabled: [String: Bool] = [:]
    var customDemos: [DemoPreset] = []
    var automations: [AutomationDefinition] = []
    var runs: [RunRecord] = []

    mutating func migrateLocalAccess() {
        preferences.migrateToolDefaults()
        // Retain old serialized project fields for rollback compatibility. Only
        // their working directory survives in active conversations and schedules.
        for id in Array(threads.keys) {
            if threads[id]?.workingDirectory == nil,
               let projectID = threads[id]?.projectID,
               let path = projects.first(where: { $0.id == projectID })?.path {
                threads[id]?.workingDirectory = path
            }
        }
        for index in automations.indices {
            if automations[index].workingDirectory == nil,
               let projectID = automations[index].projectID,
               let path = projects.first(where: { $0.id == projectID })?.path {
                automations[index].workingDirectory = path
            }
        }
    }
}
