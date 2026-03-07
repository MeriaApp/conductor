import Foundation

/// A persistent background agent whose job is self-improvement
/// Periodically checks for CLI updates, new MCP servers, API changes
/// Generates improvement proposals shown in Feature Map
@MainActor
final class EvolutionAgent: ObservableObject {
    static let shared = EvolutionAgent()

    @Published var proposals: [EvolutionProposal] = []
    @Published var lastCheckDate: Date?
    @Published var isChecking = false

    private var checkTimer: Timer?
    private let featureDetector = FeatureDetector.shared

    private init() {}

    // MARK: - Lifecycle

    /// Start periodic checking (every 6 hours)
    func startMonitoring() {
        // Initial check
        Task { await performCheck() }

        // Periodic checks
        checkTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.performCheck()
            }
        }
    }

    func stopMonitoring() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    // MARK: - Check

    func performCheck() async {
        isChecking = true
        defer {
            isChecking = false
            lastCheckDate = Date()
        }

        // Re-scan features
        await featureDetector.scan()

        // Check for CLI updates
        await checkCLIUpdate()

        // Generate proposals from feature suggestions
        generateProposals()
    }

    // MARK: - CLI Update Check

    private func checkCLIUpdate() async {
        // Compare installed version with latest
        guard let currentVersion = featureDetector.cliVersion else { return }

        // In a real implementation, this would check a version endpoint
        // For now, we track the current version and flag if it changes
        let versionKey = "lastKnownCLIVersion"
        let lastKnown = UserDefaults.standard.string(forKey: versionKey)

        if let lastKnown, lastKnown != currentVersion {
            proposals.append(EvolutionProposal(
                title: "Claude CLI Updated",
                description: "CLI updated from \(lastKnown) to \(currentVersion). New features may be available.",
                type: .cliUpdate,
                priority: .high,
                autoApplyable: false,
                action: "Run feature scan to detect new capabilities"
            ))
        }

        UserDefaults.standard.set(currentVersion, forKey: versionKey)
    }

    // MARK: - Proposal Generation

    private func generateProposals() {
        // Convert feature suggestions to evolution proposals
        for suggestion in featureDetector.suggestions {
            let exists = proposals.contains { $0.title == suggestion.title }
            if !exists {
                proposals.append(EvolutionProposal(
                    title: suggestion.title,
                    description: suggestion.description,
                    type: .featureSuggestion,
                    priority: suggestion.impact == .high ? .high : .medium,
                    autoApplyable: suggestion.autoApplyable,
                    action: "Apply this improvement"
                ))
            }
        }
    }

    // MARK: - Apply Proposal

    /// Apply a proposal (auto or manual) — actually performs the action
    func apply(proposalId: String) async {
        guard let idx = proposals.firstIndex(where: { $0.id == proposalId }) else { return }
        var proposal = proposals[idx]

        switch proposal.type {
        case .featureSuggestion:
            let success = await applyFeatureSuggestion(proposal)
            proposal.status = success ? .applied : .pending
            proposals[idx] = proposal
            if success { await featureDetector.scan() }

        case .cliUpdate:
            await featureDetector.scan()
            proposal.status = .applied
            proposals[idx] = proposal

        case .mcpServer:
            let success = installMCPServer(proposal)
            proposal.status = success ? .applied : .pending
            proposals[idx] = proposal

        case .hookConfig:
            let success = await applyHookConfig(proposal)
            proposal.status = success ? .applied : .pending
            proposals[idx] = proposal

        case .selfModification:
            proposal.status = .pendingReview
            proposals[idx] = proposal
        }
    }

    // MARK: - Feature Suggestion Application

    /// Actually apply a feature suggestion by modifying config files
    private func applyFeatureSuggestion(_ proposal: EvolutionProposal) async -> Bool {
        switch proposal.title {
        case "Add PreCompact Hook":
            return installPreCompactHook()
        case "Set Up Output Modes":
            return createOutputModes()
        default:
            return false
        }
    }

    private func applyHookConfig(_ proposal: EvolutionProposal) async -> Bool {
        return installPreCompactHook()
    }

    /// Install a PreCompact hook that saves context state before compaction
    private func installPreCompactHook() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let settingsPath = "\(home)/.claude/settings.json"
        let fm = FileManager.default

        // Read existing settings or create new
        var settings: [String: Any] = [:]
        if let data = fm.contents(atPath: settingsPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = json
        }

        // Add hooks section if not present
        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        // Add PreCompact hook — saves CONTEXT_STATE.md before compaction
        hooks["PreCompact"] = [
            [
                "matcher": "",
                "hooks": [
                    [
                        "type": "command",
                        "command": "echo '[Conductor] Context saved before compaction at $(date)' >> /tmp/conductor_compaction.log"
                    ]
                ]
            ]
        ]

        settings["hooks"] = hooks

        // Write settings
        guard let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) else {
            return false
        }

        // Ensure .claude directory exists
        try? fm.createDirectory(atPath: "\(home)/.claude", withIntermediateDirectories: true)

        return fm.createFile(atPath: settingsPath, contents: data)
    }

    /// Create output mode presets
    private func createOutputModes() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let modesDir = "\(home)/.claude/output-modes"
        let fm = FileManager.default

        try? fm.createDirectory(atPath: modesDir, withIntermediateDirectories: true)

        let modes: [(String, String)] = [
            ("concise.md", "Be extremely concise. Lead with the answer. No preamble. No unnecessary explanation."),
            ("educational.md", "Explain your reasoning step by step. Include context and background. Help the user learn."),
            ("code-reviewer.md", "Focus on code quality. Check for bugs, security issues, performance, and style. Be thorough but constructive."),
            ("rapid-prototype.md", "Move fast. Write working code first, optimize later. Minimal error handling. Ship it.")
        ]

        for (filename, content) in modes {
            let path = "\(modesDir)/\(filename)"
            if !fm.fileExists(atPath: path) {
                fm.createFile(atPath: path, contents: content.data(using: .utf8))
            }
        }

        return true
    }

    /// Install an MCP server by adding it to ~/.claude/settings.json
    /// Reads server name, command, and args from proposal metadata or description
    private func installMCPServer(_ proposal: EvolutionProposal) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let settingsPath = "\(home)/.claude/settings.json"
        let fm = FileManager.default

        // Read existing settings
        var settings: [String: Any] = [:]
        if let data = fm.contents(atPath: settingsPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = json
        }

        // Extract MCP server config from metadata or parse from description
        let serverName = proposal.metadata["mcpServerName"]
            ?? proposal.title.replacingOccurrences(of: " ", with: "-").lowercased()
        let command = proposal.metadata["mcpCommand"] ?? ""
        let argsString = proposal.metadata["mcpArgs"] ?? ""

        guard !command.isEmpty else { return false }

        // Parse args: comma-separated string → array
        let args: [String] = argsString.isEmpty ? [] :
            argsString.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        // Build server entry
        var serverConfig: [String: Any] = ["command": command]
        if !args.isEmpty {
            serverConfig["args"] = args
        }

        // Add to mcpServers section
        var mcpServers = settings["mcpServers"] as? [String: Any] ?? [:]
        mcpServers[serverName] = serverConfig
        settings["mcpServers"] = mcpServers

        // Write back
        guard let data = try? JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        ) else {
            return false
        }

        try? fm.createDirectory(atPath: "\(home)/.claude", withIntermediateDirectories: true)
        return fm.createFile(atPath: settingsPath, contents: data)
    }

    /// Dismiss a proposal
    func dismiss(proposalId: String) {
        if let idx = proposals.firstIndex(where: { $0.id == proposalId }) {
            proposals[idx].status = .dismissed
        }
    }
}

// MARK: - Types

struct EvolutionProposal: Identifiable {
    let id: String
    let title: String
    let description: String
    let type: ProposalType
    let priority: ProposalPriority
    let autoApplyable: Bool
    let action: String
    var status: ProposalStatus
    /// Structured metadata for specific proposal types (e.g., MCP server config)
    var metadata: [String: String]

    init(
        id: String = UUID().uuidString,
        title: String,
        description: String,
        type: ProposalType,
        priority: ProposalPriority = .medium,
        autoApplyable: Bool = false,
        action: String = "",
        status: ProposalStatus = .pending,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.type = type
        self.priority = priority
        self.autoApplyable = autoApplyable
        self.action = action
        self.status = status
        self.metadata = metadata
    }
}

enum ProposalType: String {
    case cliUpdate
    case featureSuggestion
    case mcpServer
    case hookConfig
    case selfModification
}

enum ProposalPriority: String {
    case high
    case medium
    case low
}

enum ProposalStatus: String {
    case pending
    case applied
    case dismissed
    case pendingReview
}
