import AppKit
import Combine
import CryptoKit
import Foundation
import UniformTypeIdentifiers

@MainActor
enum WorkbenchActions {
    @discardableResult
    static func newThread(model: ChatModel, draft: String = "", workingDirectory: String? = nil,
                          skillIDs: [String] = [], systemPrompt: String = "", select: Bool = true) -> ChatModel {
        var result: ChatModel!
        ChatManager.shared.createNewChat(modelId: model.id, modelName: model.name, modelProvider: model.provider) { result = $0 }
        let store = WorkbenchStore.shared
        store.updateThread(result.chatId) {
            $0.draft = draft
            $0.workingDirectory = workingDirectory
            $0.skillIDs = skillIDs
            $0.systemPrompt = systemPrompt
        }
        if select { store.selectThread(result.chatId) }
        return result
    }

    static func fork(_ chat: ChatModel, through messageID: UUID? = nil) {
        Task {
            do {
                let history = try await ChatManager.shared.conversationSnapshot(for: chat.chatId)
                let messages = try messageID.map { try ConversationEditing.messages(in: history, through: $0) } ?? history.messages
                _ = try await branch(chat, messages: messages, originalSystemPrompt: history.systemPrompt)
            } catch { WorkbenchStore.shared.errorMessage = error.localizedDescription }
        }
    }

    @discardableResult
    static func branch(_ chat: ChatModel, messages: [Message], originalSystemPrompt: String? = nil,
                       model: ChatModel? = nil, select: Bool = true) async throws -> ChatModel {
        let store = WorkbenchStore.shared
        let metadata = store.thread(chat.chatId)
        let model = model ?? chat
        let prompt = metadata.systemPrompt.isEmpty ? originalSystemPrompt : metadata.systemPrompt
        let fork = try await ChatManager.shared.createConversation(
            modelID: model.id, modelName: model.name, provider: model.provider, title: "\(chat.title) · branch",
            messages: messages, systemPrompt: prompt)
        store.updateThread(fork.chatId) {
            $0.parentThreadID = chat.chatId
            $0.workingDirectory = metadata.workingDirectory
            $0.skillIDs = metadata.skillIDs
            $0.systemPrompt = prompt ?? ""
        }
        if select { store.selectThread(fork.chatId); WorkbenchWindows.focusComposer() }
        return fork
    }

    static func copyThread(_ chat: ChatModel) {
        Task {
            do {
                let text = try await markdown(for: chat)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            } catch { WorkbenchStore.shared.errorMessage = error.localizedDescription }
        }
    }

    static func markdown(for chat: ChatModel) async throws -> String {
        let history = try await ChatManager.shared.conversationSnapshot(for: chat.chatId)
        let title = chat.title, name = chat.name, modelID = chat.id
        return try await Task.detached(priority: .userInitiated) {
            try ConversationEditing.markdown(title: title, modelName: name, modelID: modelID, messages: history.messages)
        }.value
    }

    static func exportThread(_ chat: ChatModel, asJSON: Bool) {
        Task {
            do {
                let data: Data
                if asJSON {
                    let history = try await ChatManager.shared.conversationSnapshot(for: chat.chatId)
                    let directory = URL(fileURLWithPath: SettingManager.shared.defaultDirectory).appendingPathComponent("generated_images")
                    let archive = ConversationArchive(title: chat.title, modelID: chat.id, modelName: chat.name,
                                                      provider: chat.provider, messages: history.messages, systemPrompt: history.systemPrompt)
                    data = try await Task.detached(priority: .userInitiated) {
                        var archive = archive
                        for index in archive.messages.indices {
                            try Task.checkCancellation()
                            archive.messages[index].imageBase64Strings = try archive.messages[index].imageBase64Strings?.map {
                                try LocalImageReference.read($0, directory: directory).base64EncodedString()
                            }
                            // Keep the S3 reference; local playback paths are not portable.
                            archive.messages[index].videoUrl = nil
                        }
                        return try ConversationArchiveCodec.encode(archive)
                    }.value
                } else {
                    data = Data(try await markdown(for: chat).utf8)
                }
                save(data: data, filename: safeFilename(chat.title) + (asJSON ? ".json" : ".md"), type: asJSON ? .json : .plainText)
            } catch {
                WorkbenchStore.shared.errorMessage = "Could not export the complete conversation: \(error.localizedDescription)"
            }
        }
    }

