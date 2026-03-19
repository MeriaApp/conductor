import SwiftUI
import AppKit

/// Top status bar showing model, context %, cost, git branch, luminance
/// Per UX_DESIGN.md: "One line. Every critical metric at a glance."
struct StatusBar: View {
    @Binding var windowLabel: String

    @EnvironmentObject private var process: ClaudeProcess
    @EnvironmentObject private var theme: ThemeEngine
    @EnvironmentObject private var sessionManager: SessionManager
    @EnvironmentObject private var contextManager: ContextStateManager
    @EnvironmentObject private var contextPipeline: ContextPreservationPipeline
    @EnvironmentObject private var modelRouter: ModelRouter

    @State private var isEditingLabel = false
    @State private var editingText = ""

    var body: some View {
        HStack(spacing: 10) {
            if process.isVibeCoder {
                // Vibe Coder Mode: simplified — "Claude Code · health · cost"
                vibeCoderStatusBar
            } else {
                // Full mode
                fullStatusBar
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(theme.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.separator.opacity(0.3))
                .frame(height: 1)
        }
    }

    // MARK: - Vibe Coder Status Bar

    private var vibeCoderStatusBar: some View {
        Group {
            HStack(spacing: 4) {
                Circle()
                    .fill(process.isRunning ? theme.sage : theme.muted)
                    .frame(width: 6, height: 6)

                Text("Claude Code")
                    .font(Typography.statusBar)
                    .foregroundColor(theme.bright)
            }

            Divider()
                .frame(height: 12)
                .opacity(0.3)

            // Health status word
            let pct = contextManager.contextPercentage
            let healthLabel = pct < 0.5 ? "healthy" : pct < 0.75 ? "getting warm" : "running low"
            let healthColor = pct < 0.5 ? theme.sage : pct < 0.75 ? theme.sand : theme.rose

            Text(healthLabel)
                .font(Typography.statusBar)
                .foregroundColor(healthColor)

            Divider()
                .frame(height: 12)
                .opacity(0.3)

            // Cost
            costIndicator

            Spacer()

            // Vibe coder badge
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9))
                Text("Vibe")
                    .font(Typography.statusBarSecondary)
            }
            .foregroundColor(theme.lavender)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(theme.lavender.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }

    // MARK: - Full Status Bar

