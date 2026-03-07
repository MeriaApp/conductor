# Context State — Conductor

*Last updated: March 7, 2026 (Session 7)*

## Current State: ALL UX_DESIGN.md FEATURES COMPLETE

---

## What Changed — Session 7 (March 7, 2026)

### 11 Remaining UX Spec Features — ALL IMPLEMENTED

#### Group A: Vibe Coder Enhancements (4 features)
- **A1. Deploy Button** — "Deploy" button in vibe action buttons, sends `process.send("Deploy this project to production")`
- **A2. Error Translation** — Friendly "Something went wrong. Claude is looking into it." when tool blocks have `isError == true` in vibe mode
- **A3. Auto-Approve Permissions** — `autoApproveAll` flag on PermissionManager with early return in `evaluate()`. Synced with vibe mode toggle (Ctrl+V and command palette)
- **A4. Suggested Follow-Ups** — "What's next?" button sends `"What should I do next based on what we just changed?"`

#### Group B: Thinking Toggle (1 feature)
- **B1. Toggle Thinking Visibility** — `showThinking: Bool` on ClaudeProcess. ContentBlockRenderer skips ThinkingView when false. Cmd+Shift+T shortcut, command palette "Toggle Thinking", HelpOverlay entry

#### Group C: Context Panel Enhancements (2 features)
- **C1. Allocation Breakdown** — Stacked colored bar (lavender=system est., sky=conversation, sage=output, sand=cache). Categorized rows with color dots and token counts. System prompt estimated at ~30% of input tokens
- **C2. Pin Context** — `isContextPinned: Bool` on ContextStateManager. Pin/unpin button in context panel. CompactionEngine.prepareForCompaction() respects pin. Visual indicator when pinned

#### Group D: Full-Screen Diff Overlay (1 feature)
- **D1. Fullscreen Diff** — Expand button (arrow.up.left.and.arrow.down.right) on DiffView header. `FullscreenDiffOverlay` view at bottom of DiffView.swift (~50 lines). Full-width side-by-side/unified toggle. Esc to close. Wired through ContentBlockRenderer → MessageView → ConversationView → AppShell

#### Group E: Session Enhancements (2 features)
- **E1. Session Forking** — `forkedFrom: String?` on Session. `forkSession()` and `deleteSession()` on SessionManager. Right-click context menu on SessionRow: Fork/Delete
- **E2. Auto-Summary** — `summary: String?` on Session. `generateSummary()` extracts turn count + file names. `endSession(messages:)` generates summary. Shown in SessionRow metadata

#### Group F: Permission Number Keys (1 feature)
- **F1. Number Badges** — Index numbers (1-9) displayed on PermissionRequestRow. `.onKeyPress` handler for digits 1-9 approves corresponding request

### Refactoring
- Extracted `vibeButton()` helper in MessageView (DRY for 4 action buttons)
- Removed duplicate `Conductor 2.xcodeproj`

### Files Modified (13 files, ~229 lines added)
- `Sources/Views/ConversationView.swift` — Deploy/suggest/diffExpand callbacks, error translation, vibeButton helper, ContentBlockRenderer thinking gate + diff expand
- `Sources/Views/AppShell.swift` — Wire deploy/suggest/diffExpand callbacks, fullscreen diff state+overlay, Cmd+Shift+T shortcut, thinking command palette, vibe→auto-approve sync, endSession with messages
- `Sources/Services/ClaudeProcess.swift` — `showThinking: Bool`
- `Sources/Services/PermissionManager.swift` — `autoApproveAll` flag, early return in evaluate()
- `Sources/Views/PermissionQueue.swift` — Number badges, keyboard handler for 1-9
- `Sources/Views/DiffView.swift` — Expand button, `onExpand` callback, `FullscreenDiffOverlay` view (~50 lines)
- `Sources/Views/DashboardPanel.swift` — Stacked bar visualization, categorized breakdown rows, pin button, contextRow helper
- `Sources/Services/ContextStateManager.swift` — `isContextPinned: Bool`
- `Sources/Services/CompactionEngine.swift` — Pin guard in prepareForCompaction
- `Sources/Models/Session.swift` — `forkedFrom`, `summary` fields
- `Sources/Services/SessionManager.swift` — `forkSession()`, `deleteSession()`, `generateSummary()`, `extractFileNames()`, updated `endSession(messages:)`
- `Sources/Views/SessionBrowser.swift` — Context menu (fork/delete), summary display in SessionRow
- `Sources/Views/HelpOverlay.swift` — Cmd+Shift+T shortcut entry

