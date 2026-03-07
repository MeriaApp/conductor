import SwiftUI

/// Shows all running agents with status, tasks, and inter-agent messages
struct AgentPanel: View {
    @EnvironmentObject private var orchestrator: AgentOrchestrator
    @EnvironmentObject private var messageBus: AgentMessageBus
    @EnvironmentObject private var theme: ThemeEngine
    @State private var showSpawnSheet = false
    @State private var selectedAgentId: String?
    @State private var taskInput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Agents")
                    .font(Typography.heading2)
                    .foregroundColor(theme.bright)

                Spacer()

                // Pattern selector
                Menu {
                    ForEach(OrchestrationPattern.allCases, id: \.self) { pattern in
                        Button {
                            orchestrator.activePattern = pattern
                        } label: {
                            Label(pattern.displayName, systemImage: pattern.icon)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: orchestrator.activePattern.icon)
                        Text(orchestrator.activePattern.displayName)
                    }
                    .font(Typography.caption)
                    .foregroundColor(theme.secondary)
                }
                .menuStyle(.borderlessButton)

                // Presets with memory indicator
                if AgentPresets.shared.presets.contains(where: { $0.memoryEnabled }) {
                    HStack(spacing: 3) {
                        Image(systemName: "brain")
                            .font(.system(size: 9))
                        Text("\(AgentPresets.shared.presets.filter { $0.memoryEnabled }.count)")
                            .font(Typography.caption)
                    }
                    .foregroundColor(theme.lavender)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(theme.lavender.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .help("Presets with persistent memory")
                }

                // Spawn button
                Button {
                    showSpawnSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(theme.sky)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().opacity(0.3)

            // Agent list
            if orchestrator.agents.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(orchestrator.agents) { agent in
                            AgentRow(agent: agent, isSelected: selectedAgentId == agent.id)
                                .onTapGesture {
                                    selectedAgentId = agent.id
                                }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }

            // Selected agent's conversation + task input
            if let agentId = selectedAgentId,
               orchestrator.agents.contains(where: { $0.id == agentId }) {

                Divider().opacity(0.3)

                // Agent conversation preview
                if let process = orchestrator.getProcess(for: agentId) {
                    AgentConversationPreview(process: process)
                }

                Divider().opacity(0.3)

                // Task input
                AgentTaskInput(
                    agentId: agentId,
                    agentName: orchestrator.agents.first(where: { $0.id == agentId })?.name ?? "Agent",
                    taskInput: $taskInput
                )
            }

            // Message log (collapsible)
            if !messageBus.messages.isEmpty {
                Divider().opacity(0.3)
                MessageLogView()
            }
        }
        .background(theme.surface)
        .sheet(isPresented: $showSpawnSheet) {
            SpawnAgentSheet()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "person.3")
                .font(.system(size: 32))
                .foregroundColor(theme.muted)
            Text("No agents running")
                .font(Typography.body)
                .foregroundColor(theme.muted)
            Text("Spawn an agent to start collaborating")
                .font(Typography.caption)
                .foregroundColor(theme.muted)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

// MARK: - Agent Row

struct AgentRow: View {
    let agent: Agent
    let isSelected: Bool
    @EnvironmentObject private var theme: ThemeEngine
    @EnvironmentObject private var orchestrator: AgentOrchestrator

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                // Role icon
                Image(systemName: agent.role.icon)
                    .font(.system(size: 12))
                    .foregroundColor(theme.sky)

                // Name
                Text(agent.name)
                    .font(Typography.bodyBold)
                    .foregroundColor(theme.bright)

                // Role badge
                Text(agent.role.displayName)
                    .font(Typography.caption)
                    .foregroundColor(theme.muted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(theme.elevated)
                    .clipShape(Capsule())

                Spacer()

                // State indicator
                AgentStateIndicator(state: agent.state)

                // Stop button
                Button {
                    orchestrator.stopAgent(id: agent.id)
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 12))
                        .foregroundColor(theme.muted)
                }
                .buttonStyle(.plain)
            }

            // Current task
            if let task = agent.currentTask {
                Text(task)
                    .font(Typography.caption)
                    .foregroundColor(theme.secondary)
                    .lineLimit(2)
            }

