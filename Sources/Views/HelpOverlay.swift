import SwiftUI

/// Help overlay (?) — quick reference for all keyboard shortcuts and features
struct HelpOverlay: View {
    @EnvironmentObject private var theme: ThemeEngine
    @EnvironmentObject private var process: ClaudeProcess
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "keyboard")
                    .font(.system(size: 14))
                    .foregroundColor(theme.sky)
                Text("Keyboard Shortcuts")
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
                    if process.isVibeCoder {
                        // Simplified help for vibe mode
                        shortcutSection("Essentials", shortcuts: [
                            ("Enter", "Send message"),
                            ("Shift+Enter", "New line"),
                            ("Ctrl+V", "Exit Vibe Mode"),
                            ("Cmd+S", "Browse sessions"),
                            ("Cmd+F", "Search conversation"),
                            ("Cmd+L", "Clear conversation"),
                            ("Escape", "Close overlays"),
                        ])
                    } else {
                    shortcutSection("Navigation", shortcuts: [
                        ("Cmd+K", "Command Palette"),
                        ("Cmd+F", "Search conversation"),
                        ("Cmd+S", "Session Browser"),
                        ("Tab", "Cycle: Focus → Dashboard → Agents → Moodboard"),
                        ("Ctrl+V", "Toggle Vibe Coder Mode"),
                        ("Cmd+?", "This help overlay"),
                        ("Escape", "Close overlays / Cancel"),
                    ])

                    shortcutSection("Chat", shortcuts: [
                        ("Enter", "Send message"),
                        ("Shift+Enter", "New line"),
                        ("Cmd+Shift+Z", "Undo last assistant response"),
                        ("Cmd+Shift+T", "Toggle thinking blocks"),
                        ("Cmd+O", "Cycle output mode (Standard/Concise/Detailed/Code)"),
                        ("Cmd+E", "Export conversation as markdown"),
                        ("Ctrl+T", "Terminal passthrough — quick shell command"),
                        ("Cmd+C", "Copy selected text"),
                    ])

                    shortcutSection("View", shortcuts: [
                        ("Cmd++", "Increase font size"),
                        ("Cmd+-", "Decrease font size"),
                        ("Cmd+0", "Reset font size"),
                        ("Cmd+L", "Clear conversation"),
                        ("Cmd+N", "New session"),
                        ("Cmd+]", "Luminance up (brighter)"),
                        ("Cmd+[", "Luminance down (darker)"),
                    ])

                    shortcutSection("Overlays", shortcuts: [
                        ("Cmd+Shift+F", "Feature Map"),
                        ("Cmd+Shift+X", "Context Manager"),
                        ("Cmd+Shift+P", "Performance Dashboard"),
                        ("Cmd+Shift+M", "Multi-Agent Split View"),
                        ("Cmd+Shift+H", "Manage CLI hooks"),
                        ("Cmd+Shift+K", "Browse & create skills"),
                        ("Shift+Tab", "Toggle Plan Mode"),
                    ])

                    shortcutSection("Agents", shortcuts: [
                        ("Cmd+K → Spawn...", "Create agent (or use presets)"),
                        ("Cmd+K → Build & Verify", "Run build pipeline"),
                        ("Cmd+K → Stop All", "Stop all agents"),
                    ])

                    shortcutSection("Session", shortcuts: [
                        ("Cmd+K → Effort", "Set effort level (Low/Medium/High)"),
                        ("Cmd+K → Mode", "Set permission mode"),
                        ("Cmd+K → Output", "Set output mode"),
                        ("Cmd+K → Budget", "Set cost cap ($1/$5/$10/$25)"),
                    ])

                    // Feature summary
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Features")
                            .font(Typography.bodyBold)
                            .foregroundColor(theme.bright)

                        featureRow("gauge.with.dots.needle.67percent", "Dashboard", "Files touched, live tool activity, context usage. Tab to toggle.")
                        featureRow("person.3.fill", "Multi-Agent", "Spawn agents with roles. Presets for common workflows. Supervisor/Pipeline/Consensus/Swarm.")
                        featureRow("hammer.fill", "Build & Verify", "Autonomous pipeline: Build → Test → Audit → Report. No human needed.")
                        featureRow("chart.bar.fill", "Performance", "Token usage, cost, timing, agent stats, session history.")
                        featureRow("gauge.with.dots.needle.67percent", "Context Manager", "Track token usage, selective compaction, zero-loss context.")
                        featureRow("arrow.triangle.2.circlepath", "Context Preservation", "Auto-extracts decisions, files, tasks. Detects compaction, reinjects context. Zero information loss.")
                        featureRow("map.fill", "Feature Map", "Discover CLI features, MCP servers, hooks. Auto-suggest improvements.")
                        featureRow("brain", "Shared Intelligence", "Cross-project knowledge registry. APIs, tools, patterns shared across all projects.")
                        featureRow("terminal", "Terminal", "Ctrl+T for quick shell commands without leaving the conversation.")
                        featureRow("bolt.fill", "Auto-Optimizations", "MCP search, dir lock, smart compaction — enabled by default. Toggle via Dashboard or Cmd+K.")
                        featureRow("sparkles", "Vibe Coder", "Simplified mode — hides tools, thinking, metadata. Just describe what you want.")
                        featureRow("sun.min", "Luminance", "Continuous theme from midnight to paper. All colors adjust proportionally.")
                    }
                    .padding(.top, 4)

                    } // end else (non-vibe mode)
                }
                .padding(16)
            }
            .frame(maxHeight: 450)
        }
        .background(theme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.sky.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 30, y: 10)
        .frame(width: 480)
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
    }

    private func shortcutSection(_ title: String, shortcuts: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Typography.bodyBold)
                .foregroundColor(theme.bright)

            ForEach(shortcuts, id: \.0) { key, desc in
                HStack {
                    Text(key)
                        .font(Typography.codeBlock)
                        .foregroundColor(theme.sky)
                        .frame(width: 140, alignment: .leading)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 3))

                    Text(desc)
                        .font(Typography.body)
                        .foregroundColor(theme.primary)
                }
            }
        }
    }

    private func featureRow(_ icon: String, _ name: String, _ desc: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(theme.sky)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(Typography.bodyBold)
                    .foregroundColor(theme.primary)
                Text(desc)
                    .font(Typography.caption)
                    .foregroundColor(theme.muted)
            }
        }
    }
}
