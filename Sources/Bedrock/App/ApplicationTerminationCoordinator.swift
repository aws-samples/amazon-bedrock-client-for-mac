import AppKit

/// Keep AppKit's normal event loop alive while asynchronous saves finish.
/// A deferred termination loop does not reliably service Swift concurrency tasks.
@MainActor
final class ApplicationTerminationCoordinator {
    private enum State { case idle, preparing, approved }
    private var state: State = .idle
    private var task: Task<Void, Never>?
    private let prepare: @MainActor () async -> Bool
    private let cancelled: @MainActor () -> Void
    init(prepare: @escaping @MainActor () async -> Bool,
         cancelled: @escaping @MainActor () -> Void) {
        self.prepare = prepare
        self.cancelled = cancelled
    }

    func shouldTerminate() -> NSApplication.TerminateReply {
        if state == .approved { return .terminateNow }
        guard state == .idle else { return .terminateCancel }
        state = .preparing
        task = Task { [weak self] in
            guard let self else { return }
            let saved = await prepare()
            task = nil
            guard saved else {
                state = .idle
                cancelled()
                return
            }
            state = .approved
            NSApp.terminate(nil)
        }
        // .terminateLater enters AppKit's termination loop before Task can run.
        // Cancel this request and issue a fresh, synchronous approval after saving.
        return .terminateCancel
    }
}
