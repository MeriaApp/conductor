import Foundation

/// Orchestrates multiple Claude CLI agent instances
/// Supports patterns: supervisor, pipeline, consensus, swarm
@MainActor
final class AgentOrchestrator: ObservableObject {
    @Published var agents: [Agent] = []
    @Published var activePattern: OrchestrationPattern = .supervisor

    private var processes: [String: ClaudeProcess] = [:] // agentId -> process
    private let messageBus: AgentMessageBus
    private let permissionManager: PermissionManager

    /// Track pipeline subscription IDs for cleanup
    private var pipelineSubscriptionIds: [String] = []

    init(messageBus: AgentMessageBus, permissionManager: PermissionManager) {
        self.messageBus = messageBus
        self.permissionManager = permissionManager
    }

    // MARK: - Agent Lifecycle

    /// Reference to main process for inheriting settings
    weak var mainProcess: ClaudeProcess?

    /// Spawn a new agent with a given role
    @discardableResult
    func spawnAgent(name: String, role: AgentRole, directory: String? = nil) -> Agent {
        let agent = Agent(name: name, role: role)
        agents.append(agent)

        // Create a dedicated ClaudeProcess for this agent
        let process = ClaudeProcess()
        process.systemPrompt = role.systemPromptSuffix

        // Inherit token optimization settings from the main process
        if let main = mainProcess {
            process.optimizationsEnabled = main.optimizationsEnabled
            process.autoCompactThreshold = main.autoCompactThreshold
            process.selectedModel = main.selectedModel
            // Sub-agents default to medium effort (narrower tasks than main)
            process.effortLevel = .medium
        }

        processes[agent.id] = process

        // Wire result callback — when agent finishes, broadcast on message bus
        let agentId = agent.id
        process.onResult = { [weak self] result in
            Task { @MainActor in
                guard let self = self else { return }
                self.updateAgentState(id: agentId, state: .completed)

                // Broadcast result to message bus for other agents to see
                self.messageBus.broadcastResult(
                    from: agentId,
                    result: result.result ?? "Task completed",
                    context: ["sessionId": result.sessionId ?? "", "cost": "\(result.totalCostUSD ?? 0)"]
                )
            }
        }

        // Wire system callback — capture session info
        process.onSystem = { [weak self] event in
            Task { @MainActor in
                if let model = event.model {
                    self?.updateAgentModel(id: agentId, model: model)
                }
            }
        }

        // Wire tool use auditing through PermissionManager
        let pm = permissionManager
        process.onToolUse = { [weak self] toolName, input in
            Task { @MainActor in
                let agentName = self?.agents.first(where: { $0.id == agentId })?.name ?? "Agent"
                let status = pm.evaluate(agentId: agentId, agentName: agentName, toolName: toolName, input: input)
                // Log critical-risk tools to message bus so other agents can see
                if status == .pending {
                    self?.messageBus.send(AgentMessage(
                        from: agentId,
                        type: .question,
                        payload: "Tool requires review: \(toolName) — \(input.prefix(200))"
                    ))
                }
            }
        }

        // Wire streaming state tracking
        process.onError = { [weak self] error in
            Task { @MainActor in
                self?.updateAgentState(id: agentId, state: .failed)
                self?.messageBus.send(AgentMessage(
                    from: agentId,
                    type: .error,
                    payload: error
                ))
            }
        }

        // Subscribe to message bus for incoming messages
        messageBus.subscribe(agentId: agent.id) { [weak self] message in
            Task { @MainActor in
                self?.handleMessageForAgent(agentId: agent.id, message: message)
            }
        }

        // Use the main process's working directory if none specified
        let dir = directory ?? processes.values.first?.workingDirectory
        process.start(directory: dir)

        updateAgentState(id: agentId, state: .idle)

        return agent
    }

