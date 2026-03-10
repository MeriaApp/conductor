# Context State — Conductor (Public Distribution Version)

*Last updated: March 11, 2026*

## What This Is

This is the **distributable version** of Conductor, forked from the original at `claude-terminal/Conductor/`. The original stays untouched (Jesse runs it daily). This version is modified for other users to install and use.

**Repo:** `MeriaApp/conductor` (private) — https://github.com/MeriaApp/conductor
**Codebase:** `/Users/jesse/Documents/meria-os/conductor-public/`

---

## Current State: v3.0.0+ — UX Fixes (Mar 11, 2026)

**Base:** v3.0.0 — Invisible Intelligence Made Visible

### Mar 11 Session — Two UX Fixes (ConversationView.swift only)

1. **Auto-scroll fix** — `ScrollPositionMonitor.Coordinator` split into two handlers (`liveScrollDidChange` / `liveScrollDidEnd`). Mid-animation scroll events no longer accidentally disengage auto-scroll. Only intentional upward scroll (>10px) disengages. Re-engage threshold bumped from 50px to 80px. Fixes "Jump to bottom" appearing unexpectedly in smaller windows.

2. **Cross-block text selection** — New `MergedTextView` struct and `BlockGroup` enum. Consecutive text-renderable blocks (TextBlock, ListBlock, BlockquoteBlock) are merged into a single `AttributedString` and rendered as one `Text` view, enabling click-drag selection across paragraphs, headings, lists, and blockquotes. Non-text blocks (CodeBlock, DiffBlock, ToolUseBlock, ThinkingBlock) naturally break the chain. List bullets rendered inline (sky-colored triangle). Blockquotes use `│` character instead of drawn bar.

**File changed:** `Sources/Views/ConversationView.swift`
**Build:** SUCCEEDED (ad-hoc signed, debug build launched)
**Not yet:** Committed, pushed, released, installed to /Applications. Jesse needs to test both fixes before committing.
**Test:** Send a message that produces headings + paragraphs + bullet lists. Verify: (a) auto-scroll sticks during streaming in a small window, (b) can click-drag to select across headings/paragraphs/lists.

---

**Previous release:** v2.2.0 — smart cost controls

### v3.0.0 Changes (4 Items from CONDUCTOR_V3_PLAN.md)

1. **Savings Tracker** (`ClaudeProcess.swift`, `StatusBar.swift`) — DONE.
2. **Compaction Toast** (`ContextPreservationPipeline.swift`, `ConversationView.swift`, `AppShell.swift`) — DONE.
3. **Status Bar Simplification** (`StatusBar.swift`) — DONE.
4. **Multi-Agent Workflow Presets** (`AgentOrchestrator.swift`, `AppShell.swift`) — DONE.
5. **Direct API Backend** — DEFERRED to separate session.

### v3.0.0 Terminal Parity Audit (10 Items from CONDUCTOR_AUDIT_PLAN.md)

1. **Blockquote rendering** — `MarkdownParser.swift`, `ContentBlock.swift`, `ConversationView.swift`. New `BlockquoteBlock` type with sand left-bar styling.
2. **Line numbers in code blocks** — `CodeBlockView.swift`, `Typography.swift`. Gutter with line numbers for multi-line blocks.
3. **Luminance-aware code theme** — `CodeBlockView.swift`. Switches atomOne↔xcode at luminance 0.6.
4. **Copy buttons** — `ToolUseView.swift`, `ThinkingView.swift`. Copy button on expanded tool output and thinking blocks.
5. **Search highlighting** — `ConversationView.swift`. Sky-blue left-edge bar on matched messages.
6. **Streaming optimization** — `ClaudeProcess.swift`. In-place block update instead of message rebuild.
7. **Centralized Escape** — `AppShell.swift`. Single handler dismisses topmost overlay.
8. **Process timeout** — `ClaudeProcess.swift`. 5-minute watchdog kills hung processes.
9. **Stderr surfacing** — `ClaudeProcess.swift`. `lastStderrMessage` published property.
10. **File path autocomplete** — `InputBar.swift`. Type `@/path` for filesystem completion with Tab/Esc.

### v3.0.0 Polish Pass (7 Additional Items)

A. **Diff auto-fallback** — `DiffView.swift`. GeometryReader auto-switches to unified view below 600px width.
B. **Session preview** — `SessionBrowser.swift`. 2-line summary, "View Only" for sessions without active session.
C. **Command palette sections** — `CommandPalette.swift`. Grouped by category with section headers when not searching.
D. **Clickable markdown links** — `ConversationView.swift`. `.tint(theme.sky)` + underline on link runs.
E. **Vibe mode consistency** — `WelcomeView.swift`, `HelpOverlay.swift`. Simplified views in vibe mode.
F. **Git ahead/behind** — `AppShell.swift`. Shows "+2/-1" next to branch name via `git rev-list --left-right --count`.
G. **Terminal passthrough bar** — Already existed (`AppShell.swift:1831`). Ctrl+T opens command bar.

