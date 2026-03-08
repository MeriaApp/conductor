import Foundation

/// Manages Claude CLI communication via per-message subprocess calls
/// Each user message launches: claude -p "message" --output-format stream-json --include-partial-messages --verbose --resume <sessionId>
/// Session continuity maintained via --resume with the CLI-generated session ID
@MainActor
final class ClaudeProcess: ObservableObject {

    // MARK: - Published State

    @Published var isRunning = false       // Session is active (ready to accept messages)
    @Published var isStreaming = false      // Currently receiving a response
    @Published var events: [StreamEvent] = []
    @Published var messages: [ConversationMessage] = []
    @Published var currentModel: String = "claude-opus-4-6"
    @Published var sessionId: String?      // CLI-generated session ID (from system event)
    @Published var cliVersion: String?
    @Published var totalCostUSD: Double = 0
    @Published var totalInputTokens: Int = 0
    @Published var totalOutputTokens: Int = 0
    @Published var error: String?

    /// Vibe Coder Mode — strips UI to essentials (no tool blocks, no thinking, simplified status)
    @Published var isVibeCoder: Bool = false

    /// Toggle thinking block visibility globally (Cmd+Shift+T)
    @Published var showThinking: Bool = true

    /// Auto-optimizations: env vars that save tokens and prevent drift
    @Published var optimizationsEnabled: Bool = true

    /// Auto-compaction threshold (percentage, 0-100). Default 85.
    @Published var autoCompactThreshold: Int = 85

    /// Agent Teams — enables Claude to autonomously spawn sub-agents for parallel work
    @Published var agentTeamsEnabled: Bool = false

    // MARK: - Private

    private var currentProcess: Process?
    private var readTask: Task<Void, Never>?

    /// Current message being streamed
    private var streamingMessage: ConversationMessage?
    private var streamingTextBlock: TextBlock?
    private var streamingThinkingBlock: ThinkingBlock?
    private var streamStartTime: Date?

    /// Error recovery: auto-retry on transient failures
    private var retryCount = 0
    private let maxRetries = 2
    private var lastPrompt: String?

    /// Watchdog: kills hung processes after timeout
    private var watchdogTask: Task<Void, Never>?
    private static let processTimeoutSeconds: TimeInterval = 300 // 5 minutes

    /// Stderr output (surfaced to UI instead of hidden)
    @Published var lastStderrMessage: String?

    /// Pending savings multiplier from effort/model routing (applied when turn cost arrives)
    var _pendingSavingsMultiplier: Double = 0
    /// Pending model savings multiplier (Opus→Sonnet = 0.80, Opus→Haiku = 0.95)
    var _pendingModelSavings: Double = 0

    /// Path to claude CLI
    private let claudePath: String

    /// Working directory for the session
    @Published var workingDirectory: String?

    /// System prompt appended to the agent's role (used on first message only)
    var systemPrompt: String?

    /// CLI configuration flags
    @Published var effortLevel: EffortLevel = .medium
    /// When true, effort level auto-adjusts per message complexity (default on)
    @Published var smartEffort: Bool = true
    @Published var permissionMode: CLIPermissionMode = .bypassPermissions
    @Published var useWorktree: Bool = false
    @Published var outputMode: OutputMode = .standard
    @Published var selectedModel: ModelChoice?

    /// Max budget in USD per session (default $5 — prevents runaway sessions)
    var maxBudgetUSD: Double = 5.0

    /// Per-turn cost of the most recent turn (for display)
    @Published var lastTurnCostUSD: Double = 0

    /// Estimated cumulative savings from smart effort + model routing
    @Published var estimatedSavingsUSD: Double = 0

    /// Callbacks for service integration
    var onResult: ((ResultEvent) -> Void)?
    var onSystem: ((SystemEvent) -> Void)?
    var onError: ((String) -> Void)?
    var onToolUse: ((String, String) -> Void)?  // (toolName, input) — fires when agent uses a tool
    var onAssistantText: ((String) -> Void)?    // Full text of each assistant turn
    var onTurnComplete: ((TurnMetrics) -> Void)? // Per-turn metrics (for compaction detection)
    var onBeforeSend: ((String) -> String)?     // Transform message before sending (for reinjection)
    var onEmptyResponse: (() -> Void)?           // Fires when Claude returns near-empty response (context loss signal)

    /// Last user message text (for retry on empty response)
    var lastUserMessage: String? {
        messages.last(where: { $0.role == .user })?.copyText()
    }