### Build Status
- **Compiles:** YES (BUILD SUCCEEDED)
- **Deployed:** Copied to /Applications/Conductor.app

---

## What Changed — Session 6 (March 7, 2026)

### New Feature: Vibe Coder Mode (Ctrl+V)
- Toggle via Ctrl+V or Command Palette → "Toggle Vibe Coder"
- **StatusBar:** Simplified to "Claude Code · healthy/getting warm/running low · $cost" + sparkles badge. Hides model name, effort picker, permission picker, git branch, working dir, luminance, Cmd+K chip
- **ConversationView:** ToolUseBlock and ThinkingBlock hidden with EmptyView(). Duration hidden. StreamingDots replaced with "Working..." text. Action buttons ("Undo" + "See Changes") appear after last assistant message
- **InputBar:** Prompt `▸` hidden, "What do you want to build?" placeholder overlay when input empty
- **HelpOverlay:** Ctrl+V in Navigation shortcuts, Vibe Coder in Features list
- Pure UI filtering — no data model changes, no process changes. Toggle off restores everything.

### Files Modified
- `Sources/Services/ClaudeProcess.swift` — Added `@Published var isVibeCoder: Bool`
- `Sources/Views/StatusBar.swift` — vibeCoderStatusBar / fullStatusBar split
- `Sources/Views/ConversationView.swift` — Block filtering, action buttons, "Working..." text, onUndo/onSeeChanges callbacks
- `Sources/Views/InputBar.swift` — Placeholder overlay, conditional prompt character
- `Sources/Views/AppShell.swift` — Ctrl+V shortcut, command palette entry, ConversationView callback wiring
- `Sources/Views/HelpOverlay.swift` — Ctrl+V shortcut, Vibe Coder feature entry

---

## What Changed — Part 4c (March 6, 2026, Session 5)

### New Feature: Sound Manager
- Subtle NSSound effects: Tink (response complete), Glass (background complete), Purr (permission needed)
- Off by default, toggleable via command palette ("Sound On/Off")
- Only plays Glass when app is inactive (not focused)
- Wired: `handleResult()` → Tink, `PermissionManager.evaluate()` → Purr
- File: `Sources/Services/SoundManager.swift`

### New Feature: Plugin Manager
- Manages Claude CLI plugins via subprocess calls
- Methods: `refresh()`, `install()`, `enable()`, `disable()`, `uninstall()`
- Parses `claude plugin list` output into `PluginInfo` structs
- Command palette entry: "Refresh Plugins"
- File: `Sources/Services/PluginManager.swift`

### New Feature: Performance Dashboard (Cmd+Shift+P)
- Floating overlay with analytics: token usage, cost, timing, agent performance, session history
- Sections: Current Session Stats (grid), Token Breakdown (visual bars), Message Analysis, Agent Stats, Recent Sessions
- Escape to dismiss, click backdrop to dismiss
- File: `Sources/Views/PerformanceDashboard.swift`

### New Feature: Agent Presets
- Persistent agent configurations saved to `~/Library/Application Support/Conductor/agent_presets.json`
- 4 default presets: Quick Builder, Security Auditor, Refactor Scout, Test Writer
- Each preset has: name, role, effort level, custom system prompt, optional initial task, icon
- Spawn from command palette: "Spawn: Quick Builder", etc.
- File: `Sources/Services/AgentPresets.swift`

### New Feature: Output Modes (o key)
- 4 modes: Standard, Concise, Detailed, Code Only
- `o` key cycles through modes (when no overlays open)
- Each mode applies a system prompt prefix that adjusts response style
- Visible in StatusBar (dropdown) when not Standard
- Command palette entries for all 4 modes
- Enum: `OutputMode` in ClaudeProcess.swift

### New Feature: Terminal Passthrough (Ctrl+T)
- Quick shell command bar appears above input area
- Green terminal-themed bar with `$` prompt
- Type command, Enter to execute (sends to Claude as shell command request)
- Escape to dismiss
- Command palette entry: "Terminal Command"
- View: `TerminalBar` struct in AppShell.swift

### New Feature: Undo (u key)
- Removes last assistant + user message pair
- Only works when not streaming and no overlays open
- Subtle sound acknowledgment
- Command palette entry: "Undo Last Response"

