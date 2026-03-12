import SwiftUI

/// Dashboard right sidebar — 3 stacked panels: Files, Tools, Context
/// Per UX_DESIGN.md: Shows files touched, live tool activity, and context token usage
struct DashboardPanel: View {
    @EnvironmentObject private var process: ClaudeProcess
    @EnvironmentObject private var theme: ThemeEngine
    @EnvironmentObject private var contextManager: ContextStateManager
    @EnvironmentObject private var sessionManager: SessionManager

    @State private var collapsedSections: Set<String> = []
    @State private var fileDiffStats: [String: String] = [:] // path → "+N -N"
    @State private var diffStatsLoaded = false

    /// Callback to scroll to a pinned message
    var onScrollToMessage: ((String) -> Void)?

    /// Callback to open session diff review
    var onShowSessionDiff: (() -> Void)?

    /// Toolkit panel callbacks
    var onOpenGemini: (() -> Void)?
    var onOpenDevTools: (() -> Void)?
    var onOpenMCPCatalog: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // PINNED section (only if there are pinned messages)
            let pinned = process.messages.filter { $0.isPinned }
            if !pinned.isEmpty {
                dashboardSection("PINNED", icon: "pin.fill", isCollapsed: collapsedSections.contains("pinned")) {
                    collapsedSections.formSymmetricDifference(["pinned"])
                } content: {
                    pinnedPanel(pinned)
                }

                Divider().opacity(0.2)
            }

            // FILES section
            dashboardSection("FILES", icon: "doc.text.fill", isCollapsed: collapsedSections.contains("files")) {
                collapsedSections.formSymmetricDifference(["files"])
            } content: {
                filesPanel
            }

            Divider().opacity(0.2)

            // TOOLS section
            dashboardSection("TOOLS", icon: "wrench.and.screwdriver.fill", isCollapsed: collapsedSections.contains("tools")) {
                collapsedSections.formSymmetricDifference(["tools"])
            } content: {
                toolsPanel
            }

            Divider().opacity(0.2)

            // COST section
            dashboardSection("COST", icon: "dollarsign.circle.fill", isCollapsed: collapsedSections.contains("cost")) {
                collapsedSections.formSymmetricDifference(["cost"])
            } content: {
                costPanel
            }

            Divider().opacity(0.2)

            // OPTIMIZATIONS section
            dashboardSection("OPTIMIZATIONS", icon: "bolt.fill", isCollapsed: collapsedSections.contains("optimizations")) {
                collapsedSections.formSymmetricDifference(["optimizations"])
            } content: {
                optimizationsPanel
            }

            Divider().opacity(0.2)

            // TOOLKIT section
            dashboardSection("TOOLKIT", icon: "puzzlepiece.extension.fill", isCollapsed: collapsedSections.contains("toolkit")) {
                collapsedSections.formSymmetricDifference(["toolkit"])
            } content: {
                toolkitPanel
            }

            Divider().opacity(0.2)

            // CONTEXT section
            dashboardSection("CONTEXT", icon: "diamond.fill", isCollapsed: collapsedSections.contains("context")) {
                collapsedSections.formSymmetricDifference(["context"])
            } content: {
                contextPanel
            }