    /// Whether any real work happened — tool use (file edits, bash, etc.) or 4+ message exchanges.
    /// Used to skip closeout ceremony for trivial/empty sessions.
    var hasSubstantiveWork: Bool {
        guard !messages.isEmpty else { return false }
        // Any tool use = real work
        let hasToolUse = messages.contains { msg in
            msg.blocks.contains { $0 is ToolUseBlock }
        }
        if hasToolUse { return true }
        // 4+ messages = enough conversation to be worth saving
        return messages.count >= 4
    }

    init(claudePath: String? = nil) {
        if let path = claudePath {
            self.claudePath = path
        } else {
            let candidates = [
                "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/claude",
                "/usr/local/bin/claude",
                "/opt/homebrew/bin/claude"
            ]
            self.claudePath = candidates.first { FileManager.default.fileExists(atPath: $0) }
                ?? "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/claude"
        }
    }

    // MARK: - Lifecycle

    /// Initialize session state — no process launched until first send()
    func start(directory: String? = nil, resumeSession: String? = nil) {
        stop()
        workingDirectory = directory ?? workingDirectory
        if let session = resumeSession {
            sessionId = session
        }
        isRunning = true
        error = nil
    }

    /// Send user input to Claude — launches a new CLI process for this turn
    func send(_ text: String) {
        guard isRunning else { return }

        // Cancel any in-flight turn
        cancelCurrentTurn()

        // Reset retry state for new user message
        retryCount = 0
        lastPrompt = text

        // Smart effort: auto-adjust effort level based on message complexity
        if smartEffort {
            let routed = SmartEffortRouter.classify(text)
            effortLevel = routed
            // Track savings: effort downgrade from high baseline
            switch routed {
            case .low: _pendingSavingsMultiplier = 0.50  // ~50% cheaper than high
            case .medium: _pendingSavingsMultiplier = 0.30  // ~30% cheaper than high
            case .high: _pendingSavingsMultiplier = 0.0
            }
        }

        // Add user message to conversation (show original text)
        let userMessage = ConversationMessage(
            role: .user,
            blocks: [TextBlock(text: text)]
        )
        messages.append(userMessage)

        // Apply before-send transform (e.g., context reinjection)
        let promptText = onBeforeSend?(text) ?? text

        // Launch process for this turn
        launchTurn(prompt: promptText)
    }

    /// Interrupt current operation (SIGINT)
    func interrupt() {
        currentProcess?.interrupt()
        isStreaming = false
        finalizeStreamingMessage()
    }

    /// Stop the session entirely
    func stop() {
        cancelCurrentTurn()
        isRunning = false
    }

    /// Trigger manual context compaction, optionally with instructions about what to preserve
    func compact(instructions: String? = nil) {
        let cmd = instructions.map { "/compact \($0)" } ?? "/compact"
        send(cmd)
    }

    private func cancelCurrentTurn() {
        readTask?.cancel()
        readTask = nil
        if let proc = currentProcess, proc.isRunning {
            proc.terminate()
        }
        currentProcess = nil
        isStreaming = false
        finalizeStreamingMessage()
    }

    // MARK: - Per-Message Process Launch

    private func launchTurn(prompt: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: claudePath)

        var args = [
            "-p", prompt,
            "--output-format", "stream-json",
            "--include-partial-messages",
            "--verbose"
        ]
        // Permission mode
        switch permissionMode {
        case .bypassPermissions:
            args += ["--dangerously-skip-permissions"]
        case .default_:
            break // No flag needed
        case .acceptEdits:
            args += ["--permission-mode", "acceptEdits"]
        case .plan:
            args += ["--permission-mode", "plan"]
        }
        // Effort level
        args += ["--effort", effortLevel.rawValue]
        // Model override
        if let model = selectedModel {
            args += ["--model", model.rawValue]
        }
        // Worktree
        if useWorktree && sessionId == nil {
            args += ["--worktree"]
        }
        // Budget cap
        if maxBudgetUSD > 0 {
            args += ["--max-budget-usd", String(format: "%.2f", maxBudgetUSD)]
        }
        if let session = sessionId {
            args += ["--resume", session]
        }
        // Add role system prompt on first turn (before session exists)
        // Output mode prefix is prepended to the system prompt
        let modePrefix = outputMode.systemPromptPrefix
        let fullSystemPrompt = [modePrefix, systemPrompt].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n")
        if sessionId == nil, !fullSystemPrompt.isEmpty {
            args += ["--append-system-prompt", fullSystemPrompt]
        }
        proc.arguments = args

