import Foundation

/// Manages Claude Code Safeguards — screenshot hook, binary deny rules, quality rules.
/// Handles installation to both user-level (~/.claude/) and project-level (.claude/).
/// Reads/writes settings.json for hooks and deny rules. Copies hook scripts and rule files.
@MainActor
final class SafeguardsManager: ObservableObject {
    static let shared = SafeguardsManager()

    // MARK: - Published State

    @Published var isScreenshotHookInstalled = false
    @Published var isScreenshotHookEnabled = true
    @Published var binaryDenyRulesInstalled = false
    @Published var rulesFileCount = 0
    @Published var trackedImageFiles: [TrackedImage] = []

    // MARK: - Constants

    private static let screenshotHookFilename = "process-screenshot.sh"
    private static let blockDestructiveHookFilename = "block-destructive-commands.sh"
    private static let saveContextHookFilename = "save-context-before-compact.sh"
    private static let maxTrackedImages = 20

    /// Binary file extensions that should be denied
    static let binaryDenyPatterns = [
        "Read(*.mp4)", "Read(*.mov)", "Read(*.avi)", "Read(*.mkv)",
        "Read(*.mp3)", "Read(*.wav)", "Read(*.flac)", "Read(*.aac)",
        "Read(*.zip)", "Read(*.tar.gz)", "Read(*.rar)", "Read(*.7z)",
        "Read(*.dmg)", "Read(*.iso)",
        "Read(*.psd)", "Read(*.ai)", "Read(*.sketch)", "Read(*.fig)",
    ]

    /// Safeguard rule file content (embedded — no external dependency)
    static let safeguardRules: [(filename: String, content: String)] = [
        ("binary-file-handling.md", Rules.binaryFileHandling),
        ("context-management.md", Rules.contextManagement),
        ("quality-standard.md", Rules.qualityStandard),
        ("git-workflow.md", Rules.gitWorkflow),
        ("coding-standards.md", Rules.codingStandards),
        ("gemini-orchestration.md", Rules.geminiOrchestration),
        ("full-app-audit.md", Rules.fullAppAudit),
        ("file-hygiene.md", Rules.fileHygiene),
        ("screenshots.md", Rules.screenshots),
        ("capabilities.md", Rules.capabilities),
    ]

    private let fileManager = FileManager.default

    // MARK: - Paths

    private var homePath: String { fileManager.homeDirectoryForCurrentUser.path }
    private var globalClaudeDir: String { "\(homePath)/.claude" }
    private var globalHooksDir: String { "\(globalClaudeDir)/hooks" }
    private var globalRulesDir: String { "\(globalClaudeDir)/rules" }
    private var globalSettingsPath: String { "\(globalClaudeDir)/settings.json" }

    // MARK: - Init

    private init() {
        checkInstallationState()
    }

    // MARK: - Installation State Check

    func checkInstallationState() {
        // Screenshot hook
        let hookPath = "\(globalHooksDir)/\(Self.screenshotHookFilename)"
        isScreenshotHookInstalled = fileManager.fileExists(atPath: hookPath)

        // Check if hook is registered in settings.json
        if let settings = readSettings(at: globalSettingsPath) {
            isScreenshotHookEnabled = settingsContainScreenshotHook(settings)
            binaryDenyRulesInstalled = settingsContainDenyRules(settings)
        }

        // Count installed safeguard rules
        rulesFileCount = Self.safeguardRules.filter { filename, _ in
            fileManager.fileExists(atPath: "\(globalRulesDir)/\(filename)")
        }.count
    }

    // MARK: - Global Install (User-Level ~/.claude/)

    /// Install all safeguards to ~/.claude/ — hooks, deny rules, rule files.
    /// Safe to call multiple times. Merges with existing settings, never overwrites rules.
    func installGlobally() {
        createDirIfNeeded(globalHooksDir)
        createDirIfNeeded(globalRulesDir)

        installScreenshotHook(hooksDir: globalHooksDir)
        installBlockDestructiveHook(hooksDir: globalHooksDir)
        installSaveContextHook(hooksDir: globalHooksDir)
        installDenyRules(settingsPath: globalSettingsPath)
        registerScreenshotHookInSettings(settingsPath: globalSettingsPath, hooksDir: globalHooksDir)
        registerBlockDestructiveHookInSettings(settingsPath: globalSettingsPath, hooksDir: globalHooksDir)
        registerSaveContextHookInSettings(settingsPath: globalSettingsPath, hooksDir: globalHooksDir)
        installRuleFiles(rulesDir: globalRulesDir)

        checkInstallationState()
    }

