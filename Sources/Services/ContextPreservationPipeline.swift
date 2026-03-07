import Foundation

/// Zero-loss context preservation — auto-extracts, detects compaction, reinjects
/// The brain that wires ContextStateManager, CompactionEngine, and SessionContinuity together.
/// Automatically tracks file operations from tool use, decisions from assistant text,
/// detects compaction via per-turn token drop, and reinjects preserved context after.
@MainActor
final class ContextPreservationPipeline: ObservableObject {
    // MARK: - Published State

    @Published var compactionDetected = false
    @Published var recoveryPending = false
    @Published var snapshotTaken = false

    // MARK: - Configuration

    var projectDirectory: String?

    // MARK: - Dependencies

    private let contextManager: ContextStateManager
    private let compactionEngine: CompactionEngine

    // MARK: - Compaction Detection State

    private var previousTurnInputTokens: Int = 0
    private var pendingReinjection: String?
    private var hasSnapshotted = false

    // MARK: - Debounced Write

    private var writeTask: Task<Void, Never>?

    init(contextManager: ContextStateManager, compactionEngine: CompactionEngine) {
        self.contextManager = contextManager
        self.compactionEngine = compactionEngine
    }

    // MARK: - Tool Use Processing

    /// Called for every tool use — extracts file paths, bash commands, task updates
    func processToolUse(toolName: String, input: String) {
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        switch toolName {
        case "Read":
            if let path = json["file_path"] as? String {
                contextManager.trackFileChange(
                    path: path, type: .modified, summary: "Read"
                )
            }

        case "Edit":
            if let path = json["file_path"] as? String {
                let oldStr = (json["old_string"] as? String)?.prefix(60) ?? ""
                contextManager.trackFileChange(
                    path: path, type: .modified,
                    summary: "Edited: \(oldStr)..."
                )
            }

        case "Write":
            if let path = json["file_path"] as? String {
                contextManager.trackFileChange(
                    path: path, type: .created, summary: "Written"
                )
            }

        case "Bash":
            if let command = json["command"] as? String {
                processBashCommand(command)
            }

        case "TaskCreate":
            if let subject = json["subject"] as? String {
                contextManager.trackTask(subject, status: .pending)
            }

        case "TaskUpdate":
            if let statusStr = json["status"] as? String,
               let taskId = json["taskId"] as? String {
                let status: TaskItemStatus = statusStr == "completed" ? .completed
                    : statusStr == "in_progress" ? .inProgress : .pending
                contextManager.trackTask("Task \(taskId)", status: status)
            }

        default:
            break
        }

        scheduleContextWrite()
    }

    // MARK: - Assistant Text Processing

    /// Called with full text of each assistant turn — extracts decisions, next steps, current task
    func processAssistantText(_ text: String) {
        extractDecisions(from: text)
        extractNextSteps(from: text)
        inferCurrentTask(from: text)
        scheduleContextWrite()
    }

    // MARK: - Turn Metrics / Compaction Detection

    /// Called after each turn completes — detects compaction via token drop
    func processTurnMetrics(_ metrics: TurnMetrics) {
        let thisTurnInput = metrics.inputTokens

        print("[ContextPipeline] Turn input: \(thisTurnInput) tokens (prev: \(previousTurnInputTokens))")

        // Compaction detection: input drops >50% AND previous was >50K
        if previousTurnInputTokens > 50_000 && thisTurnInput > 0 {
            let dropRatio = Double(thisTurnInput) / Double(previousTurnInputTokens)
            if dropRatio < 0.5 {
                compactionDetected = true
                print("[ContextPipeline] COMPACTION DETECTED — input dropped from \(previousTurnInputTokens) to \(thisTurnInput)")

                if let recovery = compactionEngine.generateReinjectionPrompt() {
                    pendingReinjection = recovery
                    recoveryPending = true
                }
            }
        }

        // Pre-compaction snapshot at 70%
        let totalUsed = metrics.cumulativeInputTokens + metrics.cumulativeOutputTokens
        let contextPct = Double(totalUsed) / Double(contextManager.maxContextTokens)

        if contextPct > 0.7 && !hasSnapshotted {
            hasSnapshotted = true
            snapshotTaken = true
            print("[ContextPipeline] Context at \(Int(contextPct * 100))% — taking pre-compaction snapshot")

            let sessionId = metrics.sessionId ?? "active"
            compactionEngine.prepareForCompaction(sessionId: sessionId, projectDir: projectDirectory)
        }

        previousTurnInputTokens = thisTurnInput
        scheduleContextWrite()
    }