### New Feature: Budget Cap
- `maxBudgetUSD` property on ClaudeProcess, passed as `--max-budget-usd` flag
- Command palette cycles through common values: Off/$1/$5/$10/$25
- StatusBar indicator (amber, turns rose when >80% of budget)

### New Feature: Plan Mode indicator in StatusBar
- Lavender "PLAN" badge appears when `permissionMode == .plan`
- Combined Shift+Tab handler toggles plan mode

### Updated: HelpOverlay
- Now includes ALL keyboard shortcuts: o, u, Ctrl+T, Cmd+Shift+P, Cmd+Shift+M, Shift+Tab
- Updated features list: Performance, Terminal, Agent Presets
- Updated Session section: Output modes, Budget cap

### Files Created
- `Sources/Services/SoundManager.swift`
- `Sources/Services/PluginManager.swift`
- `Sources/Services/AgentPresets.swift`
- `Sources/Views/PerformanceDashboard.swift`

### Files Modified
- `Sources/Services/ClaudeProcess.swift` — OutputMode enum, maxBudgetUSD, --max-budget-usd flag, output mode system prompt prefix
- `Sources/Views/AppShell.swift` — Terminal bar, undo, output mode cycling, agent preset spawning, budget command palette entries, TerminalBar view
- `Sources/Views/StatusBar.swift` — Plan mode indicator, output mode dropdown, budget indicator
- `Sources/Views/HelpOverlay.swift` — All new shortcuts and features
- `Sources/Services/PermissionManager.swift` — Sound on permission needed
- `CLAUDE.md` — Updated project structure with new files

---

## What Changed This Session — Part 4b (March 6, 2026)

### New Feature: Dashboard Mode (Tab cycling)
- 3-panel right sidebar: FILES (files touched), TOOLS (live tool activity), CONTEXT (token usage)
- Tab key cycles: Focus → Dashboard → Agents → Moodboard → Focus
- FILES: extracts file paths from tool use blocks, shows read/modified/created icons + diff stats
- TOOLS: shows last 8 tool uses with status icons (✓/⟳/✗/⏸), name, summary, duration
- CONTEXT: visual progress bar, token breakdown (input/output/cache/free), compaction warning at 70%+
- Collapsible sections
- Command palette entry: "Toggle Dashboard"
- File: `Sources/Views/DashboardPanel.swift`

### New Feature: Effort Level Selector
- Dropdown in StatusBar with Low/Medium/High
- Maps to CLI `--effort` flag
- Icons: hare (low), figure.walk (medium), flame (high)
- Current level highlighted in sky color
- Switchable via command palette ("Effort: Low/Medium/High")

### New Feature: Permission Mode Selector
- Dropdown in StatusBar with Default/Accept Edits/Bypass/Plan
- Maps to CLI `--permission-mode` flag
- Color-coded: sage (default), amber (acceptEdits), rose (bypass), lavender (plan)
- Lock icons show current security posture
- Switchable via command palette

### New Feature: Shared Intelligence Registry
- Cross-project knowledge sharing at `~/.claude/shared-intelligence/registry.json`
- 8 default entries seeded on first launch (IndexNow, Pexels, pg_cron, Resend, satori, CLI stream-json, --resume, AppleScript IPC)
- CRUD operations: register, verify, invalidate, prune
- Lookup by name/description/tags/category
- Categories: API, Tool, Automation, Pattern, Config, Service
- Export as markdown for context injection
- Command palette: "Show Intelligence Registry" sends registry to Claude for reference
- Injected as `@EnvironmentObject` via ConductorApp
- File: `Sources/Services/SharedIntelligence.swift`

### Files Created
- `Sources/Views/DashboardPanel.swift` — Dashboard right sidebar (Files/Tools/Context panels)
- `Sources/Services/SharedIntelligence.swift` — Cross-project intelligence registry

### Files Modified
- `Sources/Views/AppShell.swift` — Dashboard state, Tab cycling, command palette entries (dashboard, effort, permission, intelligence)
- `Sources/Views/StatusBar.swift` — Effort picker, permission mode indicator with dropdowns
- `Sources/Views/HelpOverlay.swift` — Updated shortcuts (Tab cycling), new features list
- `Sources/Services/ClaudeProcess.swift` — `effortLevel`, `permissionMode` properties, EffortLevel/CLIPermissionMode enums, CLI flag passthrough in `launchTurn()`
- `Sources/ConductorApp.swift` — SharedIntelligence injection

