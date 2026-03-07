import Foundation

/// Pre-compaction state capture — saves everything that matters before context is compressed
struct ContextSnapshot: Codable, Identifiable {
    let id: String
    let sessionId: String
    let timestamp: Date
    var decisions: [ContextDecision]         // Architectural decisions made
    var fileChanges: [FileChange]            // Files modified with line ranges
    var taskProgress: [TaskProgressItem]     // Task status tracking
    var keyDiscoveries: [String]             // Important findings
    var activeConstraints: [String]          // Rules/constraints in effect
    var currentTask: String?                 // What was being worked on
    var nextSteps: [String]                  // What to do next
    var buildStatus: BuildStatus?            // Last build/deploy state
    var tokenUsage: TokenUsageSnapshot       // Token state at capture time

    init(
        id: String = UUID().uuidString,
        sessionId: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.sessionId = sessionId
        self.timestamp = timestamp
        self.decisions = []
        self.fileChanges = []
        self.taskProgress = []
        self.keyDiscoveries = []
        self.activeConstraints = []
        self.currentTask = nil
        self.nextSteps = []
        self.buildStatus = nil
        self.tokenUsage = TokenUsageSnapshot()
    }
}

struct ContextDecision: Codable, Identifiable {
    let id: String
    let description: String
    let reasoning: String
    let timestamp: Date

    init(id: String = UUID().uuidString, description: String, reasoning: String, timestamp: Date = Date()) {
        self.id = id
        self.description = description
        self.reasoning = reasoning
        self.timestamp = timestamp
    }
}

struct FileChange: Codable, Identifiable {
    let id: String
    let filePath: String
    let changeType: FileChangeType
    let lineRange: String?       // e.g., "45-78"
    let summary: String

    init(id: String = UUID().uuidString, filePath: String, changeType: FileChangeType, lineRange: String? = nil, summary: String) {
        self.id = id
        self.filePath = filePath
        self.changeType = changeType
        self.lineRange = lineRange
        self.summary = summary
    }
}

enum FileChangeType: String, Codable {
    case created, modified, deleted
}

struct TaskProgressItem: Codable, Identifiable {
    let id: String
    var description: String
    var status: TaskItemStatus

    init(id: String = UUID().uuidString, description: String, status: TaskItemStatus = .pending) {
        self.id = id
        self.description = description
        self.status = status
    }
}

enum TaskItemStatus: String, Codable {
    case pending, inProgress, completed, blocked
}

struct BuildStatus: Codable {
    let compiled: Bool
    let deployed: Bool
    let deployTarget: String?    // e.g., "Vercel", "App Store", "device"
    let timestamp: Date
}

struct TokenUsageSnapshot: Codable {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheReadTokens: Int = 0
    var contextPercentage: Double = 0
    var estimatedRemainingTokens: Int = 200_000
}
