import SwiftUI

/// Performance analytics overlay — token usage, cost trends, timing
struct PerformanceDashboard: View {
    @EnvironmentObject private var process: ClaudeProcess
    @EnvironmentObject private var theme: ThemeEngine
    @EnvironmentObject private var sessionManager: SessionManager
    @EnvironmentObject private var contextManager: ContextStateManager
    @EnvironmentObject private var orchestrator: AgentOrchestrator
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 14))
                    .foregroundColor(theme.sky)
                Text("Performance")
                    .font(Typography.heading2)
                    .foregroundColor(theme.bright)
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(theme.muted)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider().opacity(0.3)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Current Session Stats
                    statsSection("Current Session", stats: currentSessionStats())

                    Divider().opacity(0.2)

                    // Token Breakdown
                    tokenBreakdown

                    Divider().opacity(0.2)

                    // Message Analysis
                    messageAnalysis

                    Divider().opacity(0.2)

                    // Agent Stats (if any agents running)
                    if !orchestrator.agents.isEmpty {
                        agentStats

                        Divider().opacity(0.2)
                    }

                    // Session History
                    sessionHistory
                }
                .padding(16)
            }
        }
        .background(theme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.sky.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 30, y: 10)
        .frame(width: 560, height: 600)
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
    }

    // MARK: - Stats Section

    private func statsSection(_ title: String, stats: [(String, String, Color)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(Typography.bodyBold)
                .foregroundColor(theme.bright)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 10) {
                ForEach(stats, id: \.0) { label, value, color in
                    VStack(spacing: 4) {
                        Text(value)
                            .font(.system(size: 18, weight: .semibold, design: .monospaced))
                            .foregroundColor(color)
                        Text(label)
                            .font(Typography.caption)
                            .foregroundColor(theme.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    // MARK: - Token Breakdown

    private var tokenBreakdown: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Token Usage")
                .font(Typography.bodyBold)
                .foregroundColor(theme.bright)

            // Visual bars
            tokenBar("Input", count: contextManager.inputTokens, max: contextManager.maxContextTokens, color: theme.sky)
            tokenBar("Output", count: contextManager.outputTokens, max: contextManager.maxContextTokens, color: theme.sage)
            tokenBar("Cache Read", count: contextManager.cacheReadTokens, max: contextManager.maxContextTokens, color: theme.lavender)

            // Efficiency metric
            let total = contextManager.inputTokens + contextManager.outputTokens
            if total > 0 {
                let ratio = Double(contextManager.outputTokens) / Double(total)
                HStack(spacing: 6) {
                    Text("Output/Total Ratio:")
                        .font(Typography.caption)
                        .foregroundColor(theme.muted)
                    Text(String(format: "%.0f%%", ratio * 100))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(ratio > 0.3 ? theme.sage : theme.muted)
                }
            }
        }
    }

    private func tokenBar(_ label: String, count: Int, max: Int, color: Color) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(Typography.caption)
                .foregroundColor(theme.muted)
                .frame(width: 70, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(theme.surface)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geo.size.width * min(Double(count) / Double(max), 1.0))
                }
            }
            .frame(height: 8)

            Text(formatTokens(count))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(theme.secondary)
                .frame(width: 50, alignment: .trailing)
        }
    }

    // MARK: - Message Analysis

    private var messageAnalysis: some View {
        let msgs = process.messages
        let userMsgs = msgs.filter { $0.role == .user }
        let assistantMsgs = msgs.filter { $0.role == .assistant }
        let toolUseCount = msgs.flatMap { $0.blocks }.compactMap { $0 as? ToolUseBlock }.count
        let codeBlockCount = msgs.flatMap { $0.blocks }.compactMap { $0 as? CodeBlock }.count

        let avgDuration: Double = {
            let durations = assistantMsgs.compactMap { $0.duration }
            guard !durations.isEmpty else { return 0 }
            return durations.reduce(0, +) / Double(durations.count)
        }()

        return VStack(alignment: .leading, spacing: 10) {
            Text("Message Analysis")
                .font(Typography.bodyBold)
                .foregroundColor(theme.bright)

            HStack(spacing: 16) {
                statPill("User Msgs", value: "\(userMsgs.count)", color: theme.sky)
                statPill("Responses", value: "\(assistantMsgs.count)", color: theme.sage)
                statPill("Tool Uses", value: "\(toolUseCount)", color: theme.lavender)
                statPill("Code Blocks", value: "\(codeBlockCount)", color: theme.amber)
            }

            if avgDuration > 0 {
                HStack(spacing: 6) {
                    Text("Avg Response Time:")
                        .font(Typography.caption)
                        .foregroundColor(theme.muted)
                    Text(String(format: "%.1fs", avgDuration))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(theme.secondary)
                }
            }
        }
    }

    private func statPill(_ label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(theme.muted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Agent Stats

    private var agentStats: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Agent Performance")
                .font(Typography.bodyBold)
                .foregroundColor(theme.bright)

            ForEach(orchestrator.agents) { agent in
                HStack(spacing: 10) {
                    Image(systemName: agent.role.icon)
                        .font(.system(size: 10))
                        .foregroundColor(theme.sky)
                        .frame(width: 16)

                    Text(agent.name)
                        .font(Typography.body)
                        .foregroundColor(theme.primary)

                    Spacer()

                    Text(formatTokens(agent.inputTokens + agent.outputTokens))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(theme.muted)

                    Text(formatCost(agent.costUSD))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(theme.amber)

                    AgentStateIndicator(state: agent.state)
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Session History

    private var sessionHistory: some View {
        let sessions = sessionManager.sessions
            .sorted { $0.lastActiveAt > $1.lastActiveAt }
            .prefix(5)

        return VStack(alignment: .leading, spacing: 10) {
            Text("Recent Sessions")
                .font(Typography.bodyBold)
                .foregroundColor(theme.bright)

            if sessions.isEmpty {
                Text("No session history")
                    .font(Typography.caption)
                    .foregroundColor(theme.muted)
            } else {
                ForEach(Array(sessions), id: \.id) { session in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(session.id == sessionManager.activeSession?.id ? theme.sage : theme.muted.opacity(0.3))
                            .frame(width: 6, height: 6)

                        Text(session.title)
                            .font(Typography.body)
                            .foregroundColor(theme.primary)
                            .lineLimit(1)

                        Spacer()

                        if session.messageCount > 0 {
                            Text("\(session.messageCount) msgs")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(theme.muted)
                        }

                        if session.totalCostUSD > 0.01 {
                            Text(formatCost(session.totalCostUSD))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(theme.amber)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - Helpers

    private func currentSessionStats() -> [(String, String, Color)] {
        let totalTokens = process.totalInputTokens + process.totalOutputTokens
        let pct = contextManager.contextPercentage
        return [
            ("Total Tokens", formatTokens(totalTokens), theme.sky),
            ("Total Cost", formatCost(process.totalCostUSD), theme.amber),
            ("Context Used", "\(Int(pct * 100))%", pct < 0.5 ? theme.sky : pct < 0.75 ? theme.sand : theme.rose),
            ("Messages", "\(process.messages.count)", theme.primary),
            ("Model", formatModel(process.currentModel), theme.secondary),
            ("Agents", "\(orchestrator.agents.count)", theme.lavender),
        ]
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }

    private func formatCost(_ cost: Double) -> String {
        if cost < 0.01 { return "$0.00" }
        return String(format: "$%.2f", cost)
    }

    private func formatModel(_ model: String) -> String {
        if model.contains("opus") { return "Opus" }
        if model.contains("sonnet") { return "Sonnet" }
        if model.contains("haiku") { return "Haiku" }
        return model.components(separatedBy: "-").last ?? model
    }
}
