import SwiftUI

/// Split-pane view showing multiple agents working side by side
/// Each pane shows an agent's conversation in real-time
struct MultiAgentSplitView: View {
    @EnvironmentObject private var orchestrator: AgentOrchestrator
    @EnvironmentObject private var theme: ThemeEngine
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "rectangle.split.3x1.fill")
                    .font(.system(size: 14))
                    .foregroundColor(theme.sky)
                Text("Multi-Agent View")
                    .font(Typography.heading2)
                    .foregroundColor(theme.bright)

                Spacer()

                Text("\(orchestrator.agents.count) agents")
                    .font(Typography.caption)
                    .foregroundColor(theme.muted)

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(theme.muted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider().opacity(0.3)

            if orchestrator.agents.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "person.3")
                        .font(.system(size: 32))
                        .foregroundColor(theme.muted)
                    Text("No agents running")
                        .font(Typography.body)
                        .foregroundColor(theme.muted)
                    Text("Use Cmd+K to spawn agents")
                        .font(Typography.caption)
                        .foregroundColor(theme.muted)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Split panes — one per active agent
                HSplitView {
                    ForEach(orchestrator.agents) { agent in
                        if let process = orchestrator.getProcess(for: agent.id) {
                            AgentPane(agent: agent, process: process)
                        }
                    }
                }
            }
        }
        .background(theme.base)
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
    }
}

// MARK: - Agent Pane

/// A single agent's conversation pane in the split view
struct AgentPane: View {
    let agent: Agent
    @ObservedObject var process: ClaudeProcess
    @EnvironmentObject private var orchestrator: AgentOrchestrator
    @EnvironmentObject private var theme: ThemeEngine
    @State private var taskText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Agent header
            HStack(spacing: 6) {
                Image(systemName: agent.role.icon)
                    .font(.system(size: 11))
                    .foregroundColor(theme.sky)

                Text(agent.name)
                    .font(Typography.bodyBold)
                    .foregroundColor(theme.bright)

                Text(agent.role.displayName)
                    .font(Typography.caption)
                    .foregroundColor(theme.muted)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(theme.elevated)
                    .clipShape(Capsule())

                Spacer()

                AgentStateIndicator(state: agent.state)

                Button {
                    orchestrator.stopAgent(id: agent.id)
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 11))
                        .foregroundColor(theme.muted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(theme.surface)

            Divider().opacity(0.3)

            // Conversation
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(process.messages) { msg in
                            SplitPaneMessageRow(message: msg)
                                .id(msg.id)
                        }

                        if process.isStreaming && process.messages.last?.isStreaming != true {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.mini)
                                    .scaleEffect(0.7)
                                Text("thinking...")
                                    .font(Typography.caption)
                                    .foregroundColor(theme.lavender)
                            }
                            .padding(.horizontal, 10)
                            .id("streaming")
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .onChange(of: process.messages.count) { _, _ in
                    if let lastId = process.messages.last?.id {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }

            Divider().opacity(0.3)

            // Task input
            HStack(spacing: 6) {
                TextField("Task...", text: $taskText)
                    .textFieldStyle(.plain)
                    .font(Typography.caption)
                    .foregroundColor(theme.primary)
                    .padding(6)
                    .background(theme.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .onSubmit { sendTask() }

                Button {
                    sendTask()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 10))
                        .foregroundColor(taskText.isEmpty ? theme.muted : theme.sky)
                }
                .buttonStyle(.plain)
                .disabled(taskText.isEmpty)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            // Stats bar
            HStack(spacing: 8) {
                Text("\(process.totalInputTokens + process.totalOutputTokens) tokens")
                    .font(Typography.caption)
                    .foregroundColor(theme.muted)
                Text(formatCost(process.totalCostUSD))
                    .font(Typography.caption)
                    .foregroundColor(theme.amber)
                Spacer()
                Text("\(process.messages.count) msgs")
                    .font(Typography.caption)
                    .foregroundColor(theme.muted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(theme.surface)
        }
        .frame(minWidth: 250)
    }

    private func sendTask() {
        let task = taskText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty else { return }
        orchestrator.assignTask(agentId: agent.id, task: task)
        taskText = ""
    }

    private func formatCost(_ cost: Double) -> String {
        if cost < 0.01 { return "$0.00" }
        return String(format: "$%.2f", cost)
    }
}

// MARK: - Split Pane Message Row

/// Compact message display for split pane view
struct SplitPaneMessageRow: View {
    let message: ConversationMessage
    @EnvironmentObject private var theme: ThemeEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Role + duration
            HStack {
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

            // Blocks
            ForEach(Array(message.blocks.enumerated()), id: \.offset) { _, block in
                if let textBlock = block as? TextBlock {
                    Text(textBlock.text)
                        .font(Typography.caption)
                        .foregroundColor(theme.primary)
                        .lineLimit(8)
                        .textSelection(.enabled)
                } else if let codeBlock = block as? CodeBlock {
                    Text(codeBlock.code)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(theme.secondary)
                        .lineLimit(5)
                        .padding(4)
                        .background(theme.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                } else if let toolBlock = block as? ToolUseBlock {
                    HStack(spacing: 3) {
                        Image(systemName: toolBlock.status == .completed ? "checkmark" : toolBlock.status == .failed ? "xmark" : "gear")
                            .font(.system(size: 8))
                            .foregroundColor(toolBlock.status == .failed ? theme.rose : theme.muted)
                        Text(toolBlock.toolName)
                            .font(Typography.caption)
                            .foregroundColor(theme.secondary)
                    }
                } else if block is ThinkingBlock {
                    HStack(spacing: 3) {
                        Image(systemName: "brain")
                            .font(.system(size: 8))
                            .foregroundColor(theme.lavender)
                        Text("thinking...")
                            .font(Typography.caption)
                            .foregroundColor(theme.lavender)
                            .italic()
                    }
                }
            }
        }
        .padding(5)
        .background(message.role == .user ? theme.elevated.opacity(0.3) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
