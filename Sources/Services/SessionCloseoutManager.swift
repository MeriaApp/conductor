import Foundation

/// Manages graceful session closeout — sends a structured prompt to Claude
/// asking it to commit changes and write a summary, then calls completion.
@MainActor
final class SessionCloseoutManager: ObservableObject {

    @Published var isClosingOut = false
    @Published var closeoutStatus = "Closing session..."

    /// Deterministic closeout prompt — no conversational fluff
    static let closeoutPrompt = """
    [SESSION CLOSEOUT] This session is ending. Please:
    1. Check for uncommitted changes — commit with appropriate messages
    2. Update CONTEXT_STATE.md
    3. Write 3-bullet summary: Where we are / What's next / First action tomorrow
    Be concise. Automated closeout — no conversational text needed.
    """

    private var timeoutTask: Task<Void, Never>?
    private var originalOnResult: ((ResultEvent) -> Void)?

    /// Graceful closeout: interrupt streaming, persist artifacts, call completion.
    /// Does NOT send a Claude prompt — avoids wasting a full context-window read (~160K tokens)
    /// just for "please commit and summarize". Artifacts are already auto-saved every turn.
    func beginCloseout(process: ClaudeProcess, completion: @escaping () -> Void) {
        guard !isClosingOut else {
            // Already closing — second click means "just close now"
            completion()
            return
        }

        // Nothing to close out if no conversation happened
        guard process.isRunning, !process.messages.isEmpty else {
            completion()
            return
        }

        isClosingOut = true
        closeoutStatus = "Saving session..."

        // If Claude is mid-stream, interrupt first
        if process.isStreaming {
            closeoutStatus = "Interrupting current response..."
            process.interrupt()
        }

        // Immediate completion — artifacts already persisted via onResult auto-save
        finishCloseout(completion: completion)
    }

    /// Quick save — immediate artifact persistence without Claude prompt (for Cmd+Q)
    func quickSave(session: Session?, process: ClaudeProcess, sessionContinuity: SessionContinuity, contextManager: ContextStateManager, sessionManager: SessionManager) {
        guard let session else { return }
        sessionContinuity.saveSessionEnd(
            sessionId: session.id,
            projectPath: session.projectPath,
            process: process,
            contextManager: contextManager
        )
        sessionManager.endSession(id: session.id, messages: process.messages)
    }

    private func finishCloseout(completion: @escaping () -> Void) {
        guard isClosingOut else { return }
        timeoutTask?.cancel()
        timeoutTask = nil
        isClosingOut = false
        closeoutStatus = ""
        // Don't restore onResult — the window is closing
        completion()
    }
}
