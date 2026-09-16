import Combine
import Foundation

/// The welcome composer exists before a conversation is created. Give its
/// attachments the same restart protection as a normal conversation draft.
@MainActor
final class ComposerDraft: ObservableObject {
    static let welcome = ComposerDraft()
    let media = AttachmentStore()
    @Published private(set) var isRestoring = true
    private let writer = ConversationAttachmentDraftWriter()
    private var revision: UInt64 = 0
    private var restored = false
    private var changedBeforeRestore = false
    private var canWrite = true
    private var restoreTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private let threadID = "new-thread"

    private init() {
        media.onAttachmentsChanged = { [weak self] in self?.changed() }
        restoreTask = Task { await restore() }
    }

    private func restore() async {
        defer { isRestoring = false }
        do {
            let url = try ConversationAttachmentDraftFile.url(threadID: threadID, directory: AppStore.shared.directory)
            let draft = try await Task.detached(priority: .userInitiated) { try ConversationAttachmentDraftFile.read(url) }.value
            if !draft.isEmpty { try await media.restoreAttachmentDraft(draft) }
            restored = true
            AppStore.shared.updateThread(threadID) { $0.hasDraftAttachments = !media.isEmpty }
            if changedBeforeRestore { changed() }
        } catch {
            restored = true
            canWrite = false
            AppStore.shared.errorMessage = "Could not restore the new-chat attachments. The saved draft was kept.\n\(error.localizedDescription)"
        }
    }

    private func changed() {
        guard restored else { changedBeforeRestore = true; return }
        revision &+= 1
        AppStore.shared.updateThread(threadID) { $0.hasDraftAttachments = !media.isEmpty }
        saveTask?.cancel()
        saveTask = Task {
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            _ = await persist()
        }
    }

    private func persist() async -> Bool {
        guard canWrite else { return false }
        do {
            let snapshot = try media.attachmentDraft()
            let url = try ConversationAttachmentDraftFile.url(threadID: threadID, directory: AppStore.shared.directory)
            try await writer.write(snapshot, to: url, revision: revision)
            return true
        } catch {
            AppStore.shared.errorMessage = "Could not save the new-chat attachments. Keep the app open and check the data folder.\n\(error.localizedDescription)"
            return false
        }
    }

    func flush() async -> Bool {
        await restoreTask?.value
        await media.waitForImports()
        saveTask?.cancel()
        return await persist()
    }

    func prepareForSending() async -> Bool {
        await restoreTask?.value
        await media.waitForImports()
        return canWrite
    }
}
