# Conductor Stability Audit -- March 2026

## Summary
- **Version:** v4.1.0 | ~70 Swift files | ~22,000 lines
- **Architecture:** Per-window state isolation, NDJSON streaming, async/await, @MainActor throughout
- P0: 3 findings (crash risks)
- P1: 5 findings (user-facing bugs or degraded experience)
- P2: 9 findings (tech debt or latent risk)
- P3: 4 findings (improvement opportunities)

---

## P0 -- Critical (crash, data loss)

### 1. Force-unwraps on streaming blocks during concurrent delta processing
**File:** `Sources/Services/ClaudeProcess.swift:945`, `962`, `995-998`
**Issue:** `streamingTextBlock!.text += text` and `streamingThinkingBlock!.text += text` are force-unwrapped. While nil-checks guard each path (lines 941 and 958), `finalizeStreamingThinking()` at line 938 sets `streamingThinkingBlock` to nil (via `finalizeStreamingMessage` -> nil assignment at line 1019). If a race between a thinking delta and a text delta arrives in rapid succession, `appendToStreamingText` could call `finalizeStreamingThinking()` which nils out the thinking block, then a concurrent call to `appendToStreamingThinking` would force-unwrap nil. This is mitigated by `@MainActor` isolation (all calls to `processLine` go through `await self?.processLine(line)` which serializes on the main actor), but `processLine` is called from a `Task.detached` at line 505 via `await self?.processLine(line)`. If the detached task's output read delivers two lines before either `await` completes, the implicit MainActor hop serializes them, so the risk is theoretical. However, these should still be `guard let` unwraps for defensive safety.
**Impact:** Crash on unexpected nil during streaming. Theoretical due to MainActor serialization, but a force-unwrap in a hot path is always a risk.
**Fix:** Replace `streamingTextBlock!` with `guard let block = streamingTextBlock else { return }` pattern.

### 2. Force-unwrap on `selectedModel` in StatusBar
**File:** `Sources/Views/StatusBar.swift:238-239`
**Issue:** `process.selectedModel!.rawValue` and `process.selectedModel!.displayName` are force-unwrapped. The guard is `process.selectedModel != nil` on line 237, which makes this safe in a single-threaded check. However, `selectedModel` is a `@Published` property that can be set to `nil` from `ModelRouter` logic in `onBeforeSend` (AppShell.swift:1201-1203) or from any keyboard shortcut. Since SwiftUI body re-evaluation and state changes can interleave, there is a window where `selectedModel` becomes nil between the `if` check and the force-unwrap during the same body evaluation cycle.
**Impact:** Crash in the StatusBar view during model routing transitions.
**Fix:** Bind to a local `let` once: `if let model = process.selectedModel, !formatModelName(...).contains(model.rawValue)`.

### 3. Unbounded message array growth in very long sessions
**File:** `Sources/Services/ClaudeProcess.swift:14-15` (`messages` array)
**Issue:** The `events` array is capped at 200 entries (line 654), but `messages: [ConversationMessage]` has no cap. Each ConversationMessage stores blocks which can contain large strings (full file contents from Read tool output, large diffs, multi-thousand-line code blocks). In a long multi-hour session with heavy tool use, the messages array can grow to hundreds of megabytes. `ConversationView` uses `LazyVStack` (line 54) which mitigates rendering cost, but the in-memory data grows without bound.
**Impact:** Memory exhaustion leading to macOS killing the process. More likely than other crashes in extended sessions.
**Fix:** Cap messages at a reasonable limit (e.g., 500) or implement message summarization/trimming for old messages while preserving recent context.

---

## P1 -- High (user-facing bugs or degraded experience)

### 4. Stderr reader captures `self` without `[weak self]` in `MainActor.run`
**File:** `Sources/Services/ClaudeProcess.swift:537-544`
**Issue:** Inside `startReadingErrors`, the `Task.detached` closure correctly uses `[weak self]`, but the inner `await MainActor.run` block at line 537 does NOT capture `[weak self]`. Instead it references `self?` which is the weak self from the outer closure. This is actually safe because of the outer `[weak self]`, but the pattern is fragile -- if anyone adds a strong `self` reference in the `MainActor.run` block between the existing optional chains, it would silently create a retain cycle. Not a bug today, but a maintenance hazard.
**Impact:** No current bug, but fragile pattern that could cause a retain cycle on future edits.
**Fix:** Add explicit `[weak self]` to the `MainActor.run` closure for clarity.

