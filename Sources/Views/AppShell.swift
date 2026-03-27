import SwiftUI
import AppKit

/// Main window layout — status bar + conversation + input bar + optional agent panel
/// Per UX_DESIGN.md: Focus mode (default) + Dashboard mode (Tab to toggle)
struct AppShell: View {
    @EnvironmentObject private var process: ClaudeProcess
    @EnvironmentObject private var theme: ThemeEngine
    @EnvironmentObject private var sessionManager: SessionManager
    @EnvironmentObject private var orchestrator: AgentOrchestrator
    @EnvironmentObject private var permissionManager: PermissionManager
    @EnvironmentObject private var contextManager: ContextStateManager
    @EnvironmentObject private var compactionEngine: CompactionEngine
    @EnvironmentObject private var budgetOptimizer: ContextBudgetOptimizer
    @EnvironmentObject private var sessionContinuity: SessionContinuity
    @EnvironmentObject private var contextPipeline: ContextPreservationPipeline
    @EnvironmentObject private var fontScale: FontScale
    @EnvironmentObject private var modelRouter: ModelRouter
    @EnvironmentObject private var projectManager: ProjectManager
    @Environment(\.openWindow) private var openWindow

    @State private var showAgentPanel = false
    @State private var showDashboard = false
    @State private var showContextOverlay = false
    @State private var showCommandPalette = false
    @State private var showSessionBrowser = false
    @State private var showHelp = false
    @State private var showMultiAgentView = false
    @State private var showPerformance = false
    @State private var isPlanMode = false
    @State private var showTerminalBar = false
    @State private var terminalCommand = ""
    @State private var showSearchBar = false
    @State private var searchText = ""
    @State private var currentSearchMatchIndex = 0
    @State private var previewFilePath: String?
    @State private var fullscreenDiff: DiffBlock?
    @State private var healthIssues: [HealthIssue] = []
    @State private var showHooksManager = false
    @State private var showSkillsBrowser = false
    @State private var showCommandsBrowser = false
    @State private var showMCPManager = false
    @State private var showGeminiPanel = false
    @State private var showDevToolPanel = false
    @State private var showCompactBar = false
    @State private var compactInstructions = ""
    @State private var showSessionDiff = false
    @State private var showProjectSwitcher = false
    @State private var hasInitializedSession = false
    @StateObject private var closeoutManager = SessionCloseoutManager()
    /// Per-window session tracking — NOT the shared singleton's activeSession
    @State private var windowSession: Session?
    /// User-defined window label (shown in title bar + status bar)
    @State private var windowLabel: String = ""
    /// Scaffold prompt for new project directories
    @State private var showScaffoldPrompt = false
    @State private var pendingScaffoldURL: URL?
    /// Track which pinned message IDs were already sent — avoid resending every turn
    @State private var lastSentPinnedIds: Set<String> = []
    /// Empty response warning — possible context loss
    @State private var showEmptyResponseWarning = false
    /// Persistent process error — does NOT auto-dismiss (process death, unrecoverable errors)
    @State private var persistentErrorMessage: String?
    /// Compaction toast — shows briefly when context is compacted
    @State private var compactionToastMessage: String?
    /// Session handoff toast — shows when resuming from a previous session
    @State private var handoffToastMessage: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            HSplitView {
                // Main conversation
                VStack(spacing: 0) {
                    StatusBar(windowLabel: $windowLabel)

                    // Autonomous mode banner — persistent, unmissable
                    if process.autonomousMode {
                        HStack(spacing: 6) {
                            Image(systemName: "bolt.shield.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text("AUTONOMOUS MODE")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                            Text("— permissions bypassed, auto-retry enabled")
                                .font(.system(size: 11))
                                .opacity(0.7)
                            Spacer()
                            Button("Turn Off") {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    process.autonomousMode = false
                                    process.permissionMode = .default_
                                }
                            }
                            .font(.system(size: 10, weight: .semibold))
                            .buttonStyle(.plain)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.white.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(theme.amber.opacity(0.85))
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    ZStack(alignment: .top) {
                        ConversationView(
                            searchText: searchText,
                            currentMatchIndex: currentSearchMatchIndex,
                            onFilePathTap: { path in
                                previewFilePath = path
                            },
                            onTogglePin: { messageId in
                                togglePin(messageId: messageId)
                            },
                            onUndo: { undoLastMessage() },
                            onSeeChanges: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showDashboard = true
                                    showAgentPanel = false
                                }
                            },
                            onDeploy: {
                                process.send("Deploy this project to production")
                            },
                            onSuggestNext: {
                                process.send("What should I do next based on what we just changed?")
                            },
                            onDiffExpand: { diff in
                                fullscreenDiff = diff
                            },
                            onCommandPalette: { showCommandPalette = true },
                            onToggleVibe: {
                                process.isVibeCoder.toggle()
                                permissionManager.autoApproveAll = process.isVibeCoder
                            },
                            onSessionBrowser: { showSessionBrowser = true },
                            onShowHelp: { showHelp = true }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        // Search bar (Cmd+F)
                        if showSearchBar {
                            SearchBar(
                                searchText: $searchText,
                                isPresented: $showSearchBar,
                                matchCount: searchMatchCount,
                                currentMatchIndex: $currentSearchMatchIndex
                            )
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        // Compaction toast — auto-dismisses after 4s
                        if let toast = compactionToastMessage {
                            CompactionToast(message: toast)
                                .padding(.top, 8)
                                .transition(.move(edge: .top).combined(with: .opacity))
                                .animation(.easeOut(duration: 0.3), value: compactionToastMessage)
                        }

                        // Session handoff toast — auto-dismisses after 3s
                        if let toast = handoffToastMessage {
                            CompactionToast(message: toast)
                                .padding(.top, 8)
                                .transition(.move(edge: .top).combined(with: .opacity))
                                .animation(.easeOut(duration: 0.3), value: handoffToastMessage)
                        }

                        // Persistent process error — does NOT auto-dismiss
                        if let errorMsg = persistentErrorMessage {
                            ProcessErrorBanner(
                                message: errorMsg,
                                onRestart: {
                                    persistentErrorMessage = nil
                                    startNewSession()
                                },
                                onDismiss: {
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        persistentErrorMessage = nil
                                    }
                                }
                            )
                            .padding(.top, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .animation(.easeOut(duration: 0.3), value: persistentErrorMessage)
                        }
                    }

                    // Empty response warning — possible context loss
                    if showEmptyResponseWarning {
                        EmptyResponseWarning(
                            onRetry: {
                                showEmptyResponseWarning = false
                                if let lastPrompt = process.lastUserMessage {
                                    process.send(lastPrompt)
                                }
                            },
                            onNewSession: {
                                showEmptyResponseWarning = false
                                startNewSession()
                            },
                            onDismiss: {
                                showEmptyResponseWarning = false
                            }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    InputBar(
                        onCommandPalette: { showCommandPalette = true },
                        onToggleVibe: {
                            process.isVibeCoder.toggle()
                            permissionManager.autoApproveAll = process.isVibeCoder
                        },
                        onShowHelp: { showHelp = true },
                        onSessionBrowser: { showSessionBrowser = true }
                    )
                }

                // Right sidebar (dashboard, agents, or moodboard)
                if showDashboard || showAgentPanel {
                    VStack(spacing: 0) {
                        // Sidebar tab picker
                        HStack(spacing: 0) {
                            sidebarTab("Dashboard", icon: "gauge.with.dots.needle.67percent", isActive: showDashboard) {
                                showDashboard = true
                                showAgentPanel = false
                            }
                            sidebarTab("Agents", icon: "person.3.fill", isActive: showAgentPanel) {
                                showAgentPanel = true
                                showDashboard = false
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 6)

                        Divider().opacity(0.3)

                        if showDashboard {
                            DashboardPanel(
                                onShowSessionDiff: {
                                    withAnimation(.easeOut(duration: 0.15)) {
                                        showSessionDiff = true
                                    }
                                },
                                onOpenGemini: {
                                    withAnimation(.easeOut(duration: 0.15)) {
                                        showGeminiPanel = true
                                    }
                                },
                                onOpenDevTools: {
                                    withAnimation(.easeOut(duration: 0.15)) {
                                        showDevToolPanel = true
                                    }
                                },
                                onOpenMCPCatalog: {
                                    withAnimation(.easeOut(duration: 0.15)) {
                                        showMCPManager = true
                                    }
                                }
                            )
                        } else if showAgentPanel {
                            AgentPanel()
                        }
                    }
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)
                }
            }
            .background(theme.base)

            // Command Palette (Cmd+K)
            if showCommandPalette {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { showCommandPalette = false }

                VStack {
                    CommandPalette(
                        commands: buildCommandList(),
                        isPresented: $showCommandPalette
                    )
                    .padding(.top, 80)
                    Spacer()
                }
                .transition(.opacity)
            }

            // Error banner — non-blocking for retries, actionable only for unrecoverable errors
            if let error = process.error {
                let isRetrying = error.hasPrefix("Retrying") || error.hasPrefix("Reconnecting")
                VStack {
                    HStack(spacing: 8) {
                        if isRetrying {
                            ProgressView()
                                .controlSize(.mini)
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(theme.rose)
                        }
                        Text(error)
                            .font(Typography.caption)
                            .foregroundColor(theme.bright)
                        Spacer()
                        if !isRetrying {
                            if process.sessionId != nil {
                                Button("Resume Session") {
                                    process.start(resumeSession: process.sessionId)
                                }
                                .font(Typography.caption)
                                .foregroundColor(theme.sky)
                                .buttonStyle(.plain)
                            }
                            Button("New Session") {
                                startNewSession()
                            }
                            .font(Typography.caption)
                            .foregroundColor(theme.sky)
                            .buttonStyle(.plain)
                            Button {
                                process.error = nil
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10))
                                    .foregroundColor(theme.muted)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                    .background(
                        (isRetrying ? theme.amber : theme.rose)
                            .opacity(0.15)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    Spacer()
                }
                .animation(.easeInOut(duration: 0.2), value: error)
            }

            // Health check banner (amber for warnings, red for errors)
            if let issue = healthIssues.first {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: issue.severity == .error
                            ? "exclamationmark.triangle.fill"
                            : "info.circle.fill")
                            .foregroundColor(issue.severity == .error ? theme.rose : theme.amber)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(issue.title)
                                .font(Typography.bodyBold)
                                .foregroundColor(theme.bright)
                            Text(issue.detail)
                                .font(Typography.caption)
                                .foregroundColor(theme.muted)
                        }
                        Spacer()
                        Button {
                            healthIssues.removeFirst()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(theme.muted)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(
                        (issue.severity == .error ? theme.rose : theme.amber)
                            .opacity(0.15)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    Spacer()
                }
            }

            // Session Browser (Cmd+S)
            if showSessionBrowser {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { showSessionBrowser = false }

                VStack {
                    SessionBrowser(isPresented: $showSessionBrowser)
                        .padding(.top, 60)
                    Spacer()
                }
                .transition(.opacity)
            }

            // Help Overlay (?)
            if showHelp {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { showHelp = false }

                VStack {
                    HelpOverlay(isPresented: $showHelp)
                        .padding(.top, 60)
                    Spacer()
                }
                .transition(.opacity)
            }

            // Terminal Passthrough bar (Ctrl+T)
            if showTerminalBar {
                VStack {
                    Spacer()
                    TerminalBar(
                        command: $terminalCommand,
                        isPresented: $showTerminalBar,
                        onExecute: { cmd in
                            process.send("Run this shell command and show me the output: `\(cmd)`")
                            terminalCommand = ""
                            showTerminalBar = false
                        }
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 80)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Permission queue overlay (bottom, non-blocking)
            if !permissionManager.pendingRequests.isEmpty {
                PermissionQueue()
                    .padding(.horizontal, 20)
                    .padding(.bottom, 80) // Above input bar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // File Preview Panel
            if let filePath = previewFilePath {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { previewFilePath = nil }

                VStack {
                    FilePreviewPanel(
                        filePath: filePath,
                        isPresented: Binding(
                            get: { previewFilePath != nil },
                            set: { if !$0 { previewFilePath = nil } }
                        )
                    )
                    .padding(.top, 40)
                    .padding(.horizontal, 40)
                    Spacer()
                }
                .transition(.opacity)
            }

            // Hooks Manager (Cmd+Shift+H)
            if showHooksManager {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { showHooksManager = false }

                VStack {
                    HooksOverlay(isPresented: $showHooksManager)
                        .padding(.top, 60)
                    Spacer()
                }
                .transition(.opacity)
            }

            // Skills Browser (Cmd+Shift+K)
            if showSkillsBrowser {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { showSkillsBrowser = false }

                VStack {
                    SkillsBrowser(isPresented: $showSkillsBrowser)
                        .padding(.top, 60)
                    Spacer()
                }
                .transition(.opacity)
            }

            // Commands Browser (Cmd+Shift+J)
            if showCommandsBrowser {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { showCommandsBrowser = false }

                VStack {
                    CommandsBrowser(isPresented: $showCommandsBrowser)
                        .padding(.top, 60)
                    Spacer()
                }
                .transition(.opacity)
            }

            // MCP Server Manager (Cmd+Shift+I)
            if showMCPManager {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { showMCPManager = false }

                VStack {
                    MCPServerOverlay(isPresented: $showMCPManager)
                        .padding(.top, 60)
                    Spacer()
                }
                .transition(.opacity)
            }

            // Gemini Panel (Cmd+Shift+G)
            if showGeminiPanel {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { showGeminiPanel = false }

                VStack {
                    GeminiPanel(isPresented: $showGeminiPanel)
                        .padding(.top, 60)
                    Spacer()
                }
                .transition(.opacity)
            }

            // Dev Tools Panel (Cmd+Shift+L)
            if showDevToolPanel {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { showDevToolPanel = false }

                VStack {
                    DevToolPanel(isPresented: $showDevToolPanel, projectDir: process.workingDirectory)
                        .padding(.top, 60)
                    Spacer()
                }
                .transition(.opacity)
            }

            // Compact Instructions bar
            if showCompactBar {
                VStack {
                    Spacer()
                    CompactInstructionsBar(
                        instructions: $compactInstructions,
                        isPresented: $showCompactBar,
                        onCompact: { instructions in
                            process.compact(instructions: instructions.isEmpty ? nil : instructions)
                            compactInstructions = ""
                            showCompactBar = false
                        }
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 80)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Fullscreen Diff Overlay
            if let diff = fullscreenDiff {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { fullscreenDiff = nil }

                FullscreenDiffOverlay(
                    block: diff,
                    isPresented: Binding(
                        get: { fullscreenDiff != nil },
                        set: { if !$0 { fullscreenDiff = nil } }
                    )
                )
                .transition(.opacity)
            }

            // Session Diff Review Overlay (Cmd+Shift+D)
            if showSessionDiff {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { showSessionDiff = false }

                SessionDiffOverlay(isPresented: $showSessionDiff)
                    .transition(.opacity)
            }

            // Project Switcher Overlay (Cmd+P)
            if showProjectSwitcher {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { showProjectSwitcher = false }

                ProjectSwitcher(isPresented: $showProjectSwitcher)
                    .transition(.opacity)
            }
        }
        .navigationTitle(windowTitle)
        .onAppear {
            guard !hasInitializedSession else { return }
            hasInitializedSession = true
            TemplateScaffolder.shared.scaffoldUserLevel()
            startNewSession()
            NotificationService.shared.requestPermission()
            runHealthCheck()
        }
        .alert("Set Up Claude Instructions?", isPresented: $showScaffoldPrompt) {
            Button("Set Up") {
                if let url = pendingScaffoldURL {
                    TemplateScaffolder.shared.scaffoldProject(at: url)
                }
            }
            Button("Skip", role: .cancel) {}
        } message: {
            Text("Conductor can create optimized .claude/ rules and skills for this project. This won't overwrite any existing files.")
        }
        // Centralized Escape — dismiss topmost overlay in priority order
        .onKeyPress(.escape) {
            if showCommandPalette {
                withAnimation(.easeOut(duration: 0.15)) { showCommandPalette = false }
                return .handled
            }
            if showSearchBar {
                withAnimation(.easeOut(duration: 0.15)) { showSearchBar = false; searchText = ""; currentSearchMatchIndex = 0 }
                return .handled
            }
            if showHelp {
                withAnimation(.easeOut(duration: 0.15)) { showHelp = false }
                return .handled
            }
            if showSessionBrowser {
                withAnimation(.easeOut(duration: 0.15)) { showSessionBrowser = false }
                return .handled
            }
            if showContextOverlay {
                showContextOverlay = false
                return .handled
            }
            if showMultiAgentView {
                withAnimation(.easeOut(duration: 0.15)) { showMultiAgentView = false }
                return .handled
            }
            if showPerformance {
                withAnimation(.easeOut(duration: 0.15)) { showPerformance = false }
                return .handled
            }
            if showMCPManager {
                withAnimation(.easeOut(duration: 0.15)) { showMCPManager = false }
                return .handled
            }
            if showGeminiPanel {
                withAnimation(.easeOut(duration: 0.15)) { showGeminiPanel = false }
                return .handled
            }
            if showDevToolPanel {
                withAnimation(.easeOut(duration: 0.15)) { showDevToolPanel = false }
                return .handled
            }
            return .ignored
        }
        // Luminance (Cmd+[ / Cmd+])
        .onKeyPress(characters: CharacterSet(charactersIn: "["), phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            theme.adjustLuminance(by: -0.1)
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "]"), phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            theme.adjustLuminance(by: 0.1)
            return .handled
        }
        // Shift+Tab: Plan Mode toggle (requires modifier, safe)
        .onKeyPress(.tab, phases: .down) { press in
            guard press.modifiers.contains(.shift) else { return .ignored }
            withAnimation(.easeInOut(duration: 0.2)) {
                isPlanMode.toggle()
                process.permissionMode = isPlanMode ? .plan : .bypassPermissions
            }
            return .handled
        }
        // Command Palette (Cmd+K, but not Cmd+Shift+K which opens Skills)
        .onKeyPress(characters: CharacterSet(charactersIn: "k"), phases: .down) { press in
            if press.modifiers.contains([.command, .shift]) {
                // Cmd+Shift+K handled by Skills Browser handler
                return .ignored
            }
            if press.modifiers.contains(.command) {
                withAnimation(.easeOut(duration: 0.15)) {
                    showCommandPalette.toggle()
                }
                return .handled
            }
            return .ignored
        }
        // Search (Cmd+F)
        .onKeyPress(characters: CharacterSet(charactersIn: "f"), phases: .down) { press in
            if press.modifiers.contains(.command) && !press.modifiers.contains(.shift) {
                withAnimation(.easeOut(duration: 0.15)) {
                    showSearchBar.toggle()
                    if !showSearchBar {
                        searchText = ""
                        currentSearchMatchIndex = 0
                    }
                }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "x"), phases: .down) { press in
            if press.modifiers.contains([.command, .shift]) {
                showContextOverlay.toggle()
                return .handled
            }
            return .ignored
        }
        // Session Browser (Cmd+S)
        .onKeyPress(characters: CharacterSet(charactersIn: "s"), phases: .down) { press in
            if press.modifiers.contains(.command) {
                withAnimation(.easeOut(duration: 0.15)) {
                    showSessionBrowser.toggle()
                }
                return .handled
            }
            return .ignored
        }
        // Help (Cmd+?)
        .onKeyPress(characters: CharacterSet(charactersIn: "?"), phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            withAnimation(.easeOut(duration: 0.15)) {
                showHelp.toggle()
            }
            return .handled
        }
        // Hooks Manager (Cmd+Shift+H)
        .onKeyPress(characters: CharacterSet(charactersIn: "h"), phases: .down) { press in
            if press.modifiers.contains([.command, .shift]) {
                withAnimation(.easeOut(duration: 0.15)) {
                    showHooksManager.toggle()
                }
                return .handled
            }
            return .ignored
        }
        // Skills Browser (Cmd+Shift+K)
        .onKeyPress(characters: CharacterSet(charactersIn: "k"), phases: .down) { press in
            if press.modifiers.contains([.command, .shift]) {
                withAnimation(.easeOut(duration: 0.15)) {
                    showSkillsBrowser.toggle()
                }
                return .handled
            }
            return .ignored
        }
        // Commands Browser (Cmd+Shift+J)
        .onKeyPress(characters: CharacterSet(charactersIn: "j"), phases: .down) { press in
            if press.modifiers.contains([.command, .shift]) {
                withAnimation(.easeOut(duration: 0.15)) {
                    showCommandsBrowser.toggle()
                }
                return .handled
            }
            return .ignored
        }
        // MCP Server Manager (Cmd+Shift+I)
        .onKeyPress(characters: CharacterSet(charactersIn: "i"), phases: .down) { press in
            if press.modifiers.contains([.command, .shift]) {
                withAnimation(.easeOut(duration: 0.15)) {
                    showMCPManager.toggle()
                }
                return .handled
            }
            return .ignored
        }
        // Gemini Panel (Cmd+Shift+G)
        .onKeyPress(characters: CharacterSet(charactersIn: "g"), phases: .down) { press in
            if press.modifiers.contains([.command, .shift]) {
                withAnimation(.easeOut(duration: 0.15)) {
                    showGeminiPanel.toggle()
                }
                return .handled
            }
            return .ignored
        }
        // Dev Tools Panel (Cmd+Shift+L)
        .onKeyPress(characters: CharacterSet(charactersIn: "l"), phases: .down) { press in
            if press.modifiers.contains([.command, .shift]) {
                withAnimation(.easeOut(duration: 0.15)) {
                    showDevToolPanel.toggle()
                }
                return .handled
            }
            return .ignored
        }
        // Session Diff Review (Cmd+Shift+D)
        .onKeyPress(characters: CharacterSet(charactersIn: "d"), phases: .down) { press in
            if press.modifiers.contains([.command, .shift]) {
                withAnimation(.easeOut(duration: 0.15)) {
                    showSessionDiff.toggle()
                }
                return .handled
            }
            return .ignored
        }
        // Multi-Agent Split View (Cmd+Shift+M)
        .onKeyPress(characters: CharacterSet(charactersIn: "m"), phases: .down) { press in
            if press.modifiers.contains([.command, .shift]) {
                showMultiAgentView.toggle()
                return .handled
            }
            return .ignored
        }
        // Performance Dashboard (Cmd+Shift+P) / Project Switcher (Cmd+P)
        .onKeyPress(characters: CharacterSet(charactersIn: "p"), phases: .down) { press in
            if press.modifiers.contains([.command, .shift]) {
                withAnimation(.easeOut(duration: 0.15)) {
                    showPerformance.toggle()
                }
                return .handled
            }
            if press.modifiers.contains(.command) {
                withAnimation(.easeOut(duration: 0.15)) {
                    showProjectSwitcher.toggle()
                }
                return .handled
            }
            return .ignored
        }
        // Output Mode (Cmd+O) — cycle through output modes
        .onKeyPress(characters: CharacterSet(charactersIn: "o"), phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            process.outputMode = process.outputMode.next()
            return .handled
        }
        // Undo (Cmd+Z) — remove last assistant message
        .onKeyPress(characters: CharacterSet(charactersIn: "z"), phases: .down) { press in
            guard press.modifiers.contains([.command, .shift]) else { return .ignored }
            guard !process.isStreaming else { return .ignored }
            undoLastMessage()
            return .handled
        }
        // Terminal Passthrough (Ctrl+T) — quick shell command
        .onKeyPress(characters: CharacterSet(charactersIn: "t"), phases: .down) { press in
            if press.modifiers.contains([.command, .shift]) {
                process.showThinking.toggle()
                return .handled
            }
            if press.modifiers.contains(.control) {
                withAnimation(.easeOut(duration: 0.15)) {
                    showTerminalBar.toggle()
                }
                return .handled
            }
            return .ignored
        }
        // Vibe Coder Mode (Ctrl+V)
        .onKeyPress(characters: CharacterSet(charactersIn: "v"), phases: .down) { press in
            if press.modifiers.contains(.control) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    process.isVibeCoder.toggle()
                    permissionManager.autoApproveAll = process.isVibeCoder
                }
                return .handled
            }
            return .ignored
        }
        // Autonomous Mode (Cmd+Shift+A)
        .onKeyPress(characters: CharacterSet(charactersIn: "a"), phases: .down) { press in
            guard press.modifiers.contains([.command, .shift]) else { return .ignored }
            withAnimation(.easeInOut(duration: 0.2)) {
                process.autonomousMode.toggle()
                if process.autonomousMode {
                    process.permissionMode = .bypassPermissions
                    compactionToastMessage = "Autonomous Mode ON — permissions bypassed, auto-retry enabled"
                } else {
                    process.permissionMode = .default_
                    compactionToastMessage = "Autonomous Mode OFF"
                }
            }
            // Auto-dismiss toast
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                withAnimation(.easeOut(duration: 0.3)) {
                    compactionToastMessage = nil
                }
            }
            return .handled
        }
        // Font size: Cmd+ / Cmd- / Cmd+0
        .onKeyPress(characters: CharacterSet(charactersIn: "=+"), phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            fontScale.increase()
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "-"), phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            fontScale.decrease()
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "0"), phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            fontScale.reset()
            return .handled
        }
        // New Window (Cmd+N)
        .onKeyPress(characters: CharacterSet(charactersIn: "n"), phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            openWindow(id: "conductor", value: UUID())
            return .handled
        }
        // Clear conversation (Cmd+L) — like terminal clear. Guard against Cmd+Shift+L (Dev Tools).
        .onKeyPress(characters: CharacterSet(charactersIn: "l"), phases: .down) { press in
            guard press.modifiers.contains(.command), !press.modifiers.contains(.shift) else { return .ignored }
            process.messages.removeAll()
            return .handled
        }
        // Export conversation (Cmd+E)
        .onKeyPress(characters: CharacterSet(charactersIn: "e"), phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            exportConversation()
            return .handled
        }
        // Overlay sheets
        .sheet(isPresented: $showContextOverlay) {
            ContextOverlay()
        }
        .sheet(isPresented: $showMultiAgentView) {
            MultiAgentSplitView(isPresented: $showMultiAgentView)
                .frame(minWidth: 800, minHeight: 500)
        }
        // Performance Dashboard overlay
        .overlay {
            if showPerformance {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture { showPerformance = false }

                    PerformanceDashboard(isPresented: $showPerformance)
                }
                .transition(.opacity)
            }
        }
        // Window close interception — triggers closeout on Cmd+W / X button
        .background(WindowCloseInterceptor(closeoutManager: closeoutManager, process: process, onCloseout: {
            performCloseout {
                // After closeout, save state and close the window
                saveSessionState()
            }
        }))
        // Closeout overlay — blocks interaction while Claude commits/summarizes
        .overlay {
            if closeoutManager.isClosingOut {
                ZStack {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()

                    VStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.large)
                            .tint(theme.sky)

                        Text(closeoutManager.closeoutStatus)
                            .font(Typography.body)
                            .foregroundColor(theme.bright)

                        Text("Click again to close immediately")
                            .font(Typography.caption)
                            .foregroundColor(theme.muted)
                    }
                    .padding(32)
                    .background(theme.surface.opacity(0.95))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .transition(.opacity)
            }
        }
        // Cmd+Q quick save — no closeout prompt, just persist artifacts
        .onReceive(NotificationCenter.default.publisher(for: .conductorAppTerminating)) { _ in
            closeoutManager.quickSave(
                session: windowSession,
                process: process,
                sessionContinuity: sessionContinuity,
                contextManager: contextManager,
                sessionManager: sessionManager
            )
        }
        // End Session (Cmd+Shift+W)
        .onKeyPress(characters: CharacterSet(charactersIn: "w"), phases: .down) { press in
            guard press.modifiers.contains([.command, .shift]) else { return .ignored }
            performEndSession()
            return .handled
        }
        // Save state on window close (fallback for non-intercepted closes)
        .onDisappear {
            saveSessionState()
        }
    }

