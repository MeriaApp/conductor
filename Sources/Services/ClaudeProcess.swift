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

    /// Process health state — drives the status bar health indicator
    enum ProcessHealth: String {
        case healthy    // Process running, responsive
        case retrying   // Auto-retry in progress
        case dead       // Process died, retries exhausted
        case stopped    // Deliberately stopped
    }
    @Published var processHealth: ProcessHealth = .stopped

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
    private static let responseTimeoutSeconds: TimeInterval = 600 // 10 minutes per response (generous for complex ops)

    /// Tracks whether stop() was called deliberately vs process dying unexpectedly
    private var processTerminatedDeliberately = false

    /// Guard against send() auto-restart infinite recursion
    private var sendRestartAttempts: Int = 0
    private static let maxSendRestartAttempts = 2

    // MARK: - Auto-Retry Infrastructure

    /// Current auto-retry attempt (0 = no retry in progress)
    private var autoRetryAttempt: Int = 0
    /// Max auto-retry attempts before giving up and showing blocking error
    private static let maxAutoRetries = 3
    /// Base delay for exponential backoff (1s, 2s, 4s)
    private static let retryBaseDelaySeconds: TimeInterval = 1.0
    /// Active retry task (cancelled on stop() or successful recovery)
    private var autoRetryTask: Task<Void, Never>?
    /// Callback when auto-retry begins — passes attempt number and max for UI display
    var onAutoRetry: ((Int, Int) -> Void)?
    /// Callback when auto-retry succeeds — UI should clear retry banners
    var onAutoRetrySuccess: (() -> Void)?

    /// Event history cap — prevents unbounded memory growth on long sessions
    private static let maxEventCount = 200
    private static let eventTrimTarget = 150

    /// Message history cap — prevents unbounded memory growth on long sessions
    private static let maxMessageCount = 500
    private static let messageTrimTarget = 400

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
        autoRetryAttempt = 0
        autoRetryTask?.cancel()
        autoRetryTask = nil
        launchPersistentProcess()
    }

    /// Write a user message to the persistent Claude CLI process via stdin.
    func send(_ text: String) {
        guard isRunning, stdinHandle != nil else {
            // Guard against infinite recursion — max 2 restart attempts from send()
            sendRestartAttempts += 1
            guard sendRestartAttempts <= Self.maxSendRestartAttempts else {
                sendRestartAttempts = 0
                processHealth = .dead
                let msg = "Session ended — could not restart process"
                error = msg
                onError?(msg)
                NotificationService.shared.sendCriticalNotification(
                    title: "Claude Process Failed",
                    body: "Could not restart after \(Self.maxSendRestartAttempts) attempts. Start a new session."
                )
                return
            }

            // Auto-restart: save the message, relaunch with session resume, then resend
            print("[ClaudeProcess] Process not running — auto-restarting to deliver message (attempt \(sendRestartAttempts)/\(Self.maxSendRestartAttempts))")
            autoRetryTask?.cancel()
            autoRetryTask = Task { [weak self] in
                guard let self else { return }
                // Brief pause before restart
                try? await Task.sleep(for: .seconds(Self.retryBaseDelaySeconds))
                guard !Task.isCancelled else { return }
                self.processTerminatedDeliberately = false
                self.error = "Reconnecting..."
                self.processHealth = .retrying
                self.launchPersistentProcess()
                // Wait for process to initialize
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, self.isRunning else {
                    self.sendRestartAttempts = 0
                    self.processHealth = .dead
                    self.error = "Session ended — restart to continue"
                    self.onError?(self.error ?? "")
                    return
                }
                self.error = nil
                self.onAutoRetrySuccess?()
                self.send(text)
            }
            return
        }

        // Successful send path — reset restart counter
        sendRestartAttempts = 0

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
        trimMessagesIfNeeded()

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
                    // Write failed — pipe is dead. Auto-retry by restarting process.
                    self.isStreaming = false
                    self.isRunning = false
                    self.scheduleAutoRetry(reason: "Connection lost", resendPrompt: text)
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
        autoRetryTask?.cancel()
        autoRetryTask = nil
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
        processHealth = .stopped
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
                self.isRunning = false

                if status != 0 && status != 2 {
                    // Unexpected exit — notify + auto-retry with session resume
                    let reason = "Process exited (code \(status))"
                    print("[ClaudeProcess] Unexpected termination: \(reason)")
                    NotificationService.shared.sendCriticalNotification(
                        title: "Claude Process Crashed",
                        body: "Exit code \(status) — attempting recovery..."
                    )
                    self.scheduleAutoRetry(reason: reason, resendPrompt: self.lastPrompt)
                } else {
                    // Clean exit (0) or SIGINT (2) — auto-restart if we have a session to resume
                    if self.sessionId != nil && !self.processTerminatedDeliberately {
                        self.scheduleAutoRetry(reason: "Process ended", resendPrompt: nil)
                    }
                }
            }
        }

        do {
            try proc.run()
            isRunning = true
            error = nil
            processHealth = .healthy
            // Successful launch — reset retry counter
            if autoRetryAttempt > 0 {
                print("[ClaudeProcess] Auto-retry succeeded on attempt \(autoRetryAttempt)")
                autoRetryAttempt = 0
                onAutoRetrySuccess?()
            }
            startReadingOutput(from: stdoutPipe)
            startReadingErrors(from: stderrPipe)
        } catch {
            isRunning = false
            // CLI not found = unrecoverable. Other launch failures = retry.
            let isCliMissing = error.localizedDescription.contains("No such file")
                || error.localizedDescription.contains("not a valid")
            if isCliMissing {
                let msg = "Claude CLI not found — install with: npm install -g @anthropic-ai/claude-code"
                self.error = msg
                onError?(msg)
            } else {
                scheduleAutoRetry(reason: "Launch failed: \(error.localizedDescription)", resendPrompt: nil)
            }
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
    /// Auto-retries the last prompt instead of blocking with an error
    private func startResponseWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.responseTimeoutSeconds))
            guard !Task.isCancelled else { return }
            guard let self, self.isStreaming else { return }
            print("[ClaudeProcess] Response timed out after \(Int(Self.responseTimeoutSeconds))s — auto-retrying")
            self.currentProcess?.interrupt()
            self.isStreaming = false
            self.finalizeStreamingMessage()
            // Auto-retry the last prompt
            if let prompt = self.lastPrompt {
                self.scheduleAutoRetry(reason: "Response timed out", resendPrompt: prompt)
            } else {
                self.error = "Response timed out — send a new message to continue"
            }
        }
    }

    // MARK: - Auto-Retry with Exponential Backoff

    /// Schedule an automatic retry with exponential backoff (1s, 2s, 4s).
    /// Preserves context by resuming the existing session.
    /// Only shows a blocking error after all retries are exhausted.
    private func scheduleAutoRetry(reason: String, resendPrompt: String?) {
        autoRetryAttempt += 1

        guard autoRetryAttempt <= Self.maxAutoRetries else {
            // All retries exhausted — show blocking error + critical notification
            autoRetryAttempt = 0
            processHealth = .dead
            let msg = "\(reason) — automatic recovery failed after \(Self.maxAutoRetries) attempts"
            error = msg
            onError?(msg)
            NotificationService.shared.sendCriticalNotification(
                title: "Claude Process Died",
                body: msg
            )
            return
        }

        processHealth = .retrying
        let attempt = autoRetryAttempt
        let delay = Self.retryBaseDelaySeconds * pow(2.0, Double(attempt - 1)) // 1s, 2s, 4s
        let retryMsg = "Retrying... attempt \(attempt)/\(Self.maxAutoRetries)"
        error = retryMsg
        onAutoRetry?(attempt, Self.maxAutoRetries)

        print("[ClaudeProcess] \(reason) — scheduling auto-retry \(attempt)/\(Self.maxAutoRetries) in \(delay)s")

        autoRetryTask?.cancel()
        autoRetryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            guard let self else { return }

            // Save context state before retrying
            let savedSessionId = self.sessionId
            let savedDirectory = self.workingDirectory

            // Kill any lingering process state without triggering deliberate termination flag
            self.readTask?.cancel()
            self.readTask = nil
            self.stderrReadTask?.cancel()
            self.stderrReadTask = nil
            if let handle = self.stdinHandle {
                try? handle.close()
                self.stdinHandle = nil
            }
            if let proc = self.currentProcess, proc.isRunning {
                proc.terminate()
            }
            self.currentProcess = nil

            // Relaunch — resume existing session to preserve context
            self.processTerminatedDeliberately = false
            self.sessionGeneration += 1

            if let sid = savedSessionId {
                self.sessionId = sid
            }
            self.workingDirectory = savedDirectory

            self.launchPersistentProcess()

            // If we have a prompt to resend, wait for process then send
            if let prompt = resendPrompt, self.isRunning {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, self.isRunning else { return }
                // Remove the user message that was already added to messages array
                // (writeTurn adds it, but the write failed — avoid duplicate)
                if let lastIdx = self.messages.indices.last,
                   self.messages[lastIdx].role == .user {
                    self.messages.removeLast()
                }
                self.error = nil
                self.send(prompt)
            }
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
        trimMessagesIfNeeded()

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

        // Handle error results (API errors, rate limits, overloaded) with auto-retry
        if event.isError == true {
            let errorText = event.result ?? "Unknown API error"
            let isRecoverable = isRecoverableError(errorText)
            if isRecoverable {
                print("[ClaudeProcess] Recoverable error from CLI: \(errorText) — auto-retrying")
                scheduleAutoRetry(reason: errorText, resendPrompt: lastPrompt)
                return
            }
            // Non-recoverable error (auth failure, etc.) — show blocking error
            error = errorText
            onError?(errorText)
            return
        }

        // Successful result — reset auto-retry counter
        if autoRetryAttempt > 0 {
            autoRetryAttempt = 0
            onAutoRetrySuccess?()
        }

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

    /// Determine if an error is recoverable (worth auto-retrying) vs permanent (auth, billing)
    private func isRecoverableError(_ errorText: String) -> Bool {
        let lowered = errorText.lowercased()
        // Permanent errors — don't retry
        let permanentPatterns = [
            "authentication", "auth failed", "invalid api key", "unauthorized",
            "billing", "payment required", "account suspended",
            "permission denied", "forbidden",
            "not found", "cli not found"
        ]
        if permanentPatterns.contains(where: { lowered.contains($0) }) {
            return false
        }
        // Recoverable — rate limits, overloaded, timeouts, server errors
        let recoverablePatterns = [
            "rate limit", "overloaded", "capacity", "timeout", "timed out",
            "server error", "500", "502", "503", "529",
            "connection", "network", "socket", "reset",
            "try again", "retry", "temporary", "transient"
        ]
        if recoverablePatterns.contains(where: { lowered.contains($0) }) {
            return true
        }
        // Default: treat unknown errors as recoverable (better to retry than block)
        return true
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

        guard streamingTextBlock != nil else {
            print("[ClaudeProcess] streamingTextBlock unexpectedly nil after initialization — skipping text delta")
            return
        }
        streamingTextBlock?.text += text
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

        guard streamingThinkingBlock != nil else {
            print("[ClaudeProcess] streamingThinkingBlock unexpectedly nil after initialization — skipping thinking delta")
            return
        }
        streamingThinkingBlock?.text += text
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
        } else if var newMsg = streamingMessage {
            var blocks: [any ContentBlockProtocol] = []
            if let thinking = streamingThinkingBlock {
                blocks.append(thinking)
            }
            if let text = streamingTextBlock {
                blocks.append(text)
            }
            newMsg.blocks = blocks
            messages.append(newMsg)
            trimMessagesIfNeeded()
        }
    }

    private func finalizeStreamingThinking() {
        guard streamingThinkingBlock != nil else { return }
        streamingThinkingBlock?.isStreaming = false
        streamingThinkingBlock?.isCollapsed = true
        if let start = streamStartTime {
            streamingThinkingBlock?.duration = Date().timeIntervalSince(start)
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

    /// Trim messages array when it exceeds the cap, dropping oldest non-system messages.
    private func trimMessagesIfNeeded() {
        guard messages.count > Self.maxMessageCount else { return }
        let excess = messages.count - Self.messageTrimTarget
        // Find the first N non-system messages to drop
        var removedCount = 0
        messages.removeAll { msg in
            guard removedCount < excess else { return false }
            if msg.role != .system {
                removedCount += 1
                return true
            }
            return false
        }
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