    /// Stop and remove an agent
    func stopAgent(id: String) {
        processes[id]?.stop()
        processes.removeValue(forKey: id)
        messageBus.unsubscribe(agentId: id)
        // Also clean up any pipeline subscriptions referencing this agent
        // (e.g., "agentId_pipeline", "agentId_verify_pipeline", "agentId_supervisor")
        messageBus.unsubscribe(agentId: "\(id)_pipeline")
        messageBus.unsubscribe(agentId: "\(id)_verify_pipeline")
        messageBus.unsubscribe(agentId: "\(id)_supervisor")
        updateAgentState(id: id, state: .stopped)
    }

    /// Clean up all tracked pipeline subscriptions
    func cleanupPipeline() {
        for subId in pipelineSubscriptionIds {
            messageBus.unsubscribe(subscriptionId: subId)
        }
        pipelineSubscriptionIds.removeAll()
    }

    /// Send a task to a specific agent
    func assignTask(agentId: String, task: String) {
        guard let process = processes[agentId] else { return }

        updateAgentState(id: agentId, state: .working)
        updateAgentTask(id: agentId, task: task)

        // Send the task as input to the agent's Claude process
        process.send(task)

        // Also broadcast on the message bus
        messageBus.sendTask(
            from: "orchestrator",
            to: agentId,
            task: task
        )
    }

    /// Send a task to all agents
    func broadcastTask(task: String) {
        for agent in agents where agent.state == .idle {
            assignTask(agentId: agent.id, task: task)
        }
    }

    // MARK: - Orchestration Patterns

    /// Run a supervisor pattern: one agent delegates, others execute
    func runSupervisor(supervisorId: String, task: String) {
        cleanupPipeline()
        activePattern = .supervisor

        // The supervisor gets the task with delegation instructions
        let prompt = """
        You are the supervisor agent. Your job is to break this task into subtasks and delegate to worker agents.

        Available workers:
        \(agents.filter { $0.id != supervisorId }.map { "- \($0.name) (\($0.role.displayName))" }.joined(separator: "\n"))

        Task: \(task)

        Break this into subtasks and tell me which worker should handle each one. Format each as:
        ASSIGN [worker name]: [subtask description]
        """

        assignTask(agentId: supervisorId, task: prompt)

        // Subscribe to supervisor results to parse ASSIGN directives
        let subId = messageBus.subscribe(agentId: "\(supervisorId)_supervisor") { [weak self] message in
            guard message.from == supervisorId, message.type == .result else { return }
            Task { @MainActor in
                self?.parseSupervisorDirectives(message.payload)
            }
        }
        pipelineSubscriptionIds.append(subId)
    }

