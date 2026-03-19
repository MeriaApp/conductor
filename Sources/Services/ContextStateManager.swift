import Foundation

/// Real-time context tracking — monitors token usage, warns on approaching limits
/// Uses graduated warnings: sky (fine) -> sand (warm) -> rose (critical)
@MainActor
final class ContextStateManager: ObservableObject {
    @Published var inputTokens: Int = 0
    @Published var outputTokens: Int = 0
    @Published var cacheReadTokens: Int = 0
    @Published var contextPercentage: Double = 0
    @Published var warningLevel: ContextWarningLevel = .none
    @Published var snapshots: [ContextSnapshot] = []
    @Published var currentSnapshot: ContextSnapshot?
    /// When true, prevents automatic context compaction
    @Published var isContextPinned: Bool = false

    let maxContextTokens = 200_000

    /// Context health — aggregates token usage, image risk, and warning level into a single status
    @Published var contextHealth: ContextHealth = .healthy

    init() {}

    /// Last turn's input tokens — reflects actual context window size
    @Published var lastTurnInputTokens: Int = 0

    // MARK: - Token Tracking

    /// Update cumulative totals from a ClaudeProcess (for cost display)
    func updateFromProcess(_ process: ClaudeProcess) {
        inputTokens = process.totalInputTokens
        outputTokens = process.totalOutputTokens
    }

    /// Update context percentage from per-turn metrics (actual context window size)
    func updateFromTurnMetrics(_ metrics: TurnMetrics) {
        lastTurnInputTokens = metrics.inputTokens
        // Per-turn inputTokens = actual context window size for that turn
        contextPercentage = Double(metrics.inputTokens) / Double(maxContextTokens)
        warningLevel = ContextWarningLevel.from(percentage: contextPercentage)
        updateContextHealth()
    }

    /// Recalculate context health from all signals
    func updateContextHealth() {
        let imageTokens = SafeguardsManager.shared.totalImageTokens
        let imageCount = SafeguardsManager.shared.trackedImageFiles.count

        if contextPercentage > 0.85 {
            contextHealth = .critical(reason: "Context at \(Int(contextPercentage * 100))% — auto-compact imminent")
        } else if contextPercentage > 0.75 {
            if imageCount > 0 {
                contextHealth = .warning(reason: "Context \(Int(contextPercentage * 100))% + \(imageCount) image\(imageCount == 1 ? "" : "s") (~\(imageTokens / 1000)K tokens)")
            } else {
                contextHealth = .warning(reason: "Context at \(Int(contextPercentage * 100))% — consider compacting")
            }
        } else if imageCount >= 3 {
            contextHealth = .warning(reason: "\(imageCount) images in context (~\(imageTokens / 1000)K tokens) — may cause blowup")
        } else {
            contextHealth = .healthy
        }
    }

    /// Estimate tokens for a pending message before sending
    func estimateTokens(for text: String) -> Int {
        // Rough estimate: ~4 chars per token for English text
        return text.count / 4
    }

    /// Check if sending a message would trigger compaction
    func wouldTriggerCompaction(estimatedTokens: Int) -> Bool {
        let projected = Double(lastTurnInputTokens + estimatedTokens) / Double(maxContextTokens)
        return projected > 0.85 // Default compaction threshold
    }

    // MARK: - Snapshot Management

    /// Take a snapshot of current context state
    func takeSnapshot(sessionId: String) -> ContextSnapshot {
        var snapshot = ContextSnapshot(sessionId: sessionId)
        snapshot.tokenUsage = TokenUsageSnapshot(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadTokens,
            contextPercentage: contextPercentage,
            estimatedRemainingTokens: maxContextTokens - inputTokens - outputTokens
        )

        // Copy current snapshot's tracked data if it exists
        if let current = currentSnapshot {
            snapshot.decisions = current.decisions
            snapshot.fileChanges = current.fileChanges
            snapshot.taskProgress = current.taskProgress
            snapshot.keyDiscoveries = current.keyDiscoveries
            snapshot.activeConstraints = current.activeConstraints
            snapshot.currentTask = current.currentTask
            snapshot.nextSteps = current.nextSteps
            snapshot.buildStatus = current.buildStatus
        }

        snapshots.append(snapshot)
        return snapshot
    }

    // MARK: - Context Tracking

    /// Track a decision made during the session
    func trackDecision(_ description: String, reasoning: String) {
        if currentSnapshot == nil {
            currentSnapshot = ContextSnapshot(sessionId: "active")
        }
        currentSnapshot?.decisions.append(
            ContextDecision(description: description, reasoning: reasoning)
        )
    }

