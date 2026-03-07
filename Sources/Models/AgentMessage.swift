import Foundation

/// Message passed between agents via the shared message bus
struct AgentMessage: Identifiable {
    let id: String
    let from: String           // Agent ID
    let to: String?            // Agent ID, nil = broadcast to all
    let type: AgentMessageType
    let payload: String        // The actual content (prompt, result, review, etc.)
    let context: [String: String] // Shared state / metadata
    let timestamp: Date

    init(
        id: String = UUID().uuidString,
        from: String,
        to: String? = nil,
        type: AgentMessageType,
        payload: String,
        context: [String: String] = [:],
        timestamp: Date = Date()
    ) {
        self.id = id
        self.from = from
        self.to = to
        self.type = type
        self.payload = payload
        self.context = context
        self.timestamp = timestamp
    }
}

/// Types of inter-agent messages
enum AgentMessageType: String {
    case task       // Assign a task to an agent
    case result     // Report task completion / results
    case review     // Request a code review
    case approval   // Approve or reject a proposed change
    case question   // Ask another agent (or human) for clarification
    case status     // Status update (progress report)
    case error      // Report an error
    case context    // Share context / findings

    var icon: String {
        switch self {
        case .task: return "arrow.right.circle"
        case .result: return "checkmark.circle"
        case .review: return "eye.circle"
        case .approval: return "hand.thumbsup"
        case .question: return "questionmark.circle"
        case .status: return "info.circle"
        case .error: return "exclamationmark.triangle"
        case .context: return "doc.text"
        }
    }
}

/// Permission request from an agent
struct PermissionRequest: Identifiable {
    let id: String
    let agentId: String
    let agentName: String
    let toolName: String
    let input: String          // Tool input (file path, command, etc.)
    let riskLevel: RiskLevel
    let timestamp: Date
    var status: PermissionStatus

    init(
        id: String = UUID().uuidString,
        agentId: String,
        agentName: String,
        toolName: String,
        input: String,
        riskLevel: RiskLevel = .low,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.agentId = agentId
        self.agentName = agentName
        self.toolName = toolName
        self.input = input
        self.riskLevel = riskLevel
        self.timestamp = timestamp
        self.status = .pending
    }
}

enum RiskLevel: String {
    case low      // Auto-approved (read-only)
    case medium   // Auto-approved with logging (edits in project dir)
    case high     // Requires human review (destructive ops)
    case critical // Always requires human review (system commands, force push)

    var color: String {
        switch self {
        case .low: return "sage"
        case .medium: return "sky"
        case .high: return "sand"
        case .critical: return "rose"
        }
    }
}

enum PermissionStatus: String {
    case pending
    case approved
    case denied
    case autoApproved
}

/// A rule that auto-approves certain permission patterns
struct PermissionRule: Identifiable, Codable {
    let id: String
    let toolName: String       // e.g., "Read", "Edit", "Bash"
    let pattern: String        // Glob pattern for input (e.g., "src/**/*.ts")
    let action: RuleAction
    let timesMatched: Int
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        toolName: String,
        pattern: String,
        action: RuleAction,
        timesMatched: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.toolName = toolName
        self.pattern = pattern
        self.action = action
        self.timesMatched = timesMatched
        self.createdAt = createdAt
    }
}

enum RuleAction: String, Codable {
    case autoApprove
    case approveWithLogging
    case requireReview
    case deny
}
