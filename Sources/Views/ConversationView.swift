import SwiftUI

/// Main conversation display — scrollable list of messages with typed content blocks
struct ConversationView: View {
    @EnvironmentObject private var process: ClaudeProcess
    @EnvironmentObject private var theme: ThemeEngine
    @State private var scrollProxy: ScrollViewProxy?

    /// Search text passed from AppShell (Cmd+F)
    var searchText: String = ""
    /// Index of current search match to scroll to
    var currentMatchIndex: Int = 0
    /// Callback when a file path is tapped in tool use blocks
    var onFilePathTap: ((String) -> Void)?
    /// Callback to toggle pin on a message
    var onTogglePin: ((String) -> Void)?
    /// Callback to undo last assistant message (vibe mode action button)
    var onUndo: (() -> Void)?
    /// Callback to show changes dashboard (vibe mode action button)
    var onSeeChanges: (() -> Void)?
    /// Callback to deploy project (vibe mode action button)
    var onDeploy: (() -> Void)?
    /// Callback to suggest next steps (vibe mode action button)
    var onSuggestNext: (() -> Void)?
    /// Callback to expand a diff block to fullscreen
    var onDiffExpand: ((DiffBlock) -> Void)?
    /// Welcome screen callbacks
    var onCommandPalette: (() -> Void)?
    var onToggleVibe: (() -> Void)?
    var onSessionBrowser: (() -> Void)?
    var onShowHelp: (() -> Void)?

    /// Message IDs that contain the search text
    private var matchingMessageIds: [String] {
        guard !searchText.isEmpty else { return [] }
        let query = searchText.lowercased()
        return process.messages.compactMap { message in
            message.copyText().lowercased().contains(query) ? message.id : nil
        }
    }

    var body: some View {
        if process.messages.isEmpty && !process.isStreaming {
            WelcomeView(
                onCommandPalette: onCommandPalette,
                onToggleVibe: onToggleVibe,
                onSessionBrowser: onSessionBrowser,
                onShowHelp: onShowHelp
            )
        } else {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(process.messages) { message in
                        let isMatch = matchingMessageIds.contains(message.id)
                        MessageView(
                            message: message,
                            onFilePathTap: onFilePathTap,
                            onUndo: message.id == process.messages.last?.id ? onUndo : nil,
                            onSeeChanges: message.id == process.messages.last?.id ? onSeeChanges : nil,
                            onDeploy: message.id == process.messages.last?.id ? onDeploy : nil,
                            onSuggestNext: message.id == process.messages.last?.id ? onSuggestNext : nil,
                            onDiffExpand: onDiffExpand
                        )
                            .id(message.id)
                            .background(
                                isMatch
                                    ? RoundedRectangle(cornerRadius: 4)
                                        .fill(theme.sky.opacity(0.08))
                                    : nil
                            )
                            .contextMenu {
                                Button(message.isPinned ? "Unpin Message" : "Pin Message") {
                                    onTogglePin?(message.id)
                                }
                                Button("Copy Message") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(message.copyText(), forType: .string)
                                }
                            }

                        // Separator between messages
                        if message.id != process.messages.last?.id {
                            MessageSeparator()
                        }
                    }

                    // Streaming indicator
                    if process.isStreaming && process.messages.last?.isStreaming != true {
                        StreamingIndicator()
                            .id("streaming-indicator")
                    }

                    // Bottom anchor for auto-scroll
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.vertical, 16)
            }
            .onAppear { scrollProxy = proxy }
            .onChange(of: process.messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: process.isStreaming) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: currentMatchIndex) { _, newIndex in
                scrollToMatch(proxy: proxy, index: newIndex)
            }
            .onChange(of: searchText) { _, _ in
                // Scroll to first match when search text changes
                if !matchingMessageIds.isEmpty {
                    scrollToMatch(proxy: proxy, index: 0)
                }
            }
        }
        } // else
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    private func scrollToMatch(proxy: ScrollViewProxy, index: Int) {
        guard index >= 0, index < matchingMessageIds.count else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(matchingMessageIds[index], anchor: .center)
        }
    }
}

// MARK: - Message View

struct MessageView: View {
    let message: ConversationMessage
    var onFilePathTap: ((String) -> Void)?
    var onUndo: (() -> Void)?
    var onSeeChanges: (() -> Void)?
    var onDeploy: (() -> Void)?
    var onSuggestNext: (() -> Void)?
    var onDiffExpand: ((DiffBlock) -> Void)?
    @EnvironmentObject private var process: ClaudeProcess
    @EnvironmentObject private var theme: ThemeEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Role header
            HStack {
                if message.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundColor(theme.sand)
                }

                Text(message.role == .user ? "You" : "Claude")
                    .font(Typography.bodyBold)
                    .foregroundColor(message.role == .user ? theme.bright : theme.sky)

                Spacer()

                // Hide duration in vibe mode
                if !process.isVibeCoder, let duration = message.duration {
                    Text(String(format: "%.1fs", duration))
                        .font(Typography.caption)
                        .foregroundColor(theme.muted)
                }