    /// Number of messages matching current search text
    private var searchMatchCount: Int {
        guard !searchText.isEmpty else { return 0 }
        let query = searchText.lowercased()
        return process.messages.filter { $0.copyText().lowercased().contains(query) }.count
    }

    private func sidebarTab(_ label: String, icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(Typography.caption)
            }
            .foregroundColor(isActive ? theme.sky : theme.muted)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(isActive ? theme.sky.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    /// Dynamic window title — Terminal-style: "folder — model — Conductor"
    private var windowTitle: String {
        if !windowLabel.isEmpty { return windowLabel }
        guard let dir = process.workingDirectory else { return "Conductor" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if dir == home { return "Conductor" }
        let folder = URL(fileURLWithPath: dir).lastPathComponent
        let model = process.selectedModel?.displayName ?? formatModelForTitle(process.currentModel)
        return "\(folder) — \(model) — Conductor"
    }

    private func formatModelForTitle(_ model: String) -> String {
        if model.contains("opus") { return "Opus" }
        if model.contains("sonnet") { return "Sonnet" }
        if model.contains("haiku") { return "Haiku" }
        if model.isEmpty { return "Claude" }
        return model.components(separatedBy: "-").last ?? model
    }

    private func startNewSession() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let session = sessionManager.createSession(directory: homeDir)
        windowSession = session

        // Load context from previous session in same project (if <24h old)
        let maxHandoffAge: TimeInterval = 24 * 60 * 60
        var resumePrompt: String?
        if let artifact = sessionContinuity.latestArtifact(for: homeDir),
           artifact.projectPath == homeDir,
           Date().timeIntervalSince(artifact.timestamp) < maxHandoffAge,
           !artifact.contextForResume.isEmpty {
            resumePrompt = artifact.contextForResume
            contextManager.setCurrentTask("Resumed from previous session")
        }

        // Detect git branch
        detectGitBranch(in: homeDir)

        // Wire process callbacks to services
        let sm = sessionManager
        let cm = contextManager
        let bo = budgetOptimizer
        let proc = process
        let pipeline = contextPipeline

        // Reset pipeline for new session
        pipeline.reset()
        pipeline.projectDirectory = homeDir

        let sc = sessionContinuity
        let sessionId = session.id
        process.onResult = { _ in
            sm.updateSession(id: sessionId, from: proc)
            cm.updateFromProcess(proc)
            bo.analyze(messages: proc.messages)
            NotificationService.shared.sendCompletionNotification(
                title: "Response Complete",
                body: "Claude finished responding"
            )

            // Auto-save session artifact after every turn — crash-proof context persistence
            if let sid = proc.sessionId {
                sc.saveSessionEnd(
                    sessionId: sid,
                    projectPath: proc.workingDirectory,
                    process: proc,
                    contextManager: cm
                )
            }
        }

        process.onError = { [self] msg in
            // Non-retry errors get a persistent banner (not auto-dismissing toast)
            if !msg.hasPrefix("Retrying") && !msg.hasPrefix("Reconnecting") {
                withAnimation(.easeOut(duration: 0.3)) {
                    self.persistentErrorMessage = msg
                }
            }
        }

        process.onAutoRetry = { [self] attempt, maxAttempts in
            // Show non-blocking retry toast
            self.compactionToastMessage = "Retrying... attempt \(attempt)/\(maxAttempts)"
            // Auto-dismiss after 5 seconds (will be replaced by next retry or success)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                if let msg = self.compactionToastMessage, msg.hasPrefix("Retrying") {
                    withAnimation(.easeOut(duration: 0.3)) {
                        self.compactionToastMessage = nil
                    }
                }
            }
        }