        // Unset CLAUDECODE env to avoid nested session check
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "CLAUDECODE")

        // Auto-enable Conductor optimizations
        if optimizationsEnabled {
            env["ENABLE_EXPERIMENTAL_MCP_CLI"] = "true"                              // On-demand MCP tool loading, ~80% fewer tokens
            env["CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR"] = "1"                    // Prevent cd drift between bash commands
            env["CLAUDE_AUTOCOMPACT_PCT_OVERRIDE"] = String(autoCompactThreshold)    // User-tunable compaction
        }

        // Agent Teams — autonomous sub-agent spawning
        if agentTeamsEnabled {
            env["CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"] = "1"
        }

        proc.environment = env

        if let dir = workingDirectory {
            proc.currentDirectoryURL = URL(fileURLWithPath: dir)
        }

        let stdout = Pipe()
        let stderr = Pipe()
        proc.standardOutput = stdout
        proc.standardError = stderr
        // No stdin needed — prompt is passed via -p flag

        currentProcess = proc
        isStreaming = true
        streamStartTime = Date()
        error = nil

        proc.terminationHandler = { [weak self] process in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isStreaming = false
                self.watchdogTask?.cancel()
                self.watchdogTask = nil
                self.finalizeStreamingMessage()
                self.currentProcess = nil

                // Non-zero exit (except SIGINT=2) is an error
                let status = process.terminationStatus
                if status != 0 && status != 2 {
                    // Auto-retry for transient failures if we have a session to resume
                    if self.retryCount < self.maxRetries, self.sessionId != nil, let prompt = self.lastPrompt {
                        self.retryCount += 1
                        self.error = "Retrying... (\(self.retryCount)/\(self.maxRetries + 1))"
                        // Brief delay before retry
                        try? await Task.sleep(for: .seconds(1))
                        self.launchTurn(prompt: prompt)
                    } else {
                        let msg = "Claude CLI exited with code \(status)"
                        self.error = msg
                        self.onError?(msg)
                    }
                }
            }
        }

        do {
            try proc.run()
            startReadingOutput(from: stdout)
            startReadingErrors(from: stderr)
            startWatchdog()
        } catch {
            self.error = "Failed to launch Claude CLI: \(error.localizedDescription)"
            isStreaming = false
            onError?(self.error!)
        }
    }

    // MARK: - Output Reading

    private func startReadingOutput(from pipe: Pipe) {
        readTask = Task.detached { [weak self] in
            let handle = pipe.fileHandleForReading
            var buffer = Data()

            while !Task.isCancelled {
                let newData = handle.availableData
                if newData.isEmpty { break } // EOF

                buffer.append(newData)

                // Process complete lines
                while let newlineRange = buffer.range(of: Data("\n".utf8)) {
                    let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                    buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)

                    if let line = String(data: lineData, encoding: .utf8),
                       !line.trimmingCharacters(in: .whitespaces).isEmpty {
                        await self?.processLine(line)
                    }
                }
            }
        }
    }

    private func startReadingErrors(from pipe: Pipe) {
        Task.detached { [weak self] in
            let handle = pipe.fileHandleForReading
            var accumulated = ""
            while !Task.isCancelled {
                let data = handle.availableData
                if data.isEmpty { break }
                if let text = String(data: data, encoding: .utf8) {
                    accumulated += text
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    await MainActor.run {
                        print("[Claude stderr] \(trimmed)")
                        // Surface meaningful errors (skip progress/debug noise)
                        if !trimmed.isEmpty && !trimmed.hasPrefix("Downloading") && !trimmed.hasPrefix("  ") {
                            self?.lastStderrMessage = String(trimmed.prefix(200))
                        }
                    }
                }
            }
        }
    }

    /// Kill the process if it runs longer than the timeout
    private func startWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.processTimeoutSeconds))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.isStreaming else { return }
                let msg = "Process timed out after \(Int(Self.processTimeoutSeconds))s"
                self.error = msg
                self.onError?(msg)
                self.currentProcess?.terminate()
            }
        }
    }

    // MARK: - Event Processing

    private func processLine(_ line: String) {
        guard let event = StreamEventParser.parse(line: line) else { return }

        // Cap events array to prevent unbounded memory growth
        if events.count >= 200 {
            events.removeFirst(events.count - 150)
        }
        events.append(event)

        switch event {
        case .system(let systemEvent):
            handleSystem(systemEvent)

        case .assistant(let assistantEvent):
            handleAssistant(assistantEvent)

        case .user(let userEvent):
            handleToolResult(userEvent)

        case .contentBlockDelta(let delta):
            handleDelta(delta)

        case .result(let resultEvent):
            handleResult(resultEvent)
        }
    }

    private func handleSystem(_ event: SystemEvent) {
        if let model = event.model {
            currentModel = model
        }
        // Store CLI-generated session ID for --resume on subsequent messages
        if let sid = event.sessionId {
            sessionId = sid
        }
        // Update working directory from CLI (drives window title)
        if let cwd = event.cwd {
            workingDirectory = cwd
        }
        cliVersion = event.cliVersion
        onSystem?(event)
    }

    private func handleAssistant(_ event: AssistantEvent) {
        // The assistant event contains the complete message
        // If we were streaming, discard the streaming message — the assistant event supersedes it
        let hadStreaming = streamingMessage != nil
        finalizeStreamingMessage()

        if hadStreaming,
           let lastIdx = messages.indices.last,
           messages[lastIdx].role == .assistant {
            messages.removeLast()
        }

        var blocks: [any ContentBlockProtocol] = []

        for raw in event.message.content {
            switch raw.type {
            case "text":
                if let text = raw.text {
                    // Parse markdown into typed blocks (code, lists, diffs, etc.)
                    blocks.append(contentsOf: MarkdownParser.parse(text))
                }
            case "tool_use":
                let toolName = raw.name ?? "unknown"
                let input = raw.input?.prettyJSON ?? ""
                blocks.append(ToolUseBlock(toolName: toolName, input: input, status: .running))
                onToolUse?(toolName, input)
            case "thinking":
                let text = raw.thinking ?? raw.text ?? ""
                blocks.append(ThinkingBlock(text: text))
            default:
                if let text = raw.text {
                    blocks.append(TextBlock(text: text))
                }
            }
        }

        if let model = event.message.model {
            currentModel = model
        }

        let message = ConversationMessage(
            role: .assistant,
            blocks: blocks,
            isStreaming: false
        )
        messages.append(message)

        // Fire assistant text callback with concatenated text content
        var fullText = ""
        for raw in event.message.content {
            if raw.type == "text", let text = raw.text {
                fullText += text
            }
        }
        if !fullText.isEmpty {
            onAssistantText?(fullText)
        }

        // Empty response detection — signal possible context loss
        let responseLength = fullText.trimmingCharacters(in: .whitespacesAndNewlines).count
        let elapsed = streamStartTime.map { Date().timeIntervalSince($0) } ?? 0
        if responseLength < 10 && elapsed > 5 {
            onEmptyResponse?()
        }
    }

    private func handleToolResult(_ event: UserEvent) {
        // Update the last tool_use block's status
        guard var lastMessage = messages.last, lastMessage.role == .assistant else { return }

        for result in event.message.content {
            for i in lastMessage.blocks.indices.reversed() {
                if var toolBlock = lastMessage.blocks[i] as? ToolUseBlock,
                   toolBlock.status == .running {
                    toolBlock.status = result.isError == true ? .failed : .completed
                    toolBlock.output = result.content
                    toolBlock.isError = result.isError ?? false
                    lastMessage.blocks[i] = toolBlock
                    break
                }
            }
        }

        messages[messages.count - 1] = lastMessage
    }

    private func handleDelta(_ delta: ContentBlockDelta) {
        isStreaming = true

        switch delta.delta.type {
        case "text_delta":
            if let text = delta.delta.text {
                appendToStreamingText(text)
            }

        case "thinking_delta":
            if let text = delta.delta.thinking {
                appendToStreamingThinking(text)
            }

        default:
            break
        }
    }

    private func handleResult(_ event: ResultEvent) {
        isStreaming = false
        finalizeStreamingMessage()

        // Capture per-turn tokens BEFORE accumulating
        let thisTurnInput = event.usage?.inputTokens ?? 0
        let thisTurnOutput = event.usage?.outputTokens ?? 0

        // Accumulate totals
        totalInputTokens += thisTurnInput
        totalOutputTokens += thisTurnOutput

        if let cost = event.totalCostUSD {
            lastTurnCostUSD = cost
            totalCostUSD += cost
            // Apply pending savings estimate
            let savingsMultiplier = max(_pendingSavingsMultiplier, _pendingModelSavings)
            if savingsMultiplier > 0 {
                estimatedSavingsUSD += cost * savingsMultiplier / (1.0 - savingsMultiplier)
            }
            _pendingSavingsMultiplier = 0
            _pendingModelSavings = 0
        }
        // Update session ID from result (should match system event)
        if let sid = event.sessionId {
            sessionId = sid
        }

        // Fire turn-complete callback with per-turn metrics
        onTurnComplete?(TurnMetrics(
            inputTokens: thisTurnInput,
            outputTokens: thisTurnOutput,
            cumulativeInputTokens: totalInputTokens,
            cumulativeOutputTokens: totalOutputTokens,
            totalCostUSD: totalCostUSD,
            sessionId: sessionId
        ))

        onResult?(event)

        // Sound + notification: response complete
        SoundManager.shared.playResponseComplete()
        SoundManager.shared.playBackgroundComplete()
        NotificationService.shared.sendCompletionNotification(
            title: "Claude finished",
            body: String(messages.last?.copyText().prefix(100) ?? "Response complete")
        )
    }

    // MARK: - Streaming Message Assembly

    private func appendToStreamingText(_ text: String) {
        if streamingMessage == nil {
            streamingTextBlock = TextBlock(text: "")
            streamingMessage = ConversationMessage(
                role: .assistant,
                blocks: [],
                isStreaming: true
            )
        }

        if streamingThinkingBlock != nil {
            // Transition from thinking to text
            finalizeStreamingThinking()
        }

        if streamingTextBlock == nil {
            streamingTextBlock = TextBlock(text: "")
        }

        streamingTextBlock!.text += text
        updateStreamingMessage()
    }

    private func appendToStreamingThinking(_ text: String) {
        if streamingMessage == nil {
            streamingMessage = ConversationMessage(
                role: .assistant,
                blocks: [],
                isStreaming: true
            )
        }

        if streamingThinkingBlock == nil {
            streamingThinkingBlock = ThinkingBlock(text: "", isCollapsed: false, isStreaming: true)
        }

        streamingThinkingBlock!.text += text
        updateStreamingMessage()
    }

    private func updateStreamingMessage() {
        guard let msg = streamingMessage else { return }

        // Find or append the streaming message
        if let lastIdx = messages.indices.last,
           messages[lastIdx].role == .assistant && messages[lastIdx].isStreaming {
            // Update blocks in-place instead of rebuilding the entire array
            var blocks: [any ContentBlockProtocol] = []
            if let thinking = streamingThinkingBlock {
                blocks.append(thinking)
            }
            if let text = streamingTextBlock {
                blocks.append(text)
            }
            messages[lastIdx].blocks = blocks
        } else {
            var newMsg = msg
            var blocks: [any ContentBlockProtocol] = []
            if let thinking = streamingThinkingBlock {
                blocks.append(thinking)
            }
            if let text = streamingTextBlock {
                blocks.append(text)
            }
            newMsg.blocks = blocks
            messages.append(newMsg)
        }
    }

    private func finalizeStreamingThinking() {
        if streamingThinkingBlock != nil {
            streamingThinkingBlock!.isStreaming = false
            streamingThinkingBlock!.isCollapsed = true
            if let start = streamStartTime {
                streamingThinkingBlock!.duration = Date().timeIntervalSince(start)
            }
        }
    }

    private func finalizeStreamingMessage() {
        guard var msg = streamingMessage else { return }

        finalizeStreamingThinking()
        msg.isStreaming = false
        if let start = streamStartTime {
            msg.duration = Date().timeIntervalSince(start)
        }

        // Update the message in the array
        if let lastIdx = messages.indices.last,
           messages[lastIdx].role == .assistant && messages[lastIdx].isStreaming {
            messages[lastIdx] = msg
        }

        streamingMessage = nil
        streamingTextBlock = nil
        streamingThinkingBlock = nil
        streamStartTime = nil
    }
}

