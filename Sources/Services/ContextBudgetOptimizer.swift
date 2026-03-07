import Foundation

/// Analyzes context usage and suggests reductions
/// Proactive: warns before sending a prompt that would trigger compaction
@MainActor
final class ContextBudgetOptimizer: ObservableObject {
    @Published var optimizationSuggestions: [OptimizationSuggestion] = []
    @Published var estimatedSavings: Int = 0

    private let contextManager: ContextStateManager

    init(contextManager: ContextStateManager) {
        self.contextManager = contextManager
    }

    // MARK: - Analysis

    /// Analyze current context and generate optimization suggestions
    func analyze(messages: [ConversationMessage]) {
        optimizationSuggestions.removeAll()
        estimatedSavings = 0

        analyzeRedundantToolResults(messages: messages)
        analyzeLargeFileReads(messages: messages)
        analyzeVerboseErrors(messages: messages)
        analyzeOldConversation(messages: messages)
    }

    /// Check if a pending message would trigger compaction
    func checkBeforeSend(text: String) -> PreSendWarning? {
        let estimatedTokens = contextManager.estimateTokens(for: text)

        if contextManager.wouldTriggerCompaction(estimatedTokens: estimatedTokens) {
            return PreSendWarning(
                message: "This message may trigger context compaction",
                estimatedTokens: estimatedTokens,
                currentUsage: contextManager.contextPercentage,
                suggestion: "Consider compacting selectively first (Cmd+X), or keep the message concise."
            )
        }

        return nil
    }

    // MARK: - Specific Analyses

    private func analyzeRedundantToolResults(messages: [ConversationMessage]) {
        // Find tool results that show the same file being read multiple times
        var fileReadCounts: [String: Int] = [:]

        for message in messages {
            for block in message.blocks {
                if let tool = block as? ToolUseBlock, tool.toolName == "Read" {
                    fileReadCounts[tool.input, default: 0] += 1
                }
            }
        }

        for (file, count) in fileReadCounts where count > 2 {
            let savings = count * 500 // Rough estimate per read
            optimizationSuggestions.append(OptimizationSuggestion(
                type: .redundantRead,
                description: "\(file) read \(count) times — older reads could be summarized",
                estimatedTokenSavings: savings,
                autoApplyable: true
            ))
            estimatedSavings += savings
        }
    }

    private func analyzeLargeFileReads(messages: [ConversationMessage]) {
        for message in messages {
            for block in message.blocks {
                if let tool = block as? ToolUseBlock,
                   tool.toolName == "Read",
                   let output = tool.output,
                   output.count > 5000 {
                    let savings = output.count / 4 // tokens saved if summarized
                    optimizationSuggestions.append(OptimizationSuggestion(
                        type: .largeFileRead,
                        description: "Large file read (\(output.count) chars) could be cached or summarized",
                        estimatedTokenSavings: savings,
                        autoApplyable: false
                    ))
                    estimatedSavings += savings
                }
            }
        }
    }

    private func analyzeVerboseErrors(messages: [ConversationMessage]) {
        for message in messages {
            for block in message.blocks {
                if let tool = block as? ToolUseBlock,
                   tool.isError,
                   let output = tool.output,
                   output.count > 2000 {
                    let savings = (output.count - 500) / 4 // Keep 500 chars, summarize rest
                    optimizationSuggestions.append(OptimizationSuggestion(
                        type: .verboseError,
                        description: "Verbose error output could be compressed (keep key lines only)",
                        estimatedTokenSavings: savings,
                        autoApplyable: true
                    ))
                    estimatedSavings += savings
                }
            }
        }
    }

    private func analyzeOldConversation(messages: [ConversationMessage]) {
        // Messages older than 10 turns ago could be summarized
        if messages.count > 20 {
            let oldMessages = messages.prefix(messages.count - 10)
            let oldTokenEstimate = oldMessages.reduce(0) { total, msg in
                total + msg.blocks.reduce(0) { $0 + $1.copyText().count / 4 }
            }

            if oldTokenEstimate > 5000 {
                optimizationSuggestions.append(OptimizationSuggestion(
                    type: .oldConversation,
                    description: "\(oldMessages.count) old messages could be summarized while preserving decisions and code",
                    estimatedTokenSavings: oldTokenEstimate / 2, // 50% savings from summarization
                    autoApplyable: true
                ))
                estimatedSavings += oldTokenEstimate / 2
            }
        }
    }
}

// MARK: - Types

struct OptimizationSuggestion: Identifiable {
    let id = UUID().uuidString
    let type: OptimizationType
    let description: String
    let estimatedTokenSavings: Int
    let autoApplyable: Bool
}

enum OptimizationType: String {
    case redundantRead
    case largeFileRead
    case verboseError
    case oldConversation
}

struct PreSendWarning {
    let message: String
    let estimatedTokens: Int
    let currentUsage: Double
    let suggestion: String
}