### v2.2.0 Changes (5 Smart Cost Controls)

**Problem:** $16.62 for a single session. Effort always "high", no budget cap, model router too conservative, no visibility into per-turn cost, no context loss detection.

**Changes:**
1. **Smart Effort Routing** (`ClaudeProcess.swift`) — Default changed from `high` to `medium`. New `SmartEffortRouter` auto-classifies messages: conversational→low, general→medium, complex work→high. Toggle "Smart (Auto)" in effort picker. ~30-50% token reduction.
2. **Default $5 Budget Cap** (`ClaudeProcess.swift`) — `maxBudgetUSD` changed from 0 (unlimited) to 5.0. Budget options: $5, $10, $25, $50, unlimited. Always visible in status bar.
3. **Expanded ModelRouter** (`ModelRouter.swift`) — Added conversational message detection (Haiku for "yes", "go ahead", "wait" etc). Added medium-complexity routing to Sonnet. Much more aggressive downgrading for non-code messages. ~10-20% cost savings.
4. **Empty Response Detection** (`ClaudeProcess.swift`, `ConversationView.swift`, `AppShell.swift`) — Detects <10 char response after >5s delay. Shows warning banner with Retry / New Session / Dismiss options. Catches context loss like the bug in the screenshot.
5. **Per-Turn Cost Display** (`StatusBar.swift`, `ClaudeProcess.swift`) — Shows `(+$0.XX)` next to session total. Turns >$0.50 highlighted in rose. Gives real-time visibility into which messages are expensive.

**Files changed:**
- `Sources/Services/ClaudeProcess.swift` — SmartEffortRouter, default budget, lastTurnCostUSD, lastUserMessage, onEmptyResponse callback, smartEffort toggle
- `Sources/Services/ModelRouter.swift` — isConversational(), isComplexWork(), expanded routing rules
- `Sources/Views/StatusBar.swift` — per-turn cost display, smart effort picker with Auto toggle, always-visible budget
- `Sources/Views/ConversationView.swift` — EmptyResponseWarning view
- `Sources/Views/AppShell.swift` — wired onEmptyResponse, empty response warning state, budget cycling updated

**Build:** SUCCEEDED (ad-hoc signed)
**Not yet:** committed, pushed, released, installed

### v2.1.0 Changes (10 Token Optimizations + 2 UX Fixes)

**Token Efficiency (all 10 applied):**
1. `ContextStateManager.swift` — Fixed context % to use per-turn input tokens (was using meaningless cumulative totals)
2. `SessionCloseoutManager.swift` — Removed wasteful Claude round-trip on session close (~160K tokens saved/session)
3. `AppShell.swift` — Trimmed system prompt from ~700 to ~150 tokens
4. `AppShell.swift` — Deduplicated pinned message injection (only on change or post-compaction)
5. `CompactionEngine.swift` — Removed post-compaction acknowledge round-trip
6. `ContextPreservationPipeline.swift` — Stopped tracking Read tool calls as file modifications
7. `ModelRouter.swift` — Enabled auto-routing by default (Haiku for simple lookups)
8. `AgentOrchestrator.swift` — Sub-agents inherit optimizations from main process
9. `ClaudeProcess.swift` — Capped events array at 200 entries
10. `PerformanceDashboard.swift` — Wired ContextBudgetOptimizer suggestions into UI

**UX Fixes:**
- `InputBar.swift` — Fixed multiline cursor: enabled overlay scroller so all lines are clickable
- `InputBar.swift` — File drop spacing: `\n\n` blank lines before/after `@path` for visual separation (drag-drop, paste, onFileDrop callback)

### Previous Changes (v1.0.0 → v1.1.0, still included)

- Bloat removed (7 files: MoodBoard, EvolutionAgent, SharedIntelligence, FeatureDetector)
- Smart auto-scroll, up-arrow message history, input placeholder text
- macOS notification on background completion, clipboard image paste
- Image attachment strip, dynamic input bar height, window naming
- TemplateScaffolder, text selection, status bar cleanup, terminal-style title bar
- v1.1.0 build was installed to /Applications/Conductor v1.1.app

**Still on roadmap:**
- App icon (still default Xcode globe)
- Notarization (needs Apple ID app-specific password)
- API key support (monetization path — users bring their own key)
- Landing page
- Sparkle auto-updates

---

## What Changed From Original Conductor

### 1. New 5-Step Guided Onboarding (`Sources/Views/OnboardingView.swift`)
Complete rewrite of the 3-step onboarding into a 5-step guided wizard:
- **Step 1: Welcome** — explains Conductor + shows live checklist
- **Step 2: Node.js Check** — auto-detects, shows version
- **Step 3: Claude CLI Install** — "Install Now" button runs `npm install -g @anthropic-ai/claude-code`
- **Step 4: Authentication** — guides through `claude auth login`
- **Step 5: Shortcuts** — key shortcuts overview