    /// Remove all safeguards from ~/.claude/
    func uninstallGlobally() {
        removeScreenshotHook(hooksDir: globalHooksDir)
        removeDenyRules(settingsPath: globalSettingsPath)
        removeScreenshotHookFromSettings(settingsPath: globalSettingsPath)
        removeRuleFiles(rulesDir: globalRulesDir)

        checkInstallationState()
    }

    // MARK: - Project-Level Install

    /// Install safeguards into a project's .claude/ directory
    func installForProject(at projectDir: URL) {
        let claudeDir = projectDir.appendingPathComponent(".claude")
        let hooksDir = claudeDir.appendingPathComponent("hooks").path
        let rulesDir = claudeDir.appendingPathComponent("rules").path
        let settingsPath = claudeDir.appendingPathComponent("settings.json").path

        createDirIfNeeded(hooksDir)
        createDirIfNeeded(rulesDir)

        installScreenshotHook(hooksDir: hooksDir)
        installBlockDestructiveHook(hooksDir: hooksDir)
        installSaveContextHook(hooksDir: hooksDir)
        installRuleFiles(rulesDir: rulesDir)

        // Project-level settings.json for deny rules and hooks
        installDenyRules(settingsPath: settingsPath)
        registerScreenshotHookInSettings(settingsPath: settingsPath, hooksDir: hooksDir)
        registerBlockDestructiveHookInSettings(settingsPath: settingsPath, hooksDir: hooksDir)
        registerSaveContextHookInSettings(settingsPath: settingsPath, hooksDir: hooksDir)
    }

    // MARK: - Screenshot Hook Toggle

    func enableScreenshotHook() {
        registerScreenshotHookInSettings(settingsPath: globalSettingsPath, hooksDir: globalHooksDir)
        isScreenshotHookEnabled = true
    }

    func disableScreenshotHook() {
        removeScreenshotHookFromSettings(settingsPath: globalSettingsPath)
        isScreenshotHookEnabled = false
    }

    // MARK: - Image Tracking

    /// Track an image file that was read or referenced in the conversation.
    /// Used by ContextStateManager to warn about large images in context.
    func trackImageFile(path: String, estimatedTokens: Int) {
        let image = TrackedImage(path: path, estimatedTokens: estimatedTokens, timestamp: Date())

        // Deduplicate by path
        if !trackedImageFiles.contains(where: { $0.path == path }) {
            trackedImageFiles.append(image)
            if trackedImageFiles.count > Self.maxTrackedImages {
                trackedImageFiles.removeFirst()
            }
        }
    }

    /// Total estimated tokens from tracked images
    var totalImageTokens: Int {
        trackedImageFiles.reduce(0) { $0 + $1.estimatedTokens }
    }

    /// Clear image tracking (e.g., on session restart)
    func clearTrackedImages() {
        trackedImageFiles.removeAll()
    }

    // MARK: - Private: Screenshot Hook Install/Remove