    /// Track a file change
    func trackFileChange(path: String, type: FileChangeType, lineRange: String? = nil, summary: String) {
        if currentSnapshot == nil {
            currentSnapshot = ContextSnapshot(sessionId: "active")
        }
        currentSnapshot?.fileChanges.append(
            FileChange(filePath: path, changeType: type, lineRange: lineRange, summary: summary)
        )
    }

    /// Track task progress
    func trackTask(_ description: String, status: TaskItemStatus = .pending) {
        if currentSnapshot == nil {
            currentSnapshot = ContextSnapshot(sessionId: "active")
        }
        currentSnapshot?.taskProgress.append(
            TaskProgressItem(description: description, status: status)
        )
    }

    /// Track a key discovery
    func trackDiscovery(_ discovery: String) {
        if currentSnapshot == nil {
            currentSnapshot = ContextSnapshot(sessionId: "active")
        }
        currentSnapshot?.keyDiscoveries.append(discovery)
    }

    /// Set current task
    func setCurrentTask(_ task: String) {
        if currentSnapshot == nil {
            currentSnapshot = ContextSnapshot(sessionId: "active")
        }
        currentSnapshot?.currentTask = task
    }

    /// Set next steps (auto-extracted from assistant text)
    func setNextSteps(_ steps: [String]) {
        if currentSnapshot == nil {
            currentSnapshot = ContextSnapshot(sessionId: "active")
        }
        currentSnapshot?.nextSteps = steps
    }

    /// Set build/deploy status (auto-detected from bash commands)
    func setBuildStatus(_ status: BuildStatus) {
        if currentSnapshot == nil {
            currentSnapshot = ContextSnapshot(sessionId: "active")
        }
        currentSnapshot?.buildStatus = status
    }

    // MARK: - Write CONTEXT_STATE.md

    /// Generate and write a CONTEXT_STATE.md file to the project directory
    func writeContextState(to directory: String) {
        guard let snapshot = currentSnapshot else { return }

        var md = "# Context State\n"
        md += "*Auto-generated by Conductor — \(ISO8601DateFormatter().string(from: Date()))*\n\n"

        if let task = snapshot.currentTask {
            md += "## Current Task\n\(task)\n\n"
        }

        if !snapshot.decisions.isEmpty {
            md += "## Decisions Made\n"
            for d in snapshot.decisions {
                md += "- **\(d.description)**: \(d.reasoning)\n"
            }
            md += "\n"
        }

        if !snapshot.fileChanges.isEmpty {
            md += "## Files Changed\n"
            for f in snapshot.fileChanges {
                let range = f.lineRange.map { " (lines \($0))" } ?? ""
                md += "- `\(f.filePath)`\(range) — \(f.summary)\n"
            }
            md += "\n"
        }

        if !snapshot.taskProgress.isEmpty {
            md += "## Task Progress\n"
            for t in snapshot.taskProgress {
                let marker = t.status == .completed ? "[x]" : "[ ]"
                md += "- \(marker) \(t.description)\n"
            }
            md += "\n"
        }

        if !snapshot.nextSteps.isEmpty {
            md += "## Next Steps\n"
            for step in snapshot.nextSteps {
                md += "- \(step)\n"
            }
            md += "\n"
        }

        md += "## Token Usage\n"
        md += "- Input: \(snapshot.tokenUsage.inputTokens)\n"
        md += "- Output: \(snapshot.tokenUsage.outputTokens)\n"
        md += "- Context: \(Int(snapshot.tokenUsage.contextPercentage * 100))%\n"

        let path = "\(directory)/CONTEXT_STATE.md"
        try? md.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

/// Context warning levels — graduated, never modal
enum ContextWarningLevel: String {
    case none       // < 50% — sky
    case warm       // 50-75% — sand
    case critical   // > 75% — rose

    static func from(percentage: Double) -> ContextWarningLevel {
        if percentage > 0.75 { return .critical }
        if percentage > 0.50 { return .warm }
        return .none
    }
}

/// Aggregated context health — combines token percentage + image risk
enum ContextHealth: Equatable {
    case healthy
    case warning(reason: String)
    case critical(reason: String)

    var label: String {
        switch self {
        case .healthy: return "Healthy"
        case .warning: return "Warning"
        case .critical: return "Critical"
        }
    }

    var icon: String {
        switch self {
        case .healthy: return "heart.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        }
    }

    var isHealthy: Bool {
        if case .healthy = self { return true }
        return false
    }

    var reason: String? {
        switch self {
        case .healthy: return nil
        case .warning(let r): return r
        case .critical(let r): return r
        }
    }
}
