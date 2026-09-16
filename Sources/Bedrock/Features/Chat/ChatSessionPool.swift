import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ChatSessionPool {
    static let shared = ChatSessionPool()
    private var sessions: [String: ChatViewModel] = [:]
    private var recentlyUsed: [String] = []
    private var retiring: [String: UUID] = [:]

    func session(chatID: String, backend: BedrockConnection) -> ChatViewModel {
        recentlyUsed.removeAll { $0 == chatID }
        recentlyUsed.append(chatID)
        if let existing = sessions[chatID] {
            retiring.removeValue(forKey: chatID)
            existing.retainSession()
            return existing
        }
        let session = ChatViewModel(chatId: chatID, backendModel: backend, sharedMediaDataSource: AttachmentStore())
        session.loadInitialData()
        sessions[chatID] = session
        for id in recentlyUsed.dropLast(8) {
            guard retiring[id] == nil, let existing = sessions[id], !existing.isSending, existing.sharedMediaDataSource.isEmpty,
                  !existing.sharedMediaDataSource.isImporting, existing.outbox.queued.isEmpty,
                  existing.outbox.inFlight == nil, !existing.isSavingLocalWork else { continue }
            // Evicting a view model is not a user request to stop that chat's
            // background command. The registry retains it across tool turns.
            existing.discardSession(stopProcesses: false)
            sessions.removeValue(forKey: id)
        }
        recentlyUsed.removeAll { sessions[$0] == nil }
        return session
    }
    func remove(_ id: String) {
        guard let session = sessions[id] else { return }
        let token = UUID()
        retiring[id] = token
        Task {
            let saved = await session.flushLocalWork(stopRun: true)
            guard retiring[id] == token else { return }
            retiring.removeValue(forKey: id)
            if saved { forget(id) }
        }
    }
    func forget(_ id: String) {
        sessions[id]?.discardSession()
        sessions.removeValue(forKey: id)
        retiring.removeValue(forKey: id)
        recentlyUsed.removeAll { $0 == id }
    }
    func isSavingLocalWork(_ id: String) -> Bool {
        retiring[id] != nil || sessions[id]?.isSavingLocalWork == true || sessions[id]?.sharedMediaDataSource.isImporting == true
    }
    func prepareToTerminate() async -> Bool {
        var saved = true
        for session in Array(sessions.values) {
            if !(await session.flushLocalWork(stopRun: true)) { saved = false }
        }
        if !saved { resumeAfterCancelledQuit() }
        return saved
    }
    func resumeAfterCancelledQuit() {
        for session in sessions.values { session.retainSession() }
    }
    func flushDrafts() async -> Bool {
        var saved = true
        for session in Array(sessions.values) {
            if !(await session.flushLocalWork()) { saved = false }
        }
        return saved
    }
}
