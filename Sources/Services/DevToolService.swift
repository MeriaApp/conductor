import Foundation

/// Runs local dev tools (CodeRabbit, SwiftLint, Periphery, Fastlane) in the project directory.
/// Each tool is invoked via login shell so all PATH entries and env vars are available.
@MainActor
final class DevToolService: ObservableObject {
    static let shared = DevToolService()

    @Published var isRunning = false
    @Published var output: String = ""
    @Published var activeTool: DevTool?
    @Published var exitCode: Int32?

    private var currentProcess: Process?

    private init() {}

    func run(_ tool: DevTool, projectDir: String) {
        guard !isRunning else { return }
        isRunning = true
        activeTool = tool
        output = ""
        exitCode = nil

        let shellCommand = tool.shellCommand(projectDir: projectDir)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-l", "-c", shellCommand]
        proc.currentDirectoryURL = URL(fileURLWithPath: projectDir, isDirectory: true)

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        currentProcess = proc  // Set before dispatch so cancel() can reach it immediately

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let handle = pipe.fileHandleForReading
            handle.readabilityHandler = { fh in
                let data = fh.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                DispatchQueue.main.async { self?.output += text }
            }

            do {
                try proc.run()
                proc.waitUntilExit()
                handle.readabilityHandler = nil
                // Drain remaining output
                let remaining = handle.readDataToEndOfFile()
                if !remaining.isEmpty, let text = String(data: remaining, encoding: .utf8) {
                    DispatchQueue.main.async { self?.output += text }
                }
                let status = proc.terminationStatus
                DispatchQueue.main.async {
                    self?.exitCode = status
                    self?.isRunning = false
                    self?.currentProcess = nil
                }
            } catch {
                handle.readabilityHandler = nil
                DispatchQueue.main.async {
                    self?.output += "\nError launching tool: \(error.localizedDescription)\n"
                    self?.exitCode = 1
                    self?.isRunning = false
                    self?.currentProcess = nil
                }
            }
        }
    }

    func cancel() {
        currentProcess?.terminate()
        currentProcess = nil
        isRunning = false
        output += "\n[Cancelled]\n"
    }

    func clearOutput() {
        output = ""
        exitCode = nil
    }
}

// MARK: - Tool Definitions

enum DevTool: String, CaseIterable, Identifiable {
    case codeRabbit = "coderabbit"
    case swiftLint = "swiftlint"
    case periphery = "periphery"
    case fastlane = "fastlane"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codeRabbit: return "CodeRabbit Review"
        case .swiftLint: return "SwiftLint"
        case .periphery: return "Periphery"
        case .fastlane: return "Fastlane Deliver"
        }
    }

    var description: String {
        switch self {
        case .codeRabbit: return "AI code review on current git diff"
        case .swiftLint: return "Lint Swift code — style and common errors"
        case .periphery: return "Find unused declarations and dead code"
        case .fastlane: return "Deploy to App Store via fastlane deliver"
        }
    }

    var icon: String {
        switch self {
        case .codeRabbit: return "doc.text.magnifyingglass"
        case .swiftLint: return "checkmark.seal"
        case .periphery: return "eye.slash"
        case .fastlane: return "paperplane.fill"
        }
    }

    var successMessage: String {
        switch self {
        case .codeRabbit: return "Review complete"
        case .swiftLint: return "No violations"
        case .periphery: return "No dead code found"
        case .fastlane: return "Delivered"
        }
    }

    func shellCommand(projectDir: String) -> String {
        let escaped = projectDir.replacingOccurrences(of: "'", with: "'\\''")
        switch self {
        case .codeRabbit:
            return "cd '\(escaped)' && coderabbit review --plain 2>&1"
        case .swiftLint:
            return "cd '\(escaped)' && swiftlint lint 2>&1"
        case .periphery:
            return "cd '\(escaped)' && periphery scan 2>&1"
        case .fastlane:
            return "cd '\(escaped)' && fastlane deliver 2>&1"
        }
    }
}