                if message.isStreaming {
                    if process.isVibeCoder {
                        Text("Working...")
                            .font(Typography.caption)
                            .foregroundColor(theme.lavender)
                    } else {
                        StreamingDots()
                    }
                }
            }

            // Content blocks
            ForEach(Array(message.blocks.enumerated()), id: \.offset) { _, block in
                // In vibe mode, hide tool use and thinking blocks
                if process.isVibeCoder && (block is ToolUseBlock || block is ThinkingBlock) {
                    EmptyView()
                } else {
                    ContentBlockRenderer(block: block, onFilePathTap: onFilePathTap, onDiffExpand: onDiffExpand)
                }
            }

            // Vibe mode: friendly error translation
            if process.isVibeCoder && message.role == .assistant {
                let hasError = message.blocks.contains { ($0 as? ToolUseBlock)?.isError == true }
                if hasError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundColor(theme.sand)
                        Text("Something went wrong. Claude is looking into it.")
                            .font(Typography.body)
                            .foregroundColor(theme.sand)
                    }
                    .padding(.top, 4)
                }
            }

            // Vibe mode action buttons (on last assistant message only, when not streaming)
            if process.isVibeCoder && message.role == .assistant && !message.isStreaming {
                vibeActionButtons
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Vibe Action Buttons

    private var vibeActionButtons: some View {
        HStack(spacing: 10) {
            vibeButton("arrow.uturn.backward", "Undo") { onUndo?() }
            vibeButton("doc.text.magnifyingglass", "See Changes") { onSeeChanges?() }
            vibeButton("arrow.up.circle", "Deploy") { onDeploy?() }
            vibeButton("sparkle.magnifyingglass", "What's next?") { onSuggestNext?() }
        }
        .padding(.top, 4)
    }

    private func vibeButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(Typography.caption)
            }
            .foregroundColor(theme.muted)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(theme.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Content Block Router

struct ContentBlockRenderer: View {
    let block: any ContentBlockProtocol
    var onFilePathTap: ((String) -> Void)?
    var onDiffExpand: ((DiffBlock) -> Void)?
    @EnvironmentObject private var process: ClaudeProcess
    @EnvironmentObject private var theme: ThemeEngine

    var body: some View {
        Group {
            if let textBlock = block as? TextBlock {
                MarkdownTextView(text: textBlock.text)
            } else if let codeBlock = block as? CodeBlock {
                CodeBlockView(block: codeBlock)
            } else if let diffBlock = block as? DiffBlock {
                DiffView(block: diffBlock, onExpand: onDiffExpand)
            } else if let toolBlock = block as? ToolUseBlock {
                ToolUseView(block: toolBlock, onFilePathTap: onFilePathTap)
            } else if let thinkingBlock = block as? ThinkingBlock {
                if process.showThinking {
                    ThinkingView(block: thinkingBlock)
                }
            } else if let listBlock = block as? ListBlock {
                ListBlockView(block: listBlock)
            }
        }
    }
}

// MARK: - Markdown Text Rendering

struct MarkdownTextView: View {
    let text: String
    @EnvironmentObject private var theme: ThemeEngine

    var body: some View {
        Text(parseInlineMarkdown(text))
            .font(Typography.body)
            .foregroundColor(theme.primary)
            .textSelection(.enabled)
            .lineSpacing(4)
    }

    /// Parse inline markdown (bold, italic, code, links) into AttributedString
    private func parseInlineMarkdown(_ text: String) -> AttributedString {
        // Try AttributedString's built-in markdown parsing
        if let attributed = try? AttributedString(markdown: text, options: .init(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )) {
            return attributed
        }
        return AttributedString(text)
    }
}

// MARK: - List Block

struct ListBlockView: View {
    let block: ListBlock
    @EnvironmentObject private var theme: ThemeEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(block.items.enumerated()), id: \.offset) { idx, item in
                HStack(alignment: .top, spacing: 8) {
                    Text(bullet(for: idx))
                        .font(Typography.body)
                        .foregroundColor(theme.sky)
                        .frame(width: 20, alignment: .leading)

                    Text(item)
                        .font(Typography.body)
                        .foregroundColor(theme.primary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func bullet(for index: Int) -> String {
        switch block.style {
        case .bullet: return "\u{25B8}" // Small right triangle
        case .numbered: return "\(index + 1)."
        case .checkbox: return "[ ]"
        }
    }
}

// MARK: - Separators & Indicators

struct MessageSeparator: View {
    @EnvironmentObject private var theme: ThemeEngine

    var body: some View {
        // Dashed separator between messages (per UX_DESIGN.md)
        Rectangle()
            .fill(theme.separator.opacity(0.3))
            .frame(height: 1)
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
    }
}

struct StreamingIndicator: View {
    @EnvironmentObject private var theme: ThemeEngine

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.mini)
                .scaleEffect(0.8)
            Text("Claude is thinking...")
                .font(Typography.caption)
                .foregroundColor(theme.lavender)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
}

struct StreamingDots: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.4)) { timeline in
            let dotCount = Int(timeline.date.timeIntervalSinceReferenceDate / 0.4) % 3
            Text(String(repeating: ".", count: dotCount + 1))
                .font(Typography.caption)
                .foregroundColor(.secondary)
        }
    }
}
