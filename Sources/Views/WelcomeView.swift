import SwiftUI

/// Empty-state welcome screen shown when conversation has no messages.
/// Surfaces all shortcuts and features so nothing needs to be memorized.
struct WelcomeView: View {
    @EnvironmentObject private var theme: ThemeEngine
    @EnvironmentObject private var process: ClaudeProcess

    var onCommandPalette: (() -> Void)?
    var onToggleVibe: (() -> Void)?
    var onSessionBrowser: (() -> Void)?
    var onShowHelp: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 40)

                // Header
                VStack(spacing: 6) {
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 28))
                        .foregroundColor(theme.sky)

                    Text("Conductor")
                        .font(.system(size: 22, weight: .semibold, design: .default))
                        .foregroundColor(theme.bright)

                    Text(process.isVibeCoder ? "Just describe what you want to build." : "Claude Code, orchestrated.")
                        .font(Typography.body)
                        .foregroundColor(theme.muted)
                }

                if process.isVibeCoder {
                    // Vibe mode: minimal welcome — just essentials
                    HStack(spacing: 10) {
                        quickAction("Exit Vibe", shortcut: "Ctrl+V", icon: "sparkles") {
                            onToggleVibe?()
                        }
                        quickAction("Sessions", shortcut: "Cmd+S", icon: "clock.arrow.circlepath") {
                            onSessionBrowser?()
                        }
                    }

                    Text("Type what you want below — Conductor handles the rest")
                        .font(Typography.caption)
                        .foregroundColor(theme.muted)

                    Spacer(minLength: 20)
                } else {

                // Quick-start action buttons
                HStack(spacing: 10) {
                    quickAction("Command Palette", shortcut: "Cmd+K", icon: "command") {
                        onCommandPalette?()
                    }
                    quickAction("Vibe Mode", shortcut: "Ctrl+V", icon: "sparkles") {
                        onToggleVibe?()
                    }
                    quickAction("Sessions", shortcut: "Cmd+S", icon: "clock.arrow.circlepath") {
                        onSessionBrowser?()
                    }
                    quickAction("All Shortcuts", shortcut: "?", icon: "keyboard") {
                        onShowHelp?()
                    }
                }

                // Shortcut reference cards
                HStack(alignment: .top, spacing: 12) {
                    // Essential shortcuts
                    shortcutCard("Essentials", shortcuts: [
                        ("Cmd+K", "Command Palette"),
                        ("Tab", "Toggle Dashboard"),
                        ("Ctrl+V", "Vibe Coder Mode"),
                        ("Cmd+S", "Browse Sessions"),
                        ("Cmd+N", "New Session"),
                        ("?", "Help & Shortcuts"),
                        ("Esc", "Close Overlays"),
                    ])

                    // Chat shortcuts
                    shortcutCard("Chat", shortcuts: [
                        ("Enter", "Send message"),
                        ("Shift+Enter", "New line"),
                        ("Cmd+F", "Search conversation"),
                        ("Ctrl+T", "Terminal command"),
                        ("Cmd+Shift+Z", "Undo last response"),
                        ("Cmd+Shift+T", "Toggle thinking"),
                        ("Cmd+E", "Export conversation"),
                    ])

                    // View shortcuts
                    shortcutCard("View & Settings", shortcuts: [
                        ("Cmd+L", "Clear conversation"),
                        ("Cmd+O", "Cycle output mode"),
                        ("Cmd+]  Cmd+[", "Adjust luminance"),
                        ("Cmd++  Cmd+-", "Font size"),
                        ("Shift+Tab", "Plan mode"),
                    ])
                }
                .frame(maxWidth: 680)

                // Feature highlights
                featureGrid

                // Footer
                Text("Type a message below to get started")
                    .font(Typography.caption)
                    .foregroundColor(theme.muted)

                Spacer(minLength: 20)

                } // end else (non-vibe mode)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Quick Action Button

    private func quickAction(_ label: String, shortcut: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(theme.sky)
                    .frame(height: 20)

                Text(label)
                    .font(Typography.bodyBold)
                    .foregroundColor(theme.primary)

                Text(shortcut)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(theme.muted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .frame(width: 130, height: 80)
            .background(theme.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(theme.separator.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shortcut Card

    private func shortcutCard(_ title: String, shortcuts: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Typography.bodyBold)
                .foregroundColor(theme.bright)
                .padding(.bottom, 2)

            ForEach(shortcuts, id: \.0) { key, desc in
                HStack(spacing: 8) {
                    Text(key)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(theme.sky)
                        .frame(minWidth: 80, alignment: .leading)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 3))

                    Text(desc)
                        .font(Typography.caption)
                        .foregroundColor(theme.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.separator.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Feature Grid

    private var featureGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Features")
                .font(Typography.bodyBold)
                .foregroundColor(theme.bright)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
            ], spacing: 8) {
                featurePill("gauge.with.dots.needle.67percent", "Dashboard", "Tab")
                featurePill("person.3.fill", "Multi-Agent", "Cmd+K")
                featurePill("diamond.fill", "Context Mgr", "Cmd+Shift+X")
                featurePill("chart.bar.fill", "Performance", "Cmd+Shift+P")
                featurePill("sparkles", "Vibe Coder", "Ctrl+V")
                featurePill("sun.min", "Luminance", "Cmd+] [")
            }
        }
        .frame(maxWidth: 680)
    }

    private func featurePill(_ icon: String, _ name: String, _ shortcut: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(theme.sky)
                .frame(width: 14)

            Text(name)
                .font(Typography.caption)
                .foregroundColor(theme.primary)
                .lineLimit(1)

            Spacer()

            Text(shortcut)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(theme.muted)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(theme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
