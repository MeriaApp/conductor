import Foundation

/// Manages Claude CLI as a persistent interactive process.
/// Launches once on start(), keeps stdin open, writes JSON messages per turn.
/// Uses: claude -p --input-format stream-json --output-format stream-json --include-partial-messages --verbose
/// Session is a single live process — same as running Claude CLI in terminal.
@MainActor
final class ClaudeProcess: ObservableObject {

    // MARK: - Published State

    @Published var isRunning = false       // Session is active (process alive, ready for messages)
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

    /// Autonomous Mode — bypass permissions + auto-retry on empty response (ON by default for power users)
    @Published var autonomousMode: Bool = true

    /// Auto-optimizations: env vars that save tokens and prevent drift
    @Published var optimizationsEnabled: Bool = true

    /// Auto-compaction threshold (percentage, 0-100). Default 85.
    @Published var autoCompactThreshold: Int = 85

    /// Agent Teams — enables Claude to autonomously spawn sub-agents for parallel work
    @Published var agentTeamsEnabled: Bool = true

    // MARK: - Private

    private var currentProcess: Process?
    private var stdinHandle: FileHandle?
    private var readTask: Task<Void, Never>?
    private var stderrReadTask: Task<Void, Never>?
    private var pendingSendTask: Task<Void, Never>?

    /// Generation counter — detects stale writes after stop()+start() cycles
    private var sessionGeneration: Int = 0

    /// Current message being streamed
    private var streamingMessage: ConversationMessage?
    private var streamingTextBlock: TextBlock?
    private var streamingThinkingBlock: ThinkingBlock?
    private var streamStartTime: Date?

    /// Error recovery
    private var lastPrompt: String?
    /// Auto-retry counter for empty responses (max 1 retry per turn)
    private var emptyResponseRetryCount: Int = 0
    /// Deferred retry — set in handleAssistant, executed in handleResult after stream ends cleanly
    private var pendingRetryPrompt: String?

    /// Per-response watchdog (not per-process — process is long-lived)
    private var watchdogTask: Task<Void, Never>?
    private static let responseTimeoutSeconds: TimeInterval = 300 // 5 minutes per response

    /// Tracks whether stop() was called deliberately vs process dying unexpectedly
    private var processTerminatedDeliberately = false

    /// Event history cap — prevents unbounded memory growth on long sessions
    private static let maxEventCount = 200
    private static let eventTrimTarget = 150

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

    /// System prompt appended to the agent's role (set at process launch)
    var systemPrompt: String?

    /// CLI configuration flags (applied at process launch — changes require restart)
    @Published var effortLevel: EffortLevel = .medium
    /// When true, effort level is tracked for savings display (informational in interactive mode)
    @Published var smartEffort: Bool = true
    @Published var permissionMode: CLIPermissionMode = .bypassPermissions
    @Published var useWorktree: Bool = false
    @Published var outputMode: OutputMode = .standard
    @Published var selectedModel: ModelChoice?

    /// Max budget in USD per session (default $5 — prevents runaway sessions)
    var maxBudgetUSD: Double = 0

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
        let hasToolUse = messages.contains { msg in
            msg.blocks.contains { $0 is ToolUseBlock }
        }
        if hasToolUse { return true }
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

    /// Launch a persistent Claude CLI process.
    /// The process stays alive for the entire session — messages are written to stdin.
    func start(directory: String? = nil, resumeSession: String? = nil) {
        stop()
        sessionGeneration += 1
        workingDirectory = directory ?? workingDirectory
        // Only resume if explicitly requested — otherwise clear stale session ID
        sessionId = resumeSession
        error = nil
        processTerminatedDeliberately = false
        emptyResponseRetryCount = 0
        pendingRetryPrompt = nil
        launchPersistentProcess()
    }

    /// Write a user message to the persistent Claude CLI process via stdin.
    func send(_ text: String) {
        guard isRunning, stdinHandle != nil else {
            let msg = "Session ended — restart to continue"
            error = msg
            onError?(msg)
            return
        }

        // Interrupt any in-flight response (SIGINT, not kill)
        if isStreaming {
            currentProcess?.interrupt()
            isStreaming = false
            finalizeStreamingMessage()
            // Cancel any previous pending send, then wait for CLI to process interrupt
            pendingSendTask?.cancel()
            pendingSendTask = Task {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                writeTurn(text)
            }
            return
        }

        writeTurn(text)
    }