// MARK: - Turn Metrics

/// Per-turn token metrics for compaction detection
struct TurnMetrics {
    let inputTokens: Int            // THIS turn's input tokens (context window size)
    let outputTokens: Int           // THIS turn's output tokens
    let cumulativeInputTokens: Int  // Running total across all turns
    let cumulativeOutputTokens: Int
    let totalCostUSD: Double
    let sessionId: String?
}

// MARK: - CLI Configuration Enums

/// Effort levels for Claude CLI (maps to --effort flag)
enum EffortLevel: String, CaseIterable {
    case low = "low"
    case medium = "medium"
    case high = "high"

    var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    var icon: String {
        switch self {
        case .low: return "hare"
        case .medium: return "figure.walk"
        case .high: return "flame"
        }
    }
}

/// Model choices for the model switcher
enum ModelChoice: String, CaseIterable {
    case opus = "opus"
    case sonnet = "sonnet"
    case haiku = "haiku"

    var displayName: String {
        switch self {
        case .opus: return "Opus"
        case .sonnet: return "Sonnet"
        case .haiku: return "Haiku"
        }
    }

    var icon: String {
        switch self {
        case .opus: return "diamond.fill"
        case .sonnet: return "sparkle"
        case .haiku: return "leaf"
        }
    }
}