            Spacer(minLength: 0)
        }
        .background(theme.surface.opacity(0.5))
    }

    // MARK: - Section Container

    private func dashboardSection<Content: View>(
        _ title: String,
        icon: String,
        isCollapsed: Bool,
        toggle: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            Button(action: toggle) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 9))
                        .foregroundColor(theme.muted)
                    Text(title)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(theme.secondary)
                    Spacer()
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 8))
                        .foregroundColor(theme.muted)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                content()
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
            }
        }
    }

    // MARK: - PINNED Panel

    private func pinnedPanel(_ pinned: [ConversationMessage]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(pinned) { message in
                Button {
                    onScrollToMessage?(message.id)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8))
                            .foregroundColor(theme.sand)
                            .frame(width: 12)

                        Text(message.copyText().prefix(60).description)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(theme.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - COST Panel

    private var costPanel: some View {
        let sessionCost = process.totalCostUSD
        let todayCost = sessionManager.costToday
        let weekCost = sessionManager.costThisWeek

        return VStack(alignment: .leading, spacing: 6) {
            costRow("Session", cost: sessionCost)
            costRow("Today", cost: todayCost)
            costRow("This Week", cost: weekCost)

            // Budget progress bar (if set)
            if process.maxBudgetUSD > 0 {
                let pct = min(sessionCost / process.maxBudgetUSD, 1.0)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(theme.elevated)
                            .frame(height: 4)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(costColor(for: sessionCost))
                            .frame(width: geo.size.width * pct, height: 4)
                    }
                }
                .frame(height: 4)

                Text(String(format: "Budget: $%.2f / $%.2f", sessionCost, process.maxBudgetUSD))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(theme.muted)
            }

            // Model rates
            Text("Opus: $15/$75 · Sonnet: $3/$15 per MTok")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(theme.muted.opacity(0.6))
        }
    }

    private func costRow(_ label: String, cost: Double) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(theme.muted)
                .frame(width: 65, alignment: .leading)
            Text(String(format: "$%.2f", cost))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(costColor(for: cost))
        }
    }

    private func costColor(for cost: Double) -> Color {
        if cost < 1.0 { return theme.muted }
        if cost < 5.0 { return theme.amber }
        return theme.rose
    }

    // MARK: - FILES Panel

    private var filesPanel: some View {
        let files = extractFilesFromMessages()

        return Group {
            if files.isEmpty {
                Text("No files touched yet")
                    .font(Typography.caption)
                    .foregroundColor(theme.muted)
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    // Review All Changes button
                    if files.contains(where: { $0.action == .modified || $0.action == .created }) {
                        Button {
                            onShowSessionDiff?()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.text.magnifyingglass")
                                    .font(.system(size: 9))
                                Text("Review All Changes")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                            }
                            .foregroundColor(theme.sky)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(theme.sky.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 2)
                    }

                    ForEach(Array(files.enumerated()), id: \.offset) { _, file in
                        HStack(spacing: 6) {
                            Text(file.icon)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(file.iconColor(theme))
                                .frame(width: 12)

                            Text(file.shortPath)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(theme.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Spacer()

                            if let stats = file.diffStats ?? fileDiffStats[file.path] {
                                Text(stats)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(theme.sage)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onShowSessionDiff?()
                        }
                    }
                }
                .onAppear {
                    loadDiffStats(for: files)
                }
                .onChange(of: files.count) { _, _ in
                    loadDiffStats(for: files)
                }
            }
        }
    }

    /// Load git diff stats for modified/created files
    private func loadDiffStats(for files: [FileEntry]) {
        guard let dir = process.workingDirectory else { return }
        let modifiedFiles = files.filter { $0.action == .modified || $0.action == .created }
        guard !modifiedFiles.isEmpty else { return }

        Task {
            for file in modifiedFiles {
                if fileDiffStats[file.path] == nil {
                    if let stats = await GitDiffService.shared.diffStat(for: file.path, in: dir) {
                        fileDiffStats[file.path] = stats
                    }
                }
            }
        }
    }

    // MARK: - TOOLS Panel

    private var toolsPanel: some View {
        let tools = extractRecentTools()

        return Group {
            if tools.isEmpty {
                Text("No tool activity yet")
                    .font(Typography.caption)
                    .foregroundColor(theme.muted)
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(tools.suffix(8).enumerated()), id: \.offset) { _, tool in
                        HStack(spacing: 6) {
                            Text(tool.statusIcon)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(tool.statusColor(theme))
                                .frame(width: 12)

                            Text(tool.toolName)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(theme.primary)

                            Text(tool.summary)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(theme.muted)
                                .lineLimit(1)
                                .truncationMode(.tail)

                            Spacer()

                            if let duration = tool.duration {
                                Text(String(format: "%.1fs", duration))
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(theme.muted)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - OPTIMIZATIONS Panel

    private var optimizationsPanel: some View {
        let enabled = process.optimizationsEnabled

        return VStack(alignment: .leading, spacing: 6) {
            optimizationRow("MCP Tool Search", detail: "~80% fewer tokens", active: enabled)
            optimizationRow("Working Dir Lock", detail: "No cd drift", active: enabled)
            optimizationRow("Auto-Compact \(process.autoCompactThreshold)%", detail: "Tunable threshold", active: enabled)

            // Compaction threshold slider
            if enabled {
                HStack(spacing: 6) {
                    Text("Compact")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(theme.muted)
                    Slider(
                        value: Binding(
                            get: { Double(process.autoCompactThreshold) },
                            set: { process.autoCompactThreshold = Int($0) }
                        ),
                        in: 60...95,
                        step: 5
                    )
                    .controlSize(.mini)
                    Text("\(process.autoCompactThreshold)%")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(theme.secondary)
                        .frame(width: 28, alignment: .trailing)
                }
            }

            // Toggle button
            Button {
                process.optimizationsEnabled.toggle()
            } label: {
                Text(enabled ? "Disable All" : "Enable All")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(enabled ? theme.muted : theme.sky)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(enabled ? theme.elevated : theme.sky.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
        }
    }

    private func optimizationRow(_ name: String, detail: String, active: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(active ? theme.sage : theme.muted.opacity(0.3))
                .frame(width: 6, height: 6)

            Text(name)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(active ? theme.primary : theme.muted)

            Spacer()

            Text(detail)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(theme.muted)
        }
    }

    // MARK: - TOOLKIT Panel

    private var toolkitPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            toolkitButton(
                icon: "sparkles",
                label: "Ask Gemini",
                detail: "Long context · second opinion",
                shortcut: "⌘⇧G",
                color: theme.lavender,
                runningIndicator: GeminiProcess.shared.isRunning,
                action: onOpenGemini
            )
            toolkitButton(
                icon: "hammer.fill",
                label: "Dev Tools",
                detail: "Lint · review · dead code · deploy",
                shortcut: "⌘⇧L",
                color: theme.sand,
                runningIndicator: DevToolService.shared.isRunning,
                action: onOpenDevTools
            )
            toolkitButton(
                icon: "puzzlepiece.extension.fill",
                label: "MCP Catalog",
                detail: "Install integrations one-click",
                shortcut: "⌘⇧I",
                color: theme.sky,
                runningIndicator: false,
                action: onOpenMCPCatalog
            )
        }
    }

    private func toolkitButton(
        icon: String,
        label: String,
        detail: String,
        shortcut: String,
        color: Color,
        runningIndicator: Bool,
        action: (() -> Void)?
    ) -> some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(color)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(theme.primary)
                    Text(detail)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(theme.muted)
                }

                Spacer()

                if runningIndicator {
                    ProgressView().controlSize(.mini).padding(.trailing, 2)
                } else {
                    Text(shortcut)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(theme.muted.opacity(0.6))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(theme.elevated.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(color.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - CONTEXT Panel

    private var contextPanel: some View {
        let pct = contextManager.contextPercentage
        let systemEstimate = Int(Double(contextManager.inputTokens) * 0.3)
        let conversationEstimate = contextManager.inputTokens - systemEstimate
        let free = contextManager.maxContextTokens - contextManager.inputTokens - contextManager.outputTokens

        return VStack(alignment: .leading, spacing: 6) {
            // Stacked bar visualization
            GeometryReader { geo in
                let total = Double(contextManager.maxContextTokens)
                let systemW = geo.size.width * Double(systemEstimate) / total
                let convW = geo.size.width * Double(conversationEstimate) / total
                let outputW = geo.size.width * Double(contextManager.outputTokens) / total
                let cacheW = geo.size.width * Double(contextManager.cacheReadTokens) / total

                HStack(spacing: 0) {
                    Rectangle().fill(theme.lavender.opacity(0.6)).frame(width: max(systemW, 0))
                    Rectangle().fill(theme.sky.opacity(0.6)).frame(width: max(convW, 0))
                    Rectangle().fill(theme.sage.opacity(0.6)).frame(width: max(outputW, 0))
                    if cacheW > 0 {
                        Rectangle().fill(theme.sand.opacity(0.4)).frame(width: max(cacheW, 0))
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: 6)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .background(
                    RoundedRectangle(cornerRadius: 2).fill(theme.elevated)
                )
            }
            .frame(height: 6)

            // Percentage
            Text("\(Int(pct * 100))% used")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(contextColor(for: pct))

            // Categorized breakdown
            VStack(alignment: .leading, spacing: 2) {
                contextRow("System", count: systemEstimate, color: theme.lavender, note: "est.")
                contextRow("Conversation", count: conversationEstimate, color: theme.sky, note: nil)
                contextRow("Output", count: contextManager.outputTokens, color: theme.sage, note: nil)
                contextRow("Cache Hits", count: contextManager.cacheReadTokens, color: theme.sand, note: nil)
                contextRow("Available", count: free, color: theme.muted, note: nil)
            }

            // Pin context button
            Button {
                contextManager.isContextPinned.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: contextManager.isContextPinned ? "pin.fill" : "pin")
                        .font(.system(size: 9))
                    Text(contextManager.isContextPinned ? "Unpin Context" : "Pin Context")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                }
                .foregroundColor(contextManager.isContextPinned ? theme.sand : theme.muted)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(contextManager.isContextPinned ? theme.sand.opacity(0.15) : theme.elevated)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)

            // Compaction threshold
            if pct > 0.7 {
                HStack(spacing: 4) {
                    Image(systemName: contextManager.isContextPinned ? "pin.fill" : "exclamationmark.triangle")
                        .font(.system(size: 8))
                    Text(contextManager.isContextPinned ? "Pinned — compaction disabled" : "Compaction at 85%")
                        .font(.system(size: 9, design: .monospaced))
                }
                .foregroundColor(theme.sand)
            }
        }
    }

    private func contextRow(_ label: String, count: Int, color: Color, note: String?) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(theme.muted)
            Spacer()
            if let note {
                Text(note)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(theme.muted.opacity(0.6))
            }
            Text(formatTokenCount(count))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(theme.secondary)
        }
    }

    private func tokenRow(_ label: String, count: Int) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(theme.muted)
                .frame(width: 45, alignment: .leading)
            Text(formatTokenCount(count))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(theme.secondary)
        }
    }

    // MARK: - Data Extraction

    /// Extract files from tool use blocks in conversation
    private func extractFilesFromMessages() -> [FileEntry] {
        var seen: [String: FileEntry] = [:]

        for message in process.messages {
            for block in message.blocks {
                guard let tool = block as? ToolUseBlock else { continue }

                let filePath = extractFilePath(from: tool.input, toolName: tool.toolName)
                guard let filePath, !filePath.isEmpty else { continue }

                let action: FileAction
                switch tool.toolName {
                case "Read": action = .read
                case "Edit": action = .modified
                case "Write": action = .created
                default: continue
                }

                // Update or create entry — later actions win
                if var existing = seen[filePath] {
                    if action == .modified || action == .created {
                        existing.action = action
                    }
                    existing.touchCount += 1
                    seen[filePath] = existing
                } else {
                    seen[filePath] = FileEntry(path: filePath, action: action, touchCount: 1)
                }
            }
        }

        return Array(seen.values).sorted { $0.path < $1.path }
    }

    /// Extract recent tool use blocks for the tools panel
    private func extractRecentTools() -> [ToolEntry] {
        var tools: [ToolEntry] = []

        for message in process.messages {
            for block in message.blocks {
                guard let tool = block as? ToolUseBlock else { continue }
                let summary = extractToolSummary(tool)
                tools.append(ToolEntry(
                    toolName: tool.toolName,
                    summary: summary,
                    status: tool.status,
                    duration: tool.duration
                ))
            }
        }

        return tools
    }

    /// Parse file path from tool input JSON
    private func extractFilePath(from input: String, toolName: String) -> String? {
        // Tool inputs are pretty-printed JSON — extract file_path or path
        if let range = input.range(of: "file_path\"\\s*:\\s*\"([^\"]+)\"", options: .regularExpression) {
            let match = String(input[range])
            if let pathStart = match.range(of: "\"", range: match.index(match.startIndex, offsetBy: 10)..<match.endIndex),
               let pathEnd = match.range(of: "\"", options: .backwards) {
                let start = match.index(after: pathStart.lowerBound)
                let end = pathEnd.lowerBound
                if start < end {
                    return String(match[start..<end])
                }
            }
        }

        // Fallback: look for path in input
        if let range = input.range(of: "\"path\"\\s*:\\s*\"([^\"]+)\"", options: .regularExpression) {
            let match = String(input[range])
            if let pathStart = match.range(of: "\"", range: match.index(match.startIndex, offsetBy: 6)..<match.endIndex),
               let pathEnd = match.range(of: "\"", options: .backwards) {
                let start = match.index(after: pathStart.lowerBound)
                let end = pathEnd.lowerBound
                if start < end {
                    return String(match[start..<end])
                }
            }
        }

        return nil
    }

    /// Extract a short summary from tool input
    private func extractToolSummary(_ tool: ToolUseBlock) -> String {
        let input = tool.input
        switch tool.toolName {
        case "Read", "Edit", "Write":
            if let path = extractFilePath(from: input, toolName: tool.toolName) {
                return shortenPath(path)
            }
        case "Bash":
            // Extract command
            if let range = input.range(of: "\"command\"\\s*:\\s*\"([^\"]+)\"", options: .regularExpression) {
                let match = String(input[range])
                let parts = match.components(separatedBy: "\"")
                if parts.count >= 4 {
                    let cmd = parts[3]
                    return String(cmd.prefix(40))
                }
            }
        case "Grep":
            if let range = input.range(of: "\"pattern\"\\s*:\\s*\"([^\"]+)\"", options: .regularExpression) {
                let match = String(input[range])
                let parts = match.components(separatedBy: "\"")
                if parts.count >= 4 {
                    return parts[3]
                }
            }
        case "Glob":
            if let range = input.range(of: "\"pattern\"\\s*:\\s*\"([^\"]+)\"", options: .regularExpression) {
                let match = String(input[range])
                let parts = match.components(separatedBy: "\"")
                if parts.count >= 4 {
                    return parts[3]
                }
            }
        default:
            break
        }
        return String(input.prefix(30))
    }

    private func shortenPath(_ path: String) -> String {
        let components = path.components(separatedBy: "/").filter { !$0.isEmpty }
        if components.count <= 3 { return path }
        return components.suffix(3).joined(separator: "/")
    }

    private func contextColor(for percentage: Double) -> Color {
        if percentage < 0.5 { return theme.sky }
        if percentage < 0.75 { return theme.sand }
        return theme.rose
    }

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1000 {
            return "\(count / 1000)K"
        }
        return "\(count)"
    }
}

// MARK: - Data Models

struct FileEntry {
    let path: String
    var action: FileAction
    var touchCount: Int
    var diffStats: String? = nil

    var icon: String {
        switch action {
        case .read: return "●"
        case .modified: return "✎"
        case .created: return "+"
        }
    }

    @MainActor func iconColor(_ theme: ThemeEngine) -> Color {
        switch action {
        case .read: return theme.muted
        case .modified: return theme.sky
        case .created: return theme.sage
        }
    }

    var shortPath: String {
        let components = path.components(separatedBy: "/").filter { !$0.isEmpty }
        if components.count <= 2 { return path }
        return components.suffix(2).joined(separator: "/")
    }
}

enum FileAction {
    case read
    case modified
    case created
}

struct ToolEntry {
    let toolName: String
    let summary: String
    let status: ToolStatus
    let duration: TimeInterval?

    var statusIcon: String {
        switch status {
        case .completed: return "✓"
        case .running: return "⟳"
        case .failed: return "✗"
        case .pending: return "⏸"
        }
    }

    @MainActor func statusColor(_ theme: ThemeEngine) -> Color {
        switch status {
        case .completed: return theme.sage
        case .running: return theme.sky
        case .failed: return theme.rose
        case .pending: return theme.muted
        }
    }
}