        process.onAutoRetrySuccess = { [self] in
            // Clear retry-related UI
            withAnimation(.easeOut(duration: 0.3)) {
                if let msg = self.compactionToastMessage, msg.hasPrefix("Retrying") {
                    self.compactionToastMessage = nil
                }
                self.showEmptyResponseWarning = false
            }
            // Brief success toast
            self.compactionToastMessage = "Reconnected successfully"
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                if self.compactionToastMessage == "Reconnected successfully" {
                    withAnimation(.easeOut(duration: 0.3)) {
                        self.compactionToastMessage = nil
                    }
                }
            }
        }

        process.onToolUse = { toolName, input in
            pipeline.processToolUse(toolName: toolName, input: input)
        }

        process.onAssistantText = { text in
            pipeline.processAssistantText(text)
        }

        process.onEmptyResponse = { [self] in
            // In autonomous mode, don't show blocking warning — the auto-retry in
            // ClaudeProcess already handled the first retry attempt silently
            if proc.autonomousMode {
                // Show brief non-blocking toast instead
                self.compactionToastMessage = "Context may have been lost — consider starting a new session"
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(5))
                    if self.compactionToastMessage?.contains("Context may have been lost") == true {
                        withAnimation(.easeOut(duration: 0.3)) {
                            self.compactionToastMessage = nil
                        }
                    }
                }
            } else {
                self.showEmptyResponseWarning = true
            }
        }

        pipeline.onCompactionDetected = { [self] message in
            self.compactionToastMessage = message
            // Auto-dismiss after 4 seconds
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                if self.compactionToastMessage == message {
                    withAnimation(.easeOut(duration: 0.3)) {
                        self.compactionToastMessage = nil
                    }
                }
            }
        }

        process.onTurnComplete = { metrics in
            cm.updateFromTurnMetrics(metrics)
            pipeline.processTurnMetrics(metrics)
        }

        // Wire multi-agent workflow completion — inject team report into main conversation
        orchestrator.onWorkflowComplete = { [self] report in
            // Add synthesized report as an assistant message in the main conversation
            let reportMessage = ConversationMessage(
                role: .assistant,
                blocks: [TextBlock(text: report)]
            )
            self.process.messages.append(reportMessage)
        }

        process.onBeforeSend = { [self] text in
            // Smart model routing — analyze message and suggest model if beneficial
            let router = self.modelRouter
            if router.isEnabled {
                let routingContext = RoutingContext(
                    contextPercentage: cm.contextPercentage,
                    agentCount: orchestrator.agents.count,
                    isSubAgent: false,
                    currentModel: proc.selectedModel
                )
                if let suggestion = router.analyze(message: text, context: routingContext) {
                    let isSimplerModel = suggestion.model != .opus
                    if router.autoApply && suggestion.confidence >= ModelRouter.autoApplyMinConfidence && isSimplerModel {
                        proc.selectedModel = suggestion.model
                        router.lastAutoApplied = suggestion
                        // Track model savings for the savings indicator
                        switch suggestion.model {
                        case .haiku: proc._pendingModelSavings = 0.95
                        case .sonnet: proc._pendingModelSavings = 0.80
                        case .opus: proc._pendingModelSavings = 0.0
                        }
                    } else {
                        router.suggestion = suggestion
                    }
                } else {
                    // No suggestion = complex work or default → reset to Opus
                    if proc.selectedModel != nil {
                        proc.selectedModel = nil
                        router.lastAutoApplied = nil
                    }
                }
            }

            var wrapped = pipeline.wrapMessage(text)
            // Prepend pinned message context only when pins changed or after compaction
            let pinned = self.pinnedMessages
            let currentPinnedIds = Set(pinned.map { $0.id })
            let pinsChanged = currentPinnedIds != self.lastSentPinnedIds
            let afterCompaction = pipeline.compactionDetected
            if !pinned.isEmpty && (pinsChanged || afterCompaction) {
                let pinnedText = pinned.map { "[\($0.role == .user ? "You" : "Claude")]: \($0.copyText())" }.joined(separator: "\n\n")
                wrapped = "<pinned-context>\n\(pinnedText)\n</pinned-context>\n\n\(wrapped)"
                self.lastSentPinnedIds = currentPinnedIds
            }
            return wrapped
        }

        // Wire notification actions → PermissionManager approve/deny
        let pm = permissionManager
        NotificationService.shared.onPermissionAction = { requestId, approved in
            if approved {
                pm.approve(requestId: requestId)
            } else {
                pm.deny(requestId: requestId)
            }
        }

        // Install PreCompact hook so CLI reads CONTEXT_STATE.md before compaction
        compactionEngine.installPreCompactHook(projectDir: homeDir)

        // Wire orchestrator to main process for agent settings inheritance
        orchestrator.mainProcess = process

        // Set Conductor self-awareness system prompt
        process.systemPrompt = Self.conductorSystemPrompt

        // Don't pass a session ID — let Claude CLI create one on first message
        // The CLI-generated session ID is captured from the system event
        process.start(directory: homeDir)

        // Inject resume prompt as first message after process starts
        if let prompt = resumePrompt {
            Task { @MainActor in
                // Brief delay to let the process initialize before sending
                try? await Task.sleep(for: .milliseconds(500))
                guard process.isRunning else { return }
                process.send(prompt)
                handoffToastMessage = "Resumed from previous session"
                // Auto-dismiss after 3 seconds
                try? await Task.sleep(for: .seconds(3))
                if handoffToastMessage == "Resumed from previous session" {
                    withAnimation(.easeOut(duration: 0.3)) {
                        handoffToastMessage = nil
                    }
                }
            }
        }
    }

    private func detectGitBranch(in directory: String) {
        Task.detached {
            let dirURL = URL(fileURLWithPath: directory)

            // Get branch name
            let branchProc = Process()
            branchProc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            branchProc.arguments = ["rev-parse", "--abbrev-ref", "HEAD"]
            branchProc.currentDirectoryURL = dirURL
            let branchPipe = Pipe()
            branchProc.standardOutput = branchPipe
            branchProc.standardError = Pipe()
            try? branchProc.run()
            branchProc.waitUntilExit()

            guard branchProc.terminationStatus == 0 else { return }
            let branchData = branchPipe.fileHandleForReading.readDataToEndOfFile()
            guard let branch = String(data: branchData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !branch.isEmpty else { return }

            // Get ahead/behind counts
            let statusProc = Process()
            statusProc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            statusProc.arguments = ["rev-list", "--left-right", "--count", "\(branch)...@{upstream}"]
            statusProc.currentDirectoryURL = dirURL
            let statusPipe = Pipe()
            statusProc.standardOutput = statusPipe
            statusProc.standardError = Pipe()
            try? statusProc.run()
            statusProc.waitUntilExit()

            var aheadBehind = ""
            if statusProc.terminationStatus == 0 {
                let statusData = statusPipe.fileHandleForReading.readDataToEndOfFile()
                if let counts = String(data: statusData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    let parts = counts.components(separatedBy: "\t")
                    if parts.count == 2 {
                        let ahead = Int(parts[0]) ?? 0
                        let behind = Int(parts[1]) ?? 0
                        var indicators: [String] = []
                        if ahead > 0 { indicators.append("+\(ahead)") }
                        if behind > 0 { indicators.append("-\(behind)") }
                        if !indicators.isEmpty {
                            aheadBehind = " " + indicators.joined(separator: "/")
                        }
                    }
                }
            }

            let fullBranch = branch + aheadBehind
            await MainActor.run { [weak sessionManager] in
                if var session = sessionManager?.activeSession {
                    session.gitBranch = fullBranch
                    sessionManager?.activeSession = session
                }
            }
        }
    }

    /// Build the command list for the Command Palette
    private func buildCommandList() -> [CommandItem] {
        var commands: [CommandItem] = []

        // Session commands
        commands.append(CommandItem(
            name: "New Session",
            icon: "plus.circle",
            shortcut: nil,
            subtitle: "Start a fresh Claude session",
            category: .session
        ) { startNewSession() })

        commands.append(CommandItem(
            name: "End Session",
            icon: "stop.circle.fill",
            shortcut: "Cmd+Shift+W",
            subtitle: "Commit changes, summarize, start fresh",
            category: .session
        ) { performEndSession() })

        commands.append(CommandItem(
            name: "Export Conversation",
            icon: "square.and.arrow.up",
            shortcut: "Cmd+E",
            subtitle: "Save conversation as markdown file",
            category: .session
        ) { exportConversation() })

        commands.append(CommandItem(
            name: "Interrupt",
            icon: "stop.circle",
            subtitle: "Stop current Claude response",
            category: .session
        ) { process.interrupt() })

        commands.append(CommandItem(
            name: "Clear Conversation",
            icon: "trash",
            subtitle: "Remove all messages",
            category: .session
        ) { process.messages.removeAll() })

        commands.append(CommandItem(
            name: "Set Working Directory",
            icon: "folder",
            subtitle: process.workingDirectory.map { shortenPath($0) } ?? "Not set",
            category: .session
        ) { openDirectoryPicker() })

        // View commands
        commands.append(CommandItem(
            name: "Toggle Dashboard",
            icon: "gauge.with.dots.needle.67percent",
            shortcut: "Tab",
            subtitle: "Show files, tools, and context panels",
            category: .view
        ) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showDashboard.toggle()
                if showDashboard { showAgentPanel = false }
            }
        })

        commands.append(CommandItem(
            name: "Toggle Agent Panel",
            icon: "person.3.fill",
            shortcut: "Tab",
            subtitle: "Show or hide the agent sidebar",
            category: .view
        ) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showAgentPanel.toggle()
                if showAgentPanel { showDashboard = false }
            }
        })


        commands.append(CommandItem(
            name: "Context Manager",
            icon: "gauge.with.dots.needle.67percent",
            shortcut: "Cmd+Shift+X",
            subtitle: "View context usage and selective compaction",
            category: .view
        ) { showContextOverlay = true })

        commands.append(CommandItem(
            name: "Luminance Up",
            icon: "sun.max",
            shortcut: "Cmd+]",
            subtitle: "Increase theme brightness",
            category: .view
        ) { theme.adjustLuminance(by: 0.1) })

        commands.append(CommandItem(
            name: "Luminance Down",
            icon: "moon",
            shortcut: "Cmd+[",
            subtitle: "Decrease theme brightness",
            category: .view
        ) { theme.adjustLuminance(by: -0.1) })

        commands.append(CommandItem(
            name: "Session Browser",
            icon: "clock.arrow.circlepath",
            shortcut: "Cmd+S",
            subtitle: "Browse and resume previous sessions",
            category: .session
        ) {
            withAnimation(.easeOut(duration: 0.15)) {
                showSessionBrowser = true
            }
        })

        commands.append(CommandItem(
            name: "Session Diff Review",
            icon: "doc.text.magnifyingglass",
            shortcut: "Cmd+Shift+D",
            subtitle: "Review all files changed during this session",
            category: .session
        ) {
            withAnimation(.easeOut(duration: 0.15)) {
                showSessionDiff = true
            }
        })

        commands.append(CommandItem(
            name: "Switch Project",
            icon: "folder.badge.gearshape",
            shortcut: "Cmd+P",
            subtitle: "\(projectManager.projects.count) projects",
            category: .session
        ) {
            withAnimation(.easeOut(duration: 0.15)) {
                showProjectSwitcher = true
            }
        })

        commands.append(CommandItem(
            name: "Smart Routing\(modelRouter.isEnabled ? " ✓" : "")",
            icon: "brain.head.profile",
            subtitle: modelRouter.isEnabled ? "Model suggestions active" : "Enable smart model suggestions",
            category: .session
        ) { modelRouter.isEnabled.toggle() })

        commands.append(CommandItem(
            name: "Auto-Apply Routing\(modelRouter.autoApply ? " ✓" : "")",
            icon: "bolt.circle",
            subtitle: modelRouter.autoApply ? "Auto-switching models" : "Enable automatic model switching",
            category: .session
        ) { modelRouter.autoApply.toggle() })

        commands.append(CommandItem(
            name: "Help & Shortcuts",
            icon: "keyboard",
            shortcut: "Cmd+?",
            subtitle: "View all keyboard shortcuts and features",
            category: .view
        ) {
            withAnimation(.easeOut(duration: 0.15)) {
                showHelp = true
            }
        })

        commands.append(CommandItem(
            name: "Multi-Agent View",
            icon: "rectangle.split.3x1.fill",
            shortcut: "Cmd+Shift+M",
            subtitle: "Side-by-side agent conversations",
            category: .agent
        ) { showMultiAgentView = true })

        // Model switcher commands
        for model in ModelChoice.allCases {
            let current = process.selectedModel == model
            commands.append(CommandItem(
                name: "Model: \(model.displayName)\(current ? " ✓" : "")",
                icon: model.icon,
                subtitle: "Switch to \(model.displayName) for next message",
                category: .session
            ) { process.selectedModel = model })
        }

        // Effort level commands
        for level in EffortLevel.allCases {
            let current = process.effortLevel == level
            commands.append(CommandItem(
                name: "Effort: \(level.displayName)\(current ? " ✓" : "")",
                icon: level.icon,
                subtitle: "Set effort to \(level.displayName.lowercased())",
                category: .session
            ) { process.effortLevel = level })
        }

        // Permission mode commands
        for mode in CLIPermissionMode.allCases {
            let current = process.permissionMode == mode
            commands.append(CommandItem(
                name: "Mode: \(mode.displayName)\(current ? " ✓" : "")",
                icon: mode == .bypassPermissions ? "lock.open" : mode == .plan ? "doc.text.magnifyingglass" : "lock",
                subtitle: mode.subtitle,
                category: .session
            ) { process.permissionMode = mode })
        }

        // Agent commands
        for role in AgentRole.allCases where role != .custom {
            commands.append(CommandItem(
                name: "Spawn \(role.displayName)",
                icon: role.icon,
                subtitle: "Create a new \(role.displayName.lowercased()) agent",
                category: .agent
            ) { [weak orchestrator] in
                orchestrator?.spawnAgent(
                    name: role.displayName,
                    role: role,
                    directory: process.workingDirectory
                )
                withAnimation { showAgentPanel = true }
            })
        }

        commands.append(CommandItem(
            name: "Build & Verify",
            icon: "hammer.fill",
            subtitle: "Run autonomous build-test-audit pipeline",
            category: .agent
        ) { [weak orchestrator] in
            if let dir = process.workingDirectory {
                orchestrator?.autoBuildVerify(projectDir: dir)
                withAnimation { showAgentPanel = true }
            }
        })

        commands.append(CommandItem(
            name: "Stop All Agents",
            icon: "xmark.octagon",
            subtitle: "Stop and remove all running agents",
            category: .agent
        ) {
            for agent in orchestrator.agents {
                orchestrator.stopAgent(id: agent.id)
            }
        })

        // Performance
        commands.append(CommandItem(
            name: "Performance Dashboard",
            icon: "chart.bar.fill",
            shortcut: "Cmd+Shift+P",
            subtitle: "Token usage, cost, timing analytics",
            category: .view
        ) {
            withAnimation(.easeOut(duration: 0.15)) {
                showPerformance = true
            }
        })

        // Plan Mode
        commands.append(CommandItem(
            name: "Toggle Plan Mode\(isPlanMode ? " ✓" : "")",
            icon: "doc.text.magnifyingglass",
            shortcut: "Shift+Tab",
            subtitle: isPlanMode ? "Exit plan mode — resume execution" : "Enter plan mode — suggest, don't execute",
            category: .session
        ) {
            withAnimation(.easeInOut(duration: 0.2)) {
                isPlanMode.toggle()
            }
        })

        // Vibe Coder Mode
        commands.append(CommandItem(
            name: "Toggle Vibe Coder\(process.isVibeCoder ? " ✓" : "")",
            icon: "sparkles",
            shortcut: "Ctrl+V",
            subtitle: process.isVibeCoder ? "Switch to full mode" : "Simplified view — hide the machinery",
            category: .view
        ) {
            withAnimation(.easeInOut(duration: 0.2)) {
                process.isVibeCoder.toggle()
                permissionManager.autoApproveAll = process.isVibeCoder
            }
        })

        // Autonomous Mode
        commands.append(CommandItem(
            name: "Toggle Autonomous Mode\(process.autonomousMode ? " ✓" : "")",
            icon: "bolt.shield.fill",
            shortcut: "Cmd+Shift+A",
            subtitle: process.autonomousMode ? "Disable autonomous operation" : "Bypass permissions + auto-retry for unattended operation",
            category: .session
        ) {
            withAnimation(.easeInOut(duration: 0.2)) {
                process.autonomousMode.toggle()
                if process.autonomousMode {
                    process.permissionMode = .bypassPermissions
                    compactionToastMessage = "Autonomous Mode ON — permissions bypassed, auto-retry enabled"
                } else {
                    process.permissionMode = .default_
                    compactionToastMessage = "Autonomous Mode OFF"
                }
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                withAnimation(.easeOut(duration: 0.3)) {
                    compactionToastMessage = nil
                }
            }
        })

        // Thinking toggle
        commands.append(CommandItem(
            name: "Toggle Thinking\(process.showThinking ? " ✓" : "")",
            icon: "brain.head.profile",
            shortcut: "Cmd+Shift+T",
            subtitle: process.showThinking ? "Hide thinking blocks" : "Show thinking blocks",
            category: .view
        ) { process.showThinking.toggle() })

        // Optimizations
        commands.append(CommandItem(
            name: "Toggle Optimizations\(process.optimizationsEnabled ? " ✓" : "")",
            icon: "bolt.fill",
            subtitle: process.optimizationsEnabled ? "3 optimizations active" : "Optimizations disabled",
            category: .session
        ) { process.optimizationsEnabled.toggle() })

        // Sound
        let soundEnabled = SoundManager.shared.isEnabled
        commands.append(CommandItem(
            name: "Sound \(soundEnabled ? "Off" : "On")",
            icon: soundEnabled ? "speaker.wave.2" : "speaker.slash",
            subtitle: soundEnabled ? "Disable sound effects" : "Enable subtle sound effects",
            category: .view
        ) {
            SoundManager.shared.toggle()
        })

        // Plugins
        commands.append(CommandItem(
            name: "Refresh Plugins",
            icon: "puzzlepiece.extension",
            subtitle: "Reload plugin list from Claude CLI",
            category: .session
        ) {
            Task { await PluginManager.shared.refresh() }
        })

        // Worktree
        commands.append(CommandItem(
            name: "New Worktree Session",
            icon: "arrow.triangle.branch",
            subtitle: "Start agent in isolated git worktree",
            category: .agent
        ) { [weak orchestrator] in
            let builder = orchestrator?.spawnAgent(
                name: "Worktree Builder",
                role: .builder,
                directory: process.workingDirectory
            )
            if let builder {
                if let agentProcess = orchestrator?.getProcess(for: builder.id) {
                    agentProcess.useWorktree = true
                }
                withAnimation { showAgentPanel = true }
            }
        })

        // Output modes
        for mode in OutputMode.allCases {
            let current = process.outputMode == mode
            commands.append(CommandItem(
                name: "Output: \(mode.displayName)\(current ? " \u{2713}" : "")",
                icon: mode.icon,
                subtitle: mode.systemPromptPrefix ?? "Default response style",
                category: .session
            ) { process.outputMode = mode })
        }

        // Undo
        commands.append(CommandItem(
            name: "Undo Last Response",
            icon: "arrow.uturn.backward",
            shortcut: "Cmd+Shift+Z",
            subtitle: "Remove last assistant message and re-prompt",
            category: .session
        ) { undoLastMessage() })

        // Terminal
        commands.append(CommandItem(
            name: "Terminal Command",
            icon: "terminal",
            shortcut: "Ctrl+T",
            subtitle: "Run a quick shell command",
            category: .session
        ) {
            withAnimation(.easeOut(duration: 0.15)) {
                showTerminalBar = true
            }
        })

        // Budget
        commands.append(CommandItem(
            name: "Set Budget Cap",
            icon: "dollarsign.circle",
            subtitle: process.maxBudgetUSD > 0 ? String(format: "Current: $%.0f", process.maxBudgetUSD) : "Current: No limit",
            category: .session
        ) {
            // Cycle between budget values (0 = no limit)
            let budgets: [Double] = [0, 5.0, 10.0, 25.0, 50.0]
            let currentIdx = budgets.firstIndex(of: process.maxBudgetUSD) ?? 0
            process.maxBudgetUSD = budgets[(currentIdx + 1) % budgets.count]
        })

        // Agent Teams (experimental)
        commands.append(CommandItem(
            name: "Agent Teams\(process.agentTeamsEnabled ? " \u{2713}" : "")",
            icon: "person.3.sequence.fill",
            subtitle: process.agentTeamsEnabled ? "Claude can spawn sub-agents autonomously" : "Enable autonomous agent spawning (experimental)",
            category: .agent
        ) { process.agentTeamsEnabled.toggle() })

        // Compact
        commands.append(CommandItem(
            name: "Compact Now",
            icon: "arrow.triangle.2.circlepath",
            subtitle: "Compact context immediately",
            category: .session
        ) { process.compact() })

        commands.append(CommandItem(
            name: "Compact with Instructions...",
            icon: "arrow.triangle.2.circlepath",
            subtitle: "Compact context, preserving specified context",
            category: .session
        ) {
            withAnimation(.easeOut(duration: 0.15)) {
                showCompactBar = true
            }
        })

        // Hooks Manager
        commands.append(CommandItem(
            name: "Manage Hooks",
            icon: "gearshape.2",
            shortcut: "Cmd+Shift+H",
            subtitle: "\(HooksManager.shared.totalCount) CLI hooks configured",
            category: .session
        ) {
            withAnimation(.easeOut(duration: 0.15)) {
                showHooksManager = true
            }
        })

        // Skills Browser
        commands.append(CommandItem(
            name: "Skills Browser",
            icon: "wand.and.stars",
            shortcut: "Cmd+Shift+K",
            subtitle: "\(SkillsManager.shared.skills.count) skills available",
            category: .session
        ) {
            withAnimation(.easeOut(duration: 0.15)) {
                showSkillsBrowser = true
            }
        })

        // Commands Browser
        commands.append(CommandItem(
            name: "Custom Commands",
            icon: "terminal.fill",
            shortcut: "Cmd+Shift+J",
            subtitle: "\(CommandsManager.shared.commands.count) commands available",
            category: .session
        ) {
            withAnimation(.easeOut(duration: 0.15)) {
                showCommandsBrowser = true
            }
        })

        // Dynamic command invocation entries
        for command in CommandsManager.shared.commands {
            commands.append(CommandItem(
                name: "Run: /\(command.name)",
                icon: "terminal.fill",
                subtitle: command.description.isEmpty ? "Run command" : String(command.description.prefix(60)),
                category: .agent
            ) {
                CommandsManager.shared.invokeCommand(name: command.name, process: process)
            })
        }

        // MCP Server Manager
        commands.append(CommandItem(
            name: "MCP Servers",
            icon: "server.rack",
            shortcut: "Cmd+Shift+I",
            subtitle: "\(MCPServerManager.shared.servers.count) servers configured",
            category: .session
        ) {
            withAnimation(.easeOut(duration: 0.15)) {
                showMCPManager = true
            }
        })

        // Gemini
        commands.append(CommandItem(
            name: "Ask Gemini...",
            icon: "sparkles",
            shortcut: "Cmd+Shift+G",
            subtitle: "Second opinion, long-context tasks, free Gemini Flash",
            category: .agent
        ) {
            withAnimation(.easeOut(duration: 0.15)) {
                showGeminiPanel = true
            }
        })

        // Dev Tools
        commands.append(CommandItem(
            name: "Dev Tools",
            icon: "hammer.fill",
            shortcut: "Cmd+Shift+L",
            subtitle: "CodeRabbit · SwiftLint · Periphery · Fastlane",
            category: .session
        ) {
            withAnimation(.easeOut(duration: 0.15)) {
                showDevToolPanel = true
            }
        })

        commands.append(CommandItem(
            name: "Review with CodeRabbit",
            icon: "doc.text.magnifyingglass",
            subtitle: "AI code review on the current git diff",
            category: .session
        ) {
            if let dir = process.workingDirectory {
                DevToolService.shared.run(.codeRabbit, projectDir: dir)
                withAnimation(.easeOut(duration: 0.15)) { showDevToolPanel = true }
            }
        })

        commands.append(CommandItem(
            name: "Lint Project (SwiftLint)",
            icon: "checkmark.seal",
            subtitle: "Run SwiftLint on the current project",
            category: .session
        ) {
            if let dir = process.workingDirectory {
                DevToolService.shared.run(.swiftLint, projectDir: dir)
                withAnimation(.easeOut(duration: 0.15)) { showDevToolPanel = true }
            }
        })

        commands.append(CommandItem(
            name: "Dead Code Scan (Periphery)",
            icon: "eye.slash",
            subtitle: "Find unused declarations in the project",
            category: .session
        ) {
            if let dir = process.workingDirectory {
                DevToolService.shared.run(.periphery, projectDir: dir)
                withAnimation(.easeOut(duration: 0.15)) { showDevToolPanel = true }
            }
        })

        // Dynamic skill invocation entries
        for skill in SkillsManager.shared.skills {
            commands.append(CommandItem(
                name: "Invoke: \(skill.name)",
                icon: "wand.and.stars",
                subtitle: skill.description.isEmpty ? "Run skill" : String(skill.description.prefix(60)),
                category: .agent
            ) {
                SkillsManager.shared.invokeSkill(name: skill.name, process: process)
            })
        }

        // One-click workflow presets
        commands.append(CommandItem(
            name: "Workflow: Audit Codebase",
            icon: "shield.checkered",
            subtitle: "Security + Quality + Performance scan (3 agents)",
            category: .agent
        ) { [weak orchestrator] in
            if let orch = orchestrator, let dir = process.workingDirectory {
                orch.runAuditWorkflow(projectDir: dir)
                withAnimation { showAgentPanel = true }
            }
        })

        commands.append(CommandItem(
            name: "Workflow: Parallel Research",
            icon: "magnifyingglass.circle.fill",
            subtitle: "Codebase + Pattern analysis (2 agents)",
            category: .agent
        ) { [weak orchestrator] in
            if let orch = orchestrator, let dir = process.workingDirectory {
                let question = process.lastUserMessage ?? "Analyze the architecture and patterns in this codebase"
                orch.runResearchWorkflow(projectDir: dir, question: question)
                withAnimation { showAgentPanel = true }
            }
        })

        // Agent presets
        for preset in AgentPresets.shared.presets {
            let memoryIcon = preset.memoryEnabled ? " \u{1F9E0}" : ""
            commands.append(CommandItem(
                name: "Spawn: \(preset.name)\(memoryIcon)",
                icon: preset.icon,
                subtitle: preset.customSystemPrompt?.prefix(60).description ?? preset.role.displayName,
                category: .agent
            ) { [weak orchestrator] in
                if let orch = orchestrator {
                    _ = AgentPresets.shared.spawn(presetId: preset.id, orchestrator: orch, directory: process.workingDirectory)
                    withAnimation { showAgentPanel = true }
                }
            })

            // Toggle memory for this preset
            commands.append(CommandItem(
                name: "Memory: \(preset.name)\(preset.memoryEnabled ? " \u{2713}" : "")",
                icon: "brain",
                subtitle: preset.memoryEnabled ? "Disable persistent memory for \(preset.name)" : "Enable persistent memory for \(preset.name)",
                category: .agent
            ) {
                var updated = preset
                updated.memoryEnabled.toggle()
                AgentPresets.shared.update(updated)
            })
        }

        return commands
    }

    // MARK: - Conductor Self-Awareness Prompt

    /// System prompt that gives Claude awareness of running inside Conductor
    /// Sets the quality bar and agent discipline for every session
    private static let conductorSystemPrompt = """
    You are running inside **Conductor**, a native macOS app wrapping Claude Code CLI. \
    When the user says "this app", they mean Conductor. All your normal tools work as usual.

    Sessions persist automatically — Conductor saves CONTEXT_STATE.md and session artifacts. \
    If a project has CONTEXT_STATE.md, read it at session start.

    ## Quality Standard
    Every output is production-grade. No shortcuts, no lazy passes, no "good enough." \
    Code is clean, typed, handles real edge cases. Design is intentional. Plans are thorough. \
    Strategy is researched. Copy is crafted. If it ships, it must be best-in-class. \
    Read the full code path before changing anything. Understand before you act.

    ## Verification
    After code changes: build. If it fails, fix it — do not report success on a broken build. \
    After features or multi-file changes: review your own work for bugs, regressions, and missed edges. \
    The standard is not "it compiles" — the standard is "this is ready for users."

    ## Agent Discipline
    Use agents to produce better work, not to go faster on trivial tasks:
    - **Research first** — on unfamiliar codebases or complex tasks, use Explore agents to understand \
      the architecture before writing code. Do not guess.
    - **Plan before building** — for work touching 5+ files or introducing new patterns, \
      use a Plan agent to design the approach. Measure twice, cut once.
    - **Verify after building** — for features and multi-file changes, spawn a review agent to audit \
      what you wrote. A second pass catches what the first missed.
    - **Parallelize when independent** — run independent research or tasks concurrently.
    For single-file fixes and direct lookups, work inline — agents add cost without value on small tasks.

    ## Self-Improvement
    Conductor's settings, system prompt, and agent presets live in the Conductor codebase. \
    If you identify ways to improve how Conductor configures or orchestrates Claude sessions, \
    surface the suggestion. The system should evolve.
    """

    /// Open folder picker to change working directory
    private func openDirectoryPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Choose Working Directory"
        panel.prompt = "Select"

        if panel.runModal() == .OK, let url = panel.url {
            let path = url.path
            process.stop()
            process.start(directory: path)
            detectGitBranch(in: path)

            // Offer to scaffold optimized Claude instructions if not already set up
            if !TemplateScaffolder.shared.hasProjectScaffold(at: url) {
                pendingScaffoldURL = url
                showScaffoldPrompt = true
            }
        }
    }

    private func shortenPath(_ path: String) -> String {
        let components = path.components(separatedBy: "/").filter { !$0.isEmpty }
        if components.count <= 2 { return path }
        return components.suffix(2).joined(separator: "/")
    }

    /// Undo last assistant message — removes last assistant+user pair
    private func undoLastMessage() {
        guard process.messages.count >= 2 else { return }
        // Remove last assistant message
        if process.messages.last?.role == .assistant {
            process.messages.removeLast()
        }
        // Remove the user message that prompted it
        if process.messages.last?.role == .user {
            process.messages.removeLast()
        }
        SoundManager.shared.playResponseComplete() // Subtle ack
    }

    /// Check if an NSTextView has keyboard focus (prevents shortcuts from eating typed characters)
    private var isTextInputActive: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        return responder is NSTextView
    }

    /// Run a shell command and show output in conversation
    private func runTerminalCommand(_ command: String) {
        process.send("Run this shell command and show the output:\n```\n\(command)\n```")
    }

    /// Toggle pin state on a message
    private func togglePin(messageId: String) {
        if let idx = process.messages.firstIndex(where: { $0.id == messageId }) {
            process.messages[idx].isPinned.toggle()
        }
    }

    /// Get all pinned messages
    private var pinnedMessages: [ConversationMessage] {
        process.messages.filter { $0.isPinned }
    }

    /// Export conversation as markdown via NSSavePanel
    private func exportConversation() {
        guard !process.messages.isEmpty else { return }

        var markdown = "# Conductor Conversation\n\n"
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short
        markdown += "*Exported \(dateFormatter.string(from: Date()))*\n\n---\n\n"

        for message in process.messages {
            let header = message.role == .user ? "## You" : "## Claude"
            markdown += "\(header)\n\n\(message.copyText())\n\n---\n\n"
        }

        let panel = NSSavePanel()
        let dateSuffix = DateFormatter()
        dateSuffix.dateFormat = "yyyy-MM-dd"
        panel.nameFieldStringValue = "conductor-\(dateSuffix.string(from: Date())).md"
        panel.allowedContentTypes = [.plainText]
        panel.title = "Export Conversation"

        if panel.runModal() == .OK, let url = panel.url {
            try? markdown.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Perform full closeout: send prompt to Claude, wait, then execute completion
    private func performCloseout(completion: @escaping () -> Void) {
        closeoutManager.beginCloseout(process: process) { [self] in
            self.saveSessionState()
            completion()
        }
    }

    /// End Session: closeout then start a new session
    private func performEndSession() {
        closeoutManager.beginCloseout(process: process) { [self] in
            self.saveSessionState()
            self.startNewSession()
        }
    }

    /// Save session state on app termination
    private func saveSessionState() {
        guard let session = windowSession else { return }
        sessionContinuity.saveSessionEnd(
            sessionId: session.id,
            projectPath: session.projectPath,
            process: process,
            contextManager: contextManager
        )
        sessionManager.endSession(id: session.id, messages: process.messages)
    }

    /// Startup health check — detect common issues and surface as dismissible banner
    private func runHealthCheck() {
        Task {
            var issues: [HealthIssue] = []
            let home = FileManager.default.homeDirectoryForCurrentUser.path

            // 1. Check CLI exists
            let candidates = [
                "\(home)/.local/bin/claude",
                "/usr/local/bin/claude",
                "/opt/homebrew/bin/claude"
            ]
            if candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) == nil {
                issues.append(HealthIssue(
                    severity: .error,
                    title: "Claude CLI not found",
                    detail: "Install with: npm install -g @anthropic-ai/claude-code"
                ))
            }

            // 2. Check settings.json is valid JSON
            let settingsPath = "\(home)/.claude/settings.json"
            if FileManager.default.fileExists(atPath: settingsPath) {
                if let data = FileManager.default.contents(atPath: settingsPath),
                   (try? JSONSerialization.jsonObject(with: data)) == nil {
                    issues.append(HealthIssue(
                        severity: .warning,
                        title: "Invalid settings.json",
                        detail: "~/.claude/settings.json contains invalid JSON"
                    ))
                }
            }

            // 3. Check disk space for session files
            if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: home),
               let freeSpace = attrs[.systemFreeSize] as? Int64,
               freeSpace < 100_000_000 {
                issues.append(HealthIssue(
                    severity: .warning,
                    title: "Low disk space",
                    detail: "Less than 100MB free — session files may fail to save"
                ))
            }

            healthIssues = issues
        }
    }
}