---

## What Changed This Session — Part 4 (March 5, 2026, Session 4 — Continuation)

### New Feature: Session Browser (Cmd+S)
- Floating overlay with search, arrow key navigation, Enter to resume, Escape to dismiss
- Sessions sorted by last active, searchable by title/project/branch
- Metadata: time ago, message count, cost, model, git branch, project path
- Resume button connects to CLI session via `--resume` with stored session ID
- Wired into AppShell with Cmd+S keyboard shortcut + command palette entry
- File: `Sources/Views/SessionBrowser.swift`

### New Feature: Help Overlay (?)
- Quick reference showing all keyboard shortcuts organized by category
- Sections: Navigation, Chat, Theme, Overlays, Agents
- Feature summary with icons and descriptions
- Wired into AppShell with `?` key shortcut + command palette entry
- File: `Sources/Views/HelpOverlay.swift`

### New Feature: Multi-Agent Split View (Cmd+Shift+M)
- HSplitView with one pane per running agent
- Each pane: agent header + state indicator, scrollable live conversation, task input field, stats bar (tokens + cost)
- `SplitPaneMessageRow` for compact rendering of text, code, tools, thinking blocks
- `AgentPane` uses `@ObservedObject ClaudeProcess` for real-time streaming
- Opens as sheet from command palette or Cmd+Shift+M
- File: `Sources/Views/MultiAgentSplitView.swift`

### New Feature: PermissionManager Integration
- Added `onToolUse` callback to ClaudeProcess (fires when tool_use content block is parsed)
- AgentOrchestrator now routes all agent tool calls through `PermissionManager.evaluate()`
- Audit trail: every tool call logged with agent name, tool, input, risk level
- Rule learning: after 3 manual approvals of same pattern, auto-adds rule
- Critical-risk tools broadcast on AgentMessageBus so other agents are alerted
- Default rules auto-approve safe tools (Read, Glob, Grep, WebFetch, WebSearch, Task*)
- Rules persist to disk at `~/Library/Application Support/Conductor/permission_rules.json`

### Files Modified
- `Sources/Views/AppShell.swift` — 3 new keyboard shortcuts (Cmd+S, ?, Cmd+Shift+M), overlay presentation, command palette entries, MultiAgentSplitView sheet
- `Sources/Views/HelpOverlay.swift` — Updated with Cmd+Shift+M shortcut
- `Sources/Services/ClaudeProcess.swift` — Added `onToolUse` callback
- `Sources/Services/AgentOrchestrator.swift` — Wired tool use auditing through PermissionManager

### Files Created
- `Sources/Views/SessionBrowser.swift` — Session browser overlay
- `Sources/Views/HelpOverlay.swift` — Help/shortcuts overlay
- `Sources/Views/MultiAgentSplitView.swift` — Split-pane multi-agent view

---

## What Changed This Session — Part 3 (March 5, 2026, Late Night Session 3)

### Bug Fixes (3 Critical Multi-Agent Bugs)

1. **AgentMessageBus subscription overwrite (FIXED)**
   - **Root cause:** Subscribers stored as `[String: callback]` dict — same key overwrites previous callback
   - **Fix:** Switched to array-based `[Subscription]` with unique IDs. Multiple subscriptions per agentId now work.
   - `subscribe()` returns a subscription ID for targeted cleanup
   - `unsubscribe(subscriptionId:)` removes specific subscription
   - `unsubscribe(agentId:)` removes all subscriptions for an agent
   - Snapshot subscriptions before iteration to avoid mutation during send

2. **Pipeline subscription memory leak (FIXED)**
   - **Root cause:** Pipeline/build-verify subscriptions created but never cleaned up
   - **Fix:** Added `pipelineSubscriptionIds: [String]` tracking in orchestrator
   - `cleanupPipeline()` method removes all tracked subscriptions
   - Called automatically: before starting any new pattern, on build-verify completion, on agent stop
   - `stopAgent()` now also cleans up synthetic subscription keys (e.g., `agentId_pipeline`, `agentId_verify_pipeline`, `agentId_supervisor`)

