# Conductor

**A native macOS app for Claude Code.**

Conductor wraps the Claude CLI in a real macOS interface — because developers deserve better than a terminal window for their most powerful tool.

![Conductor Screenshot](https://img.shields.io/badge/macOS-14.0%2B-blue) ![License](https://img.shields.io/badge/license-MIT-green) ![Version](https://img.shields.io/badge/version-3.0.0-gold)

---

## Why Conductor?

Claude Code in the terminal is powerful but limited. You can't:
- Read formatted markdown, diffs, or code blocks properly
- Manage multiple agents working in parallel
- See your context usage, cost, or token budget at a glance
- Search your conversation history
- Drag and drop files or paste images
- Get macOS notifications when background tasks finish

Conductor fixes all of that.

## What It Does

### Core
- **Native macOS SwiftUI app** — not Electron, not a web wrapper. Fast, lightweight, beautiful.
- **Full markdown rendering** — blockquotes, syntax-highlighted code with line numbers, clickable links, inline formatting. Reads like a document, not a terminal dump.
- **Side-by-side diffs** — auto-fallback to unified view in narrow windows.
- **File path autocomplete** — type `@/path` and Tab through your filesystem.
- **Terminal passthrough** — Ctrl+T for quick shell commands without leaving the conversation.

### Multi-Agent Orchestration
- **Spawn agent teams** with roles (Researcher, Builder, Reviewer, Reporter)
- **4 coordination patterns:** Supervisor, Pipeline, Consensus, Swarm
- **One-click presets:** "Audit Codebase", "Parallel Research" — agents auto-configure and report back
- **Split-pane view** to watch agents work in parallel

### Smart Cost Controls
- **Effort routing** — auto-classifies your messages (conversational → low effort, complex work → high)
- **Model routing** — routes simple messages to cheaper models automatically
- **Budget caps** — set $5/$10/$25/$50 limits per session
- **Savings tracker** — see how much Conductor saved you in the status bar
- **Per-turn cost display** — know exactly which messages are expensive

### Context Intelligence
- **Real-time context tracking** — see your token usage as a percentage
- **Compaction preservation** — when context compresses, Conductor extracts and reinjects decisions, files, and tasks. Zero information loss.
- **Compaction toast** — "Context compacted — 5 decisions, 12 files preserved"

### Polish
- **Command palette** (Cmd+K) — every action, organized by category
- **Session browser** (Cmd+S) — search and resume past conversations
- **Luminance slider** — continuous theme from midnight dark to paper white
- **Vibe Coder mode** (Ctrl+V) — hides tools, thinking, metadata. Just you and Claude.
- **Keyboard shortcuts for everything** — press ? to see them all
- **macOS notifications** — get notified when background tasks complete
- **Copy buttons** on code blocks, tool output, and thinking blocks

## Install

1. Download `Conductor.zip` from the [latest release](https://github.com/MeriaApp/conductor/releases/latest)
2. Unzip and drag `Conductor.app` to `/Applications`
3. Double-click to open (notarized — no Gatekeeper warning)

### Prerequisites
- macOS 14.0+
- [Claude CLI](https://docs.anthropic.com/en/docs/claude-code) installed: `npm install -g @anthropic-ai/claude-code`
- Authenticated: `claude auth login`

## Build From Source

```bash
# Install XcodeGen if needed
brew install xcodegen

# Generate Xcode project and build
cd conductor
xcodegen generate
xcodebuild -scheme Conductor -destination 'platform=macOS' build
```

## We Want Your Feedback

This is an early release. We built Conductor because we use Claude Code every day and wanted something better than the terminal. But we know it's not perfect yet.

**If you try it, please tell us:**
- What works well?
- What's broken or confusing?
- What feature would make you use it daily?

Open an [issue](https://github.com/MeriaApp/conductor/issues) or start a [discussion](https://github.com/MeriaApp/conductor/discussions). Every piece of feedback makes Conductor better.

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd+K | Command Palette |
| Cmd+S | Session Browser |
| Cmd+F | Search Conversation |
| Tab | Toggle Dashboard |
| Ctrl+V | Vibe Coder Mode |
| Ctrl+T | Terminal Passthrough |
| Cmd+Shift+T | Toggle Thinking Blocks |
| Cmd+O | Cycle Output Mode |
| Cmd+] / Cmd+[ | Adjust Luminance |
| Cmd++ / Cmd+- | Font Size |
| Shift+Tab | Plan Mode |
| ? | Help & All Shortcuts |

## License

MIT — use it however you want.

---

Built by [Meria](https://github.com/MeriaApp) in Charlevoix, Michigan.