            // Stats
            HStack(spacing: 12) {
                Label("\(agent.inputTokens + agent.outputTokens) tokens", systemImage: "text.word.spacing")
                    .font(Typography.caption)
                    .foregroundColor(theme.muted)

                Text(agent.formattedCost)
                    .font(Typography.caption)
                    .foregroundColor(theme.amber)
            }
        }
        .padding(10)
        .background(isSelected ? theme.elevated : theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? theme.sky.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
}

// MARK: - Agent State Indicator

struct AgentStateIndicator: View {
    let state: AgentState
    @EnvironmentObject private var theme: ThemeEngine

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(stateColor)
                .frame(width: 6, height: 6)

            Text(state.displayName)
                .font(Typography.caption)
                .foregroundColor(stateColor)
        }
    }

    private var stateColor: Color {
        switch state {
        case .idle: return theme.muted
        case .thinking: return theme.lavender
        case .working: return theme.sky
        case .waiting: return theme.sand
        case .reviewing: return theme.lavender
        case .completed: return theme.sage
        case .failed: return theme.rose
        case .stopped: return theme.muted
        }
    }
}

// MARK: - Message Log

struct MessageLogView: View {
    @EnvironmentObject private var messageBus: AgentMessageBus
    @EnvironmentObject private var theme: ThemeEngine
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Toggle header
            HStack {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9))
                    .foregroundColor(theme.muted)

                Text("Messages")
                    .font(Typography.caption)
                    .foregroundColor(theme.secondary)

                if messageBus.unreadCount > 0 {
                    Text("\(messageBus.unreadCount)")
                        .font(Typography.caption)
                        .foregroundColor(theme.base)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(theme.sky)
                        .clipShape(Capsule())
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                    if isExpanded { messageBus.markAllRead() }
                }
            }

            if isExpanded {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(messageBus.messages.suffix(20)) { msg in
                            HStack(spacing: 6) {
                                Image(systemName: msg.type.icon)
                                    .font(.system(size: 9))
                                    .foregroundColor(theme.muted)

                                Text(msg.from)
                                    .font(Typography.caption)
                                    .foregroundColor(theme.sky)

                                if let to = msg.to {
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 8))
                                        .foregroundColor(theme.muted)
                                    Text(to)
                                        .font(Typography.caption)
                                        .foregroundColor(theme.sky)
                                }

                                Text(msg.payload.prefix(50) + (msg.payload.count > 50 ? "..." : ""))
                                    .font(Typography.caption)
                                    .foregroundColor(theme.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
                .frame(maxHeight: 150)
            }
        }
    }
}

// MARK: - Agent Task Input

struct AgentTaskInput: View {
    let agentId: String
    let agentName: String
    @Binding var taskInput: String
    @EnvironmentObject private var orchestrator: AgentOrchestrator
    @EnvironmentObject private var theme: ThemeEngine

    var body: some View {
        HStack(spacing: 8) {
            TextField("Task for \(agentName)...", text: $taskInput)
                .textFieldStyle(.plain)
                .font(Typography.body)
                .foregroundColor(theme.primary)
                .padding(8)
                .background(theme.elevated)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .onSubmit {
                    sendTask()
                }

            Button {
                sendTask()
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 12))
                    .foregroundColor(taskInput.isEmpty ? theme.muted : theme.sky)
            }
            .buttonStyle(.plain)
            .disabled(taskInput.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func sendTask() {
        let task = taskInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty else { return }
        orchestrator.assignTask(agentId: agentId, task: task)
        taskInput = ""
    }
}

// MARK: - Agent Conversation Preview

/// Shows the selected agent's Claude conversation in real-time
struct AgentConversationPreview: View {
    @ObservedObject var process: ClaudeProcess
    @EnvironmentObject private var theme: ThemeEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "text.bubble")
                    .font(.system(size: 10))
                    .foregroundColor(theme.muted)
                Text("Conversation")
                    .font(Typography.caption)
                    .foregroundColor(theme.secondary)

                Spacer()

                if process.isStreaming {
                    StreamingDots()
                }

