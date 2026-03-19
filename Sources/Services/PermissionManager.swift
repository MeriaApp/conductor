import Foundation

/// Manages permission rules for agent tool use
/// The key innovation: frees humans from clicking "accept" every 5 seconds
@MainActor
final class PermissionManager: ObservableObject {
    @Published var pendingRequests: [PermissionRequest] = []
    @Published var rules: [PermissionRule] = []
    @Published var recentDecisions: [PermissionRequest] = [] // Last 50
    /// When true, all permissions are auto-approved (e.g., Vibe Coder mode)
    @Published var autoApproveAll: Bool = false

    /// Tracks manual approval patterns for learning
    private var approvalPatterns: [String: Int] = [:] // "tool:pattern" -> count

    private let rulesURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("Conductor", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        rulesURL = appDir.appendingPathComponent("permission_rules.json")
        loadRules()
        addDefaultRules()
    }

    // MARK: - Permission Evaluation

    /// Evaluate a tool use request — returns immediately if auto-approved, queues if not
    func evaluate(agentId: String, agentName: String, toolName: String, input: String) -> PermissionStatus {
        // Vibe Coder mode: auto-approve everything
        if autoApproveAll {
            logDecision(agentId: agentId, agentName: agentName, toolName: toolName, input: input, riskLevel: .low, status: .autoApproved)
            return .autoApproved
        }

        let riskLevel = assessRisk(toolName: toolName, input: input)

        // Check rules
        for rule in rules {
            if rule.toolName == toolName && matchesPattern(input: input, pattern: rule.pattern) {
                switch rule.action {
                case .autoApprove:
                    logDecision(agentId: agentId, agentName: agentName, toolName: toolName, input: input, riskLevel: .low, status: .autoApproved)
                    return .autoApproved
                case .approveWithLogging:
                    logDecision(agentId: agentId, agentName: agentName, toolName: toolName, input: input, riskLevel: .medium, status: .autoApproved)
                    return .autoApproved
                case .deny:
                    logDecision(agentId: agentId, agentName: agentName, toolName: toolName, input: input, riskLevel: riskLevel, status: .denied)
                    return .denied
                case .requireReview:
                    break // Fall through to queue
                }
            }
        }

        // Queue for human review
        let request = PermissionRequest(
            agentId: agentId,
            agentName: agentName,
            toolName: toolName,
            input: input,
            riskLevel: riskLevel
        )
        pendingRequests.append(request)

        // Sound: permission needed
        SoundManager.shared.playPermissionNeeded()

        // System notification with Approve/Deny actions
        NotificationService.shared.sendPermissionNotification(
            requestId: request.id,
            agentName: agentName,
            toolName: toolName,
            input: input,
            riskLevel: riskLevel
        )

        return .pending
    }

    // MARK: - Human Actions

    /// Approve a pending request
    func approve(requestId: String) {
        guard let idx = pendingRequests.firstIndex(where: { $0.id == requestId }) else { return }
        var request = pendingRequests.remove(at: idx)
        request.status = .approved
        recentDecisions.append(request)
        trimRecentDecisions()
        NotificationService.shared.removePermissionNotification(requestId: requestId)

        // Learn pattern
        let key = "\(request.toolName):\(extractPattern(from: request.input))"
        approvalPatterns[key, default: 0] += 1

        // Low-risk tools learn aggressively (1 approval), others need 2
        let lowRiskTools: Set<String> = ["Read", "Edit", "Write", "Glob", "Grep"]
        let threshold = lowRiskTools.contains(request.toolName) ? 1 : 2
        if approvalPatterns[key, default: 0] >= threshold {
            suggestAutoRule(toolName: request.toolName, input: request.input)
        }
    }

    /// Deny a pending request
    func deny(requestId: String) {
        guard let idx = pendingRequests.firstIndex(where: { $0.id == requestId }) else { return }
        var request = pendingRequests.remove(at: idx)
        request.status = .denied
        recentDecisions.append(request)
        trimRecentDecisions()
        NotificationService.shared.removePermissionNotification(requestId: requestId)
    }

    /// Approve all pending requests
    func approveAll() {
        for request in pendingRequests {
            var approved = request
            approved.status = .approved
            recentDecisions.append(approved)
        }
        pendingRequests.removeAll()
        trimRecentDecisions()
    }

    /// Add a custom rule
    func addRule(_ rule: PermissionRule) {
        rules.append(rule)
        saveRules()
    }

