import SwiftUI

/// Selective compaction UI (Cmd+X) — shows context usage and lets user choose what to keep/summarize
struct ContextOverlay: View {
    @EnvironmentObject private var contextManager: ContextStateManager
    @EnvironmentObject private var optimizer: ContextBudgetOptimizer
    @EnvironmentObject private var compaction: CompactionEngine
    @EnvironmentObject private var theme: ThemeEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Context Manager")
                    .font(Typography.heading1)
                    .foregroundColor(theme.bright)

                Spacer()

                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(theme.muted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider().opacity(0.3)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Context usage visualization
                    contextGauge

                    // Token breakdown
                    tokenBreakdown

                    // Warning level
                    if contextManager.warningLevel != .none {
                        warningBanner
                    }

                    // Optimization suggestions
                    if !optimizer.optimizationSuggestions.isEmpty {
                        optimizationSection
                    }

                    // Current tracked context
                    if let snapshot = contextManager.currentSnapshot {
                        trackedContextSection(snapshot: snapshot)
                    }
                }
                .padding(20)
            }
        }
        .background(theme.surface)
        .frame(minWidth: 500, minHeight: 400)
    }

    // MARK: - Context Gauge

    private var contextGauge: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Context Usage")
                    .font(Typography.bodyBold)
                    .foregroundColor(theme.bright)

                Spacer()

                Text("\(Int(contextManager.contextPercentage * 100))%")
                    .font(Typography.heading2)
                    .foregroundColor(gaugeColor)
            }

            // Visual bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(theme.elevated)
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(gaugeColor)
                        .frame(width: geo.size.width * contextManager.contextPercentage, height: 8)
                }
            }
            .frame(height: 8)

            HStack {
                Text("\(contextManager.inputTokens + contextManager.outputTokens) / \(contextManager.maxContextTokens) tokens")
                    .font(Typography.caption)
                    .foregroundColor(theme.muted)

                Spacer()

                Text("\(contextManager.maxContextTokens - contextManager.inputTokens - contextManager.outputTokens) remaining")
                    .font(Typography.caption)
                    .foregroundColor(theme.muted)
            }
        }
    }

    private var gaugeColor: Color {
        switch contextManager.warningLevel {
        case .none: return theme.sky
        case .warm: return theme.sand
        case .critical: return theme.rose
        }
    }

    // MARK: - Token Breakdown

    private var tokenBreakdown: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Token Breakdown")
                .font(Typography.bodyBold)
                .foregroundColor(theme.bright)

            HStack(spacing: 20) {
                TokenStat(label: "Input", value: contextManager.inputTokens, color: theme.sky)
                TokenStat(label: "Output", value: contextManager.outputTokens, color: theme.lavender)
                TokenStat(label: "Cache", value: contextManager.cacheReadTokens, color: theme.sage)
            }
        }
    }

    // MARK: - Warning Banner

    private var warningBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: contextManager.warningLevel == .critical ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundColor(contextManager.warningLevel == .critical ? theme.rose : theme.sand)

            VStack(alignment: .leading, spacing: 2) {
                Text(contextManager.warningLevel == .critical ? "Context Nearly Full" : "Context Getting Warm")
                    .font(Typography.bodyBold)
                    .foregroundColor(contextManager.warningLevel == .critical ? theme.rose : theme.sand)

                Text("Consider compacting or starting a new session to avoid information loss")
                    .font(Typography.caption)
                    .foregroundColor(theme.secondary)
            }
        }
        .padding(12)
        .background((contextManager.warningLevel == .critical ? theme.rose : theme.sand).opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Optimization Suggestions

    private var optimizationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Optimization Suggestions")
                    .font(Typography.bodyBold)
                    .foregroundColor(theme.bright)

                Spacer()

                Text("~\(optimizer.estimatedSavings) tokens saveable")
                    .font(Typography.caption)
                    .foregroundColor(theme.sage)
            }

            ForEach(optimizer.optimizationSuggestions) { suggestion in
                HStack(spacing: 8) {
                    Circle()
                        .fill(theme.sky)
                        .frame(width: 6, height: 6)

                    Text(suggestion.description)
                        .font(Typography.caption)
                        .foregroundColor(theme.secondary)

                    Spacer()

                    Text("-\(suggestion.estimatedTokenSavings)")
                        .font(Typography.caption)
                        .foregroundColor(theme.sage)
                }
            }
        }
    }

    // MARK: - Tracked Context

    private func trackedContextSection(snapshot: ContextSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tracked Context")
                .font(Typography.bodyBold)
                .foregroundColor(theme.bright)

            if !snapshot.decisions.isEmpty {
                Text("Decisions: \(snapshot.decisions.count)")
                    .font(Typography.caption)
                    .foregroundColor(theme.secondary)
            }

            if !snapshot.fileChanges.isEmpty {
                Text("File changes: \(snapshot.fileChanges.count)")
                    .font(Typography.caption)
                    .foregroundColor(theme.secondary)
            }

            if !snapshot.taskProgress.isEmpty {
                let completed = snapshot.taskProgress.filter { $0.status == .completed }.count
                Text("Tasks: \(completed)/\(snapshot.taskProgress.count) completed")
                    .font(Typography.caption)
                    .foregroundColor(theme.secondary)
            }
        }
    }
}

// MARK: - Token Stat

private struct TokenStat: View {
    let label: String
    let value: Int
    let color: Color
    @EnvironmentObject private var theme: ThemeEngine

    var body: some View {
        VStack(spacing: 2) {
            Text(formatTokens(value))
                .font(Typography.bodyBold)
                .foregroundColor(color)
            Text(label)
                .font(Typography.caption)
                .foregroundColor(theme.muted)
        }
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000)
        }
        return "\(count)"
    }
}