    /// Internal: prepare message and write to stdin
    private func writeTurn(_ text: String) {
        lastPrompt = text

        // Smart effort: track for savings display (informational — effort is set at launch)
        if smartEffort {
            let routed = SmartEffortRouter.classify(text)
            switch routed {
            case .low: _pendingSavingsMultiplier = 0.50
            case .medium: _pendingSavingsMultiplier = 0.30
            case .high: _pendingSavingsMultiplier = 0.0
            }
        }

        // Add user message to conversation
        let userMessage = ConversationMessage(
            role: .user,
            blocks: [TextBlock(text: text)]
        )
        messages.append(userMessage)

        // Apply before-send transform (e.g., context reinjection)
        let promptText = onBeforeSend?(text) ?? text

        // Write JSON to stdin
        let json: [String: Any] = [
            "type": "user",
            "message": [
                "role": "user",
                "content": promptText
            ]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: json),
              var jsonString = String(data: jsonData, encoding: .utf8) else {
            error = "Failed to serialize message"
            return
        }

        jsonString += "\n"

        guard let writeData = jsonString.data(using: .utf8) else { return }

        streamStartTime = Date()

        // Write to stdin using POSIX write — avoids NSFileHandleOperationException on dead pipes
        let fd = stdinHandle?.fileDescriptor ?? -1
        let generation = sessionGeneration
        Task.detached {
            guard fd >= 0 else { return }
            let result = writeData.withUnsafeBytes { ptr -> Int in
                guard let base = ptr.baseAddress else { return -1 }
                return Darwin.write(fd, base, ptr.count)
            }
            await MainActor.run { [weak self] in
                guard let self, self.sessionGeneration == generation else { return }
                if result > 0 {
                    self.isStreaming = true
                    self.startResponseWatchdog()
                } else {
                    let msg = "Claude CLI process ended — restart session to continue"
                    self.error = msg
                    self.isStreaming = false
                    self.isRunning = false
                    self.onError?(msg)
                }
            }
        }
    }

    /// Interrupt current operation (SIGINT) — process stays alive
    func interrupt() {
        currentProcess?.interrupt()
        isStreaming = false
        watchdogTask?.cancel()
        watchdogTask = nil
        finalizeStreamingMessage()
    }

    /// Stop the session — terminate the persistent process
    func stop() {
        processTerminatedDeliberately = true
        pendingSendTask?.cancel()
        pendingSendTask = nil
        watchdogTask?.cancel()
        watchdogTask = nil
        readTask?.cancel()
        readTask = nil
        stderrReadTask?.cancel()
        stderrReadTask = nil

        // Close stdin to signal EOF, then terminate
        if let handle = stdinHandle {
            try? handle.close()
            stdinHandle = nil
        }
        if let proc = currentProcess, proc.isRunning {
            proc.terminate()
        }
        currentProcess = nil
        isRunning = false
        isStreaming = false
        finalizeStreamingMessage()
    }

    /// Trigger manual context compaction
    func compact(instructions: String? = nil) {
        let cmd = instructions.map { "/compact \($0)" } ?? "/compact"
        send(cmd)
    }

    // MARK: - Persistent Process Launch

    private func launchPersistentProcess() {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: claudePath)

        var args = [
            "-p",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--include-partial-messages",
            "--verbose"
        ]

        // Permission mode
        switch permissionMode {
        case .bypassPermissions:
            args += ["--dangerously-skip-permissions"]
        case .default_:
            break
        case .acceptEdits:
            args += ["--permission-mode", "acceptEdits"]
        case .plan:
            args += ["--permission-mode", "plan"]
        }

        // Effort level (session-level)
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

        // Resume existing session
        if let session = sessionId {
            args += ["--resume", session]
        }

        // System prompt (set once at launch)
        let modePrefix = outputMode.systemPromptPrefix
        let fullSystemPrompt = [modePrefix, systemPrompt].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n")
        if sessionId == nil, !fullSystemPrompt.isEmpty {
            args += ["--append-system-prompt", fullSystemPrompt]
        }

        proc.arguments = args