    private func installScreenshotHook(hooksDir: String) {
        let hookPath = "\(hooksDir)/\(Self.screenshotHookFilename)"
        guard !fileManager.fileExists(atPath: hookPath) else { return }

        try? HookScript.screenshotHook.write(
            toFile: hookPath, atomically: true, encoding: .utf8
        )

        // Make executable
        try? fileManager.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: hookPath
        )
    }

    private func removeScreenshotHook(hooksDir: String) {
        let hookPath = "\(hooksDir)/\(Self.screenshotHookFilename)"
        try? fileManager.removeItem(atPath: hookPath)
    }

    private func installBlockDestructiveHook(hooksDir: String) {
        let hookPath = "\(hooksDir)/\(Self.blockDestructiveHookFilename)"
        guard !fileManager.fileExists(atPath: hookPath) else { return }

        try? HookScript.blockDestructiveCommands.write(
            toFile: hookPath, atomically: true, encoding: .utf8
        )

        try? fileManager.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: hookPath
        )
    }

    private func installSaveContextHook(hooksDir: String) {
        let hookPath = "\(hooksDir)/\(Self.saveContextHookFilename)"
        guard !fileManager.fileExists(atPath: hookPath) else { return }

        try? HookScript.saveContextBeforeCompact.write(
            toFile: hookPath, atomically: true, encoding: .utf8
        )

        try? fileManager.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: hookPath
        )
    }

    // MARK: - Private: Settings.json Hooks Registration

    private func registerScreenshotHookInSettings(settingsPath: String, hooksDir: String) {
        var settings = readSettings(at: settingsPath) ?? [:]
        let hookPath = "\(hooksDir)/\(Self.screenshotHookFilename)"

        // Check if already registered
        if settingsContainScreenshotHook(settings) { return }

        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        var preToolUse = hooks["PreToolUse"] as? [[String: Any]] ?? []

        preToolUse.append([
            "command": hookPath,
            "matcher": "Read",
        ])

        hooks["PreToolUse"] = preToolUse
        settings["hooks"] = hooks
        writeSettings(settings, to: settingsPath)
    }

    private func removeScreenshotHookFromSettings(settingsPath: String) {
        guard var settings = readSettings(at: settingsPath) else { return }
        guard var hooks = settings["hooks"] as? [String: Any] else { return }
        guard var preToolUse = hooks["PreToolUse"] as? [[String: Any]] else { return }

        preToolUse.removeAll { entry in
            let command = entry["command"] as? String ?? ""
            return command.contains(Self.screenshotHookFilename)
        }

        if preToolUse.isEmpty {
            hooks.removeValue(forKey: "PreToolUse")
        } else {
            hooks["PreToolUse"] = preToolUse
        }

        if hooks.isEmpty {
            settings.removeValue(forKey: "hooks")
        } else {
            settings["hooks"] = hooks
        }

        writeSettings(settings, to: settingsPath)
    }

    private func settingsContainScreenshotHook(_ settings: [String: Any]) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any],
              let preToolUse = hooks["PreToolUse"] as? [[String: Any]] else { return false }
        return preToolUse.contains { entry in
            let command = entry["command"] as? String ?? ""
            return command.contains(Self.screenshotHookFilename)
        }
    }

    private func registerBlockDestructiveHookInSettings(settingsPath: String, hooksDir: String) {
        var settings = readSettings(at: settingsPath) ?? [:]
        let hookPath = "\(hooksDir)/\(Self.blockDestructiveHookFilename)"

        // Check if already registered
        if settingsContainHook(settings, event: "PreToolUse", filename: Self.blockDestructiveHookFilename) { return }

        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        var preToolUse = hooks["PreToolUse"] as? [[String: Any]] ?? []

        preToolUse.append([
            "command": hookPath,
            "matcher": "Bash",
        ])

        hooks["PreToolUse"] = preToolUse
        settings["hooks"] = hooks
        writeSettings(settings, to: settingsPath)
    }

    private func registerSaveContextHookInSettings(settingsPath: String, hooksDir: String) {
        var settings = readSettings(at: settingsPath) ?? [:]
        let hookPath = "\(hooksDir)/\(Self.saveContextHookFilename)"

        // Check if already registered
        if settingsContainHook(settings, event: "PreCompact", filename: Self.saveContextHookFilename) { return }

        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        var preCompact = hooks["PreCompact"] as? [[String: Any]] ?? []

        preCompact.append([
            "command": hookPath,
        ])

        hooks["PreCompact"] = preCompact
        settings["hooks"] = hooks
        writeSettings(settings, to: settingsPath)
    }

    private func settingsContainHook(_ settings: [String: Any], event: String, filename: String) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any],
              let entries = hooks[event] as? [[String: Any]] else { return false }
        return entries.contains { entry in
            let command = entry["command"] as? String ?? ""
            return command.contains(filename)
        }
    }

    // MARK: - Private: Deny Rules

    private func installDenyRules(settingsPath: String) {
        var settings = readSettings(at: settingsPath) ?? [:]
        var permissions = settings["permissions"] as? [String: Any] ?? [:]
        var denyList = permissions["deny"] as? [String] ?? []

        // Merge — add only missing patterns
        for pattern in Self.binaryDenyPatterns {
            if !denyList.contains(pattern) {
                denyList.append(pattern)
            }
        }

        permissions["deny"] = denyList
        settings["permissions"] = permissions
        writeSettings(settings, to: settingsPath)
    }

    private func removeDenyRules(settingsPath: String) {
        guard var settings = readSettings(at: settingsPath),
              var permissions = settings["permissions"] as? [String: Any],
              var denyList = permissions["deny"] as? [String] else { return }

        denyList.removeAll { Self.binaryDenyPatterns.contains($0) }

        if denyList.isEmpty {
            permissions.removeValue(forKey: "deny")
        } else {
            permissions["deny"] = denyList
        }

        if permissions.isEmpty {
            settings.removeValue(forKey: "permissions")
        } else {
            settings["permissions"] = permissions
        }

        writeSettings(settings, to: settingsPath)
    }

    private func settingsContainDenyRules(_ settings: [String: Any]) -> Bool {
        guard let permissions = settings["permissions"] as? [String: Any],
              let denyList = permissions["deny"] as? [String] else { return false }
        // Check if at least half the expected deny rules are present
        let matchCount = Self.binaryDenyPatterns.filter { denyList.contains($0) }.count
        return matchCount >= Self.binaryDenyPatterns.count / 2
    }

    // MARK: - Private: Rule Files

    private func installRuleFiles(rulesDir: String) {
        for (filename, content) in Self.safeguardRules {
            let path = "\(rulesDir)/\(filename)"
            guard !fileManager.fileExists(atPath: path) else { continue }
            try? content.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    private func removeRuleFiles(rulesDir: String) {
        for (filename, _) in Self.safeguardRules {
            let path = "\(rulesDir)/\(filename)"
            try? fileManager.removeItem(atPath: path)
        }
    }

    // MARK: - Private: Settings I/O

    private func readSettings(at path: String) -> [String: Any]? {
        guard let data = fileManager.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    private func writeSettings(_ settings: [String: Any], to path: String) {
        // Ensure parent directory exists
        let dir = (path as NSString).deletingLastPathComponent
        createDirIfNeeded(dir)

        guard let data = try? JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return }

        try? data.write(to: URL(fileURLWithPath: path))
    }

    private func createDirIfNeeded(_ path: String) {
        if !fileManager.fileExists(atPath: path) {
            try? fileManager.createDirectory(
                atPath: path, withIntermediateDirectories: true
            )
        }
    }
}

// MARK: - Tracked Image

struct TrackedImage: Identifiable {
    let id = UUID()
    let path: String
    let estimatedTokens: Int
    let timestamp: Date

    var filename: String {
        (path as NSString).lastPathComponent
    }
}

// MARK: - Embedded Hook Script

private enum HookScript {

    static let screenshotHook = """
    #!/bin/bash
    # Hook: process-screenshot (PreToolUse on Read)
    # Intercepts image file reads, resizes, files into project screenshots/, blocks original read.
    # Exit 2 = block + stderr shown to Claude as feedback.
    # Exit 0 = allow read through (non-image files, already-filed screenshots).

    input=$(cat)
    tool_name=$(echo "$input" | jq -r '.tool_name // empty' 2>/dev/null || echo "")

    [ "$tool_name" != "Read" ] && exit 0

    file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo "")
    [ -z "$file_path" ] && exit 0

    # Allow reads from already-filed screenshots
    [[ "$file_path" == */screenshots/* ]] && exit 0

    # Check if image by extension
    ext="${file_path##*.}"
    ext_lower=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
    case "$ext_lower" in
      png|jpg|jpeg|gif|webp|heic|heif|tiff|bmp) ;;
      *) exit 0 ;;
    esac

    # File must exist
    [ ! -f "$file_path" ] && exit 0

    # Get file size for reporting
    file_size=$(stat -f%z "$file_path" 2>/dev/null || stat -c%s "$file_path" 2>/dev/null || echo "0")

    # Determine project root from hook's cwd field, then git, then pwd
    hook_cwd=$(echo "$input" | jq -r '.cwd // empty' 2>/dev/null || echo "")
    if [ -n "$hook_cwd" ] && [ -d "$hook_cwd" ]; then
      project_root="$hook_cwd"
    elif git rev-parse --show-toplevel >/dev/null 2>&1; then
      project_root=$(git rev-parse --show-toplevel)
    else
      project_root=$(pwd)
    fi

    screenshots_dir="${project_root}/screenshots"
    mkdir -p "$screenshots_dir"

    # Generate unique filename: YYYYMMDD_HHMMSS + collision avoidance
    timestamp=$(date +%Y%m%d_%H%M%S)
    counter=0
    output="${screenshots_dir}/${timestamp}.${ext_lower}"
    while [ -f "$output" ]; do
      ((counter++))
      output="${screenshots_dir}/${timestamp}_${counter}.${ext_lower}"
    done

    # --- macOS: use sips (built-in) ---
    if command -v sips >/dev/null 2>&1; then
      if ! sips -g pixelWidth "$file_path" >/dev/null 2>&1; then
        cp "$file_path" "$output" 2>/dev/null || exit 0
        echo "Screenshot filed (format not resizable): ${output}" >&2
        echo "Use an Agent to read and parse the screenshot at: ${output}" >&2
        exit 2
      fi

      current_width=$(sips -g pixelWidth "$file_path" 2>/dev/null | awk '/pixelWidth/ {print $2}')

      if [ -n "$current_width" ] && [ "$current_width" -gt 1400 ] 2>/dev/null; then
        sips --resampleWidth 1400 "$file_path" --out "$output" >/dev/null 2>&1 || cp "$file_path" "$output" 2>/dev/null
      else
        cp "$file_path" "$output" 2>/dev/null
      fi

      final_dims=$(sips -g pixelWidth -g pixelHeight "$output" 2>/dev/null | awk '/pixel/ {print $2}' | tr '\\n' 'x' | sed 's/x$//')

    # --- Linux: use ImageMagick if available, otherwise just copy ---
    elif command -v convert >/dev/null 2>&1; then
      current_width=$(identify -format "%w" "$file_path" 2>/dev/null || echo "0")

      if [ -n "$current_width" ] && [ "$current_width" -gt 1400 ] 2>/dev/null; then
        convert "$file_path" -resize 1400x "$output" 2>/dev/null || cp "$file_path" "$output" 2>/dev/null
      else
        cp "$file_path" "$output" 2>/dev/null
      fi

      final_dims=$(identify -format "%wx%h" "$output" 2>/dev/null || echo "?")

    # --- No image tools: just copy ---
    else
      cp "$file_path" "$output" 2>/dev/null
      final_dims="unknown"
    fi

    # Verify output
    if [ ! -f "$output" ]; then
      exit 0
    fi

    # Get final size (macOS stat vs Linux stat)
    final_size=$(stat -f%z "$output" 2>/dev/null || stat -c%s "$output" 2>/dev/null || echo "?")

    # Cleanup: keep only 50 most recent screenshots (works on macOS + Linux)
    ls -t "$screenshots_dir"/* 2>/dev/null | tail -n +51 | xargs rm -f 2>/dev/null || true

    # Block the original read — stderr goes to Claude as feedback
    echo "Screenshot filed to: ${output}" >&2
    echo "Dimensions: ${final_dims} | Size: ${final_size} bytes (original: ${file_size} bytes)" >&2
    echo "" >&2
    echo "DO NOT read the original temp file. Use an Agent to read and fully parse the filed screenshot at:" >&2
    echo "${output}" >&2
    exit 2
    """

    static let blockDestructiveCommands = """
    #!/bin/bash
    # Hook: block-destructive-commands (PreToolUse on Bash)
    # Blocks dangerous commands that could destroy work or compromise security.
    # Exit 2 = block + stderr shown to Claude as feedback.

    input=$(cat)
    tool_name=$(echo "$input" | jq -r '.tool_name // empty' 2>/dev/null || echo "")

    [ "$tool_name" != "Bash" ] && exit 0

    command=$(echo "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
    [ -z "$command" ] && exit 0

    # Block rm -rf / rm -fr (suggest trash instead)
    if echo "$command" | grep -qE 'rm\\s+-(rf|fr)\\s'; then
      echo "BLOCKED: rm -rf is destructive and irreversible." >&2
      echo "Use 'trash' (brew install trash) or move to a temp directory instead." >&2
      echo "If you truly need to delete, ask the user for explicit confirmation first." >&2
      exit 2
    fi

    # Block git push --force
    if echo "$command" | grep -qE 'git\\s+push.*--force'; then
      echo "BLOCKED: Force push is destructive and can overwrite remote history." >&2
      echo "Use 'git push' without --force, or ask the user for explicit confirmation." >&2
      exit 2
    fi

    # Block direct push to main/master
    if echo "$command" | grep -qE 'git\\s+push\\s+(origin\\s+)?(main|master)\\b'; then
      current_branch=$(git branch --show-current 2>/dev/null || echo "")
      if [ "$current_branch" = "main" ] || [ "$current_branch" = "master" ]; then
        echo "BLOCKED: Pushing directly to $current_branch." >&2
        echo "Create a feature branch first, or ask the user for explicit confirmation." >&2
        exit 2
      fi
    fi

    # Block sudo
    if echo "$command" | grep -qE '^\\s*sudo\\s'; then
      echo "BLOCKED: sudo commands require explicit user confirmation." >&2
      echo "Describe what you need to do and ask the user to run it manually." >&2
      exit 2
    fi

    # Block pipe-to-shell attacks
    if echo "$command" | grep -qE '(curl|wget)\\s.*\\|\\s*(bash|sh|zsh)'; then
      echo "BLOCKED: Piping downloads directly to shell is a security risk." >&2
      echo "Download the script first, review it, then execute." >&2
      exit 2
    fi

    # Block disk-level destructive commands
    if echo "$command" | grep -qE '^\\s*(mkfs|dd|fdisk|diskutil\\s+eraseDisk)\\s'; then
      echo "BLOCKED: Disk-level operations are extremely destructive." >&2
      echo "Ask the user to run this manually after review." >&2
      exit 2
    fi

    exit 0
    """

    static let saveContextBeforeCompact = """
    #!/bin/bash
    # Hook: save-context-before-compact (PreCompact)
    # Before context gets compressed, inject project state so it survives compaction.
    # Stdout from PreCompact hooks is added to Claude's context.

    # Try common state file locations
    for state_file in \\
      "./CONTEXT_STATE.md" \\
      "./context_state.md" \\
      "./CLAUDE.md" \\
      "./.claude/CONTEXT_STATE.md"; do
      if [ -f "$state_file" ]; then
        echo "=== Project State (preserved from $state_file) ==="
        cat "$state_file"
        echo "=== End Project State ==="
        exit 0
      fi
    done

    # No state file found -- that's fine
    exit 0
    """
}

// MARK: - Embedded Rule Content

private enum Rules {

    static let binaryFileHandling = """
    # Binary & Image File Handling

    ## Screenshots Dropped Into Chat

    A PreToolUse hook (`~/.claude/hooks/process-screenshot.sh`) intercepts ALL image reads from non-screenshots locations. When triggered:

    1. Resizes to max 1400px wide (retina screenshots are typically 2x)
    2. Files into `<project-root>/screenshots/YYYYMMDD_HHMMSS.png`
    3. Blocks the original read (exit 2 -- stderr shown to you)
    4. Auto-cleans: keeps only 50 most recent screenshots

    **Your job when the hook fires:**
    - Read the stderr message -- it contains the filed path
    - Spawn an Agent to read and fully parse the filed screenshot at the path provided
    - Reference the filed path for all subsequent work
    - NEVER retry reading the original temp path

    **Passthrough (no hook):** Reads from any `*/screenshots/*` path go through normally.

    ## Non-Image Binary Files (video, audio, archives, design files)

    Hard-denied in settings.json. Use shell tools:
    - File info: `file <path>` or `mdls <path>`
    - Archives: `unzip -l <file>` or `tar -tzf <file>`
    - Video: `ffprobe -hide_banner <file> 2>&1 | head -20`

    ## Context Management

    - Run `/compact` proactively when context feels heavy -- don't wait for auto-compaction
    - Between unrelated tasks, use `/clear`
    - Never read files >5MB directly -- use `head`, `tail`, or targeted line ranges
    - For large logs: `wc -l <file>` first, then read specific ranges
    """

    static let contextManagement = """
    # Context Management

    ## Preventing Context Overflow

    - Run `/compact` proactively when context feels heavy -- don't wait for auto-compaction
    - Between unrelated tasks, use `/clear`
    - Never read files >5MB directly -- check size first with `stat` or `wc -c`, then use line ranges
    - For large logs: `wc -l <file>` first, then read specific ranges with offset/limit
    - If a Read is blocked by the screenshot hook, use an Agent to parse the filed version

    ## Session Hygiene

    - Start each session by reading project state (CLAUDE.md, CONTEXT_STATE.md if it exists)
    - Save important findings to files BEFORE context gets compressed -- compressed context loses detail
    - After significant changes, update CONTEXT_STATE.md (if the project uses one)
    - Use `/compact "preserve: <key details>"` with explicit instructions on what to keep

    ## Avoiding Common Traps

    - If stuck in a fix loop (same approach failing 2+ times), `/clear` and restart with a better prompt
    - Don't read entire large directories -- use Glob to find specific files, then read only what's needed
    - Binary files (images, video, archives) are handled by hooks/deny rules -- never try to read them raw
    """

    static let qualityStandard = """
    # Quality Standard

    Production-grade on first write. Every output -- code, design, copy -- is held to best-in-class or refined until it is.

    ## Core Rules

    1. **Do No Harm** -- Working code has value. No rewrites for aesthetics. Refactors require measurable benefit.
    2. **Context Before Action** -- Read the full code path before proposing changes. No assumption-based work.
    3. **Net Improvement** -- Every change must improve stability, performance, UX, or maintainability. If nothing improves, don't touch it.
    4. **Risk Control** -- State risk level. Keep diffs minimal. Avoid cascading changes.
    5. **Escalate** -- If you find architectural weakness or design debt, surface it. Don't silently build around it.
    6. **Never Lazy** -- No placeholder logic. No "good enough" passes. No skipping verification. Ship complete or don't ship.

    ## Code Standard

    - Deterministic, explicit, strongly typed
    - No swallowed errors, no hidden state mutation, no magic numbers
    - Concurrency-aware, async-safe
    - Production-ready on first write -- no TODO stubs
    - Latest frameworks, latest patterns

    ## Verification Gate

    Before claiming any task is done:
    1. Re-state intended outcome
    2. Diff review -- every changed file, ripple effects
    3. Full-path validation -- trace changed behavior
    4. Run: build (required), tests, lint
    5. Negative testing -- 3-5 edge cases
    """

    static let gitWorkflow = """
    # Git Workflow

    - Only commit when explicitly asked.
    - Stage specific files by name -- never git add -A blindly.
    - Commit messages: focus on "why" not "what." Imperative mood.
    - Create new commits. Don't amend unless explicitly asked.
    - Never force push to main/master.
    - Never skip hooks (--no-verify) unless explicitly asked.
    """

    static let codingStandards = """
    # Coding Standards

    - Always read a file before editing it. Never edit blind.
    - Prefer the smallest diff that achieves the goal.
    - Don't refactor surrounding code unless asked.
    - Don't add docstrings, comments, or type annotations to unchanged code.
    - If something is unused, delete it completely. No _unused renames.
    - Never hardcode secrets, tokens, or credentials.
    - Validate at system boundaries. Trust internal code.
    - No placeholder logic, no TODO stubs -- production-ready on first write.
    - No temporary patches. Find and fix root causes, not symptoms.
    """

    static let geminiOrchestration = """
    # Gemini CLI Orchestration

    Gemini CLI gives Claude a second brain -- a different model with different strengths.

    ## When Gemini Beats Claude

    - Code review after >100-line changes (83% Aider accuracy vs 72%)
    - Full codebase scanning >200K tokens (1M context window)
    - Bulk text processing (Gemini Flash is free, 60 req/min)
    - Large file analysis (50K+ lines, fits without chunking)
    - Second opinion on architecture (different training data)

    ## How to Call

    ```bash
    cd /tmp && gemini -p "prompt" --output-format text 2>&1
    cd /tmp && gemini -p "prompt" -m gemini-2.5-flash --output-format text 2>&1
    cd /tmp && cat /path/to/file | gemini -p "Review for bugs" --output-format text 2>&1
    ```

    ## Rules

    1. Claude writes code. Gemini reviews. Never apply blindly (~30% false positives).
    2. Claude decides. Gemini advises. No flip-flopping.
    3. No secrets in prompts.
    4. Max 2 delegations per task.
    5. Run from /tmp, not ~ (avoids .Trash permission errors).
    """

    static let fullAppAudit = """
    # Full App Audit

    When asked for a "full app audit" or "engineering audit", run this standard.

    ## Audit Dimensions

    1. **Code Health** -- dead code, race conditions, memory leaks, swallowed errors, state consistency, perf, concurrency
    2. **Engineering Quality** -- architecture violations, duplicated logic, fragile patterns, missing validation, tech debt
    3. **Platform Compliance** -- store guidelines, privacy, permissions, accessibility, deprecated APIs

    ## Execution Rules

    - Use parallel agents for different directories/concerns
    - Cite every finding: `file_path:line_number`
    - Severity: P0 (crash/rejection/data loss), P1 (user-facing bugs), P2 (tech debt), P3 (improvement)
    - No false positives -- read full code path before flagging
    - Don't fix anything -- audit only
    - Save to `<project>/ENGINEERING_AUDIT_<YYYY_MM>.md`
    """

    static let fileHygiene = """
    # File Hygiene

    ## The _review/ System

    Staging area for suspected unused files. Never delete files directly.

    1. Move suspected unused files to `_review/`
    2. Log every move in `_review/REVIEW_LOG.md` (date, original path, reason)
    3. Developer reviews periodically: delete or restore
    4. Organize by category in subfolders, not flat dumps

    ## Screenshots & Test Artifacts

    Never write screenshots or test output to project roots:
    - Test screenshots -> `<project>/test-artifacts/` (gitignored)
    - Hook-filed screenshots -> `<project>/screenshots/` (gitignored)
    - Marketing screenshots -> `<project>/Screenshots/` (tracked)

    Never write PNGs or test output to home directory.
    """

    static let screenshots = """
    # Screenshot Management

    ## After Using a Screenshot

    Move processed screenshots to `_used/`:
    ```bash
    mv screenshots/filename.png screenshots/_used/
    ```

    Exceptions -- keep if: user says to save it, it's a marketing asset, it's a bug report, or it documents UI state for reference.

    ## Auto-Cleanup

    Screenshots older than 7 days in `_used/` are safe to delete:
    ```bash
    find screenshots/_used -name "*.png" -mtime +7 -delete
    ```

    ## Rules

    - Move processed screenshots to `_used/` after reading
    - File screenshots into projects with descriptive names when they have lasting value
    - Main screenshots folder should stay clean (0-3 files)
    """

    static let capabilities = """
    # Available Capabilities

    Use these proactively -- don't wait to be asked.

    ## Active Hooks (fire automatically)

    - **Screenshot interceptor** (PreToolUse/Read) -- resizes retina images, files to `project/screenshots/`, blocks oversized reads
    - **Destructive command blocker** (PreToolUse/Bash) -- blocks `rm -rf`, force push, sudo, pipe-to-shell, disk ops
    - **Context preservation** (PreCompact) -- injects CONTEXT_STATE.md before compaction

    ## Built-in Commands

    - `/compact` -- run every 20-30 min on deep sessions, or when context >70%
    - `/compact "preserve: <details>"` -- preserve specific context
    - `/clear` -- between unrelated tasks
    - `/context` -- check usage before it becomes a problem

    ## Multi-AI Orchestration

    After changes >100 lines, delegate to Gemini CLI for review:
    ```bash
    cd /tmp && git -C <project> diff | gemini -p "Review for bugs" --output-format text 2>&1
    ```
    ~30% false positive rate. Evaluate findings. See `gemini-orchestration.md`.

    ## Subagents

    Spawn parallel agents for audits, research, large refactors, and exploration.
    """
}
