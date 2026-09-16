import Combine
import Foundation

@MainActor
final class AutomationScheduler: ObservableObject {
    static let shared = AutomationScheduler()
    @Published private(set) var running: [UUID: String] = [:]
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var ticker: Task<Void, Never>?
    private var backend: BedrockConnection?

    func start(backend: BedrockConnection) {
        self.backend = backend
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
    }
    func save(_ automation: AutomationDefinition) throws {
        if let error = automation.validationError { throw LocalOperationError.invalid(error) }
        var automation = automation
        automation.nextRunAt = automation.enabled ? automation.nextDate(after: Date()) : nil
        let store = AppStore.shared
        if let index = store.state.automations.firstIndex(where: { $0.id == automation.id }) { store.state.automations[index] = automation }
        else { store.state.automations.append(automation) }
        store.flush()
    }
    func setEnabled(_ id: UUID, enabled: Bool) {
        let store = AppStore.shared
        guard let index = store.state.automations.firstIndex(where: { $0.id == id }) else { return }
        store.state.automations[index].enabled = enabled
        store.state.automations[index].nextRunAt = enabled ? store.state.automations[index].nextDate(after: Date()) : nil
    }
    func stop(_ id: UUID) {
        tasks[id]?.cancel()
        if let thread = running[id], let backend { ChatSessionPool.shared.session(chatID: thread, backend: backend).cancelSending() }
    }
    func runNow(_ automation: AutomationDefinition) {
        guard tasks[automation.id] == nil, let backend else { return }
        tasks[automation.id] = Task { [weak self] in
            guard let self else { return }
            defer { self.tasks.removeValue(forKey: automation.id); self.running.removeValue(forKey: automation.id) }
            let store = AppStore.shared
            let model = ModelCatalog.shared.models.first { $0.id == automation.modelID } ??
                ChatModel(id: automation.modelID, chatId: automation.modelID, name: automation.modelID, title: automation.name,
                          description: automation.modelID, provider: "Bedrock", lastMessageDate: Date())
            let chat = AppActions.newThread(model: model, draft: automation.prompt, workingDirectory: automation.workingDirectory,
                                                  skillIDs: automation.skillIDs, select: false)
            ConversationStore.shared.updateChatTitle(for: chat.chatId, title: automation.name, isManualRename: true)
            running[automation.id] = chat.chatId
            let session = ChatSessionPool.shared.session(chatID: chat.chatId, backend: backend)
            session.nextAutomationID = automation.id
            await session.waitUntilReady()
            session.sendMessage()
            var status: RunStatus = .running
            let deadline = Date().addingTimeInterval(TimeInterval(automation.maximumRuntime))
            while session.isSending {
                if Task.isCancelled { status = .cancelled; session.cancelSending(); break }
                if Date() >= deadline { status = .timedOut; session.cancelSending(); break }
                try? await Task.sleep(for: .milliseconds(500))
            }
            if status != .running {
                // Allow the inference/tool cancellation handler to finish its atomic history write.
                let settle = Task { @MainActor in
                    for _ in 0..<100 where session.isSending { try? await Task.sleep(for: .milliseconds(100)) }
                }
                await settle.value
            }
            if let runID = session.activeRunID {
                if status == .running { status = store.state.runs.first { $0.id == runID }?.status ?? .failed }
                else { store.finishRun(runID, status: status, error: status == .timedOut ? "Automation reached its runtime limit." : nil) }
            } else {
                status = .failed
                let runID = store.beginRun(threadID: chat.chatId, modelID: model.id, title: automation.name, automationID: automation.id)
                store.finishRun(runID, status: .failed, error: store.errorMessage ?? "The automation could not start.")
            }
            if let index = store.state.automations.firstIndex(where: { $0.id == automation.id }) {
                store.state.automations[index].lastRunAt = Date()
                store.state.automations[index].lastThreadID = chat.chatId
                store.state.automations[index].lastStatus = status
            }
            store.flush()
        }
    }
    private func tick() {
        let store = AppStore.shared
        guard store.preferences.automationsEnabled, !store.isRelocating else { return }
        let now = Date()
        for automation in store.state.automations where automation.enabled {
            guard let index = store.state.automations.firstIndex(where: { $0.id == automation.id }) else { continue }
            guard let next = automation.nextRunAt else {
                store.state.automations[index].nextRunAt = automation.nextDate(after: now)
                continue
            }
            guard next <= now else { continue }
            store.state.automations[index].nextRunAt = automation.nextDate(after: now)
            if automation.cadence == .once { store.state.automations[index].enabled = false }
            store.flush()
            // Skip missed work after sleep. Never replay each missed interval or overlap a run.
            if now.timeIntervalSince(next) <= 300, tasks[automation.id] == nil { runNow(automation) }
        }
    }
}
