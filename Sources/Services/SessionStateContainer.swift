import Foundation

/// Bundles all per-window services into a single container.
/// Each WindowGroup window gets its own container — enabling independent Claude CLI sessions,
/// token tracking, compaction, context state, and agents per window.
///
/// Global services (ThemeEngine, SoundManager, SharedIntelligence, etc.) remain singletons.
@MainActor
final class SessionStateContainer: ObservableObject {
    let process = ClaudeProcess()
    let contextManager = ContextStateManager()
    let compactionEngine: CompactionEngine
    let contextPipeline: ContextPreservationPipeline
    let budgetOptimizer: ContextBudgetOptimizer
    let sessionContinuity = SessionContinuity()
    let moodBoard = MoodBoardEngine()
    let orchestrator: AgentOrchestrator
    let messageBus = AgentMessageBus()
    let permissionManager = PermissionManager()

    init() {
        // Wire dependencies: CompactionEngine needs ContextStateManager
        compactionEngine = CompactionEngine(contextManager: contextManager)

        // BudgetOptimizer needs ContextStateManager
        budgetOptimizer = ContextBudgetOptimizer(contextManager: contextManager)

        // AgentOrchestrator needs its own MessageBus and PermissionManager
        orchestrator = AgentOrchestrator(messageBus: messageBus, permissionManager: permissionManager)

        // ContextPreservationPipeline needs both ContextStateManager and CompactionEngine
        contextPipeline = ContextPreservationPipeline(
            contextManager: contextManager,
            compactionEngine: compactionEngine
        )
    }
}