### 5. `[self]` captures in AppShell closures risk retaining the view indefinitely
**File:** `Sources/Views/AppShell.swift:1086`, `1100`, `1128`, `1147`, `1166`, `1175`
**Issue:** Multiple closures assigned to process callbacks use `[self]` (strong capture of the AppShell view's self). These closures are stored as properties on `ClaudeProcess`, `ContextPreservationPipeline`, and `AgentOrchestrator` objects. Since these are `@EnvironmentObject`s that live in `SessionStateContainer`, they outlive the view. If the AppShell view is destroyed and recreated (e.g., window tabbing, sheet presentation), the old closures holding strong `[self]` would keep the old view's state alive. In SwiftUI structs, `self` captures the value, not a reference, so this is less dangerous than in classes, but the closures capture mutable `@State` bindings like `compactionToastMessage`, `showEmptyResponseWarning`, etc. that could become stale.
**Impact:** Stale UI state after view recreation. Toast messages could appear addressed to a destroyed view, or fail to appear in the new view.
**Fix:** Use `[weak process]` patterns or route callbacks through a coordinator object that can be reset on view recreation. Alternatively, set up callbacks in `.onAppear` and nil them in `.onDisappear`.

### 6. Model routing changes `selectedModel` mid-session but CLI ignores it
**File:** `Sources/Views/AppShell.swift:1188`, `Sources/Services/ClaudeProcess.swift:377-379`
**Issue:** The model routing in `onBeforeSend` sets `proc.selectedModel` to route to Haiku/Sonnet (line 1188). However, the `--model` flag is only passed at process launch (line 377-379). In interactive `stream-json` mode, the CLI uses whatever model was specified at launch for the entire session. Setting `selectedModel` after launch only changes what the UI displays -- it does not actually change the model being used. The savings calculations at lines 1192-1194 and the `estimatedSavingsUSD` are therefore based on a model switch that never happened.
**Impact:** Users see "auto-routed to Haiku" toast and savings numbers that are fictional. The actual API calls still use whatever model was passed at launch.
**Fix:** Either (a) document that model routing is informational-only in interactive mode, (b) remove the auto-apply behavior and only show suggestions, or (c) implement per-turn model override by sending a `/model` command if the CLI supports it.

### 7. Compaction detection false positives on session resume
**File:** `Sources/Services/ContextPreservationPipeline.swift:123-145`
**Issue:** Compaction is detected when `previousTurnInputTokens > 50_000` and the next turn's input drops by >50%. When resuming a session, the first turn after resume will have a large context (all resumed history), and the second turn may have significantly fewer tokens if the CLI compacted during resume. This would trigger a false compaction detection, causing unnecessary context reinjection and a misleading toast. The `previousTurnInputTokens` is initialized to 0 and only set at the end of `processTurnMetrics`, so the first turn won't trigger it, but a session with heavy initial context followed by a normal turn could.
**Impact:** Misleading "Context compacted" toast and unnecessary context reinjection bloating the conversation.
**Fix:** Add a `turnCount` counter and skip compaction detection for the first 2 turns of a session.

### 8. `send()` auto-restart creates a recursive retry loop
**File:** `Sources/Services/ClaudeProcess.swift:188-214`
**Issue:** When `send()` is called with a dead process, it launches `autoRetryTask` which calls `self.send(text)` (line 211). If the process fails to restart (e.g., CLI is uninstalled during session), `send()` will again find `isRunning` is false and create another `autoRetryTask`. The old task is cancelled on line 193 before creating the new one, so it doesn't stack infinitely. However, this creates a tight loop of: cancel task -> create new task -> sleep 1s -> launch fails -> send() -> cancel task -> create new task. This continues until something external breaks the cycle. The `scheduleAutoRetry` in `launchPersistentProcess` (line 497) has a 3-attempt limit, but the `send()` path at line 188-214 doesn't use `scheduleAutoRetry` -- it has its own inline retry that bypasses the attempt counter.
**Impact:** Tight retry loop consuming CPU if CLI becomes unavailable during a session, with no backoff escalation or max-attempts guard.
**Fix:** Route the `send()` dead-process path through `scheduleAutoRetry` instead of implementing its own inline retry.

---

## P2 -- Medium (tech debt, latent risk)

### 9. GeminiProcess blocks a GCD thread with `waitUntilExit()`
**File:** `Sources/Services/GeminiProcess.swift:47`
**Issue:** `proc.waitUntilExit()` is called on `DispatchQueue.global(qos: .userInitiated)`. This blocks one of the limited GCD cooperative threads. If Gemini CLI hangs (network timeout, API issue), this thread is blocked indefinitely. There is no timeout mechanism.
**Impact:** Thread starvation if Gemini CLI hangs. Could degrade performance of other concurrent operations.
**Fix:** Add a timeout using a `DispatchWorkItem` that terminates the process after 60 seconds, or use `Process.terminationHandler` with an async continuation.

### 10. DevToolService blocks a GCD thread with `waitUntilExit()`
**File:** `Sources/Services/DevToolService.swift:48`
**Issue:** Same pattern as GeminiProcess -- `proc.waitUntilExit()` blocks a GCD thread. Tools like CodeRabbit or Periphery can take minutes on large codebases.
**Impact:** Thread starvation during long-running dev tool operations.
**Fix:** Same as #9 -- use termination handler or add a timeout.

### 11. Session artifacts accumulate without cleanup of orphaned process state
**File:** `Sources/Services/SessionContinuity.swift:117-124`
**Issue:** Artifacts are capped at 100 and old JSON files are deleted. However, `CompactionEngine` snapshots at `~/Library/Application Support/Conductor/snapshots/` (line 130) have no similar cap or cleanup. Each snapshot is a full JSON file. Over months of use, this directory could accumulate thousands of files.
**Impact:** Disk space waste. No immediate stability risk but degrades over time.
**Fix:** Add snapshot cleanup to `CompactionEngine`, keeping only the last 50-100 snapshots.

### 12. `installPreCompactHook` overwrites existing hooks in settings.json
**File:** `Sources/Services/CompactionEngine.swift:114-116`
**Issue:** `hooks["PreCompact"]` is set to a new array on every call, replacing any existing PreCompact hooks the user may have configured manually. This runs on every `startNewSession()` via `AppShell.swift:1233`.
**Impact:** User's custom PreCompact hooks are silently overwritten every time a new session starts.
**Fix:** Merge with existing PreCompact hooks instead of replacing. Check if the Conductor hook already exists before adding.

### 13. `ProjectManager.load()` decodes Claude CLI project paths incorrectly
**File:** `Sources/Services/ProjectManager.swift:62`
**Issue:** `let decoded = "/" + entry.replacingOccurrences(of: "-", with: "/")` converts dashes to slashes. This incorrectly decodes project paths that legitimately contain dashes. For example, a project at `/Users/jesse/my-project` would be encoded as `-Users-jesse-my-project` by the CLI, but this code would decode it as `/Users/jesse/my/project`. The Claude CLI's actual encoding may differ from this simple replacement.
**Impact:** Incorrect project paths shown in the project switcher for projects with dashes in their names.
**Fix:** Use the CLI's actual encoding scheme, or list project directories from the CLI directly via `claude project list` if available.

### 14. `saveSessions()` writes silently fail
**File:** `Sources/Services/SessionManager.swift:177`
**Issue:** `try? data.write(to: sessionsURL)` swallows write failures. If the disk is full or permissions are wrong, all session history is lost when the app restarts because `loadSessions()` finds no file.
**Impact:** Silent session history loss on write failure.
**Fix:** Log the error. Consider keeping the previous file as a backup before overwriting.

### 15. Notification permission check races with notification sends
**File:** `Sources/Services/NotificationService.swift:48-52`
**Issue:** `requestAuthorization` is async and updates `hasPermission` on the main actor. But `sendCompletionNotification` is called from `handleResult` which fires immediately on the first turn. If the first turn completes before the authorization callback fires, `hasPermission` is still false and the notification is silently dropped.
**Impact:** First-turn completion notifications may be dropped. Minor UX issue.
**Fix:** Queue notifications if permission state is unknown, or check permission state synchronously via `getNotificationSettings`.

### 16. `CrashReporter.checkForPreviousCrashes` counts all files including current session's
**File:** `Sources/Services/CrashReporter.swift:78-92`
**Issue:** `contentsOfDirectory` at the crash log directory counts all files. Since crash logs are never cleaned up, the crash count includes every crash from the app's entire lifetime, not just the most recent one. The `DispatchQueue.main.asyncAfter` at line 86 also bypasses `@MainActor` isolation (the class is not `@MainActor`), posting from a background-initiated GCD block.
**Impact:** False positive "previous crash detected" banner every launch after the first-ever crash. MainActor isolation violation (posting NotificationCenter from outside MainActor-isolated context).
**Fix:** Clean up old crash logs (e.g., keep only last 7 days). Post the notification within a `Task { @MainActor in }` block instead of `DispatchQueue.main.asyncAfter`.

### 17. Pipe buffer overflow risk on rapid stdout output
**File:** `Sources/Services/ClaudeProcess.swift:505-527`
**Issue:** `handle.availableData` reads whatever is available in the pipe buffer. macOS pipe buffers are typically 64KB. If Claude CLI outputs a very large response (e.g., reading a huge file) faster than `processLine` can process it, the pipe buffer could fill. When the buffer is full, the CLI's write to stdout blocks, which freezes the CLI process. This is the classic pipe deadlock. The `Task.detached` loop reads as fast as possible via `availableData` which should prevent this under normal conditions, but if `await self?.processLine(line)` is slow (e.g., heavy markdown parsing or SwiftUI update), the read loop could fall behind.
**Impact:** CLI process freeze on very large outputs. Rare but possible with multi-megabyte tool results.
**Fix:** Consider reading stdout into a buffer asynchronously without awaiting processLine inline, then processing the buffer separately.

---

## P3 -- Low (improvement opportunities)

### 18. `searchMatchCount` in AppShell recalculates on every view update
**File:** `Sources/Views/AppShell.swift:982-986`
**Issue:** `searchMatchCount` is a computed property that iterates all messages and calls `copyText()` + `lowercased()` + `contains()` on each. This runs on every SwiftUI view evaluation when the search bar is open. With hundreds of messages, this could cause frame drops.
**Impact:** Minor UI jank during search in long conversations.
**Fix:** Cache the match count and recompute only when `searchText` or `messages.count` changes.

### 19. `buildCommandList()` recreates entire command array on every palette open
**File:** `Sources/Views/AppShell.swift:1324-1958`
**Issue:** 634 lines of command construction run every time the command palette is opened or refreshed. This includes iterating agent presets, skills, commands, models, etc.
**Impact:** Brief stutter on command palette open with many commands/presets/skills.
**Fix:** Cache the command list and invalidate on relevant state changes.

### 20. No process cleanup on window close when closeout is skipped
**File:** `Sources/Views/AppShell.swift:2347-2356`
**Issue:** When `windowShouldClose` returns `true` (no substantive work or already closing), the `ClaudeProcess` is not explicitly stopped. It relies on `SessionStateContainer` deinitialization to clean up. If SwiftUI retains the container briefly (which it can for animation purposes), the CLI process runs as a zombie for that duration.
**Impact:** Brief zombie process after window close. Self-resolves on dealloc.
**Fix:** Explicitly call `process.stop()` in the `windowShouldClose` true-return path.

### 21. Effort level and permission mode changes require session restart but UI doesn't indicate this
**File:** `Sources/Services/ClaudeProcess.swift:110-113`
**Issue:** `effortLevel`, `permissionMode`, and other CLI flags are documented as "applied at process launch -- changes require restart" (line 109). However, the command palette allows changing these mid-session (AppShell.swift:1507-1525) without restarting the process. The changes are silently ignored by the running CLI.
**Impact:** User changes effort level or permission mode via command palette and believes it took effect, but the running session uses the original values.
**Fix:** Either restart the process on flag changes, or disable mid-session flag changes and show "requires new session" in the command palette subtitle.

---

## Architecture Notes (not findings, for context)

- **@MainActor consistency:** All ObservableObject services are correctly annotated `@MainActor`. ClaudeProcess uses `Task.detached` for I/O with proper `await MainActor.run` hops back. No data race violations detected in the current code.
- **Process lifecycle:** The `sessionGeneration` counter (line 50) correctly prevents stale termination handlers from affecting new sessions. This was a v3.2.1 fix and appears solid.
- **SIGPIPE handling:** `signal(SIGPIPE, SIG_IGN)` at app init (ConductorApp.swift:9) correctly prevents crashes when writing to dead pipes.
- **Error recovery:** The auto-retry system with exponential backoff (1s, 2s, 4s, max 3 attempts) is well-designed and handles both process crashes and API errors.
- **Multi-window isolation:** SessionStateContainer creates independent service instances per window. This is correct -- no shared mutable state between windows except global singletons (ThemeEngine, SoundManager, etc.) which are read-mostly.
