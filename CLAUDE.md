# Conductor — Development Guide

## What This Is
**Conductor** — a macOS native SwiftUI app that wraps Claude CLI. Multi-agent orchestration, context management, and a polished native UI for power users.

---

## Project Structure
```
Conductor/
├── project.yml                              — XcodeGen project spec
├── Sources/
│   ├── ConductorApp.swift              — App entry point, all service injection
│   ├── Design/
│   │   ├── ColorPalette.swift               — HSL color definitions (warm neutrals + signals)
│   │   └── Typography.swift                 — Font definitions (monospace + system)
│   ├── Models/
│   │   ├── ContentBlock.swift               — Typed content blocks (Text, Code, Diff, Tool, Thinking, List)
│   │   ├── StreamEvent.swift                — NDJSON event parsing (system, assistant, user, delta, result)
│   │   ├── Session.swift                    — Session metadata
│   │   ├── Agent.swift                      — Agent definition, role, state
│   │   ├── AgentMessage.swift               — Inter-agent communication + permission types
│   │   ├── ContextSnapshot.swift            — Pre-compaction state capture
│   │   └── SessionArtifact.swift            — Cross-session handoff data
│   ├── Services/
│   │   ├── ClaudeProcess.swift              — CLI subprocess manager (stream-json)
│   │   ├── ThemeEngine.swift                — Luminance-based continuous theming
│   │   ├── SessionManager.swift             — Session history + persistence
│   │   ├── MarkdownParser.swift             — Markdown → ContentBlock parsing
│   │   ├── AgentOrchestrator.swift          — Multi-agent coordination (supervisor/pipeline/consensus/swarm)
│   │   ├── AgentMessageBus.swift            — Shared message bus
│   │   ├── PermissionManager.swift          — Auto-approve + learning rules engine
│   │   ├── ContextStateManager.swift        — Real-time token tracking
│   │   ├── CompactionEngine.swift           — Smart selective compaction
│   │   ├── SessionContinuity.swift          — Cross-session handoff
│   │   ├── ContextBudgetOptimizer.swift     — Token optimization
│   │   ├── ContextPreservationPipeline.swift — Context preservation across compactions
│   │   ├── SoundManager.swift              — Subtle sound effects (NSSound)
│   │   ├── NotificationService.swift        — macOS notifications (completion + permissions)
│   │   ├── PluginManager.swift             — CLI plugin management
│   │   ├── AgentPresets.swift              — Persistent agent preset configurations
│   │   ├── TemplateScaffolder.swift         — Scaffolds optimized .claude/ for users
│   │   ├── ModelRouter.swift               — Model selection + routing
│   │   ├── ProjectManager.swift            — Project directory management
│   │   ├── CommandsManager.swift           — Custom commands
│   │   ├── SkillsManager.swift             — Skills browser backend
│   │   ├── HooksManager.swift              — Git/CLI hooks management
│   │   ├── MCPServerManager.swift          — MCP server configuration
│   │   ├── GitDiffService.swift            — Git diff parsing
│   │   ├── SessionCloseoutManager.swift    — Session closeout workflow
│   │   ├── SessionStateContainer.swift     — Per-window state container
│   │   └── ConversationHistoryLoader.swift — Load previous conversations
│   └── Views/
│       ├── AppShell.swift                   — Main window layout
│       ├── StatusBar.swift                  — Top bar (model, context, cost, git, luminance)
│       ├── ConversationView.swift           — Message display + content block routing
│       ├── InputBar.swift                   — User input (Enter=send, Shift+Enter=newline, up-arrow history)
│       ├── CodeBlockView.swift              — Syntax highlighted code (HighlightSwift)
│       ├── DiffView.swift                   — Inline diff display
│       ├── ToolUseView.swift                — Compact tool use indicators
│       ├── ThinkingView.swift               — Collapsible thinking blocks
│       ├── AgentPanel.swift                 — Multi-agent status + message log
│       ├── PermissionQueue.swift            — Non-blocking permission approval
│       ├── ContextOverlay.swift             — Context management + selective compaction
│       ├── DashboardPanel.swift            — Dashboard sidebar (Files/Tools/Context)
│       ├── SessionBrowser.swift            — Session browser overlay (Cmd+S)
│       ├── HelpOverlay.swift               — Keyboard shortcuts + feature reference
│       ├── MultiAgentSplitView.swift       — Split-pane multi-agent conversations
│       ├── PerformanceDashboard.swift      — Token usage, cost, timing analytics
│       ├── OnboardingView.swift            — 5-step guided setup wizard
│       ├── CommandPalette.swift            — Cmd+K command palette
│       ├── CommandsBrowser.swift           — Browse custom commands
│       ├── SkillsBrowser.swift             — Browse .claude/skills/
│       ├── ProjectSwitcher.swift           — Quick project switching
│       ├── FilePreviewPanel.swift          — File preview sidebar
│       ├── SearchBar.swift                 — In-conversation search
│       ├── SessionDiffOverlay.swift        — Session diff viewer
│       ├── HooksOverlay.swift              — Hooks configuration UI
│       ├── MCPServerOverlay.swift          — MCP server management UI
│       └── WelcomeView.swift              — Welcome/empty state
└── Resources/
    └── Assets.xcassets/                     — App icon (needs images)
```

## Build Commands
```bash
cd "/Users/jesse/Documents/meria-os/conductor-public"

# Regenerate Xcode project (after adding/removing files)
xcodegen generate

# Build (ad-hoc signed for local dev)
xcodebuild -scheme Conductor -destination 'platform=macOS' build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# Run the built app
open ~/Library/Developer/Xcode/DerivedData/Conductor-*/Build/Products/Debug/Conductor.app
```

## For Distribution (requires Apple Developer account)
```bash
# Set your team ID and build with signing
xcodebuild -scheme Conductor -destination 'platform=macOS' build \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID \
  CODE_SIGN_IDENTITY="Apple Development" \
  CODE_SIGN_STYLE=Automatic
```

## SPM Dependencies
- **HighlightSwift** — Syntax highlighting (200+ languages)
- **swift-markdown** (apple/swift-markdown) — Markdown AST parsing

## Key Architecture Patterns
- `@MainActor @ObservableObject` singletons via `static let shared`
- `@EnvironmentObject` injection at app root
- async/await (no Combine)
- HSL color system with continuous luminance slider
- NDJSON streaming from Claude CLI subprocess
- `TemplateScaffolder` — scaffolds optimized `.claude/` rules + skills for users on first run

## Design System
- Color palette (warm neutrals + signal colors)
- Luminance slider (0.0 midnight → 1.0 paper)
- Layout specs (Focus mode / Dashboard mode)
- Typography, copy/paste, keyboard shortcuts
