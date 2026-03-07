import SwiftUI

@main
struct ConductorApp: App {
    @NSApplicationDelegateAdaptor(ConductorAppDelegate.self) var appDelegate

    init() {
        // Allow window tabbing — each window gets independent state via SessionStateContainer
        NSWindow.allowsAutomaticWindowTabbing = true
    }

    // Global services (shared across all windows)
    @StateObject private var themeEngine = ThemeEngine.shared
    @StateObject private var sessionManager = SessionManager.shared
    @StateObject private var featureDetector = FeatureDetector.shared
    @StateObject private var evolutionAgent = EvolutionAgent.shared
    @StateObject private var sharedIntelligence = SharedIntelligence.shared
    @StateObject private var fontScale = FontScale.shared
    @StateObject private var modelRouter = ModelRouter.shared
    @StateObject private var projectManager = ProjectManager.shared

    // Focused window's process (for menu commands)
    @FocusedObject private var focusedProcess: ClaudeProcess?

    // Onboarding
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    // New window via environment
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup(id: "conductor", for: UUID.self) { $windowId in
            WindowContentView(hasCompletedOnboarding: hasCompletedOnboarding)
                .id(windowId)
                // Global services
                .environmentObject(themeEngine)
                .environmentObject(sessionManager)
                .environmentObject(featureDetector)
                .environmentObject(evolutionAgent)
                .environmentObject(sharedIntelligence)
                .environmentObject(fontScale)
                .environmentObject(modelRouter)
                .environmentObject(projectManager)
                .frame(minWidth: 700, minHeight: 500)
                .preferredColorScheme(.dark)
                .onAppear {
                    if windowId == nil { windowId = UUID() }
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1000, height: 700)
        .commands {
            // Replace default File > New with our multi-window action (Cmd+N)
            CommandGroup(replacing: .newItem) {
                Button("New Window") {
                    openWindow(id: "conductor", value: UUID())
                }
                .keyboardShortcut("n", modifiers: [.command])
            }

            CommandGroup(after: .textEditing) {
                Button("Interrupt Claude") {
                    focusedProcess?.interrupt()
                }
                .keyboardShortcut("c", modifiers: [.control])
                .disabled(focusedProcess == nil)
            }
        }
    }
}

/// Per-window content view that creates its own SessionStateContainer.
/// Each window gets an independent container with its own ClaudeProcess,
/// context tracking, agents, etc.
struct WindowContentView: View {
    let hasCompletedOnboarding: Bool

    /// Per-window session state — created fresh for each new window
    @StateObject private var sessionState = SessionStateContainer()

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                AppShell()
            } else {
                OnboardingView()
            }
        }
        // Per-window services from the container
        .environmentObject(sessionState)
        .environmentObject(sessionState.process)
        .environmentObject(sessionState.contextManager)
        .environmentObject(sessionState.compactionEngine)
        .environmentObject(sessionState.contextPipeline)
        .environmentObject(sessionState.budgetOptimizer)
        .environmentObject(sessionState.sessionContinuity)
        .environmentObject(sessionState.moodBoard)
        .environmentObject(sessionState.orchestrator)
        .environmentObject(sessionState.messageBus)
        .environmentObject(sessionState.permissionManager)
        // Expose the process as focused object for menu commands (Ctrl+C)
        .focusedObject(sessionState.process)
    }
}

// MARK: - App Delegate (Cmd+Q handling + File menu)

/// Handles app termination (quick-save) and provides File menu via AppKit.
final class ConductorAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        NotificationCenter.default.post(name: .conductorAppTerminating, object: nil)
        return .terminateNow
    }
}

extension Notification.Name {
    static let conductorAppTerminating = Notification.Name("conductorAppTerminating")
}