// MARK: - Health Check Types

struct HealthIssue: Identifiable {
    let id = UUID()
    let severity: HealthSeverity
    let title: String
    let detail: String
}

enum HealthSeverity {
    case error, warning, info
}

// MARK: - Terminal Passthrough Bar

/// Quick shell command bar (Ctrl+T) — runs command via Claude
struct TerminalBar: View {
    @Binding var command: String
    @Binding var isPresented: Bool
    var onExecute: (String) -> Void
    @EnvironmentObject private var theme: ThemeEngine
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.system(size: 12))
                .foregroundColor(theme.sage)

            Text("$")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(theme.sage)

            TextField("command...", text: $command)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(theme.primary)
                .focused($isFocused)
                .onSubmit {
                    let cmd = command.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cmd.isEmpty else { return }
                    onExecute(cmd)
                }

            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(theme.muted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(theme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.sage.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
        .onAppear { isFocused = true }
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
    }
}

// MARK: - Compact Instructions Bar

/// Bar for entering optional instructions before context compaction
struct CompactInstructionsBar: View {
    @Binding var instructions: String
    @Binding var isPresented: Bool
    var onCompact: (String) -> Void
    @EnvironmentObject private var theme: ThemeEngine
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 12))
                .foregroundColor(theme.sky)

            Text("Compact:")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(theme.sky)

            TextField("Preserve... (leave empty for default compaction)", text: $instructions)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(theme.primary)
                .focused($isFocused)
                .onSubmit {
                    onCompact(instructions)
                }

            Button {
                onCompact(instructions)
            } label: {
                Text("Compact")
                    .font(Typography.bodyBold)
                    .foregroundColor(theme.sky)
            }
            .buttonStyle(.plain)

            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(theme.muted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(theme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.sky.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
        .onAppear { isFocused = true }
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
    }
}