    static func importThread() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.prompt = "Import thread"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task {
                do {
                    let archive = try await Task.detached(priority: .userInitiated) {
                        var archive = try ConversationArchiveCodec.read(url)
                        for index in archive.messages.indices { archive.messages[index].videoUrl = nil }
                        return archive
                    }.value
                    let chat = try await ChatManager.shared.createConversation(
                        modelID: archive.modelID, modelName: archive.modelName, provider: archive.provider,
                        title: archive.title, messages: archive.messages, systemPrompt: archive.systemPrompt)
                    let store = WorkbenchStore.shared
                    store.updateThread(chat.chatId) { $0.systemPrompt = archive.systemPrompt ?? "" }
                    store.selectThread(chat.chatId)
                    WorkbenchWindows.focusComposer()
                } catch {
                    WorkbenchStore.shared.errorMessage = "Could not import the conversation: \(error.localizedDescription)"
                }
            }
        }
    }

    static func validate(_ archive: ConversationArchive) throws {
        try ConversationArchiveCodec.validate(archive)
    }

    static func exportDiagnostics() {
        let store = WorkbenchStore.shared
        let report: [String: Any] = [
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development",
            "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
            "region": SettingManager.shared.selectedRegion.rawValue,
            "threads": ChatManager.shared.chats.count,
            "skills": store.skills.count,
            "runs": store.state.runs.count,
            "toolProfile": store.preferences.toolProfile.rawValue,
            "enabledTools": store.preferences.enabledTools.map(\.rawValue).sorted(),
            "storage": "local",
            "generatedAt": Date().ISO8601Format()
        ]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            save(data: data, filename: "bedrock-diagnostics.json", type: .json)
        }
    }

    static func exportActivity() {
        let records = WorkbenchStore.shared.state.runs.map { run -> [String: Any] in
            // No prompts, titles, project paths, credentials or provider error bodies.
            var record: [String: Any] = [
                "id": run.id.uuidString, "model": run.modelID, "status": run.status.rawValue,
                "startedAt": run.startedAt.ISO8601Format(), "toolCalls": run.toolCalls
            ]
            record["inputTokens"] = run.inputTokens
            record["outputTokens"] = run.outputTokens
            record["cacheReadTokens"] = run.cacheReadTokens
            record["cacheWriteTokens"] = run.cacheWriteTokens
            record["durationSeconds"] = run.duration
            return record
        }
        if let data = try? JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]) {
            save(data: data, filename: "bedrock-activity.json", type: .json)
        }
    }

    static func exportDemo(_ demo: DemoPreset) {
        if let data = try? JSONEncoder().encode(demo) { save(data: data, filename: safeFilename(demo.title) + ".json", type: .json) }
    }

    static func save(data: Data, filename: String, type: UTType) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = filename
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task {
                do { try await Task.detached(priority: .userInitiated) { try data.write(to: url, options: .atomic) }.value }
                catch { WorkbenchStore.shared.errorMessage = error.localizedDescription }
            }
        }
    }

    private static func safeFilename(_ name: String) -> String {
        let value = name.replacingOccurrences(of: #"[/\\:\x00-\x1f]"#, with: "-", options: .regularExpression)
        return String(value.prefix(100))
    }
}

