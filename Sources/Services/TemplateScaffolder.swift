import Foundation

/// Scaffolds optimized CLAUDE.md, .claude/rules/, and .claude/skills/ for users.
/// Progressive disclosure architecture: lean core (always loaded) + modular rules
/// (path-scoped) + on-demand skills (triggered by task).
@MainActor
final class TemplateScaffolder {
    static let shared = TemplateScaffolder()
    private init() {}

    // MARK: - Public API

    /// Scaffold user-level ~/.claude/ with universal instructions.
    /// Only creates files that don't already exist — never overwrites.
    /// Also installs safeguards (screenshot hook, deny rules, quality rules).
    func scaffoldUserLevel() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let claudeDir = home.appendingPathComponent(".claude")
        let rulesDir = claudeDir.appendingPathComponent("rules")

        createDirIfNeeded(rulesDir)
        writeIfMissing(claudeDir.appendingPathComponent("CLAUDE.md"), content: Templates.userCLAUDE)
        writeIfMissing(rulesDir.appendingPathComponent("coding-standards.md"), content: Templates.codingStandards)
        writeIfMissing(rulesDir.appendingPathComponent("git-workflow.md"), content: Templates.gitWorkflow)

        // Install safeguards — screenshot hook, binary deny rules, quality rules
        SafeguardsManager.shared.installGlobally()
    }

    /// Scaffold project-level .claude/ in the given directory.
    /// Only creates files that don't already exist — never overwrites.
    /// Also installs project-level safeguards.
    func scaffoldProject(at directory: URL) {
        let claudeDir = directory.appendingPathComponent(".claude")
        let rulesDir = claudeDir.appendingPathComponent("rules")
        let skillsDir = claudeDir.appendingPathComponent("skills")

        createDirIfNeeded(rulesDir)
        createDirIfNeeded(skillsDir.appendingPathComponent("debug"))
        createDirIfNeeded(skillsDir.appendingPathComponent("audit"))
        createDirIfNeeded(skillsDir.appendingPathComponent("release"))

        // Project root files
        writeIfMissing(directory.appendingPathComponent("CLAUDE.md"), content: Templates.projectCLAUDE)
        writeIfMissing(directory.appendingPathComponent("CONTEXT_STATE.md"), content: Templates.contextState)

        // Rules
        writeIfMissing(rulesDir.appendingPathComponent("anti-patterns.md"), content: Templates.antiPatterns)
        writeIfMissing(rulesDir.appendingPathComponent("verification.md"), content: Templates.verification)

        // Skills
        writeIfMissing(skillsDir.appendingPathComponent("debug/SKILL.md"), content: Templates.debugSkill)
        writeIfMissing(skillsDir.appendingPathComponent("audit/SKILL.md"), content: Templates.auditSkill)
        writeIfMissing(skillsDir.appendingPathComponent("release/SKILL.md"), content: Templates.releaseSkill)

        // Safeguards — screenshot hook, deny rules, quality rules at project level
        SafeguardsManager.shared.installForProject(at: directory)
    }

    /// Check whether project-level scaffolding exists
    func hasProjectScaffold(at directory: URL) -> Bool {
        let claudeDir = directory.appendingPathComponent(".claude")
        return FileManager.default.fileExists(atPath: claudeDir.path)
    }

    // MARK: - Private

    private func createDirIfNeeded(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func writeIfMissing(_ url: URL, content: String) {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - Template Content

private enum Templates {

    // MARK: User-Level

    static let userCLAUDE = """
    # Universal Instructions

    ## Communication
    - Be concise. Lead with the answer, not the reasoning.
    - No emojis unless requested.
    - When referencing code, include file_path:line_number.
    - Show code, not descriptions of code.

    ## Code Quality
    - Production-ready on first write. No TODO stubs, no placeholder logic.
    - Strong typing where the language supports it.
    - No swallowed errors or silent failures.
    - No magic numbers — use named constants.
    - Self-documenting names. Only comment non-obvious logic.

    ## Working Principles
    - Read files before editing. Never edit blind.
    - Read the full code path before suggesting changes.
    - Prefer editing existing files over creating new ones.
    - Keep diffs minimal — only change what was asked.
    - Don't add features, refactoring, or "improvements" beyond the request.
    - Don't create abstractions for one-time operations.

    ## Context Protocol
    - Read project CLAUDE.md before starting work on any project.
    - Read CONTEXT_STATE.md at session start if it exists.
    - Update CONTEXT_STATE.md after significant batches of changes.

    ## Verification
    - Build must pass before claiming any task is "done."
    - Test affected code paths when tests exist.
    - State risk level for non-trivial changes.
    """

    static let codingStandards = """
    # Coding Standards

    - Always read a file before editing it.
    - Prefer the smallest diff that achieves the goal.
    - Don't refactor surrounding code unless asked.
    - Don't add docstrings, comments, or type annotations to unchanged code.
    - Don't add error handling for impossible scenarios.
    - If something is unused, delete it completely. No _unused renames.
    - Never hardcode secrets, tokens, or credentials.
    - Validate at system boundaries. Trust internal code.
    """

    static let gitWorkflow = """
    # Git Workflow

    - Only commit when explicitly asked.
    - Stage specific files by name — never git add -A blindly.
    - Commit messages: focus on "why" not "what." Imperative mood.
    - Create new commits. Don't amend unless explicitly asked.
    - Never force push to main/master.
    - Never skip hooks (--no-verify) unless explicitly asked.
    """

    // MARK: Project-Level

    static let projectCLAUDE = """
    # Project

    ## What This Is
    <!-- One sentence describing the project -->

    ## Tech Stack
    <!-- Language, framework, key dependencies -->

    ## Commands
    ```bash
    # Build
    # [build command]

    # Test
    # [test command]

    # Deploy
    # [deploy command]
    ```

    ## Hard Rules
    <!-- Project-specific constraints that prevent real mistakes -->

    ## Context Protocol
    - Read CONTEXT_STATE.md at session start.
    - Update CONTEXT_STATE.md after completing significant work.
    - Check .claude/rules/anti-patterns.md before making changes.
    """

    static let contextState = """
    # Context State

    <!-- Read at session start. Update after significant work. -->

    ## Current State
    <!-- What works? What's deployed? -->

    ## Recent Changes
    <!-- Files modified, features added/fixed in last session. -->

    ## What's Next
    <!-- Prioritized upcoming work. -->

    ## Discoveries
    <!-- Patterns or gotchas discovered during work.
         Promote to .claude/rules/anti-patterns.md after 3+ confirmations. -->
    """

    static let antiPatterns = """
    # Anti-Patterns

    <!-- Claude adds entries when it discovers build failures, incorrect
         assumptions, or bugs. This file evolves over time.

         Format: - NEVER: [what] -- [why] (discovered: YYYY-MM-DD)
         Review quarterly: remove rules Claude already follows without reminder. -->
    """

    static let verification = """
    # Verification Gate

    ## Before Any Task Is "Done"
    1. Build passes (required).
    2. Tests pass if they exist.
    3. Lint/typecheck clean if configured.
    4. Smoke test for UI-affecting changes.

    ## Before Deploy or Release
    1. All of the above.
    2. Review every changed file.
    3. Check 3-5 edge cases.
    4. State risk level: Low / Medium / High.
    """

    // MARK: Skills

    static let debugSkill = """
    ---
    description: Use when debugging build failures, runtime errors, or unexpected behavior. Systematically diagnoses root cause before attempting fixes.
    ---

    # Debug Workflow

    ## Step 1: Reproduce
    - What exact error or behavior?
    - What command triggers it?
    - Read the full error message and stack trace.

    ## Step 2: Isolate
    - Identify the exact file, function, and line.
    - Read the full surrounding function.
    - Check recent changes: git diff, git log --oneline -10.

    ## Step 3: Fix
    - Make the minimal change that fixes the root cause.
    - Never fix symptoms — fix the actual problem.
    - Verify the fix doesn't break anything else.

    ## Step 4: Prevent
    - Add to .claude/rules/anti-patterns.md if it could recur.
    """

    static let auditSkill = """
    ---
    description: Use when auditing code quality, reviewing architecture, or checking for issues. Evidence-based — every finding must be verified with a command before reporting.
    ---

    # Code Audit

    ## HARD RULE: Verify Before Reporting
    Every finding MUST include the command output that proves it.
    - Secrets in git? Run `git ls-files` to confirm the file is tracked, not just present locally.
    - Hardcoded credential? Show the exact line AND confirm it's reachable in production.
    - Security vulnerability? Demonstrate the attack path, don't just flag a pattern.
    - Dead code? Grep for all references before claiming it's unused.
    If you cannot verify a finding with a command, mark it as UNVERIFIED and explain what you couldn't check.

    ## Severity Definitions
    - CRITICAL: Exploitable now, causes data loss or security breach. Verified with evidence.
    - HIGH: Real bug or risk, but requires specific conditions. Verified.
    - MEDIUM: Code quality issue with concrete downside. Verified or clearly observable.
    - LOW: Tech debt, style, theoretical concern.

    ## Check For
    - Security: secrets in git (`git ls-files`), injection, hardcoded credentials, missing auth
    - Error handling: swallowed errors (.catch(() => {})), silent failures, missing error states
    - Data integrity: race conditions, missing validation at system boundaries
    - Dead code: unused imports, unreachable branches (verify with grep)
    - Performance: unnecessary work, N+1 queries, missing caching

    ## Report Format
    For each finding:
    1. File:line — exact location
    2. What's wrong — one sentence
    3. Evidence — command output or code snippet proving it
    4. Severity — using definitions above
    5. Fix — specific action to take

    ## Skip
    - Style preferences that don't affect behavior
    - Missing docs on self-documenting code
    - Theoretical concerns you cannot demonstrate
    - Patterns that look risky but are actually safe (verify first)

    ## What's Healthy
    End the audit with a section listing what IS working well.
    Audits that only list problems give a distorted picture.
    """

    static let releaseSkill = """
    ---
    description: Use when releasing a new version or deploying. Ensures nothing ships broken.
    ---

    # Release Checklist

    ## Pre-Release
    1. All changes committed.
    2. Build passes in Release config.
    3. Tests pass.
    4. CONTEXT_STATE.md updated.

    ## Release
    1. Bump version number.
    2. Rebuild after version change.
    3. Create git tag.
    4. Build release artifact.
    5. Verify artifact works.
    6. Push and create release.

    ## Post-Release
    1. Update CONTEXT_STATE.md with release status.
    """
}
