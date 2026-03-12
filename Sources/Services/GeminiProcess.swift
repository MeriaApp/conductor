import Foundation

/// Gemini CLI integration — companion AI for second opinions, bulk processing, and long-context tasks.
/// Runs: /bin/zsh -l -c "gemini --model ... -p '...' --output-format text"
/// Requires GEMINI_API_KEY in ~/.keys (sourced via login shell).
@MainActor
final class GeminiProcess: ObservableObject {
    static let shared = GeminiProcess()

    @Published var isRunning = false
    @Published var lastResponse: String?
    @Published var lastError: String?
    @Published var history: [GeminiTurn] = []

    private var currentProcess: Process?

    private init() {}

    /// Send a prompt to Gemini CLI. Appends result to history.
    /// Runs via login shell so ~/.keys and nvm PATH are available.
    @discardableResult
    func ask(_ prompt: String, projectDir: String? = nil, model: GeminiModel = .flash) async -> String? {
        guard !isRunning else { return nil }
        isRunning = true
        lastError = nil

        // Use /tmp as fallback — avoids .Trash permission errors from ~
        let workDir = projectDir ?? "/tmp"
        let escapedPrompt = prompt.replacingOccurrences(of: "'", with: "'\\''")
        let shellCommand = "gemini --model \(model.cliValue) -p '\(escapedPrompt)' --output-format text 2>&1"

        let result = await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
            proc.arguments = ["-l", "-c", shellCommand]
            proc.currentDirectoryURL = URL(fileURLWithPath: workDir, isDirectory: true)

            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe

            self.currentProcess = proc

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try proc.run()
                    proc.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }

        isRunning = false
        currentProcess = nil

        if let output = result, !output.isEmpty {
            let turn = GeminiTurn(prompt: prompt, response: output, model: model)
            history.append(turn)
            lastResponse = output
            return output
        } else {
            lastError = result == nil
                ? "Gemini CLI not found. Install: npm install -g @google/gemini-cli"
                : "Empty response — check GEMINI_API_KEY in ~/.keys"
            return nil
        }
    }

    func cancel() {
        currentProcess?.terminate()
        currentProcess = nil
        isRunning = false
    }

    func clearHistory() {
        history.removeAll()
        lastResponse = nil
        lastError = nil
    }
}

// MARK: - Models

struct GeminiTurn: Identifiable {
    let id = UUID()
    let prompt: String
    let response: String
    let model: GeminiModel
    let date = Date()
}

enum GeminiModel: String, CaseIterable {
    case flash = "flash"
    case pro = "pro"

    var cliValue: String {
        switch self {
        case .flash: return "gemini-2.5-flash"
        case .pro: return "gemini-2.5-pro"
        }
    }

    var displayName: String {
        switch self {
        case .flash: return "Flash (fast, free)"
        case .pro: return "Pro (powerful)"
        }
    }

    var icon: String {
        switch self {
        case .flash: return "bolt.fill"
        case .pro: return "sparkles"
        }
    }
}
