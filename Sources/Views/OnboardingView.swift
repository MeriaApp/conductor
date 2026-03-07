import SwiftUI

/// Full guided setup wizard for new users
/// 5-step flow: Welcome → Node.js Check → CLI Install → Authentication → Shortcuts
struct OnboardingView: View {
    @EnvironmentObject private var theme: ThemeEngine
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var step = 0

    // Detection state
    @State private var nodeFound = false
    @State private var nodeVersion: String?
    @State private var cliFound = false
    @State private var cliPath: String?
    @State private var cliVersion: String?
    @State private var isAuthenticated = false
    @State private var testPassed = false

    // Action state
    @State private var isInstallingCLI = false
    @State private var installOutput: String?
    @State private var installError: String?
    @State private var isRunningTest = false
    @State private var testOutput: String?
    @State private var isCheckingAuth = false

    // Confirmation state — explain before triggering system dialogs
    @State private var showInstallConfirm = false
    @State private var showAuthConfirm = false
    @State private var showTestConfirm = false

    private let totalSteps = 5

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 32) {
                // Step content
                switch step {
                case 0:
                    welcomeStep
                case 1:
                    nodeCheckStep
                case 2:
                    cliInstallStep
                case 3:
                    authStep
                default:
                    shortcutsStep
                }

                // Navigation
                HStack(spacing: 16) {
                    if step > 0 {
                        Button("Back") { withAnimation { step -= 1 } }
                            .buttonStyle(.plain)
                            .foregroundColor(theme.muted)
                    }

                    Spacer()

                    // Step dots
                    HStack(spacing: 6) {
                        ForEach(0..<totalSteps, id: \.self) { i in
                            Circle()
                                .fill(i == step ? theme.sky : (i < step ? theme.sage : theme.muted.opacity(0.3)))
                                .frame(width: 6, height: 6)
                        }
                    }

                    Spacer()

                    if step < totalSteps - 1 {
                        let canAdvance = canProceedFromStep(step)
                        Button("Next") { withAnimation { step += 1 } }
                            .buttonStyle(.plain)
                            .foregroundColor(canAdvance ? theme.sky : theme.muted.opacity(0.4))
                            .font(Typography.bodyBold)
                            .disabled(!canAdvance)
                    } else {
                        Button("Get Started") {
                            TemplateScaffolder.shared.scaffoldUserLevel()
                            hasCompletedOnboarding = true
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(theme.base)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(theme.sky)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .frame(maxWidth: 520)
            .padding(40)
            .background(theme.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(theme.separator.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 30, y: 10)

            Spacer()

            // Skip button — only for users who know what they're doing
            Button("Skip setup (I already have Claude CLI)") {
                TemplateScaffolder.shared.scaffoldUserLevel()
                hasCompletedOnboarding = true
            }
            .buttonStyle(.plain)
            .font(Typography.caption)
            .foregroundColor(theme.muted)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.base)
        .onAppear { runAllChecks() }
    }

    // MARK: - Step Navigation Logic

    private func canProceedFromStep(_ step: Int) -> Bool {
        switch step {
        case 0: return true // Welcome — always
        case 1: return nodeFound // Node.js must be found
        case 2: return cliFound // CLI must be installed
        case 3: return true // Auth is recommended but not blocking
        default: return true
        }
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "diamond.fill")
                .font(.system(size: 48))
                .foregroundColor(theme.sky)

            Text("Welcome to Conductor")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(theme.bright)

            Text("A native macOS interface for Claude Code.\nMulti-agent orchestration, context management,\nand a beautiful development experience.")
                .font(Typography.body)
                .foregroundColor(theme.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            // What you'll need
            VStack(alignment: .leading, spacing: 8) {
                Text("This setup will check for:")
                    .font(Typography.caption)
                    .foregroundColor(theme.muted)

                requirementRow("Node.js", "Required to install Claude CLI", nodeFound)
                requirementRow("Claude CLI", "The engine that powers Conductor", cliFound)
                requirementRow("Anthropic Account", "API key or Claude Max subscription", isAuthenticated)
            }
            .padding(16)
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func requirementRow(_ name: String, _ desc: String, _ satisfied: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: satisfied ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14))
                .foregroundColor(satisfied ? theme.sage : theme.muted.opacity(0.4))

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(Typography.bodyBold)
                    .foregroundColor(theme.primary)
                Text(desc)
                    .font(Typography.caption)
                    .foregroundColor(theme.muted)
            }

            Spacer()
        }
    }

    // MARK: - Step 2: Node.js Check

    private var nodeCheckStep: some View {
        VStack(spacing: 16) {
            Image(systemName: nodeFound ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(nodeFound ? theme.sage : theme.amber)

            Text("Node.js")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(theme.bright)

            if nodeFound, let version = nodeVersion {
                VStack(spacing: 8) {
                    Text("Installed")
                        .font(Typography.body)
                        .foregroundColor(theme.sage)

                    codeLabel(version)
                }
            } else {
                VStack(spacing: 16) {
                    Text("Node.js is required to install Claude CLI.")
                        .font(Typography.body)
                        .foregroundColor(theme.secondary)
                        .multilineTextAlignment(.center)

                    Text("Install Node.js from:")
                        .font(Typography.caption)
                        .foregroundColor(theme.muted)

                    // Option 1: Official installer
                    VStack(alignment: .leading, spacing: 8) {
                        installOption(
                            title: "Official Installer (Recommended)",
                            detail: "Download from nodejs.org",
                            action: {
                                NSWorkspace.shared.open(URL(string: "https://nodejs.org")!)
                            },
                            buttonLabel: "Open nodejs.org"
                        )

                        Divider()
                            .background(theme.separator)

                        installOption(
                            title: "Homebrew",
                            detail: "If you have Homebrew installed",
                            code: "brew install node"
                        )
                    }
                    .padding(12)
                    .background(theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    Button("Re-check") {
                        detectNode()
                    }
                    .buttonStyle(.plain)
                    .font(Typography.bodyBold)
                    .foregroundColor(theme.sky)
                }
            }
        }
    }

    // MARK: - Step 3: Claude CLI Install

    private var cliInstallStep: some View {
        VStack(spacing: 16) {
            Image(systemName: cliFound ? "checkmark.circle.fill" : "arrow.down.circle")
                .font(.system(size: 40))
                .foregroundColor(cliFound ? theme.sage : theme.sky)

            Text("Claude CLI")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(theme.bright)

            if cliFound {
                VStack(spacing: 8) {
                    Text("Installed")
                        .font(Typography.body)
                        .foregroundColor(theme.sage)

                    if let path = cliPath {
                        codeLabel(path)
                    }
                    if let version = cliVersion {
                        Text("Version: \(version)")
                            .font(Typography.caption)
                            .foregroundColor(theme.muted)
                    }
                }
            } else if isInstallingCLI {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Installing Claude CLI...")
                        .font(Typography.body)
                        .foregroundColor(theme.secondary)
                    Text("This may take a minute")
                        .font(Typography.caption)
                        .foregroundColor(theme.muted)
                }
            } else if let error = installError {
                VStack(spacing: 12) {
                    Text("Installation failed")
                        .font(Typography.body)
                        .foregroundColor(theme.rose)

                    Text(error)
                        .font(Typography.codeBlock)
                        .foregroundColor(theme.rose.opacity(0.8))
                        .padding(8)
                        .background(theme.codeBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .lineLimit(4)

                    Text("Try installing manually:")
                        .font(Typography.caption)
                        .foregroundColor(theme.muted)

                    codeLabel("npm install -g @anthropic-ai/claude-code")

                    HStack(spacing: 12) {
                        Button("Try Again") { installCLI() }
                            .buttonStyle(.plain)
                            .font(Typography.bodyBold)
                            .foregroundColor(theme.sky)

                        Button("Re-check") { detectCLI() }
                            .buttonStyle(.plain)
                            .font(Typography.bodyBold)
                            .foregroundColor(theme.muted)
                    }
                }
            } else if showInstallConfirm {
                // Explain what's about to happen before doing it
                systemActionCard(
                    icon: "lock.shield",
                    title: "Before we install",
                    explanation: "Conductor will run this command to install the Claude CLI:",
                    command: "npm install -g @anthropic-ai/claude-code",
                    details: "macOS may ask for your password to install globally. This is normal — npm needs write access to your system's package directory.",
                    confirmLabel: "Go Ahead",
                    cancelLabel: "Cancel",
                    onConfirm: {
                        showInstallConfirm = false
                        installCLI()
                    },
                    onCancel: { showInstallConfirm = false }
                )
            } else {
                VStack(spacing: 16) {
                    Text("Claude CLI powers everything in Conductor.\nLet's install it now.")
                        .font(Typography.body)
                        .foregroundColor(theme.secondary)
                        .multilineTextAlignment(.center)

                    codeLabel("npm install -g @anthropic-ai/claude-code")

                    HStack(spacing: 12) {
                        Button {
                            showInstallConfirm = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.down.circle.fill")
                                Text("Install Now")
                            }
                            .font(Typography.bodyBold)
                            .foregroundColor(theme.base)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(theme.sky)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)

                        Button("I'll install manually") {
                            // Just let them re-check
                        }
                        .buttonStyle(.plain)
                        .font(Typography.caption)
                        .foregroundColor(theme.muted)
                    }

                    Button("Re-check") { detectCLI() }
                        .buttonStyle(.plain)
                        .font(Typography.caption)
                        .foregroundColor(theme.muted)
                }
            }
        }
    }

    // MARK: - Step 4: Authentication

    private var authStep: some View {
        VStack(spacing: 16) {
            Image(systemName: isAuthenticated ? "checkmark.circle.fill" : "person.circle")
                .font(.system(size: 40))
                .foregroundColor(isAuthenticated ? theme.sage : theme.sky)

            Text("Authentication")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(theme.bright)

            if isAuthenticated {
                VStack(spacing: 8) {
                    Text("Authenticated")
                        .font(Typography.body)
                        .foregroundColor(theme.sage)

                    if testPassed {
                        Text("Test prompt succeeded")
                            .font(Typography.caption)
                            .foregroundColor(theme.sage)
                    }
                }
            } else if isCheckingAuth {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Checking authentication...")
                        .font(Typography.body)
                        .foregroundColor(theme.secondary)
                }
            } else if isRunningTest {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Running test prompt...")
                        .font(Typography.body)
                        .foregroundColor(theme.secondary)
                    Text("Verifying Claude CLI works end-to-end")
                        .font(Typography.caption)
                        .foregroundColor(theme.muted)
                }
            } else if showAuthConfirm {
                systemActionCard(
                    icon: "terminal",
                    title: "Opening Terminal",
                    explanation: "Conductor will open the Terminal app and run:",
                    command: "claude auth login",
                    details: "This will open your browser to sign in with your Anthropic account. Your credentials are stored locally by the Claude CLI — Conductor never sees them.",
                    confirmLabel: "Open Terminal",
                    cancelLabel: "Cancel",
                    onConfirm: {
                        showAuthConfirm = false
                        openTerminalWithCommand("claude auth login")
                    },
                    onCancel: { showAuthConfirm = false }
                )
            } else if showTestConfirm {
                systemActionCard(
                    icon: "play.circle",
                    title: "Running a test prompt",
                    explanation: "Conductor will send a simple test message to Claude to verify everything works:",
                    command: "claude -p \"Reply with: Conductor setup successful\"",
                    details: "This uses your API credits — it's a tiny request (a few cents at most). If macOS asks to allow a network connection, that's the CLI reaching Anthropic's servers.",
                    confirmLabel: "Run Test",
                    cancelLabel: "Cancel",
                    onConfirm: {
                        showTestConfirm = false
                        runTestPrompt()
                    },
                    onCancel: { showTestConfirm = false }
                )
            } else {
                VStack(spacing: 16) {
                    Text("Claude CLI needs to be authenticated\nwith your Anthropic account.")
                        .font(Typography.body)
                        .foregroundColor(theme.secondary)
                        .multilineTextAlignment(.center)

                    VStack(alignment: .leading, spacing: 12) {
                        authOption(
                            title: "Claude Max / Pro Subscription",
                            detail: "If you have a Claude subscription, authenticate via browser:",
                            code: "claude auth login",
                            buttonLabel: "Open Terminal to Authenticate",
                            action: { showAuthConfirm = true }
                        )

                        Divider()
                            .background(theme.separator)

                        authOption(
                            title: "API Key",
                            detail: "If you have an Anthropic API key, set it as an environment variable:",
                            code: "export ANTHROPIC_API_KEY=sk-ant-...",
                            buttonLabel: nil,
                            action: nil
                        )
                    }
                    .padding(12)
                    .background(theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    HStack(spacing: 12) {
                        Button {
                            showTestConfirm = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "play.circle.fill")
                                Text("Test Connection")
                            }
                            .font(Typography.bodyBold)
                            .foregroundColor(theme.base)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(theme.sky)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)

                        Button("Re-check") { checkAuth() }
                            .buttonStyle(.plain)
                            .font(Typography.caption)
                            .foregroundColor(theme.muted)
                    }

                    if let output = testOutput {
                        Text(output)
                            .font(Typography.codeBlock)
                            .foregroundColor(output.contains("Error") || output.contains("error") ? theme.rose : theme.sage)
                            .padding(8)
                            .background(theme.codeBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .lineLimit(3)
                    }
                }
            }
        }
    }

    // MARK: - Step 5: Shortcuts

    private var shortcutsStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundColor(theme.sky)

            Text("You're all set")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(theme.bright)

            Text("Here are the shortcuts you'll use most:")
                .font(Typography.body)
                .foregroundColor(theme.secondary)

            VStack(alignment: .leading, spacing: 8) {
                shortcutRow("Cmd+K", "Command Palette — find anything")
                shortcutRow("Cmd+F", "Search conversation")
                shortcutRow("Cmd+S", "Browse & resume sessions")
                shortcutRow("Ctrl+V", "Vibe Coder — simplified mode")
                shortcutRow("Tab", "Toggle dashboard sidebar")
                shortcutRow("?", "All shortcuts")
            }

            Text("Type a message in the input bar to start your first conversation.")
                .font(Typography.caption)
                .foregroundColor(theme.muted)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
    }

    // MARK: - System Action Confirmation Card

    /// Explains what's about to happen before triggering any system dialog or external action.
    /// Shows the command, why it needs access, and lets the user confirm or cancel.
    private func systemActionCard(
        icon: String,
        title: String,
        explanation: String,
        command: String,
        details: String,
        confirmLabel: String,
        cancelLabel: String,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(theme.amber)

            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(theme.bright)

            Text(explanation)
                .font(Typography.body)
                .foregroundColor(theme.secondary)
                .multilineTextAlignment(.center)

            codeLabel(command)

            Text(details)
                .font(Typography.caption)
                .foregroundColor(theme.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 8)

            HStack(spacing: 16) {
                Button(cancelLabel) { onCancel() }
                    .buttonStyle(.plain)
                    .font(Typography.body)
                    .foregroundColor(theme.muted)

                Button {
                    onConfirm()
                } label: {
                    Text(confirmLabel)
                        .font(Typography.bodyBold)
                        .foregroundColor(theme.base)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(theme.sky)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Reusable Components

    private func shortcutRow(_ key: String, _ desc: String) -> some View {
        HStack(spacing: 12) {
            Text(key)
                .font(Typography.codeBlock)
                .foregroundColor(theme.sky)
                .frame(width: 80, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 3))

            Text(desc)
                .font(Typography.body)
                .foregroundColor(theme.primary)
        }
    }

    private func codeLabel(_ text: String) -> some View {
        Text(text)
            .font(Typography.codeBlock)
            .foregroundColor(theme.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(theme.codeBackground)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .textSelection(.enabled)
    }

    private func installOption(title: String, detail: String, code: String? = nil, action: (() -> Void)? = nil, buttonLabel: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Typography.bodyBold)
                .foregroundColor(theme.primary)

            Text(detail)
                .font(Typography.caption)
                .foregroundColor(theme.muted)

            if let code = code {
                codeLabel(code)
            }

            if let buttonLabel = buttonLabel, let action = action {
                Button(action: action) {
                    Text(buttonLabel)
                        .font(Typography.caption)
                        .foregroundColor(theme.sky)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func authOption(title: String, detail: String, code: String, buttonLabel: String?, action: (() -> Void)?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Typography.bodyBold)
                .foregroundColor(theme.primary)

            Text(detail)
                .font(Typography.caption)
                .foregroundColor(theme.muted)

            codeLabel(code)

            if let buttonLabel = buttonLabel, let action = action {
                Button(action: action) {
                    Text(buttonLabel)
                        .font(Typography.caption)
                        .foregroundColor(theme.sky)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Detection & Actions

    private func runAllChecks() {
        detectNode()
        detectCLI()
        checkAuth()
    }

    private func detectNode() {
        Task {
            let result = await runCommand("/usr/bin/env", arguments: ["node", "--version"])
            await MainActor.run {
                if let output = result.output, !output.isEmpty, result.exitCode == 0 {
                    nodeFound = true
                    nodeVersion = output.trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    // Also check common paths directly
                    let paths = ["/usr/local/bin/node", "/opt/homebrew/bin/node"]
                    for path in paths {
                        if FileManager.default.fileExists(atPath: path) {
                            nodeFound = true
                            nodeVersion = "Found at \(path)"
                            return
                        }
                    }
                    nodeFound = false
                    nodeVersion = nil
                }
            }
        }
    }

    private func detectCLI() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude"
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                cliFound = true
                cliPath = path
                // Get version
                Task {
                    let result = await runCommand(path, arguments: ["--version"])
                    await MainActor.run {
                        if let output = result.output {
                            cliVersion = output.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                }
                return
            }
        }
        cliFound = false
        cliPath = nil
        cliVersion = nil
    }

    private func installCLI() {
        isInstallingCLI = true
        installError = nil
        installOutput = nil

        Task {
            let result = await runCommand("/usr/bin/env", arguments: ["npm", "install", "-g", "@anthropic-ai/claude-code"])
            await MainActor.run {
                isInstallingCLI = false
                if result.exitCode == 0 {
                    installOutput = result.output
                    detectCLI()
                } else {
                    installError = result.error ?? result.output ?? "Unknown error"
                }
            }
        }
    }

    private func checkAuth() {
        guard cliFound, let path = cliPath else { return }
        isCheckingAuth = true

        Task {
            // Check if claude auth is configured by running `claude auth status`
            let result = await runCommand(path, arguments: ["auth", "status"])
            await MainActor.run {
                isCheckingAuth = false
                if result.exitCode == 0, let output = result.output,
                   output.contains("authenticated") || output.contains("Logged in") || output.contains("API key") {
                    isAuthenticated = true
                } else {
                    // Also check for ANTHROPIC_API_KEY env var
                    if ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] != nil {
                        isAuthenticated = true
                    }
                }
            }
        }
    }

    private func runTestPrompt() {
        guard let path = cliPath else { return }
        isRunningTest = true
        testOutput = nil

        Task {
            let result = await runCommand(path, arguments: [
                "-p", "Reply with exactly: Conductor setup successful",
                "--output-format", "text",
                "--dangerously-skip-permissions"
            ])
            await MainActor.run {
                isRunningTest = false
                if result.exitCode == 0, let output = result.output {
                    testOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    testPassed = true
                    isAuthenticated = true
                } else {
                    testOutput = "Error: \(result.error ?? result.output ?? "Claude CLI did not respond")"
                    testPassed = false
                }
            }
        }
    }

    private func openTerminalWithCommand(_ command: String) {
        let script = """
        tell application "Terminal"
            activate
            do script "\(command)"
        end tell
        """
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }

    // MARK: - Shell Command Runner

    private func runCommand(_ path: String, arguments: [String]) async -> CommandResult {
        await withCheckedContinuation { continuation in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: path)
            proc.arguments = arguments

            // Inherit PATH so node/npm are findable
            var env = ProcessInfo.processInfo.environment
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let extraPaths = [
                "\(home)/.local/bin",
                "/usr/local/bin",
                "/opt/homebrew/bin",
                "\(home)/.nvm/versions/node/*/bin"  // nvm users
            ]
            if let existingPath = env["PATH"] {
                env["PATH"] = extraPaths.joined(separator: ":") + ":" + existingPath
            }
            proc.environment = env

            let stdout = Pipe()
            let stderr = Pipe()
            proc.standardOutput = stdout
            proc.standardError = stderr

            proc.terminationHandler = { process in
                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: CommandResult(
                    exitCode: Int(process.terminationStatus),
                    output: String(data: outData, encoding: .utf8),
                    error: String(data: errData, encoding: .utf8)
                ))
            }

            do {
                try proc.run()
            } catch {
                continuation.resume(returning: CommandResult(
                    exitCode: -1,
                    output: nil,
                    error: error.localizedDescription
                ))
            }
        }
    }
}

// MARK: - Command Result

private struct CommandResult {
    let exitCode: Int
    let output: String?
    let error: String?
}