    /// Parse ASSIGN directives from supervisor output and dispatch to workers
    private func parseSupervisorDirectives(_ text: String) {
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("ASSIGN ") else { continue }

            // Parse: ASSIGN [worker name]: [subtask description]
            let afterAssign = String(trimmed.dropFirst("ASSIGN ".count))
            guard let colonIndex = afterAssign.firstIndex(of: ":") else { continue }

            let workerName = String(afterAssign[afterAssign.startIndex..<colonIndex])
                .trimmingCharacters(in: .whitespaces)
            let subtask = String(afterAssign[afterAssign.index(after: colonIndex)...])
                .trimmingCharacters(in: .whitespaces)

            guard !workerName.isEmpty, !subtask.isEmpty else { continue }

            // Find worker agent by name (case-insensitive)
            if let worker = agents.first(where: { $0.name.lowercased() == workerName.lowercased() }) {
                assignTask(agentId: worker.id, task: subtask)
            }
        }
    }

    /// Run a pipeline: output of one agent feeds into the next
    func runPipeline(agentIds: [String], initialTask: String) {
        cleanupPipeline()
        activePattern = .pipeline

        guard let firstId = agentIds.first else { return }

        // Start the pipeline with the first agent
        assignTask(agentId: firstId, task: initialTask)

        // Set up forwarding chain
        for i in 0..<(agentIds.count - 1) {
            let currentId = agentIds[i]
            let nextId = agentIds[i + 1]

            // When current agent finishes, forward result to next
            let subId = messageBus.subscribe(agentId: "\(currentId)_pipeline") { [weak self] message in
                if message.from == currentId && message.type == .result {
                    Task { @MainActor in
                        let nextPrompt = """
                        Previous agent (\(message.from)) completed their part. Here's their output:

                        \(message.payload)

                        Continue the work from here.
                        """
                        self?.assignTask(agentId: nextId, task: nextPrompt)
                    }
                }
            }
            pipelineSubscriptionIds.append(subId)
        }
    }

    /// Run consensus: multiple agents work the same task, compare results
    func runConsensus(agentIds: [String], task: String) {
        cleanupPipeline()
        activePattern = .consensus

        var completedResults: [String: String] = [:]

        // All agents get the same task
        for id in agentIds {
            assignTask(agentId: id, task: task)

            // Track each agent's result — guard against double-reporting
            let subId = messageBus.subscribe(agentId: "\(id)_consensus") { [weak self] message in
                guard message.from == id, message.type == .result else { return }
                Task { @MainActor in
                    guard completedResults[id] == nil else { return }
                    completedResults[id] = message.payload
                    // When all agents have reported, broadcast the consensus summary
                    if completedResults.count == agentIds.count {
                        let summary = completedResults.map { agentId, result in
                            let name = self?.agents.first(where: { $0.id == agentId })?.name ?? agentId
                            return "[\(name)]:\n\(result)"
                        }.joined(separator: "\n\n---\n\n")
                        self?.messageBus.broadcastResult(
                            from: "orchestrator",
                            result: "All agents completed. Results:\n\n\(summary)",
                            context: ["pattern": "consensus", "agents": "\(agentIds.count)"]
                        )
                    }
                }
            }
            pipelineSubscriptionIds.append(subId)
        }
    }

    /// Run swarm: all agents work in parallel on different subtasks
    func runSwarm(tasks: [(agentId: String, task: String)]) {
        cleanupPipeline()
        activePattern = .swarm

        for (agentId, task) in tasks {
            assignTask(agentId: agentId, task: task)
        }
    }

    // MARK: - Agent State

    func getProcess(for agentId: String) -> ClaudeProcess? {
        processes[agentId]
    }

    /// Get conversation messages from an agent's Claude process (for UI display)
    func conversationForAgent(id: String) -> [ConversationMessage] {
        processes[id]?.messages ?? []
    }

    /// Check if an agent's process is currently streaming
    func isAgentStreaming(id: String) -> Bool {
        processes[id]?.isStreaming ?? false
    }

    private func updateAgentState(id: String, state: AgentState) {
        if let idx = agents.firstIndex(where: { $0.id == id }) {
            agents[idx].state = state
        }
    }

    private func updateAgentTask(id: String, task: String?) {
        if let idx = agents.firstIndex(where: { $0.id == id }) {
            agents[idx].currentTask = task
        }
    }

    private func updateAgentModel(id: String, model: String) {
        // Could store model info per agent if needed
    }

    // MARK: - Message Handling

    private func handleMessageForAgent(agentId: String, message: AgentMessage) {
        guard let process = processes[agentId] else { return }

        switch message.type {
        case .task:
            // Inject task into the agent's Claude session
            process.send(message.payload)
            updateAgentState(id: agentId, state: .working)
            updateAgentTask(id: agentId, task: message.payload)

        case .review:
            // Ask the agent to review the content
            let reviewPrompt = "Review the following from agent \(message.from):\n\n\(message.payload)\n\nProvide feedback."
            process.send(reviewPrompt)
            updateAgentState(id: agentId, state: .reviewing)

        case .question:
            // Forward question to the agent
            process.send("Question from \(message.from): \(message.payload)")

        default:
            break
        }
    }

    // MARK: - Autonomous Build-Verify Pipeline

    /// The default behavior after ANY code generation or modification.
    /// No human needed. Build → Test → Audit → Fix → Report.
    /// Only interrupts the user if a decision is required.
    func runBuildVerifyPipeline(
        projectDir: String,
        buildCommand: String,
        testCommand: String? = nil,
        launchCommand: String? = nil
    ) {
        cleanupPipeline()
        activePattern = .pipeline

        // Spawn dedicated agents for each stage
        let builder = spawnAgent(name: "Builder", role: .builder, directory: projectDir)
        let tester = spawnAgent(name: "Tester", role: .tester, directory: projectDir)
        let reviewer = spawnAgent(name: "Reviewer", role: .reviewer, directory: projectDir)

        // Stage 1: Build
        let buildPrompt = """
        Run the build command and report the result. If it fails, read the errors, fix them, and rebuild.
        Do NOT ask for permission — just fix and rebuild until it passes.

        Build command: \(buildCommand)
        Project directory: \(projectDir)

        When the build succeeds, respond with: BUILD_PASSED
        If you cannot fix the build after 3 attempts, respond with: BUILD_BLOCKED: [reason]
        """
        assignTask(agentId: builder.id, task: buildPrompt)

        // Stage 2: Test (triggered when build passes)
        let sub1 = messageBus.subscribe(agentId: "\(builder.id)_verify_pipeline") { [weak self] message in
            guard message.from == builder.id, message.type == .result else { return }

            if message.payload.contains("BUILD_PASSED") {
                Task { @MainActor in
                    let testPrompt: String
                    if let testCmd = testCommand {
                        testPrompt = """
                        The build passed. Now run tests and verify the app works.

                        Test command: \(testCmd)
                        \(launchCommand.map { "Launch command: \($0)" } ?? "")

                        Run the tests. If any fail, report exactly what failed and why.
                        When all tests pass, respond with: TESTS_PASSED
                        If tests fail and you cannot fix them, respond with: TESTS_BLOCKED: [failures]
                        """
                    } else {
                        testPrompt = """
                        The build passed. No test command was provided.
                        \(launchCommand.map { "Launch the app with: \($0)\nVerify it starts without crashing." } ?? "Verify the build output exists and looks correct.")

                        Respond with: TESTS_PASSED (or TESTS_BLOCKED: [reason])
                        """
                    }
                    self?.assignTask(agentId: tester.id, task: testPrompt)
                }
            } else if message.payload.contains("BUILD_BLOCKED") {
                // Build failed after retries — escalate to reviewer for diagnosis
                Task { @MainActor in
                    self?.messageBus.requestReview(from: builder.id, to: reviewer.id, content: message.payload)
                }
            }
        }

        // Stage 3: Review/Audit (triggered when tests pass)
        let sub2 = messageBus.subscribe(agentId: "\(tester.id)_verify_pipeline") { [weak self] message in
            guard message.from == tester.id, message.type == .result else { return }

            if message.payload.contains("TESTS_PASSED") {
                Task { @MainActor in
                    let auditPrompt = """
                    Build and tests passed. Now audit the code for quality:

                    1. Read the changed files
                    2. Check for security issues (injection, XSS, hardcoded secrets)
                    3. Check for performance issues (N+1 queries, memory leaks, unnecessary allocations)
                    4. Check for correctness (edge cases, error handling, race conditions)
                    5. Check for style consistency

                    Report findings. If everything looks good, respond with: AUDIT_PASSED
                    If there are issues, respond with: AUDIT_ISSUES: [list of issues]
                    """
                    self?.assignTask(agentId: reviewer.id, task: auditPrompt)
                }
            } else if message.payload.contains("TESTS_BLOCKED") {
                // Tests failed — send to reviewer
                Task { @MainActor in
                    self?.messageBus.requestReview(from: tester.id, to: reviewer.id, content: message.payload)
                }
            }
        }

        // Stage 4: Report results (triggered when audit completes)
        let sub3 = messageBus.subscribe(agentId: "\(reviewer.id)_verify_pipeline") { [weak self] message in
            guard message.from == reviewer.id, message.type == .result else { return }

            Task { @MainActor in
                let summary: String
                if message.payload.contains("AUDIT_PASSED") {
                    summary = "Build passed. Tests passed. Audit passed. Ship it."
                } else if message.payload.contains("AUDIT_ISSUES") {
                    summary = "Build and tests passed, but audit found issues:\n\(message.payload)"
                } else {
                    summary = "Pipeline completed with reviewer feedback:\n\(message.payload)"
                }

                // Broadcast final result to all
                self?.messageBus.broadcastResult(
                    from: "orchestrator",
                    result: summary,
                    context: ["pipeline": "build-verify", "status": "complete"]
                )

                // Clean up pipeline agents and subscriptions
                self?.cleanupPipeline()
                self?.stopAgent(id: builder.id)
                self?.stopAgent(id: tester.id)
                self?.stopAgent(id: reviewer.id)
            }
        }

        pipelineSubscriptionIds.append(contentsOf: [sub1, sub2, sub3])
    }

    /// Quick build-verify for the current project (auto-detects build system)
    func autoBuildVerify(projectDir: String) {
        let fm = FileManager.default

        // Auto-detect build command
        let buildCommand: String
        let testCommand: String?
        let launchCommand: String?

        if fm.fileExists(atPath: "\(projectDir)/project.yml") ||
           fm.fileExists(atPath: "\(projectDir)/\(projectDir.components(separatedBy: "/").last ?? "").xcodeproj") {
            // Xcode / xcodegen project — quote schemeName to handle spaces/special chars
            let schemeName = URL(fileURLWithPath: projectDir).lastPathComponent
            buildCommand = "cd \"\(projectDir)\" && xcodegen generate 2>/dev/null; xcodebuild -scheme \"\(schemeName)\" -destination 'platform=macOS' build 2>&1 | tail -20"
            testCommand = "cd \"\(projectDir)\" && xcodebuild -scheme \"\(schemeName)\" -destination 'platform=macOS' test 2>&1 | tail -20"
            launchCommand = nil
        } else if fm.fileExists(atPath: "\(projectDir)/package.json") {
            buildCommand = "cd \"\(projectDir)\" && npm run build 2>&1"
            testCommand = "cd \"\(projectDir)\" && npm test 2>&1"
            launchCommand = nil
        } else if fm.fileExists(atPath: "\(projectDir)/Cargo.toml") {
            buildCommand = "cd \"\(projectDir)\" && cargo build 2>&1"
            testCommand = "cd \"\(projectDir)\" && cargo test 2>&1"
            launchCommand = nil
        } else if fm.fileExists(atPath: "\(projectDir)/Package.swift") {
            buildCommand = "cd \"\(projectDir)\" && swift build 2>&1"
            testCommand = "cd \"\(projectDir)\" && swift test 2>&1"
            launchCommand = nil
        } else {
            buildCommand = "echo 'No recognized build system found in \(projectDir)'"
            testCommand = nil
            launchCommand = nil
        }

        runBuildVerifyPipeline(
            projectDir: projectDir,
            buildCommand: buildCommand,
            testCommand: testCommand,
            launchCommand: launchCommand
        )
    }

    // MARK: - Sync State

    // MARK: - One-Click Workflow Presets

    /// Callback for synthesized team results — fires when a workflow completes
    var onWorkflowComplete: ((String) -> Void)?

    /// "Audit Codebase" — spawns 3 researchers in swarm pattern
    func runAuditWorkflow(projectDir: String) {
        cleanupPipeline()
        activePattern = .swarm

        let security = spawnAgent(name: "Security Scan", role: .reviewer, directory: projectDir)
        let quality = spawnAgent(name: "Code Quality", role: .researcher, directory: projectDir)
        let performance = spawnAgent(name: "Performance", role: .researcher, directory: projectDir)

        // Set effort to medium for cost efficiency
        [security, quality, performance].forEach { agent in
            processes[agent.id]?.effortLevel = .medium
            processes[agent.id]?.smartEffort = false
        }

        assignTask(agentId: security.id, task: """
        Audit this codebase for security issues. Focus on: injection attacks, hardcoded secrets, \
        auth bypass, XSS, insecure dependencies. List findings with severity (Critical/High/Medium/Low). \
        When done, respond with AUDIT_COMPLETE followed by your findings.
        """)

        assignTask(agentId: quality.id, task: """
        Audit this codebase for code quality. Focus on: dead code, duplication, overly complex functions, \
        inconsistent patterns, missing error handling, type safety issues. List findings with impact level. \
        When done, respond with AUDIT_COMPLETE followed by your findings.
        """)

        assignTask(agentId: performance.id, task: """
        Audit this codebase for performance issues. Focus on: unnecessary allocations, N+1 patterns, \
        blocking main thread, memory leaks, inefficient algorithms, large bundle size. List findings. \
        When done, respond with AUDIT_COMPLETE followed by your findings.
        """)

        // Synthesize results when all 3 complete
        synthesizeOnCompletion(agentIds: [security.id, quality.id, performance.id], workflowName: "Codebase Audit")
    }

    /// "Parallel Research" — spawns researchers for different aspects of a question
    func runResearchWorkflow(projectDir: String, question: String) {
        cleanupPipeline()
        activePattern = .swarm

        let codebase = spawnAgent(name: "Codebase Research", role: .researcher, directory: projectDir)
        let patterns = spawnAgent(name: "Pattern Analysis", role: .researcher, directory: projectDir)

        [codebase, patterns].forEach { agent in
            processes[agent.id]?.effortLevel = .medium
            processes[agent.id]?.smartEffort = false
        }

        assignTask(agentId: codebase.id, task: """
        Research this question by reading the codebase: \(question)
        Focus on: relevant files, current implementation, data flow, dependencies. \
        When done, respond with RESEARCH_COMPLETE followed by your findings.
        """)

        assignTask(agentId: patterns.id, task: """
        Research this question by analyzing patterns and architecture: \(question)
        Focus on: design patterns used, architectural decisions, constraints, potential approaches. \
        When done, respond with RESEARCH_COMPLETE followed by your findings.
        """)

        synthesizeOnCompletion(agentIds: [codebase.id, patterns.id], workflowName: "Research")
    }

    /// Collect final results from agents and synthesize into a unified report
    private func synthesizeOnCompletion(agentIds: [String], workflowName: String) {
        var completedResults: [String: String] = [:]

        for agentId in agentIds {
            let sub = messageBus.subscribe(agentId: "\(agentId)_workflow") { [weak self] message in
                guard message.from == agentId, message.type == .result else { return }

                Task { @MainActor in
                    guard let self else { return }
                    guard completedResults[agentId] == nil else { return }
                    let agentName = self.agents.first(where: { $0.id == agentId })?.name ?? "Agent"
                    completedResults[agentId] = "### \(agentName)\n\(message.payload)"

                    // All agents done?
                    if completedResults.count == agentIds.count {
                        let report = "## \(workflowName) — Team Report\n\n" +
                            agentIds.compactMap { completedResults[$0] }.joined(separator: "\n\n---\n\n")
                        self.onWorkflowComplete?(report)
                        self.cleanupPipeline()
                    }
                }
            }
            pipelineSubscriptionIds.append(sub)
        }
    }

    /// Sync agent state from process state
    func syncAgentStates() {
        for agent in agents {
            if let process = processes[agent.id] {
                if let idx = agents.firstIndex(where: { $0.id == agent.id }) {
                    agents[idx].inputTokens = process.totalInputTokens
                    agents[idx].outputTokens = process.totalOutputTokens
                    agents[idx].costUSD = process.totalCostUSD

                    if process.isStreaming {
                        agents[idx].state = .thinking
                    } else if !process.isRunning && agents[idx].state.isActive {
                        agents[idx].state = .completed
                    }
                }
            }
        }
    }
}

/// Orchestration patterns
enum OrchestrationPattern: String, CaseIterable {
    case supervisor  // One agent delegates to workers
    case pipeline    // Output of one feeds into next
    case consensus   // Multiple agents, compare results
    case swarm       // All parallel on different subtasks

    var displayName: String {
        switch self {
        case .supervisor: return "Supervisor"
        case .pipeline: return "Pipeline"
        case .consensus: return "Consensus"
        case .swarm: return "Swarm"
        }
    }

    var icon: String {
        switch self {
        case .supervisor: return "person.3.fill"
        case .pipeline: return "arrow.right.arrow.left"
        case .consensus: return "checkmark.circle.trianglebadge.exclamationmark"
        case .swarm: return "ant.fill"
        }
    }
}