3. **Supervisor ASSIGN directives never parsed (FIXED)**
   - **Root cause:** Supervisor generates `ASSIGN [worker]: [task]` text but nobody parsed it
   - **Fix:** Added `parseSupervisorDirectives()` method that:
     - Subscribes to supervisor result messages
     - Parses lines matching `ASSIGN [worker name]: [subtask]`
     - Looks up worker agent by name (case-insensitive)
     - Dispatches the subtask via `assignTask()`

### Also Fixed: Consensus Pattern
- Was a TODO stub — now tracks all agent results and broadcasts unified summary when all complete

### New Feature: Agent Conversation Preview
- When you select an agent in AgentPanel, see its real-time conversation below the agent list
- Uses `@ObservedObject ClaudeProcess` for live updates (streaming text, tool use, thinking)
- Shows role labels ("Task" / "Agent"), content blocks (text, code, tools, thinking), duration
- Auto-scrolls to newest message
- Compact rendering with line limits — doesn't overwhelm the sidebar

### New Feature: Command Palette (Cmd+K)
- Floating overlay with search, arrow key navigation, Enter to execute, Escape to dismiss
- Commands organized by category: Session, View, Agent (color-coded icons)
- Full command list:
  - **Session:** New Session, Interrupt, Clear Conversation, Set Working Directory
  - **View:** Toggle Agent Panel, Toggle Moodboard, Feature Map, Context Manager, Luminance Up/Down
  - **Agent:** Spawn Builder/Reviewer/Tester/Deployer/Researcher/Planner, Build & Verify, Stop All Agents
- Keyboard shortcut hints shown for commands that have them
- Subtitle descriptions for discoverability

### New Feature: Working Directory Picker
- "Set Working Directory" command in palette opens NSOpenPanel folder picker
- Changes the Claude CLI working directory and re-detects git branch
- Current directory shown in StatusBar (shortened to last 2 path components)
- "Cmd+K" hint badge added to status bar for discoverability

### Files Modified
- `Sources/Services/AgentMessageBus.swift` — Full rewrite: array-based subscriptions with IDs
- `Sources/Services/AgentOrchestrator.swift` — Pipeline cleanup, ASSIGN parsing, consensus tracking, messagesForAgent/isAgentStreaming helpers
- `Sources/Views/AgentPanel.swift` — AgentConversationPreview + AgentMessageRow views
- `Sources/Views/CommandPalette.swift` — NEW: CommandPalette, CommandRow, CommandItem, CommandCategory
- `Sources/Views/AppShell.swift` — Cmd+K shortcut, palette overlay, directory picker, command list builder
- `Sources/Views/StatusBar.swift` — Working directory indicator, Cmd+K hint badge

---

## CORE PHILOSOPHY (Jesse's Directive — Non-Negotiable)

### The Autonomy Principle
**AI should NEVER assume something requires a human.** Before flagging anything as "needs you":
1. Research whether an API, tool, agent, MCP server, or automation exists to do it
2. Find best-in-class tech/tricks to actually execute it autonomously
3. Only escalate to the human **after confirming AI genuinely can't do it**
4. Even then, frame it as opportunity cost — if AI can't automate it, is it worth human time? Because that time could go toward building something with higher leverage.

**The app must embody this at every level:**
- Auto-approve and learn (permission system), don't ask for everything
- Build/test/audit without asking (build-verify pipeline)
- Find and apply improvements, don't just suggest them (evolution agent)
- Design autonomously without waiting for user screenshots (moodboard engine)
- Human interjection for direction, clarification, design input = welcome
- Human interjection as a blocker for execution = unacceptable

### Cross-Project Shared Intelligence
A persistent database/registry that ALL Claude instances can read from and write to.
See CLAUDE.md for full details.

---

## What Changed This Session — Part 2 (March 5, 2026, Late Night)

### CRITICAL: CLI Communication Fixed
- **Root cause:** Claude CLI in `stream-json` mode doesn't read interactive stdin. Required `-p` flag.
- **Fix:** Rewrote ClaudeProcess to per-message model: each send() launches `claude -p "msg" --output-format stream-json --include-partial-messages --verbose --dangerously-skip-permissions --resume <sessionId>`
- Session continuity via `--resume` with CLI-generated session ID (captured from system event)
- Streaming deltas arrive wrapped in `stream_event` type, properly unwrapped in parser
- `--dangerously-skip-permissions` required for tool use in `-p` mode (no interactive stdin for approvals)
- `--include-partial-messages` enables real-time streaming text