### 2. System Action Confirmation Cards
Before ANY action that triggers a macOS system dialog, onboarding shows an explanation card.

### 3. Default Permission Mode Changed
- Original: `CLIPermissionMode.bypassPermissions`
- Public: `CLIPermissionMode.default_` (asks before edits and commands)

### 4. Code Signing for Distribution
- Release builds use: `Developer ID Application: JESSE ROBERT MERIA (36D97ZTP6J)`
- Release script handles signing automatically

---

## How to Push Updates

### One-Command Release
```bash
cd "/Users/jesse/Documents/meria-os/conductor-public"
./scripts/release.sh 1.1.0 "What changed in this version"
```

This does everything:
1. Updates version in `project.yml`
2. Regenerates Xcode project (`xcodegen generate`)
3. Builds Release config signed with Developer ID cert
4. Zips to `releases/Conductor-v{VERSION}.zip`
5. Commits + pushes to GitHub
6. Creates GitHub release with the zip attached

---

## DISTRIBUTION PLAN — Path to Revenue

### Phase 1: Polish & Stability (Current)
- [x] Core UX improvements (auto-scroll, message history, paste images, etc.)
- [x] Strip bloat features (7 files removed)
- [ ] Notarization (removes Gatekeeper warning)
- [ ] App icon design
- [ ] Test with 2-3 friends, collect feedback
- [ ] Fix any showstopper bugs

### Phase 2: Direct API Support
**Why:** Current approach requires users to install Node.js + Claude CLI + authenticate — too much friction. Direct API support means: paste API key, start using.

**Implementation:**
- Add API key input in settings/onboarding (stored in Keychain)
- Build direct Anthropic API client (streaming, tool use parsing)
- Support BOTH: CLI backend (existing) and API backend (new)
- User chooses on first run: "I have Claude CLI" vs "I have an API key"
- Same UI, different backend

**Economics:**
- CLI users: pay Anthropic for Max subscription ($20/mo), Conductor is free or paid separately
- API users: pay per token (Sonnet ~$1-2/session, Opus ~$5-8/session)
- Jesse pays $0 for infrastructure either way

### Phase 3: Monetization
**Pricing model (Conductor itself):**
- Free: full app, unlimited use, single window
- Pro ($12-15/month): multi-agent orchestration, agent presets, performance dashboard, multi-window
- Team ($25/month): shared agent configs, team presets (future)

**Payment:** Lemonsqueezy or Gumroad (simplest for indie)
**License validation:** App checks license key on launch, stores in Keychain

### Phase 4: Distribution & Growth
- Landing page (conductorapp.dev or similar)
- Submit to Product Hunt
- Post in Claude/AI developer communities (Reddit, Discord, Twitter)
- YouTube walkthrough / demo video
- Sparkle auto-update framework for seamless updates

### Revenue Targets
- 50 paying users at $12/mo = $600/mo
- 200 paying users at $12/mo = $2,400/mo
- 500 paying users at $15/mo = $7,500/mo

**Why this could work:**
- Conductor is genuinely the best way to use Claude CLI on macOS
- No real competitor does: multi-agent, vibe mode, dashboard, sessions, context management, image paste, all in a native macOS app
- Claude Code is exploding in popularity — wrapper market is wide open
- Zero marginal cost (users bring their own API key/subscription)

---

## Architecture Notes

### Relationship to Original Conductor
- **Original:** `/Users/jesse/Documents/meria-os/claude-terminal/Conductor/` — Jesse's daily driver, DO NOT TOUCH
- **Public:** `/Users/jesse/Documents/meria-os/conductor-public/` — this project, for distribution
- These are separate git repos. Changes to one don't affect the other.

### Signing Certificates Available
```
Apple Development: JESSE ROBERT MERIA (6KQW73VUKS)
Developer ID Application: JESSE ROBERT MERIA (36D97ZTP6J)  <- used for releases
Apple Distribution: JESSE ROBERT MERIA (36D97ZTP6J)
```

---

## Build Status
- **Compiles:** YES (BUILD SUCCEEDED)
- **Signed:** YES (Developer ID Application)
- **Version:** 3.0.0
- **Released on GitHub:** v1.0.0 only — v2.1.0/v2.2.0/v3.0.0 committed but not pushed/released
- **Installed:** /Applications/Conductor.app (v3.0.0)
- **Desktop zip:** ~/Desktop/Conductor.zip (v3.0.0, Developer ID signed, 2.5MB)
- **Notarized:** YES (Mar 8, 2026). Keychain profile: `"Conductor"`. Gatekeeper: accepted, source=Notarized Developer ID.
- **Notarize command:** `xcrun notarytool submit app.zip --keychain-profile "Conductor" --wait && xcrun stapler staple Conductor.app`
- **Build flags for notarization:** `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO OTHER_CODE_SIGN_FLAGS="--options=runtime --timestamp"`