    /// Remove a rule
    func removeRule(id: String) {
        rules.removeAll { $0.id == id }
        saveRules()
    }

    // MARK: - Risk Assessment

    private func assessRisk(toolName: String, input: String) -> RiskLevel {
        // Always safe (read-only)
        let safeTools = ["Read", "Glob", "Grep", "WebFetch", "WebSearch"]
        if safeTools.contains(toolName) { return .low }

        // Destructive commands
        let destructivePatterns = [
            "rm -rf", "rm -r", "git reset --hard", "git push --force",
            "git push -f", "git checkout -- .", "drop table", "DROP TABLE",
            "kill -9", "pkill", "sudo"
        ]
        for pattern in destructivePatterns {
            if input.contains(pattern) { return .critical }
        }

        // System-level commands
        if toolName == "Bash" {
            let systemPatterns = ["sudo", "chmod", "chown", "systemctl", "launchctl"]
            for pattern in systemPatterns {
                if input.contains(pattern) { return .high }
            }
            return .medium
        }

        // File edits
        if toolName == "Edit" || toolName == "Write" {
            return .medium
        }

        return .medium
    }

    // MARK: - Pattern Matching

    private func matchesPattern(input: String, pattern: String) -> Bool {
        if pattern == "*" { return true }

        // Simple glob matching
        if pattern.hasSuffix("/**") {
            let prefix = String(pattern.dropLast(3))
            return input.hasPrefix(prefix)
        }

        if pattern.contains("*") {
            let parts = pattern.components(separatedBy: "*")
            if parts.count == 2 {
                return input.hasPrefix(parts[0]) && input.hasSuffix(parts[1])
            }
        }

        return input == pattern
    }

    private func extractPattern(from input: String) -> String {
        // Try to extract a generalizable pattern from the input
        // e.g., "/Users/jesse/project/src/file.ts" -> "src/**"
        if let lastSlash = input.lastIndex(of: "/") {
            let dir = String(input[..<lastSlash])
            if let secondLast = dir.lastIndex(of: "/") {
                return String(dir[secondLast...]) + "/**"
            }
        }
        return input
    }

    // MARK: - Learning

    private func suggestAutoRule(toolName: String, input: String) {
        let pattern = extractPattern(from: input)
        // Only suggest if rule doesn't already exist
        let exists = rules.contains { $0.toolName == toolName && $0.pattern == pattern }
        if !exists {
            let rule = PermissionRule(
                toolName: toolName,
                pattern: pattern,
                action: .approveWithLogging
            )
            // Auto-add the rule (in a real app, we'd show a suggestion UI)
            addRule(rule)
        }
    }

    // MARK: - Defaults

    private func addDefaultRules() {
        let defaults: [(String, String, RuleAction)] = [
            // Always safe
            ("Read", "*", .autoApprove),
            ("Glob", "*", .autoApprove),
            ("Grep", "*", .autoApprove),
            ("WebFetch", "*", .autoApprove),
            ("WebSearch", "*", .autoApprove),
            // Task/agent tools
            ("Task", "*", .autoApprove),
            ("TaskCreate", "*", .autoApprove),
            ("TaskUpdate", "*", .autoApprove),
            ("TaskList", "*", .autoApprove),
        ]

        for (tool, pattern, action) in defaults {
            if !rules.contains(where: { $0.toolName == tool && $0.pattern == pattern }) {
                rules.append(PermissionRule(toolName: tool, pattern: pattern, action: action))
            }
        }
    }

    // MARK: - Persistence

    private func loadRules() {
        guard FileManager.default.fileExists(atPath: rulesURL.path),
              let data = try? Data(contentsOf: rulesURL),
              let decoded = try? JSONDecoder().decode([PermissionRule].self, from: data) else {
            return
        }
        rules = decoded
    }

    private func saveRules() {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        do {
            try data.write(to: rulesURL)
        } catch {
            print("[PermissionManager] Failed to save rules: \(error)")
        }
    }

    // MARK: - Helpers

    private func logDecision(agentId: String, agentName: String, toolName: String, input: String, riskLevel: RiskLevel, status: PermissionStatus) {
        var request = PermissionRequest(
            agentId: agentId,
            agentName: agentName,
            toolName: toolName,
            input: input,
            riskLevel: riskLevel
        )
        request.status = status
        recentDecisions.append(request)
        trimRecentDecisions()
    }

    private func trimRecentDecisions() {
        if recentDecisions.count > 50 {
            recentDecisions = Array(recentDecisions.suffix(50))
        }
    }
}