@MainActor
final class WorkbenchModelCatalog: ObservableObject {
    static let shared = WorkbenchModelCatalog()
    @Published var models: [ChatModel] = []
    @Published private(set) var organized: [String: [ChatModel]] = [:]
    @Published private(set) var descriptors: [BedrockModelDescriptor] = []
    @Published private(set) var refreshedAt: Date?
    @Published var isLoading = false
    @Published var errorMessage: String?
    private var requestID = UUID()
    private var activeIdentity: String?
    private struct Cache: Codable {
        var updatedAt: Date
        var descriptors: [BedrockModelDescriptor]
    }
    var foundationModels: [BedrockModelDescriptor] {
        descriptors.filter { !$0.isProfile }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    func descriptor(_ id: String) -> BedrockModelDescriptor? {
        descriptors.first { $0.id == id } ?? descriptors.first { $0.id == BedrockModelID.base(id) }
    }
    func model(_ id: String) -> ChatModel {
        models.first { $0.id == id } ?? ChatModel(id: id, chatId: id, name: descriptor(id)?.name ?? id,
            title: descriptor(id)?.name ?? id, description: id, provider: descriptor(id)?.provider ?? BedrockModelID.providerName(id), lastMessageDate: Date())
    }
    func invocationModel(_ descriptor: BedrockModelDescriptor) -> ChatModel {
        model(BedrockCapabilityRegistry.shared.invocationID(descriptor.id, region: SettingManager.shared.selectedRegion.rawValue))
    }
    var defaultModel: ChatModel? {
        let settings = SettingManager.shared
        let requested = settings.defaultModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !requested.isEmpty, !BedrockModelID.isLegacy(requested),
           descriptor(requested)?.isLegacy != true {
            // An explicit custom model/profile ARN must remain usable even when
            // the caller lacks permission to list the catalog.
            if let descriptor = descriptor(requested), !descriptor.isProfile { return invocationModel(descriptor) }
            return model(requested)
        }
        return models.first { settings.favoriteModelIds.contains($0.id) && descriptor($0.id)?.isConversation == true }
            ?? models.first { $0.name.localizedStandardContains("Sonnet") && $0.id.hasPrefix("global.") }
            ?? models.first { $0.id.contains("nova-micro") }
            ?? models.first { descriptor($0.id)?.isConversation == true }
    }

    func refresh(backend: Backend) async {
        if WorkbenchValidationMode.isOffline {
            install(BedrockBundledCatalog.records.flatMap { $0.descriptors(in: backend.region) } +
                    BedrockMantleCatalog.descriptors(in: backend.region), region: backend.region)
            errorMessage = nil
            return
        }
        let id = UUID()
        requestID = id
        isLoading = true
        defer { if requestID == id { isLoading = false } }
        errorMessage = nil
        let settings = SettingManager.shared
        let region = backend.region
        let identity = "\(region)|\(backend.profile)|\(backend.endpoint)|\(backend.runtimeEndpoint)|\(settings.bedrockApiKey.isEmpty)"
        let hash = SHA256.hash(data: Data(identity.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        let file = LocalJSONFile<Cache>(url: WorkbenchStore.shared.directory.appendingPathComponent("model-catalog-\(hash).json"))
        if activeIdentity != identity {
            activeIdentity = identity
            if let cached = try? file.load() {
                install(cached.descriptors, region: region)
                refreshedAt = cached.updatedAt
            } else {
                install(BedrockBundledCatalog.records.flatMap { $0.descriptors(in: region) } + BedrockMantleCatalog.descriptors(in: region), region: region)
                refreshedAt = nil
            }
        }
        async let foundations = backend.listFoundationModels()
        async let profiles = backend.listInferenceProfilesResult()
        let (foundationResult, profileResult) = await (foundations, profiles)
        guard requestID == id, !Task.isCancelled else { return }
        var warnings: [String] = []
        var entries: [BedrockModelDescriptor]
        switch foundationResult {
        case .success(let summaries):
            entries = summaries.compactMap { summary in
                guard let id = summary.modelId, !id.isEmpty else { return nil }
                return BedrockModelDescriptor(id: id, name: summary.modelName ?? id,
                    provider: summary.providerName ?? BedrockModelID.providerName(id),
                    inputModalities: summary.inputModalities?.map(\.rawValue) ?? [],
                    outputModalities: summary.outputModalities?.map(\.rawValue) ?? [],
                    inferenceTypes: summary.inferenceTypesSupported?.map(\.rawValue) ?? [],
                    streaming: summary.responseStreamingSupported, lifecycle: summary.modelLifecycle?.status?.rawValue)
            }
        case .failure(let error):
            entries = descriptors.filter { !$0.isProfile && $0.origin == .runtime }
            warnings.append("Model refresh: \(error.localizedDescription)")
        }
        let foundationsByID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        switch profileResult {
        case .success(let summaries):
            entries += summaries.compactMap { profile in
                guard let id = profile.inferenceProfileId, profile.status?.rawValue == "ACTIVE" else { return nil }
                let foundationID = profile.models?.first?.modelArn.map(BedrockModelID.base) ?? BedrockModelID.base(id)
                let foundation = foundationsByID[foundationID]
                return BedrockModelDescriptor(id: id, name: foundation?.name ?? profile.inferenceProfileName ?? id,
                    provider: foundation?.provider ?? BedrockModelID.providerName(foundationID),
                    inputModalities: foundation?.inputModalities ?? [],
                    outputModalities: foundation?.outputModalities ?? [],
                    inferenceTypes: ["INFERENCE_PROFILE"], streaming: foundation?.streaming,
                    foundationID: foundationID, isProfile: true, lifecycle: foundation?.lifecycle)
            }
        case .failure(let error):
            entries += descriptors.filter { $0.isProfile }
            warnings.append("Inference profile refresh: \(error.localizedDescription)")
        }
        entries += BedrockMantleCatalog.descriptors(in: region)
        install(entries, region: region)
        if warnings.isEmpty {
            refreshedAt = Date()
            do { try file.save(Cache(updatedAt: refreshedAt!, descriptors: descriptors)) }
            catch { warnings.append("Could not save the local model catalog: \(error.localizedDescription)") }
        }
        errorMessage = warnings.isEmpty ? nil : warnings.joined(separator: "\n")
    }

    private func install(_ entries: [BedrockModelDescriptor], region: String) {
        var seen = Set<String>()
        descriptors = entries.filter { !$0.isLegacy && !$0.id.isEmpty && seen.insert($0.id).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        BedrockCapabilityRegistry.shared.replace(region: region, descriptors: descriptors)
        models = descriptors.filter { !$0.needsProvisionedThroughput }.map {
            ChatModel(id: $0.id, chatId: $0.id, name: $0.name, title: $0.name,
                      description: $0.id, provider: $0.provider, lastMessageDate: Date())
        }
        organized = Dictionary(grouping: models, by: \.provider)
        SettingManager.shared.availableModels = models
    }
}
