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

    private init() {}

    /// Analyze a message and context to determine if a model switch would be beneficial
    func analyze(message: String, context: RoutingContext) -> ModelSuggestion? {
        guard isEnabled else { return nil }

        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let wordCount = trimmed.components(separatedBy: .whitespaces).count

        // Rule 1: Short simple lookups → Haiku (10x faster, equally accurate for simple tasks)
        if wordCount <= 20 && isSimpleLookup(trimmed) {
            let suggestion = ModelSuggestion(
                model: .haiku,
                reason: "Simple lookup — Haiku is 10x faster",
                confidence: 0.75
            )
            return suggestion.confidence > 0.7 ? suggestion : nil
        }

        // Rule 2: High context pressure → Sonnet (handles compacted context efficiently)
        if context.contextPercentage > 0.80 {
            let suggestion = ModelSuggestion(
                model: .sonnet,
                reason: "Context pressure — Sonnet handles compacted context well",
                confidence: 0.72
            )
            return suggestion.confidence > 0.7 ? suggestion : nil
        }

        // Rule 3: Agent team spawning (3+ agents) → Sonnet for sub-agents
        if context.agentCount >= 3 && context.isSubAgent {
            let suggestion = ModelSuggestion(
                model: .sonnet,
                reason: "Parallel agents — Sonnet handles parallel work efficiently",
                confidence: 0.75
            )
            return suggestion.confidence > 0.7 ? suggestion : nil
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