/// Permission modes for Claude CLI (maps to --permission-mode flag)
enum CLIPermissionMode: String, CaseIterable {
    case default_ = "default"
    case acceptEdits = "acceptEdits"
    case bypassPermissions = "bypassPermissions"
    case plan = "plan"

    var displayName: String {
        switch self {
        case .default_: return "Default"
        case .acceptEdits: return "Accept Edits"
        case .bypassPermissions: return "Bypass"
        case .plan: return "Plan"
        }
    }

    var subtitle: String {
        switch self {
        case .default_: return "Ask before edits and commands"
        case .acceptEdits: return "Auto-approve file edits"
        case .bypassPermissions: return "No permission checks"
        case .plan: return "Plan mode — suggest, don't execute"
        }
    }
}

/// Smart effort routing — classifies message complexity to pick the right effort level
/// Saves 30-50% tokens by not using high effort for simple/conversational messages
enum SmartEffortRouter {

    /// Classify a user message into the appropriate effort level
    static func classify(_ message: String) -> EffortLevel {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        let wordCount = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.count

        // Very short conversational messages → low effort
        if wordCount <= 5 && isConversational(lowered) {
            return .low
        }

        // Short messages without code keywords → medium
        if wordCount <= 15 && !containsComplexWork(lowered) {
            return .medium
        }

        // Complex work patterns → high effort
        if containsComplexWork(lowered) {
            return .high
        }

        // Default: medium for everything else
        return .medium
    }