// MARK: - Window Close Interceptor

/// Intercepts window close (Cmd+W / X button) to trigger graceful closeout.
/// Sets itself as the NSWindow's delegate to intercept `windowShouldClose`.
struct WindowCloseInterceptor: NSViewRepresentable {
    let closeoutManager: SessionCloseoutManager
    let process: ClaudeProcess
    let onCloseout: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // Defer window access to next run loop — window isn't assigned yet during makeNSView
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            context.coordinator.window = window
            context.coordinator.originalDelegate = window.delegate
            window.delegate = context.coordinator
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.closeoutManager = closeoutManager
        context.coordinator.process = process
        context.coordinator.onCloseout = onCloseout
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(closeoutManager: closeoutManager, process: process, onCloseout: onCloseout)
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        var closeoutManager: SessionCloseoutManager
        var process: ClaudeProcess
        var onCloseout: () -> Void
        weak var window: NSWindow?
        weak var originalDelegate: NSWindowDelegate?

        init(closeoutManager: SessionCloseoutManager, process: ClaudeProcess, onCloseout: @escaping () -> Void) {
            self.closeoutManager = closeoutManager
            self.process = process
            self.onCloseout = onCloseout
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            // Already closing out — second click = close immediately
            if closeoutManager.isClosingOut {
                return true
            }

            // No session or no real work — close immediately
            if !process.isRunning || !process.hasSubstantiveWork {
                return true
            }

            // Begin graceful closeout
            Task { @MainActor [weak self] in
                guard let self, let window = self.window else { return }
                self.closeoutManager.beginCloseout(process: self.process) {
                    self.onCloseout()
                    window.close()
                }
            }

            // Prevent immediate close — closeout will call window.close() when done
            return false
        }

        // Forward other delegate methods to original delegate
        func windowWillClose(_ notification: Notification) {
            originalDelegate?.windowWillClose?(notification)
        }

        func windowDidBecomeKey(_ notification: Notification) {
            originalDelegate?.windowDidBecomeKey?(notification)
        }

        func windowDidResignKey(_ notification: Notification) {
            originalDelegate?.windowDidResignKey?(notification)
        }

        func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
            originalDelegate?.windowWillResize?(sender, to: frameSize) ?? frameSize
        }
    }
}
