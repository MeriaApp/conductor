import SwiftUI

/// Main conversation display — scrollable list of messages with typed content blocks
struct ConversationView: View {
    @EnvironmentObject private var process: ClaudeProcess
    @EnvironmentObject private var theme: ThemeEngine
    @State private var scrollProxy: ScrollViewProxy?
    @State private var isUserAtBottom: Bool = true

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
                .textSelection(.enabled)
                .background(
                    ScrollPositionMonitor(isAtBottom: $isUserAtBottom)
                )
            }
            .onAppear { scrollProxy = proxy }
            .onChange(of: process.messages.count) { _, _ in
                // User sent a message → always snap to bottom
                // Claude responded → only scroll if user was already at bottom
                if process.messages.last?.role == .user {
                    isUserAtBottom = true
                    scrollToBottom(proxy: proxy)
                } else if isUserAtBottom {
                    scrollToBottom(proxy: proxy)
                }
            }
            .onChange(of: process.isStreaming) { _, streaming in
                if streaming && isUserAtBottom {
                    scrollToBottom(proxy: proxy)
                }
            }
            // During streaming, periodically scroll to follow new content
            .task(id: process.isStreaming) {
                guard process.isStreaming else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(250))
                    if isUserAtBottom {
                        scrollToBottom(proxy: proxy, animated: false)
                    }
                }
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
            // Jump-to-bottom button when user has scrolled up
            .overlay(alignment: .bottom) {
                if !isUserAtBottom && !process.messages.isEmpty {
                    Button {
                        isUserAtBottom = true
                        scrollToBottom(proxy: proxy)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 10, weight: .medium))
                            Text("Jump to bottom")
                                .font(Typography.caption)
                        }
                        .foregroundColor(theme.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(theme.elevated)
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isUserAtBottom)
        }
        } // else
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        if animated {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        } else {
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

// MARK: - Scroll Position Monitor

/// Hooks into the parent NSScrollView to detect user scroll position.
/// Only responds to user-initiated scrolling (didLiveScroll), so content
/// growth during streaming doesn't falsely flip the flag.
struct ScrollPositionMonitor: NSViewRepresentable {
    @Binding var isAtBottom: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.frame = .zero
        DispatchQueue.main.async {
            context.coordinator.findScrollView(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(isAtBottom: $isAtBottom)
    }

    class Coordinator: NSObject {
        @Binding var isAtBottom: Bool
        private weak var scrollView: NSScrollView?

        init(isAtBottom: Binding<Bool>) {
            _isAtBottom = isAtBottom
        }

        func findScrollView(from view: NSView) {
            var current: NSView? = view
            while let v = current {
                if let sv = v as? NSScrollView {
                    self.scrollView = sv
                    NotificationCenter.default.addObserver(
                        self,
                        selector: #selector(userDidScroll),
                        name: NSScrollView.didLiveScrollNotification,
                        object: sv
                    )
                    NotificationCenter.default.addObserver(
                        self,
                        selector: #selector(userDidScroll),
                        name: NSScrollView.didEndLiveScrollNotification,
                        object: sv
                    )
                    return
                }
                current = v.superview
            }
        }

        @objc private func userDidScroll(_ notification: Notification) {
            guard let scrollView = scrollView else { return }
            let contentView = scrollView.contentView
            let documentHeight = scrollView.documentView?.frame.height ?? 0
            let visibleHeight = contentView.bounds.height
            let scrollOffset = contentView.bounds.origin.y
            let distanceFromBottom = documentHeight - (scrollOffset + visibleHeight)
            let atBottom = distanceFromBottom < 50

            if atBottom != isAtBottom {
                DispatchQueue.main.async {
                    self.isAtBottom = atBottom
                }
            }
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}
