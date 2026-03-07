# Context State — Conductor (Public Distribution Version)

*Last updated: March 7, 2026 (Initial Setup Session)*

## What This Is

This is the **distributable version** of Conductor, forked from the original at `claude-terminal/Conductor/`. The original stays untouched (Jesse runs it daily). This version is modified for other users to install and use.

**Repo:** `MeriaApp/conductor` (private) — https://github.com/MeriaApp/conductor
**Codebase:** `/Users/jesse/Documents/meria-os/conductor-public/`

---

## Current State: v1.0.0 RELEASED

- GitHub release live at `https://github.com/MeriaApp/conductor/releases/tag/v1.0.0`
- Signed zip on Desktop: `~/Desktop/Conductor-v1.0.0.zip` (2.6MB)
- Signed with Developer ID Application cert (Jesse's)
- NOT notarized yet — friend needs to right-click > Open first time

---

## What Changed From Original Conductor

### 1. New 5-Step Guided Onboarding (`Sources/Views/OnboardingView.swift`)
Complete rewrite of the 3-step onboarding into a 5-step guided wizard:
- **Step 1: Welcome** — explains Conductor + shows live checklist (Node.js, CLI, Auth) with green checkmarks
- **Step 2: Node.js Check** — auto-detects, shows version. If missing: links to nodejs.org + Homebrew instructions
- **Step 3: Claude CLI Install** — "Install Now" button runs `npm install -g @anthropic-ai/claude-code`. Shows progress, handles errors
- **Step 4: Authentication** — guides through `claude auth login` (opens Terminal) or API key setup. "Test Connection" runs real prompt
- **Step 5: Shortcuts** — key shortcuts overview, "Get Started" button
- Navigation blocks if requirements aren't met (can't skip past Node.js if missing)
- "Skip setup" link for power users

### 2. System Action Confirmation Cards
**IMPORTANT PATTERN:** Before ANY action that could trigger a macOS system dialog (password prompt, keychain access, network permission), the onboarding shows an explanation card with:
- What command will run
- Why it needs access
- What the user will see
- "Go Ahead" / "Cancel" buttons

This was added because Jesse got a surprise keychain prompt during the build. The principle: **never surprise users with system dialogs — explain first, then let them confirm.**

Three confirmation cards exist:
- **CLI Install** — warns about potential password prompt for global npm install
- **Open Terminal** — explains it will open Terminal and run `claude auth login`
- **Test Connection** — explains it will send a test prompt and use API credits

### 3. Default Permission Mode Changed
- Original: `CLIPermissionMode.bypassPermissions` (auto-executes everything)
- Public: `CLIPermissionMode.default_` (asks before edits and commands)
- Changed in `Sources/Services/ClaudeProcess.swift` line 65

### 4. Code Signing for Distribution
- `project.yml`: DEVELOPMENT_TEAM cleared, CODE_SIGN_IDENTITY set to `-` (ad-hoc for dev builds)
- Release builds use: `Developer ID Application: JESSE ROBERT MERIA (36D97ZTP6J)`
- Release script handles signing automatically

---

## How to Push Updates

### One-Command Release
```bash
cd "/Users/jesse/Documents/meria-os/conductor-public"
./scripts/release.sh 1.0.1 "What changed in this version"
```

This does everything:
1. Updates version in `project.yml`
2. Regenerates Xcode project (`xcodegen generate`)
3. Builds Release config signed with Developer ID cert
4. Zips to `releases/Conductor-v{VERSION}.zip`
5. Commits + pushes to GitHub
6. Creates GitHub release with the zip attached

**NOTE:** First build after restart may trigger keychain prompt for Developer ID cert. Enter Mac login password and click "Always Allow".

### Manual Release Steps (if script fails)
```bash
cd "/Users/jesse/Documents/meria-os/conductor-public"
xcodegen generate
xcodebuild -scheme Conductor -destination 'platform=macOS' -configuration Release build \
  DEVELOPMENT_TEAM=36D97ZTP6J \
  CODE_SIGN_IDENTITY="Developer ID Application: JESSE ROBERT MERIA (36D97ZTP6J)" \
  CODE_SIGN_STYLE=Manual \
  ENABLE_HARDENED_RUNTIME=YES \
  OTHER_CODE_SIGN_FLAGS="--options=runtime"

# Find the built app
APP=$(find ~/Library/Developer/Xcode/DerivedData -name "Conductor.app" -path "*/Conductor-*/Release/*" | head -1)
ditto -c -k --keepParent "$APP" ~/Desktop/Conductor-vX.Y.Z.zip

# Create release
gh release create vX.Y.Z ~/Desktop/Conductor-vX.Y.Z.zip --title "Conductor vX.Y.Z" --notes "..."
```

---

## How Users Install

1. Download `Conductor-v{VERSION}.zip` from GitHub releases
2. Unzip, drag `Conductor.app` to `/Applications`
3. Double-click to open — if macOS warns, right-click > Open once (not notarized yet)
4. Onboarding wizard walks through: Node.js check → CLI install → Auth → Test → Shortcuts
5. Start using Conductor

---

## What's NOT Done Yet (Future Work)

### Notarization (removes Gatekeeper warning)
Need to store notarytool credentials first:
```bash
xcrun notarytool store-credentials "AC_PASSWORD" --apple-id YOUR_APPLE_ID --team-id 36D97ZTP6J
```
Then add to release script: `xcrun notarytool submit ... --wait`

### Sparkle Auto-Updates
Add Sparkle framework so the app checks for updates automatically. Users wouldn't need to manually download new versions.

### Freemium Model
- Free: full app, single window, no multi-agent
- Pro ($39 or $12/mo): multi-agent, agent presets, build-verify pipeline, performance dashboard, shared intelligence
- Payment via Gumroad or Lemonsqueezy

### Landing Page / Website
- conductorapp.com or similar
- Screenshots, features, download button
- Could be a page on meria.agency

### App Icon
- Currently using system icon placeholder
- Need a proper icon in `Resources/Assets.xcassets/AppIcon.appiconset/`

---

## Architecture Notes

### Relationship to Original Conductor
- **Original:** `/Users/jesse/Documents/meria-os/claude-terminal/Conductor/` — Jesse's daily driver, DO NOT TOUCH
- **Public:** `/Users/jesse/Documents/meria-os/conductor-public/` — this project, for distribution
- These are separate git repos. Changes to one don't affect the other.
- To port features FROM original TO public: manually copy the changed files and rebuild

### Key Files Changed From Original
| File | What Changed |
|------|-------------|
| `Sources/Views/OnboardingView.swift` | Complete rewrite — 5-step wizard with system action confirmations |
| `Sources/Services/ClaudeProcess.swift` | Default permission mode: `bypassPermissions` → `default_` |
| `project.yml` | Dev team cleared, ad-hoc signing for dev builds |
| `CLAUDE.md` | Build commands updated for public project path |
| `scripts/release.sh` | NEW — one-command build+sign+zip+push+release |
| `.gitignore` | NEW — ignores releases/, *.xcodeproj, DerivedData/ |

### Signing Certificates Available
```
Apple Development: JESSE ROBERT MERIA (6KQW73VUKS)
Developer ID Application: JESSE ROBERT MERIA (36D97ZTP6J)  ← used for releases
Apple Distribution: JESSE ROBERT MERIA (36D97ZTP6J)
```

---

## Build Status
- **Compiles:** YES (BUILD SUCCEEDED)
- **Signed:** YES (Developer ID Application)
- **Released:** v1.0.0 on GitHub
- **Notarized:** No (future work)
