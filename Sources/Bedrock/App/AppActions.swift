import AppKit
import Combine
import CryptoKit
import Foundation
import UniformTypeIdentifiers

@MainActor
enum AppActions {
    @discardableResult
    static func newThread(model: ChatModel, draft: String = "", workingDirectory: String? = nil,
                          skillIDs: [String] = [], systemPrompt: String = "", select: Bool = true) -> ChatModel {
        var result: ChatModel!
        ConversationStore.shared.createNewChat(modelId: model.id, modelName: model.name, modelProvider: model.provider) { result = $0 }
        let store = AppStore.shared
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
                let history = try await ConversationStore.shared.conversationSnapshot(for: chat.chatId)
                let messages = try messageID.map { try ConversationEditing.messages(in: history, through: $0) } ?? history.messages
                _ = try await branch(chat, messages: messages, originalSystemPrompt: history.systemPrompt)
            } catch { AppStore.shared.errorMessage = error.localizedDescription }
        }
    }

    @discardableResult
    static func branch(_ chat: ChatModel, messages: [Message], originalSystemPrompt: String? = nil,
                       model: ChatModel? = nil, select: Bool = true) async throws -> ChatModel {
        let store = AppStore.shared
        let metadata = store.thread(chat.chatId)
        let model = model ?? chat
        let prompt = metadata.systemPrompt.isEmpty ? originalSystemPrompt : metadata.systemPrompt
        let fork = try await ConversationStore.shared.createConversation(
            modelID: model.id, modelName: model.name, provider: model.provider, title: "\(chat.title) · branch",
            messages: messages, systemPrompt: prompt)
        store.updateThread(fork.chatId) {
            $0.parentThreadID = chat.chatId
            $0.workingDirectory = metadata.workingDirectory
            $0.skillIDs = metadata.skillIDs
            $0.systemPrompt = prompt ?? ""
        }
        if select { store.selectThread(fork.chatId); AppWindows.focusComposer() }
        return fork
    }

    static func copyThread(_ chat: ChatModel) {
        Task {
            do {
                let text = try await markdown(for: chat)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            } catch { AppStore.shared.errorMessage = error.localizedDescription }
        }
    }

    static func markdown(for chat: ChatModel) async throws -> String {
        let history = try await ConversationStore.shared.conversationSnapshot(for: chat.chatId)
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
                    let history = try await ConversationStore.shared.conversationSnapshot(for: chat.chatId)
                    let directory = URL(fileURLWithPath: PreferencesStore.shared.defaultDirectory).appendingPathComponent("generated_images")
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
                AppStore.shared.errorMessage = "Could not export the complete conversation: \(error.localizedDescription)"
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
                    let chat = try await ConversationStore.shared.createConversation(
                        modelID: archive.modelID, modelName: archive.modelName, provider: archive.provider,
                        title: archive.title, messages: archive.messages, systemPrompt: archive.systemPrompt,
                        lastMessageDate: archive.messages.map(\.timestamp).max())
                    let store = AppStore.shared
                    store.updateThread(chat.chatId) { $0.systemPrompt = archive.systemPrompt ?? "" }
                    store.selectThread(chat.chatId)
                    AppWindows.focusComposer()
                } catch {
                    AppStore.shared.errorMessage = "Could not import the conversation: \(error.localizedDescription)"
                }
            }
        }
    }

    static func validate(_ archive: ConversationArchive) throws {
        try ConversationArchiveCodec.validate(archive)
    }

    static func exportDiagnostics() {
        let store = AppStore.shared
        let report: [String: Any] = [
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development",
            "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
            "region": PreferencesStore.shared.selectedRegion.rawValue,
            "threads": ConversationStore.shared.chats.count,
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
        let records = AppStore.shared.state.runs.map { run -> [String: Any] in
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
                catch { AppStore.shared.errorMessage = error.localizedDescription }
            }
        }
    }

    private static func safeFilename(_ name: String) -> String {
        let value = name.replacingOccurrences(of: #"[/\\:\x00-\x1f]"#, with: "-", options: .regularExpression)
        return String(value.prefix(100))
    }
}
