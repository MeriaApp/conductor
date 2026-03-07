# Conductor — Development Guide

## What This Is
**Conductor** — a macOS native SwiftUI app that wraps Claude CLI. The ultimate Claude Code wrapper with multi-agent orchestration, self-evolution, and zero-loss context management. You're not using Claude, you're *conducting* Claude.

---

## CORE PHILOSOPHY (Read This First — Non-Negotiable)

### 1. The Autonomy Principle
AI should NEVER assume something requires a human. Before flagging anything as "needs you":
1. Research whether an API, tool, agent, MCP server, or automation exists to do it
2. Find best-in-class tech/tricks to actually execute it autonomously
3. Only escalate to the human AFTER confirming AI genuinely can't do it
4. Frame it as opportunity cost — if AI can't automate it, is it worth human time?

Human interjection for direction, clarification, design input = always welcome.
Human interjection as a blocker for routine execution = unacceptable.

### 2. Opportunity Cost Is Everything
Every minute a human spends on something AI could do is a minute NOT spent on high-leverage work — building infrastructure, finding new tech, creating creative solutions for user reach. The app must constantly evaluate: "Should a human be doing this, or should AI?" If AI can do it — AI does it. If AI can't yet — research whether new tools make it possible before asking the human. The bar for human involvement is: genuinely impossible for AI, AND worth the human's time given what else they could be building.

### 3. Cross-Project Shared Intelligence
Multiple Claude CLI instances running across different projects must share knowledge:
- **Shared Knowledge Registry** (`~/.claude/shared-intelligence/` or SQLite DB)
- When one project discovers a useful API/tool/automation → writes an entry
- When any project needs to automate something → checks the registry first
- Entries: what, what it does, when found, which project, confidence, notes, alternatives
- **Always re-validate** — verify entries are still best-in-class or flag for replacement
- **Active, not passive** — deep search on every lookup, update stale entries
- Evolution Agent both consumes and contributes to this registry

### 4. Self-Evolution Is Not Optional
The app should find and apply improvements, not just suggest them. The Evolution Agent should:
- Discover new APIs, MCP servers, CLI updates, automation techniques
- Cross-reference against the Shared Intelligence Registry
- Apply improvements autonomously when safe, propose when risky
- Never let the technology stack go stale

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
│   │   ├── SessionArtifact.swift            — Cross-session handoff data
│   │   └── MoodBoard.swift                  — Moodboard, items, palette, design patterns
│   ├── Services/
│   │   ├── ClaudeProcess.swift              — CLI subprocess manager (stream-json)
│   │   ├── ThemeEngine.swift                — Luminance-based continuous theming
│   │   ├── SessionManager.swift             — Session history + persistence
│   │   ├── MarkdownParser.swift             — Markdown → ContentBlock parsing
│   │   ├── AgentOrchestrator.swift          — Multi-agent coordination (supervisor/pipeline/consensus/swarm)
│   │   ├── AgentMessageBus.swift            — Shared message bus
│   │   ├── PermissionManager.swift          — Auto-approve + learning rules engine
│   │   ├── FeatureDetector.swift            — CLI capability detection
│   │   ├── EvolutionAgent.swift             — Self-improvement engine
│   │   ├── ContextStateManager.swift        — Real-time token tracking
│   │   ├── CompactionEngine.swift           — Smart selective compaction
│   │   ├── SessionContinuity.swift          — Cross-session handoff
│   │   ├── ContextBudgetOptimizer.swift     — Token optimization
│   │   ├── MoodBoardEngine.swift            — Image analysis + autonomous design intelligence
│   │   ├── SharedIntelligence.swift         — Cross-project knowledge registry
│   │   ├── SoundManager.swift              — Subtle sound effects (NSSound)
│   │   ├── PluginManager.swift             — CLI plugin management
│   │   └── AgentPresets.swift              — Persistent agent preset configurations
│   └── Views/
│       ├── AppShell.swift                   — Main window layout
│       ├── StatusBar.swift                  — Top bar (model, context, cost, git, luminance)
│       ├── ConversationView.swift           — Message display + content block routing
│       ├── InputBar.swift                   — User input (Enter=send, Shift+Enter=newline)
│       ├── CodeBlockView.swift              — Syntax highlighted code (HighlightSwift)
│       ├── DiffView.swift                   — Inline diff display
│       ├── ToolUseView.swift                — Compact tool use indicators
│       ├── ThinkingView.swift               — Collapsible thinking blocks
│       ├── AgentPanel.swift                 — Multi-agent status + message log
│       ├── PermissionQueue.swift            — Non-blocking permission approval
│       ├── FeatureMapOverlay.swift          — Feature discovery (Active/Suggestions/Configure)
│       ├── ContextOverlay.swift             — Context management + selective compaction
│       ├── MoodBoardView.swift             — Drop zone + gallery + palette display
│       ├── DashboardPanel.swift            — Dashboard sidebar (Files/Tools/Context)
│       ├── SessionBrowser.swift            — Session browser overlay (Cmd+S)
│       ├── HelpOverlay.swift               — Keyboard shortcuts + feature reference
│       ├── MultiAgentSplitView.swift       — Split-pane multi-agent conversations
│       └── PerformanceDashboard.swift      — Token usage, cost, timing analytics
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

## Design System
See `/Users/jesse/Documents/meria-os/claude-terminal/UX_DESIGN.md` for:
- Color palette (warm neutrals + signal colors)
- Luminance slider (0.0 midnight → 1.0 paper)
- Layout specs (Focus mode / Dashboard mode)
- Typography, copy/paste, keyboard shortcuts