    private static func isConversational(_ message: String) -> Bool {
        let patterns = [
            "yes", "no", "ok", "okay", "sure", "go ahead", "do it",
            "wait", "stop", "continue", "next", "skip", "done",
            "thanks", "thank you", "got it", "perfect", "great",
            "what?", "why?", "how?", "really?", "huh",
            "i meant", "i said", "never mind", "nvm",
            "sounds good", "looks good", "lgtm", "ship it",
            "go for it", "let's do it", "proceed", "yep", "nope",
        ]
        return patterns.contains { message.hasPrefix($0) || message == $0 }
    }

    private static func containsComplexWork(_ message: String) -> Bool {
        let patterns = [
            "refactor", "architect", "design", "implement", "build",
            "debug", "fix", "investigate", "analyze", "optimize",
            "rewrite", "restructure", "migrate", "upgrade",
            "create a", "write a", "add a feature", "make a",
            "deploy", "test", "audit", "review",
            "explain how", "help me understand", "walk me through",
            "multi-file", "across the codebase", "all files",
        ]
        return patterns.contains { message.contains($0) }
    }
}

/// Output modes — control response style via system prompt prefix
enum OutputMode: String, CaseIterable {
    case standard = "standard"
    case concise = "concise"
    case detailed = "detailed"
    case codeOnly = "code-only"

    var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .concise: return "Concise"
        case .detailed: return "Detailed"
        case .codeOnly: return "Code Only"
        }
    }

    var icon: String {
        switch self {
        case .standard: return "text.alignleft"
        case .concise: return "text.line.first.and.arrowtriangle.forward"
        case .detailed: return "doc.text.fill"
        case .codeOnly: return "chevron.left.forwardslash.chevron.right"
        }
    }

    var systemPromptPrefix: String? {
        switch self {
        case .standard:
            return nil
        case .concise:
            return "Be extremely concise. Skip explanations unless asked. Lead with code or the answer. One sentence max for context."
        case .detailed:
            return "Be thorough and detailed. Explain your reasoning step by step. Include context, alternatives considered, and potential edge cases."
        case .codeOnly:
            return "Respond with code only. No explanations, no prose, no comments unless the code requires them. Just the code."
        }
    }

    /// Cycle to the next mode
    func next() -> OutputMode {
        let all = OutputMode.allCases
        guard let idx = all.firstIndex(of: self) else { return .standard }
        let nextIdx = (idx + 1) % all.count
        return all[nextIdx]
    }
}