### StreamEvent Parser Rewritten
- Switched from broken Codable to manual JSONSerialization parsing
- Fixed field name mismatches: `session_id`, `claude_code_version`, `total_cost_usd`, `duration_ms`
- Events have `uuid` not `id` — handled correctly
- `tools` in system event is `[String]` not `[ToolInfo]`
- `stream_event` wrapper properly unwrapped to extract `content_block_delta`
- `rate_limit_event` gracefully ignored

### Markdown Parsing Wired
- `handleAssistant` now routes text through `MarkdownParser.parse()` → splits into CodeBlock, ListBlock, DiffBlock, etc.
- Code blocks now get syntax highlighting via HighlightSwift (CodeBlockView already had it, just never received CodeBlocks)
- Streaming message properly replaced (not duplicated) when assistant event arrives

### Tool Use Display Improved
- ToolUseView.inputSummary now parses JSON to extract meaningful info per tool type
- Read/Edit/Write: shows shortened file path (last 3 components)
- Bash: shows command text
- Grep: shows pattern + path
- Glob: shows pattern
- Task/WebSearch/WebFetch/ToolSearch: shows relevant field

### Multi-Agent Orchestrator Wired
- Agent processes now get role-specific system prompts via `--append-system-prompt`
- `onResult` callback wired: broadcasts agent results to AgentMessageBus
- `onError` callback wired: broadcasts errors as AgentMessage
- SpawnAgentSheet passes main process working directory to new agents
- AgentPanel has task input field for sending tasks to selected agents
- Agents use same `--dangerously-skip-permissions` as main process

### Inter-Instance Communication Proven
- AppleScript successfully sent message from this CLI session to running Conductor
- Claude inside Conductor received and responded to the cross-instance message
- Foundation for proper multi-agent coordination

---

## What Changed This Session — Part 1 (March 5, 2026)

### Bug Fixes Applied (All 7 from audit — DONE)
1. **ColorPalette.swift** — FIXED: Now uses `Color(red:green:blue:)` via `hslToRGB()` instead of broken `Color(hue:saturation:brightness:)`. All colors now visually correct.
2. **InputBar.swift** — FIXED: Text color now comes from ThemeEngine via HSL color calculation. Updates dynamically with luminance changes. Insertion point color also themed.
3. **StreamEvent.swift** — FIXED: `RawContentBlock.stableId` is now a stored property, generated once during decode. Uses `toolUseId` when available, falls back to type+index+UUID.
4. **ClaudeProcess.swift** — FIXED: Claude path auto-detected from multiple candidates (`~/.local/bin/claude`, `/usr/local/bin/claude`, `/opt/homebrew/bin/claude`). Error banner added to AppShell with retry button.
5. **Session.gitBranch** — FIXED: `detectGitBranch()` runs `git rev-parse --abbrev-ref HEAD` on session start, populates the branch in StatusBar.
6. **ConversationView.swift** — FIXED: StreamingDots now uses `TimelineView(.periodic(from:by:))` instead of leaked `Timer.scheduledTimer`. Zero memory leak.
7. **ThemeEngine.swift** — FIXED: All 18+ color properties changed from `@Published` to plain `var`. Single `objectWillChange.send()` at start of `recalculate()`. One SwiftUI update cycle instead of 18.

### Integration Pass (Tier 1 — DONE)
1. **ContextStateManager** — NOW CALLED: `updateFromProcess()` called from ClaudeProcess.onResult callback
2. **SessionManager** — NOW CALLED: `updateActiveSession(from:)` called from ClaudeProcess.onResult callback. StatusBar shows real data.
3. **ContextBudgetOptimizer** — NOW CALLED: `analyze(messages:)` called from ClaudeProcess.onResult callback
4. **SessionContinuity** — NOW CALLED: `loadSessionContext()` on session start, `saveSessionEnd()` on window close
5. **EvolutionAgent** — NOW CALLED: `startMonitoring()` called from AppShell.onAppear
6. **FeatureMapOverlay** — NOW ACCESSIBLE: Cmd+Shift+F opens it as .sheet
7. **ContextOverlay** — NOW ACCESSIBLE: Cmd+Shift+X opens it as .sheet
8. **StatusBar** — NOW READS from `ContextStateManager.contextPercentage` (real data, not always-zero Session property)
9. **ClaudeProcess callbacks** — Added `onResult`, `onSystem`, `onError` closures for service integration
10. **Error display** — Error banner with retry button shows when Claude CLI fails to launch