        // Environment
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "CLAUDECODE")

        if optimizationsEnabled {
            env["ENABLE_EXPERIMENTAL_MCP_CLI"] = "true"
            env["CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR"] = "1"
            env["CLAUDE_AUTOCOMPACT_PCT_OVERRIDE"] = String(autoCompactThreshold)
        }

        if agentTeamsEnabled {
            env["CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"] = "1"
        }

        proc.environment = env

        if let dir = workingDirectory {
            proc.currentDirectoryURL = URL(fileURLWithPath: dir)
        }

        // Set up all three pipes — stdin stays open for writing
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        stdinHandle = stdinPipe.fileHandleForWriting

        currentProcess = proc

        let launchGeneration = sessionGeneration
        proc.terminationHandler = { [weak self] process in
            Task { @MainActor [weak self] in
                guard let self else { return }

                // Ignore termination from a previous session's process — a new one has already launched
                guard self.sessionGeneration == launchGeneration else { return }

                // Close stdin immediately — prevents writes to dead process
                if let handle = self.stdinHandle {
                    try? handle.close()
                    self.stdinHandle = nil
                }

                self.isStreaming = false
                self.watchdogTask?.cancel()
                self.watchdogTask = nil
                self.finalizeStreamingMessage()

                // If stop() was called, this is expected — don't surface error
                guard !self.processTerminatedDeliberately else { return }

                let status = process.terminationStatus
                if status != 0 && status != 2 {
                    // Unexpected exit — surface error
                    let msg = "Claude CLI process exited unexpectedly (code \(status))"
                    self.error = msg
                    self.isRunning = false
                    self.onError?(msg)
                } else {
                    // Clean exit (0) or SIGINT (2) — process is dead either way
                    self.isRunning = false
                }
            }
        }

        do {
            try proc.run()
            isRunning = true
            error = nil
            startReadingOutput(from: stdoutPipe)
            startReadingErrors(from: stderrPipe)
        } catch {
            let msg = "Failed to launch Claude CLI: \(error.localizedDescription)"
            self.error = msg
            isRunning = false
            onError?(msg)
        }
    }

    // MARK: - Output Reading (continuous for the life of the process)

    private func startReadingOutput(from pipe: Pipe) {
        readTask = Task.detached { [weak self] in
            let handle = pipe.fileHandleForReading
            var buffer = Data()

            while !Task.isCancelled {
                let newData = handle.availableData
                if newData.isEmpty { break } // EOF — process died or stdin closed

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
        stderrReadTask = Task.detached { [weak self] in
            let handle = pipe.fileHandleForReading
            while !Task.isCancelled {
                let data = handle.availableData
                if data.isEmpty { break }
                if let text = String(data: data, encoding: .utf8) {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    await MainActor.run {
                        if !trimmed.isEmpty {
                            print("[Claude stderr] \(trimmed)")
                        }
                        // Surface meaningful errors (skip progress/debug noise)
                        if !trimmed.isEmpty && !trimmed.hasPrefix("Downloading") && !trimmed.hasPrefix("  ") {
                            self?.lastStderrMessage = String(trimmed.prefix(200))
                        }
                    }
                }
            }
        }
    }

    /// Per-response watchdog — interrupts response if no result event within timeout
    private func startResponseWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.responseTimeoutSeconds))
            guard !Task.isCancelled else { return }
            guard let self, self.isStreaming else { return }
            let msg = "Response timed out after \(Int(Self.responseTimeoutSeconds))s"
            self.error = msg
            self.onError?(msg)
            self.currentProcess?.interrupt()
            self.isStreaming = false
            self.finalizeStreamingMessage()
        }
    }

    // MARK: - Event Processing

    private func processLine(_ line: String) {
        guard let event = StreamEventParser.parse(line: line) else { return }

        // Cap events array to prevent unbounded memory growth
        if events.count >= Self.maxEventCount {
            events.removeFirst(events.count - Self.eventTrimTarget)
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
        if let sid = event.sessionId {
            sessionId = sid
        }
        if let cwd = event.cwd {
            workingDirectory = cwd
        }
        cliVersion = event.cliVersion
        onSystem?(event)
    }

    private func handleAssistant(_ event: AssistantEvent) {
        let hadStreaming = streamingMessage != nil
        finalizeStreamingMessage()

        if hadStreaming,
           let lastIdx = messages.indices.last,
           messages[lastIdx].role == .assistant,
           messages[lastIdx].isStreaming {
            messages.removeLast()
        }

        var blocks: [any ContentBlockProtocol] = []

        for raw in event.message.content {
            switch raw.type {
            case "text":
                if let text = raw.text {
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

        // Fire assistant text callback
        var fullText = ""
        for raw in event.message.content {
            if raw.type == "text", let text = raw.text {
                fullText += text
            }
        }
        if !fullText.isEmpty {
            onAssistantText?(fullText)
        }

        // Empty response detection — only for text-only responses (not tool use)
        // Tool-use responses legitimately have no text — don't treat them as empty
        let hasToolUse = event.message.content.contains { $0.type == "tool_use" }
        let hasThinking = event.message.content.contains { $0.type == "thinking" }
        let isFinalResponse = event.message.stopReason == "end_turn"

        if !hasToolUse && !hasThinking && isFinalResponse {
            let responseLength = fullText.trimmingCharacters(in: .whitespacesAndNewlines).count
            let elapsed = streamStartTime.map { Date().timeIntervalSince($0) } ?? 0
            if responseLength < 10 && elapsed > 5 {
                if emptyResponseRetryCount == 0, let prompt = lastPrompt {
                    emptyResponseRetryCount += 1
                    print("[ClaudeProcess] Context may have been lost — scheduling retry")
                    // Flag for retry — handled in handleResult after stream ends cleanly
                    pendingRetryPrompt = prompt
                } else {
                    // Retry already attempted or no prompt — surface warning to user
                    onEmptyResponse?()
                }
            } else {
                // Successful non-empty response — reset retry counter
                emptyResponseRetryCount = 0
            }
        } else {
            // Tool use / thinking response — always reset retry counter
            emptyResponseRetryCount = 0
        }
    }

    private func handleToolResult(_ event: UserEvent) {
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
        watchdogTask?.cancel()
        watchdogTask = nil
        finalizeStreamingMessage()

        // Capture per-turn tokens BEFORE accumulating
        let thisTurnInput = event.usage?.inputTokens ?? 0
        let thisTurnOutput = event.usage?.outputTokens ?? 0

        totalInputTokens += thisTurnInput
        totalOutputTokens += thisTurnOutput

        if let cost = event.totalCostUSD {
            lastTurnCostUSD = cost
            totalCostUSD += cost
            let savingsMultiplier = max(_pendingSavingsMultiplier, _pendingModelSavings)
            if savingsMultiplier > 0 {
                estimatedSavingsUSD += cost * savingsMultiplier / (1.0 - savingsMultiplier)
            }
            _pendingSavingsMultiplier = 0
            _pendingModelSavings = 0
        }

        if let sid = event.sessionId {
            sessionId = sid
        }

        onTurnComplete?(TurnMetrics(
            inputTokens: thisTurnInput,
            outputTokens: thisTurnOutput,
            cumulativeInputTokens: totalInputTokens,
            cumulativeOutputTokens: totalOutputTokens,
            totalCostUSD: totalCostUSD,
            sessionId: sessionId
        ))

        onResult?(event)

        // Execute deferred retry AFTER stream has ended cleanly (no SIGINT needed)
        if let retryPrompt = pendingRetryPrompt {
            pendingRetryPrompt = nil
            print("[ClaudeProcess] Executing deferred retry after stream completed")
            // Remove the empty assistant message
            if let lastIdx = messages.indices.last, messages[lastIdx].role == .assistant {
                messages.removeLast()
            }
            // Remove the user message — send() re-adds it
            if let lastIdx = messages.indices.last, messages[lastIdx].role == .user {
                messages.removeLast()
            }
            send(retryPrompt)
            return // Skip completion sounds/notifications — retry is in progress
        }

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
        guard streamingMessage != nil else { return }

        if let lastIdx = messages.indices.last,
           messages[lastIdx].role == .assistant && messages[lastIdx].isStreaming {
            var blocks: [any ContentBlockProtocol] = []
            if let thinking = streamingThinkingBlock {
                blocks.append(thinking)
            }
            if let text = streamingTextBlock {
                blocks.append(text)
            }
            messages[lastIdx].blocks = blocks
        } else {
            var newMsg = streamingMessage!
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

/// Smart effort routing — classifies message complexity for savings tracking
/// In interactive mode, effort is set at launch. This is informational for the savings display.
enum SmartEffortRouter {

    static func classify(_ message: String) -> EffortLevel {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        let wordCount = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.count

        if wordCount <= 5 && isConversational(lowered) {
            return .low
        }

        if wordCount <= 15 && !containsComplexWork(lowered) {
            return .medium
        }

        if containsComplexWork(lowered) {
            return .high
        }

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

    func next() -> OutputMode {
        let all = OutputMode.allCases
        guard let idx = all.firstIndex(of: self) else { return .standard }
        let nextIdx = (idx + 1) % all.count
        return all[nextIdx]
    }
}