    private var fullStatusBar: some View {
        Group {
            // Plan mode indicator
            if process.permissionMode == .plan {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 9))
                    Text("PLAN")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                }
                .foregroundColor(theme.lavender)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(theme.lavender.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 4))

                statusDivider
            }

            // Window name (only show when set or editing)
            if !windowLabel.isEmpty || isEditingLabel {
                windowNameIndicator
                statusDivider
            }

            // === LEFT ZONE: Metrics (checked every turn) ===

            modelIndicator

            if let suggestion = modelRouter.suggestion {
                modelSuggestionPill(suggestion)
            }

            if let autoApplied = modelRouter.lastAutoApplied {
                autoAppliedIndicator(autoApplied)
            }

            statusDivider

            contextIndicator

            if !contextManager.contextHealth.isHealthy {
                contextHealthIndicator
            }

            if contextPipeline.compactionDetected || contextPipeline.snapshotTaken {
                compactionIndicator
            }

            statusDivider

            costIndicator

            statusDivider

            // === CENTER ZONE: Project context ===

            if let dir = process.workingDirectory {
                directoryIndicator(dir)
                statusDivider
            }

            if let branch = sessionManager.activeSession?.gitBranch {
                gitIndicator(branch: branch)
                statusDivider
            }

            Spacer()

            // === RIGHT ZONE: Settings (rarely changed) ===
            // Only show non-default indicators to reduce clutter

            if process.agentTeamsEnabled {
                agentTeamsIndicator
                statusDivider
            }

            if process.outputMode != .standard {
                outputModeIndicator
                statusDivider
            }

            // Budget: only show when a cap is actively set (0 = no limit = hidden)
            if process.maxBudgetUSD > 0 {
                budgetIndicator
                statusDivider
            }

            effortPicker

            if process.autonomousMode {
                autonomousIndicator
                statusDivider
            }

            permissionIndicator

            luminanceControl
        }
    }

    private var statusDivider: some View {
        Divider()
            .frame(height: 12)
            .opacity(0.3)
    }

    // MARK: - Model

    private var modelIndicator: some View {
        Menu {
            ForEach(ModelChoice.allCases, id: \.rawValue) { model in
                Button {
                    process.selectedModel = model
                } label: {
                    HStack {
                        Image(systemName: model.icon)
                        Text(model.displayName)
                        if isModelSelected(model) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            Divider()
            Button {
                process.selectedModel = nil
            } label: {
                HStack {
                    Text("Auto (CLI default)")
                    if process.selectedModel == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(process.isRunning ? theme.sage : theme.muted)
                    .frame(width: 6, height: 6)

                Text(modelDisplayName)
                    .font(Typography.statusBar)
                    .foregroundColor(theme.bright)

                if process.selectedModel != nil,
                   !formatModelName(process.currentModel).lowercased().contains(process.selectedModel!.rawValue) {
                    Text("→ \(process.selectedModel!.displayName)")
                        .font(Typography.statusBarSecondary)
                        .foregroundColor(theme.sky)
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(theme.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    /// Display name: show selected model if set, otherwise current model from CLI
    private var modelDisplayName: String {
        if let selected = process.selectedModel {
            return selected.displayName
        }
        return formatModelName(process.currentModel)
    }

    /// Check if a model choice matches current state
    private func isModelSelected(_ model: ModelChoice) -> Bool {
        if let selected = process.selectedModel {
            return selected == model
        }
        return formatModelName(process.currentModel).lowercased() == model.rawValue
    }

    // MARK: - Context

    private var contextIndicator: some View {
        let pct = contextManager.contextPercentage
        let color = contextColor(for: pct)

        return HStack(spacing: 4) {
            Image(systemName: "diamond.fill")
                .font(.system(size: 8))
                .foregroundColor(color)

            Text("\(Int(pct * 100))%")
                .font(Typography.statusBar)
                .foregroundColor(color)
        }
    }

    // MARK: - Context Health

    private var contextHealthIndicator: some View {
        let health = contextManager.contextHealth
        let isCritical: Bool = {
            if case .critical = health { return true }
            return false
        }()
        let color = isCritical ? theme.rose : theme.amber

        return HStack(spacing: 3) {
            Image(systemName: health.icon)
                .font(.system(size: 9))
            Text(health.label)
                .font(Typography.statusBarSecondary)
        }
        .foregroundColor(color)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .help(health.reason ?? "Context is healthy")
    }

    // MARK: - Compaction

    private var compactionIndicator: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 9))
            Text(contextPipeline.recoveryPending ? "Recovery" : "Snapshot")
                .font(Typography.statusBarSecondary)
        }
        .foregroundColor(contextPipeline.recoveryPending ? theme.sand : theme.sage)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(theme.sand.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .help(contextPipeline.recoveryPending
            ? "Context was compacted — recovery will be injected on next message"
            : "Pre-compaction snapshot taken at 70% context")
    }

    // MARK: - Cost

    private var costIndicator: some View {
        let cost = process.totalCostUSD
        let turnCost = process.lastTurnCostUSD
        let savings = process.estimatedSavingsUSD

        return HStack(spacing: 4) {
            Text(formatCost(cost))
                .font(Typography.statusBar)
                .foregroundColor(cost > 1.0 ? theme.amber : theme.muted)

            // Per-turn cost (only show when > $0.01)
            if turnCost >= 0.01 {
                Text(String(format: "(+$%.2f)", turnCost))
                    .font(Typography.statusBarSecondary)
                    .foregroundColor(turnCost > 0.50 ? theme.rose : theme.muted)
            }

            // Savings indicator (only show when > $0.10)
            if savings >= 0.10 {
                Text(String(format: "saved ~$%.2f", savings))
                    .font(Typography.statusBarSecondary)
                    .foregroundColor(theme.sage)
            }
        }
    }

    // MARK: - Git

    private func gitIndicator(branch: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 10))
                .foregroundColor(theme.muted)

            Text(branch)
                .font(Typography.statusBar)
                .foregroundColor(theme.secondary)
        }
    }

    // MARK: - Directory

    private func directoryIndicator(_ path: String) -> some View {
        Button {
            openDirectoryPicker()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 10))
                    .foregroundColor(theme.muted)

                Text(shortenDirectory(path))
                    .font(Typography.statusBar)
                    .foregroundColor(theme.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Click to change working directory")
    }

    /// Open folder picker to change working directory (same as AppShell)
    private func openDirectoryPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Choose Working Directory"
        panel.prompt = "Select"

        if panel.runModal() == .OK, let url = panel.url {
            let path = url.path
            process.stop()
            process.start(directory: path)
        }
    }

    private func shortenDirectory(_ path: String) -> String {
        let components = path.components(separatedBy: "/").filter { !$0.isEmpty }
        if components.count <= 2 { return path }
        return components.suffix(2).joined(separator: "/")
    }

    // MARK: - Effort Level

    private var effortPicker: some View {
        Menu {
            // Smart effort toggle
            Button {
                process.smartEffort.toggle()
            } label: {
                HStack {
                    Image(systemName: "brain")
                    Text("Smart (Auto)")
                    if process.smartEffort {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Divider()

            ForEach(EffortLevel.allCases, id: \.rawValue) { level in
                Button {
                    process.smartEffort = false
                    process.effortLevel = level
                } label: {
                    HStack {
                        Image(systemName: level.icon)
                        Text(level.displayName)
                        if !process.smartEffort && process.effortLevel == level {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: process.smartEffort ? "brain" : process.effortLevel.icon)
                    .font(.system(size: 9))
                Text(process.smartEffort ? "Auto" : process.effortLevel.displayName)
                    .font(Typography.statusBarSecondary)
            }
            .foregroundColor(process.smartEffort ? theme.sage : (process.effortLevel == .high ? theme.sky : theme.muted))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(theme.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Permission Mode

    private var permissionIndicator: some View {
        Menu {
            ForEach(CLIPermissionMode.allCases, id: \.rawValue) { mode in
                Button {
                    process.permissionMode = mode
                } label: {
                    VStack(alignment: .leading) {
                        HStack {
                            Text(mode.displayName)
                            if process.permissionMode == mode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: permissionIcon)
                    .font(.system(size: 9))
                Text(process.permissionMode.displayName)
                    .font(Typography.statusBarSecondary)
            }
            .foregroundColor(permissionColor)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(theme.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var permissionIcon: String {
        switch process.permissionMode {
        case .bypassPermissions: return "lock.open"
        case .acceptEdits: return "lock.open.trianglebadge.exclamationmark"
        case .default_: return "lock"
        case .plan: return "doc.text.magnifyingglass"
        }
    }

    private var permissionColor: Color {
        switch process.permissionMode {
        case .bypassPermissions: return theme.rose
        case .acceptEdits: return theme.amber
        case .default_: return theme.sage
        case .plan: return theme.lavender
        }
    }

    // MARK: - Output Mode

    private var outputModeIndicator: some View {
        Menu {
            ForEach(OutputMode.allCases, id: \.rawValue) { mode in
                Button {
                    process.outputMode = mode
                } label: {
                    HStack {
                        Image(systemName: mode.icon)
                        Text(mode.displayName)
                        if process.outputMode == mode {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: process.outputMode.icon)
                    .font(.system(size: 9))
                Text(process.outputMode.displayName)
                    .font(Typography.statusBarSecondary)
            }
            .foregroundColor(theme.lavender)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(theme.lavender.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Budget

    private var budgetIndicator: some View {
        HStack(spacing: 3) {
            Image(systemName: "dollarsign.circle")
                .font(.system(size: 9))
            Text(String(format: "$%.0f cap", process.maxBudgetUSD))
                .font(Typography.statusBarSecondary)
        }
        .foregroundColor(process.totalCostUSD > process.maxBudgetUSD * 0.8 ? theme.rose : theme.amber)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(theme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    // MARK: - Agent Teams

    private var agentTeamsIndicator: some View {
        HStack(spacing: 3) {
            Image(systemName: "person.3.sequence.fill")
                .font(.system(size: 9))
            Text("Teams")
                .font(Typography.statusBarSecondary)
        }
        .foregroundColor(theme.lavender)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(theme.lavender.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .help("Agent Teams enabled — Claude can spawn sub-agents autonomously")
    }

    // MARK: - Autonomous Mode

    private var autonomousIndicator: some View {
        Button {
            process.autonomousMode = false
            process.permissionMode = .default_
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "bolt.shield.fill")
                    .font(.system(size: 9))
                Text("Autonomous")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
            }
            .foregroundColor(theme.amber)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(theme.amber.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .help("Autonomous Mode active — click to disable")
    }

    // MARK: - Luminance

    private var luminanceControl: some View {
        HStack(spacing: 4) {
            Image(systemName: "sun.min")
                .font(.system(size: 10))
                .foregroundColor(theme.muted)

            Slider(value: $theme.luminance, in: 0...1, step: 0.05)
                .frame(width: 60)
                .controlSize(.mini)

            Image(systemName: "sun.max")
                .font(.system(size: 10))
                .foregroundColor(theme.muted)
        }
    }

    // MARK: - Model Suggestion

    private func modelSuggestionPill(_ suggestion: ModelSuggestion) -> some View {
        Button {
            process.selectedModel = suggestion.model
            modelRouter.dismissSuggestion()
        } label: {
            HStack(spacing: 3) {
                Text("→ \(suggestion.model.displayName)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
            }
            .foregroundColor(theme.sky)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(theme.sky.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .lineLimit(1)
            .fixedSize()
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Dismiss") {
                modelRouter.dismissSuggestion()
            }
            Button("Disable Smart Routing") {
                modelRouter.isEnabled = false
                modelRouter.dismissSuggestion()
            }
        }
        .help(suggestion.reason)
    }

    // MARK: - Auto-Applied Model

    private func autoAppliedIndicator(_ suggestion: ModelSuggestion) -> some View {
        HStack(spacing: 3) {
            Text("\u{2192} \(suggestion.model.displayName) (auto)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
        }
        .foregroundColor(theme.sage)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(theme.sage.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .lineLimit(1)
        .fixedSize()
        .help(suggestion.reason)
        .onAppear {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                withAnimation(.easeOut(duration: 0.3)) {
                    modelRouter.lastAutoApplied = nil
                }
            }
        }
    }

    // MARK: - Window Name

    private var windowNameIndicator: some View {
        Group {
            if isEditingLabel {
                HStack(spacing: 4) {
                    Image(systemName: "pencil")
                        .font(.system(size: 9))
                        .foregroundColor(theme.sky)

                    TextField("Name this window...", text: $editingText, onCommit: {
                        windowLabel = editingText.trimmingCharacters(in: .whitespaces)
                        isEditingLabel = false
                    })
                    .textFieldStyle(.plain)
                    .font(Typography.statusBar)
                    .foregroundColor(theme.bright)
                    .frame(width: 150)
                    .onExitCommand {
                        isEditingLabel = false
                    }
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(theme.sky.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                Button {
                    editingText = windowLabel
                    isEditingLabel = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: windowLabel.isEmpty ? "tag" : "tag.fill")
                            .font(.system(size: 9))
                            .foregroundColor(windowLabel.isEmpty ? theme.muted : theme.sky)

                        Text(windowLabel.isEmpty ? "Name" : windowLabel)
                            .font(Typography.statusBar)
                            .foregroundColor(windowLabel.isEmpty ? theme.muted : theme.bright)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(theme.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Click to name this window")
            }
        }
    }

    // MARK: - Helpers

    private func formatModelName(_ model: String) -> String {
        if model.contains("opus") { return "Opus" }
        if model.contains("sonnet") { return "Sonnet" }
        if model.contains("haiku") { return "Haiku" }
        return model.components(separatedBy: "-").last ?? model
    }

    private func contextColor(for percentage: Double) -> Color {
        if percentage < 0.5 { return theme.sky }
        if percentage < 0.75 { return theme.sand }
        return theme.rose
    }

    private func formatCost(_ cost: Double) -> String {
        if cost < 0.01 { return "$0.00" }
        return String(format: "$%.2f", cost)
    }
}