### Files Modified
- `Sources/Design/ColorPalette.swift` — HSL→Color conversion fix, removed unused hslToBrightness()
- `Sources/Models/StreamEvent.swift` — Stable RawContentBlock.id via stored property + custom init(from:)
- `Sources/Services/ClaudeProcess.swift` — Auto-detect claude path, added onResult/onSystem/onError callbacks
- `Sources/Services/ThemeEngine.swift` — Batched color updates (single objectWillChange.send())
- `Sources/Views/AppShell.swift` — Full integration wiring: 5 new @EnvironmentObject, overlay state, keyboard shortcuts, git branch detection, error banner, session save on disappear
- `Sources/Views/ConversationView.swift` — StreamingDots uses TimelineView
- `Sources/Views/InputBar.swift` — Theme-aware text color via NSColor from HSL
- `Sources/Views/StatusBar.swift` — Reads from ContextStateManager instead of Session

---

## Build Status
- **Compiles:** YES (xcodebuild BUILD SUCCEEDED)
- **Deployed:** Not yet launched/tested interactively
- **Tests:** None yet

## What's Still Pending

### Architecture Issues (Not Yet Fixed)
- ~~AgentMessageBus: dictionary-keyed subscriptions overwrite~~ DONE
- ~~AgentOrchestrator: supervisor ASSIGN directives generated but never parsed~~ DONE
- ~~Pipeline subscriptions never cleaned up (memory leak)~~ DONE
- ~~FeatureDetector.runCommand() blocks main thread~~ DONE (uses Task.detached)
- ~~FeatureDetector.detectProjectType() uses "/" (wrong for app)~~ DONE (takes directory param)
- ~~EvolutionAgent.apply() is a no-op~~ DONE (installs PreCompact hook, creates output modes)
- ~~CompactionEngine sends invalid "/context inject" command~~ DONE (sends as regular message)
- ~~PermissionManager.evaluate() still not called~~ DONE (wired into AgentOrchestrator via onToolUse callback)

### CLI v2.1.70 Feature Support
- ~~Plugin system (`claude plugin install/list/enable`)~~ DONE (PluginManager service)
- ~~Permission modes (`--permission-mode`)~~ DONE (selector in StatusBar + command palette)
- Custom agents via CLI (`--agents` JSON) — not yet integrated (have presets instead)
- ~~Effort levels (`--effort`)~~ DONE (selector in StatusBar + command palette)
- ~~Worktrees (`--worktree`)~~ DONE (flag passed for worktree sessions)
- ~~Budget cap (`--max-budget-usd`)~~ DONE (command palette + StatusBar)

### Missing UX Features — ALL DONE
- ~~Command Palette (Cmd+K)~~ DONE
- ~~Session Browser (Cmd+S)~~ DONE
- ~~Working directory picker~~ DONE
- ~~Dashboard Mode~~ DONE
- ~~Help overlay (?)~~ DONE
- ~~Sound design~~ DONE (SoundManager)
- ~~Performance dashboard~~ DONE (Cmd+Shift+P)
- ~~Output modes~~ DONE (o key)
- ~~Terminal passthrough~~ DONE (Ctrl+T)
- ~~Undo~~ DONE (u key)
- ~~Agent presets~~ DONE (AgentPresets service)
- ~~Budget cap~~ DONE

### What's Still Pending (Low Priority)
- Custom agents via CLI `--agents` JSON flag (presets cover most use cases)
- Full interactive terminal emulator (current Ctrl+T is command-by-command)
- ~~Diff viewer overlay (separate from inline diffs)~~ DONE (Fullscreen Diff Overlay)
- ~~Vibe Coder mode (Ctrl+V from UX_DESIGN.md)~~ DONE
- ~~Deploy button in vibe mode~~ DONE
- ~~Error translation in vibe mode~~ DONE
- ~~Auto-approve in vibe mode~~ DONE
- ~~Suggested follow-ups~~ DONE
- ~~Thinking toggle (Cmd+Shift+T)~~ DONE
- ~~Context allocation breakdown~~ DONE
- ~~Pin context~~ DONE
- ~~Session forking~~ DONE
- ~~Session auto-summary~~ DONE
- ~~Permission number keys~~ DONE
- iOS companion app
