# Conductor Audit Plan — Terminal Parity + Polish

*Created: March 8, 2026*

## Execution Order

| # | Item | Files | Status |
|---|------|-------|--------|
| 1 | Complete markdown (blockquotes, inline code, bold/italic, links) | MarkdownParser.swift, ContentBlock.swift, ConversationView.swift | DONE |
| 2 | Line numbers in code blocks | CodeBlockView.swift, Typography.swift | DONE |
| 3 | Luminance-aware code theme | CodeBlockView.swift | DONE |
| 4 | Copy buttons on tool output + thinking | ToolUseView.swift, ThinkingView.swift | DONE |
| 5 | Search highlighting + scroll-to-match | ConversationView.swift | DONE |
| 6 | Streaming block append (not rebuild) | ClaudeProcess.swift | DONE |
| 7 | Centralized Escape key handler | AppShell.swift | DONE |
| 8 | Process timeout watchdog (5min) | ClaudeProcess.swift | DONE |
| 9 | Surface stderr errors to user | ClaudeProcess.swift | DONE |
| 10 | File path autocomplete in input | InputBar.swift | DONE |

## Notes

- Item 1: Added `BlockquoteBlock` type + `BlockquoteView` with sand-colored left bar. Inline markdown (bold, italic, code, links) already handled by SwiftUI's `AttributedString(markdown:)` in `MarkdownTextView`.
- Item 2: Line numbers gutter with separator, only shown for multi-line blocks. Added `Typography.codeLineHeight`.
- Item 3: Switches between `atomOne` (dark) and `xcode` (light) theme at luminance > 0.6.
- Item 4: Copy button on tool output (in expanded view) and thinking blocks (when expanded).
- Item 5: Added sky-blue left-edge bar on matched messages for stronger visual indicator.
- Item 6: Update blocks in-place on existing streaming message instead of creating new message object.
- Item 7: Single `.onKeyPress(.escape)` at top of AppShell handler chain dismisses topmost overlay in priority order.
- Item 8: 5-minute watchdog task, cancelled on normal termination.
- Item 9: `lastStderrMessage` published property surfaces meaningful stderr (filters progress noise).
- Item 10: Type `@/path` to get filesystem autocomplete. Tab to accept, Esc to dismiss. Directories stay open for drill-down.

## Phase 2 — Additional Polish

| # | Item | Files | Status |
|---|------|-------|--------|
| A | Diff auto-fallback (unified below 600px) | DiffView.swift | DONE |
| B | Session preview (2-line summary, "View Only" label) | SessionBrowser.swift | DONE |
| C | Command palette section headers | CommandPalette.swift | DONE |
| D | Clickable markdown links | ConversationView.swift | DONE |
| E | Vibe mode consistency (Welcome + Help) | WelcomeView.swift, HelpOverlay.swift | DONE |
| F | Git ahead/behind counts | AppShell.swift | DONE |
| G | Terminal passthrough bar (Ctrl+T) | AppShell.swift | DONE (already existed) |

## Build Status
- **Compiles:** YES
- **Installed:** /Applications/Conductor.app (v3.0.0)
- **Desktop zip:** ~/Desktop/Conductor.zip (2.5MB)
- **All 17 audit items: COMPLETE**
