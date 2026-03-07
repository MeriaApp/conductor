# Context State — Conductor (Public Distribution Version)

*Last updated: March 7, 2026*

## What This Is

This is the **distributable version** of Conductor, forked from the original at `claude-terminal/Conductor/`. The original stays untouched (Jesse runs it daily). This version is modified for other users to install and use.

**Repo:** `MeriaApp/conductor` (private) — https://github.com/MeriaApp/conductor
**Codebase:** `/Users/jesse/Documents/meria-os/conductor-public/`

---

## Current State: v1.0.0 RELEASED + Post-Release Improvements

- GitHub release live at `https://github.com/MeriaApp/conductor/releases/tag/v1.0.0`
- Signed with Developer ID Application cert (Jesse's)
- NOT notarized yet — users need to right-click > Open first time

### Changes Since v1.0.0 (not yet released)

**Bloat Removed (7 files deleted):**
- MoodBoardEngine + MoodBoardView + MoodBoard model — design moodboard nobody used
- EvolutionAgent — "self-improvement engine" that ran background timers for nothing
- SharedIntelligence — cross-project knowledge registry, cool concept, zero practical value
- FeatureDetector + FeatureMapOverlay — meta-UI about the app's own features
- All references cleaned from AppShell, ConductorApp, SessionStateContainer, ProjectSwitcher

**Features Added:**
- Smart auto-scroll — locks to bottom during streaming, stays put when user scrolls up, magnets back when user scrolls to bottom. "Jump to bottom" button when scrolled up.
- Up-arrow message history — press up/down to recall previous messages (like Terminal)
- Input placeholder text — "Message Claude..." shown in normal mode (vibe mode shows "What do you want to build?")
- macOS notification when Claude finishes in background — if app is unfocused, notification banner appears
- Clipboard image paste (Cmd+V screenshots) — auto-converts TIFF to PNG
- Image attachment strip — drag/drop images appear as thumbnails, not inline text
- Dynamic input bar height — starts compact, grows with content, max 200px
- Window naming — click tag icon in status bar to label windows
- Smaller minimum window size (480x300, down from 700x500)
- TemplateScaffolder — auto-scaffolds optimized ~/.claude/ (user-level) and .claude/ (project-level) with rules + skills
  - User-level: CLAUDE.md + rules/coding-standards.md + rules/git-workflow.md (created on first run + onboarding)
  - Project-level: CLAUDE.md, CONTEXT_STATE.md, rules/anti-patterns.md, rules/verification.md, skills/debug, skills/audit, skills/release (prompted when opening a new directory)
  - Never overwrites existing files
- Removed redundant Resources/Templates/ directory (content embedded in TemplateScaffolder.swift)
- Updated CLAUDE.md to reflect actual file structure (removed 7 deleted file references)
- Text selection — `.textSelection(.enabled)` moved to LazyVStack container level for cross-paragraph drag selection
- Status bar cleanup — removed Cmd+K hint, "? for help", empty Name placeholder, removed dividers between right-side controls, tightened spacing (16→10), fixed model suggestion pill overflow (dropped reason text, lineLimit+fixedSize)
- Terminal-style title bar — shows "folder — model — Conductor" instead of just "Conductor"
- WelcomeView cleaned — removed Feature Map and Moodboard from feature grid (deleted features)
- v1.1.0 build installed to /Applications/Conductor v1.1.app

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
- **Released:** v1.0.0 on GitHub
- **Post-release changes:** Built and verified, not yet released
- **Notarized:** No (future work)
