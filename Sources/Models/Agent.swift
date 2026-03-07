import Foundation

/// Represents a Claude agent instance with a specific role and state
struct Agent: Identifiable {
    let id: String
    var name: String
    var role: AgentRole
    var state: AgentState
    var currentTask: String?
    var inputTokens: Int
    var outputTokens: Int
    var costUSD: Double
    var messageLog: [AgentMessage]
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        role: AgentRole,
        state: AgentState = .idle
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.state = state
        self.currentTask = nil
        self.inputTokens = 0
        self.outputTokens = 0
        self.costUSD = 0
        self.messageLog = []
        self.createdAt = Date()
    }

    var formattedCost: String {
        if costUSD < 0.01 { return "$0.00" }
        return String(format: "$%.2f", costUSD)
    }
}

/// Predefined agent roles
enum AgentRole: String, CaseIterable, Identifiable {
    case builder     // Writes code, creates files
    case reviewer    // Reviews code, suggests improvements
    case tester      // Runs tests, validates behavior
    case deployer    // Handles deployment, CI/CD
    case researcher  // Explores codebase, gathers context
    case planner     // Plans implementation strategy
    case custom      // User-defined role

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .builder: return "Builder"
        case .reviewer: return "Reviewer"
        case .tester: return "Tester"
        case .deployer: return "Deployer"
        case .researcher: return "Researcher"
        case .planner: return "Planner"
        case .custom: return "Custom"
        }
    }

    var icon: String {
        switch self {
        case .builder: return "hammer.fill"
        case .reviewer: return "eye.fill"
        case .tester: return "checkmark.shield.fill"
        case .deployer: return "arrow.up.doc.fill"
        case .researcher: return "magnifyingglass"
        case .planner: return "map.fill"
        case .custom: return "star.fill"
        }
    }

    /// Default system prompt suffix for each role
    var systemPromptSuffix: String {
        switch self {
        case .builder:
            return "You are a builder agent. Write clean, production-ready code. Follow existing patterns."
        case .reviewer:
            return "You are a code reviewer. Check for bugs, security issues, performance problems, and style violations. Be thorough but constructive."
        case .tester:
            return "You are a testing agent. Run tests, validate behavior, check edge cases. Report failures clearly."
        case .deployer:
            return "You are a deployment agent. Handle builds, deploys, and CI/CD. Verify everything works after deployment."
        case .researcher:
            return "You are a research agent. Explore the codebase, gather context, find relevant patterns and files. Report findings clearly."
        case .planner:
            return "You are a planning agent. Analyze requirements, design implementation plans, identify risks and dependencies."
        case .custom:
            return ""
        }
    }
}

/// Agent lifecycle states
enum AgentState: String {
    case idle          // Ready but not doing anything
    case thinking      // Processing / generating response
    case working       // Executing tools (reading, writing, running commands)
    case waiting       // Waiting for permission or human input
    case reviewing     // Reviewing another agent's work
    case completed     // Task finished
    case failed        // Task failed
    case stopped       // Manually stopped

    var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .thinking: return "Thinking"
        case .working: return "Working"
        case .waiting: return "Waiting"
        case .reviewing: return "Reviewing"
        case .completed: return "Done"
        case .failed: return "Failed"
        case .stopped: return "Stopped"
        }
    }

    var isActive: Bool {
        switch self {
        case .thinking, .working, .reviewing: return true
        default: return false
        }
    }
}
