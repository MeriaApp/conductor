import Foundation

/// Represents a Claude CLI conversation session
struct Session: Identifiable, Codable {
    let id: String
    var title: String
    let createdAt: Date
    var lastActiveAt: Date
    var model: String
    var sessionId: String?       // Claude CLI session ID (from system event)
    var projectPath: String?     // Working directory
    var gitBranch: String?
    var totalCostUSD: Double
    var totalInputTokens: Int
    var totalOutputTokens: Int
    var messageCount: Int
    var isActive: Bool
    var forkedFrom: String?      // Session ID this was forked from
    var summary: String?         // Auto-generated summary on session end

    init(
        id: String = UUID().uuidString,
        title: String = "New Session",
        createdAt: Date = Date(),
        model: String = "claude-opus-4-6",
        projectPath: String? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.lastActiveAt = createdAt
        self.model = model
        self.sessionId = nil
        self.projectPath = projectPath
        self.gitBranch = nil
        self.totalCostUSD = 0
        self.totalInputTokens = 0
        self.totalOutputTokens = 0
        self.messageCount = 0
        self.isActive = true
        self.forkedFrom = nil
        self.summary = nil
    }

    /// Context usage as percentage (rough estimate based on token limits)
    var contextPercentage: Double {
        let maxTokens = 200_000 // Opus/Sonnet context window
        let used = totalInputTokens + totalOutputTokens
        return min(1.0, Double(used) / Double(maxTokens))
    }

    /// Formatted cost string
    var formattedCost: String {
        if totalCostUSD < 0.01 {
            return "$0.00"
        }
        return String(format: "$%.2f", totalCostUSD)
    }
}