    // MARK: - Message Wrapping (Reinjection)

    /// Called before sending — prepends recovery context if pending
    func wrapMessage(_ text: String) -> String {
        guard let recovery = pendingReinjection else { return text }

        // Clear pending state
        pendingReinjection = nil
        recoveryPending = false

        print("[ContextPipeline] Reinjecting preserved context (\(recovery.count) chars)")

        return """
        [CONTEXT RECOVERY] The previous conversation was compacted. Here is the preserved context:

        \(recovery)

        ---

        \(text)
        """
    }

    // MARK: - Reset

    /// Reset state for a new session
    func reset() {
        compactionDetected = false
        recoveryPending = false
        snapshotTaken = false
        previousTurnInputTokens = 0
        pendingReinjection = nil
        hasSnapshotted = false
        writeTask?.cancel()
        writeTask = nil
    }

    // MARK: - Private: Decision Extraction

    private func extractDecisions(from text: String) {
        let patterns = [
            "I'll ", "I will ", "The approach is ", "Going with ",
            "Decision: ", "We'll ", "The fix is ", "The solution is "
        ]

        for pattern in patterns {
            guard let range = text.range(of: pattern) else { continue }

            let start = range.lowerBound
            let rest = text[start...]
            let lineEnd = rest.firstIndex(of: "\n") ?? rest.endIndex
            let decision = String(rest[start..<lineEnd]).prefix(200)

            if !decision.isEmpty {
                contextManager.trackDecision(
                    String(decision),
                    reasoning: "Auto-extracted from assistant response"
                )
            }
        }
    }

    // MARK: - Private: Next Steps Extraction

    private func extractNextSteps(from text: String) {
        let markers = ["Next steps:", "TODO:", "Remaining:", "Next:", "What's left:"]
        var steps: [String] = []

        for marker in markers {
            guard let range = text.range(of: marker, options: .caseInsensitive) else { continue }

            let afterMarker = text[range.upperBound...]
            let lines = afterMarker.components(separatedBy: "\n")

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
                    let step = String(trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)).prefix(200)
                    if !step.isEmpty {
                        steps.append(String(step))
                    }
                } else if trimmed.isEmpty {
                    continue
                } else if !trimmed.hasPrefix("#") {
                    break // End of list
                }
            }
        }

        if !steps.isEmpty {
            contextManager.setNextSteps(steps)
        }
    }

    // MARK: - Private: Task Inference

    private func inferCurrentTask(from text: String) {
        guard contextManager.currentSnapshot?.currentTask == nil else { return }

        // Use the first substantive line as the current task
        let lines = text.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && trimmed.count > 10 && !trimmed.hasPrefix("#") {
                contextManager.setCurrentTask(String(trimmed.prefix(200)))
                return
            }
        }
    }

    // MARK: - Private: Bash Command Analysis

    private func processBashCommand(_ command: String) {
        let cmd = command.lowercased()

        // Build detection
        let buildPatterns = ["xcodebuild", "npm run build", "swift build", "make ", "cargo build", "go build"]
        if buildPatterns.contains(where: { cmd.contains($0) }) {
            contextManager.setBuildStatus(BuildStatus(
                compiled: true,
                deployed: false,
                deployTarget: nil,
                timestamp: Date()
            ))
            return
        }

        // Deploy detection
        let deployPatterns: [(pattern: String, target: String)] = [
            ("vercel --prod", "Vercel"),
            ("wrangler pages deploy", "Cloudflare Pages"),
            ("git push", "Git Remote"),
            ("firebase deploy", "Firebase"),
            ("fly deploy", "Fly.io"),
        ]
        for (pattern, target) in deployPatterns {
            if cmd.contains(pattern) {
                contextManager.setBuildStatus(BuildStatus(
                    compiled: true,
                    deployed: true,
                    deployTarget: target,
                    timestamp: Date()
                ))
                return
            }
        }

        // Test detection
        let testPatterns = ["xcodebuild test", "npm test", "swift test", "pytest", "jest", "cargo test"]
        if testPatterns.contains(where: { cmd.contains($0) }) {
            contextManager.trackDiscovery("Tests executed: \(String(command.prefix(100)))")
        }
    }

    // MARK: - Private: Debounced Write

    private func scheduleContextWrite() {
        writeTask?.cancel()
        writeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.writeContextState()
        }
    }

    private func writeContextState() {
        guard let dir = projectDirectory else { return }
        contextManager.writeContextState(to: dir)
    }
}
