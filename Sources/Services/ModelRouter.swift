import Foundation

/// Smart model routing — suggests the best model per task
/// Opus is always default. Only suggests switching when another model is genuinely better.
/// Jesse's rule: Opus default. Only switch when better, never for cost.
@MainActor
final class ModelRouter: ObservableObject {
    static let shared = ModelRouter()

    @Published var suggestion: ModelSuggestion?
    @Published var isEnabled: Bool = true
    /// Auto-apply model suggestions (enabled by default for simple lookups)
    @Published var autoApply: Bool = true
    /// Last auto-applied suggestion (for brief UI toast)
    @Published var lastAutoApplied: ModelSuggestion?

    static let autoApplyMinConfidence: Double = 0.85

    private init() {}

    /// Analyze a message and context to determine if a model switch would be beneficial
    func analyze(message: String, context: RoutingContext) -> ModelSuggestion? {
        guard isEnabled else { return nil }

        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let wordCount = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.count

        // Rule 1: Very short conversational messages → Haiku (acknowledgments, confirmations, corrections)
        if wordCount <= 8 && isConversational(trimmed) {
            return ModelSuggestion(
                model: .haiku,
                reason: "Short conversational message — Haiku is 10x cheaper",
                confidence: 0.85
            )
        }

        // Rule 2: Short simple lookups → Haiku (10x faster, equally accurate for simple tasks)
        if wordCount <= 20 && isSimpleLookup(trimmed) {
            return ModelSuggestion(
                model: .haiku,
                reason: "Simple lookup — Haiku is 10x faster",
                confidence: 0.75
            )
        }

        // Rule 3: Medium-complexity questions without code work → Sonnet
        if wordCount <= 30 && !isComplexWork(trimmed) && !isSimpleLookup(trimmed) {
            return ModelSuggestion(
                model: .sonnet,
                reason: "General question — Sonnet handles this efficiently",
                confidence: 0.72
            )
        }

        // Rule 4: High context pressure → Sonnet (handles compacted context efficiently)
        if context.contextPercentage > 0.80 {
            return ModelSuggestion(
                model: .sonnet,
                reason: "Context pressure — Sonnet handles compacted context well",
                confidence: 0.72
            )
        }

        // Rule 5: Agent team spawning (3+ agents) → Sonnet for sub-agents
        if context.agentCount >= 3 && context.isSubAgent {
            return ModelSuggestion(
                model: .sonnet,
                reason: "Parallel agents — Sonnet handles parallel work efficiently",
                confidence: 0.75
            )
        }

        // Default: Stay on Opus — the best model for architecture, reasoning, debugging, creative work
        return nil
    }

    /// Accept the current suggestion and apply it
    func acceptSuggestion(process: Any?) {
        guard let suggestion = suggestion else { return }
        // The caller (AppShell) handles actually setting process.selectedModel
        self.suggestion = nil
        _ = suggestion // Used by caller
    }

    /// Dismiss the current suggestion without applying
    func dismissSuggestion() {
        suggestion = nil
    }

    // MARK: - Pattern Detection

    /// Short conversational messages that don't need Opus-level reasoning
    private func isConversational(_ message: String) -> Bool {
        let patterns = [
            "yes", "no", "ok", "okay", "sure", "go ahead", "do it",
            "wait", "stop", "continue", "next", "skip", "done",
            "thanks", "thank you", "got it", "perfect", "great",
            "sounds good", "looks good", "lgtm", "ship it",
            "go for it", "let's do it", "proceed", "yep", "nope",
            "i meant", "i said", "never mind", "nvm",
            "what's up", "what?", "why?", "how?", "huh",
        ]
        return patterns.contains { message.hasPrefix($0) || message == $0 }
    }

    /// Detects messages that require deep reasoning (architecture, debugging, multi-file changes)
    private func isComplexWork(_ message: String) -> Bool {
        let patterns = [
            "refactor", "architect", "design", "implement", "build",
            "debug", "fix", "investigate", "analyze", "optimize",
            "rewrite", "restructure", "migrate", "upgrade",
            "create a", "write a", "add a feature", "make a",
            "deploy", "test", "audit", "review the",
            "explain how", "help me understand", "walk me through",
            "multi-file", "across the codebase", "all files",
        ]
        return patterns.contains { message.contains($0) }
    }

    private func isSimpleLookup(_ message: String) -> Bool {
        let lookupPatterns = [
            "what is", "what's in", "what are", "what does",
            "list the", "list all", "show me", "show the",
            "check if", "check the", "check whether",
            "how many", "how much",
            "where is", "where are", "where does",
            "is there", "are there",
            "find the", "find all",
            "which file", "which files"
        ]

        // Must match a lookup pattern
        let matchesPattern = lookupPatterns.contains { message.hasPrefix($0) || message.contains($0) }
        guard matchesPattern else { return false }

        // Exclude complex patterns that need Opus
        let complexIndicators = [
            "refactor", "architect", "design", "implement", "build",
            "debug", "fix", "investigate", "analyze", "optimize",
            "rewrite", "restructure", "migrate", "upgrade",
            "why does", "why is", "explain how", "help me understand",
            "create a", "write a", "add a", "make a"
        ]

        return !complexIndicators.contains { message.contains($0) }
    }
}

// MARK: - Data Models

struct ModelSuggestion {
    let model: ModelChoice
    let reason: String
    let confidence: Double // 0-1, only suggest if > 0.7
}

struct RoutingContext {
    let contextPercentage: Double
    let agentCount: Int
    let isSubAgent: Bool
    let currentModel: ModelChoice?
}