                Text("\(process.messages.count) msgs")
                    .font(Typography.caption)
                    .foregroundColor(theme.muted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            if process.messages.isEmpty {
                Text("No messages yet")
                    .font(Typography.caption)
                    .foregroundColor(theme.muted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(process.messages) { msg in
                                AgentMessageRow(message: msg)
                                    .id(msg.id)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                    .frame(maxHeight: 250)
                    .onChange(of: process.messages.count) { _, _ in
                        if let lastId = process.messages.last?.id {
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Compact display of a single message from an agent's conversation
struct AgentMessageRow: View {
    let message: ConversationMessage
    @EnvironmentObject private var theme: ThemeEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Role label
            HStack(spacing: 4) {
                Text(message.role == .user ? "Task" : "Agent")
                    .font(Typography.caption)
                    .foregroundColor(message.role == .user ? theme.sky : theme.sage)

                if message.isStreaming {
                    StreamingDots()
                }

                Spacer()

                if let duration = message.duration {
                    Text(String(format: "%.1fs", duration))
                        .font(Typography.caption)
                        .foregroundColor(theme.muted)
                }
            }

            // Content blocks (simplified)
            ForEach(Array(message.blocks.enumerated()), id: \.offset) { _, block in
                if let textBlock = block as? TextBlock {
                    Text(textBlock.text)
                        .font(Typography.caption)
                        .foregroundColor(theme.primary)
                        .lineLimit(6)
                        .textSelection(.enabled)
                } else if let codeBlock = block as? CodeBlock {
                    Text(codeBlock.code)
                        .font(Typography.codeBlock)
                        .foregroundColor(theme.secondary)
                        .lineLimit(4)
                        .padding(4)
                        .background(theme.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else if let toolBlock = block as? ToolUseBlock {
                    HStack(spacing: 4) {
                        Image(systemName: toolBlock.status == .completed ? "checkmark" : toolBlock.status == .failed ? "xmark" : "gear")
                            .font(.system(size: 9))
                            .foregroundColor(toolBlock.status == .failed ? theme.rose : theme.muted)
                        Text(toolBlock.toolName)
                            .font(Typography.caption)
                            .foregroundColor(theme.secondary)
                        Text(toolBlock.input.prefix(40) + (toolBlock.input.count > 40 ? "..." : ""))
                            .font(Typography.caption)
                            .foregroundColor(theme.muted)
                            .lineLimit(1)
                    }
                } else if block is ThinkingBlock {
                    HStack(spacing: 4) {
                        Image(systemName: "brain")
                            .font(.system(size: 9))
                            .foregroundColor(theme.lavender)
                        Text("thinking...")
                            .font(Typography.caption)
                            .foregroundColor(theme.lavender)
                            .italic()
                    }
                }
            }
        }
        .padding(6)
        .background(message.role == .user ? theme.elevated.opacity(0.3) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Spawn Agent Sheet

struct SpawnAgentSheet: View {
    @EnvironmentObject private var orchestrator: AgentOrchestrator
    @EnvironmentObject private var process: ClaudeProcess
    @EnvironmentObject private var theme: ThemeEngine
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selectedRole: AgentRole = .builder

    var body: some View {
        VStack(spacing: 20) {
            Text("Spawn Agent")
                .font(Typography.heading2)
                .foregroundColor(theme.bright)

            // Name field
            TextField("Agent name", text: $name)
                .textFieldStyle(.roundedBorder)

            // Role picker
            Picker("Role", selection: $selectedRole) {
                ForEach(AgentRole.allCases) { role in
                    Label(role.displayName, systemImage: role.icon)
                        .tag(role)
                }
            }
            .pickerStyle(.radioGroup)

            // Working directory info
            if let dir = process.workingDirectory {
                HStack {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 10))
                        .foregroundColor(theme.muted)
                    Text(dir)
                        .font(Typography.caption)
                        .foregroundColor(theme.muted)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Spawn") {
                    let agentName = name.isEmpty ? selectedRole.displayName : name
                    orchestrator.spawnAgent(
                        name: agentName,
                        role: selectedRole,
                        directory: process.workingDirectory
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 350)
    }
}
