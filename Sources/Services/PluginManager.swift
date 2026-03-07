import Foundation

/// Manages Claude CLI plugins — list, install, enable, disable
@MainActor
final class PluginManager: ObservableObject {
    static let shared = PluginManager()

    @Published var plugins: [PluginInfo] = []
    @Published var isLoading = false

    private let claudePath: String

    private init() {
        let candidates = [
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude"
        ]
        self.claudePath = candidates.first { FileManager.default.fileExists(atPath: $0) }
            ?? "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/claude"
    }

    /// Refresh plugin list from CLI
    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        let output = await runCLI(["plugin", "list"])
        plugins = parsePluginList(output)
    }

    /// Install a plugin
    func install(name: String, scope: PluginScope = .user) async -> Bool {
        let output = await runCLI(["plugin", "install", name, "--scope", scope.rawValue])
        await refresh()
        return !output.contains("Error")
    }

    /// Enable a plugin
    func enable(name: String) async -> Bool {
        let output = await runCLI(["plugin", "enable", name])
        await refresh()
        return !output.contains("Error")
    }

    /// Disable a plugin
    func disable(name: String) async -> Bool {
        let output = await runCLI(["plugin", "disable", name])
        await refresh()
        return !output.contains("Error")
    }

    /// Uninstall a plugin
    func uninstall(name: String) async -> Bool {
        let output = await runCLI(["plugin", "uninstall", name])
        await refresh()
        return !output.contains("Error")
    }

    // MARK: - CLI Execution

    private func runCLI(_ args: [String]) async -> String {
        await withCheckedContinuation { continuation in
            Task.detached {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: self.claudePath)
                proc.arguments = args
                let pipe = Pipe()
                proc.standardOutput = pipe
                proc.standardError = pipe

                var env = ProcessInfo.processInfo.environment
                env.removeValue(forKey: "CLAUDECODE")
                proc.environment = env

                do {
                    try proc.run()
                    proc.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(returning: "Error: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Parsing

    private func parsePluginList(_ output: String) -> [PluginInfo] {
        var result: [PluginInfo] = []
        let lines = output.components(separatedBy: .newlines)

        var currentName: String?
        var currentVersion: String?
        var currentScope: PluginScope = .user
        var currentEnabled = true

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Plugin name line: "> swift-lsp@claude-plugins-official"
            if trimmed.hasPrefix(">") {
                // Save previous plugin
                if let name = currentName {
                    result.append(PluginInfo(
                        name: name,
                        version: currentVersion ?? "unknown",
                        scope: currentScope,
                        isEnabled: currentEnabled
                    ))
                }

                currentName = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                currentVersion = nil
                currentScope = .user
                currentEnabled = true
            }

            if trimmed.hasPrefix("Version:") {
                currentVersion = String(trimmed.dropFirst("Version:".count)).trimmingCharacters(in: .whitespaces)
            }
            if trimmed.hasPrefix("Scope:") {
                let scope = String(trimmed.dropFirst("Scope:".count)).trimmingCharacters(in: .whitespaces)
                currentScope = PluginScope(rawValue: scope) ?? .user
            }
            if trimmed.hasPrefix("Status:") {
                let status = String(trimmed.dropFirst("Status:".count)).trimmingCharacters(in: .whitespaces)
                currentEnabled = status == "enabled"
            }
        }

        // Save last plugin
        if let name = currentName {
            result.append(PluginInfo(
                name: name,
                version: currentVersion ?? "unknown",
                scope: currentScope,
                isEnabled: currentEnabled
            ))
        }

        return result
    }
}

// MARK: - Models

struct PluginInfo: Identifiable {
    let id = UUID().uuidString
    let name: String
    let version: String
    let scope: PluginScope
    var isEnabled: Bool

    var shortName: String {
        name.components(separatedBy: "@").first ?? name
    }

    var marketplace: String? {
        let parts = name.components(separatedBy: "@")
        return parts.count > 1 ? parts[1] : nil
    }
}

enum PluginScope: String, CaseIterable {
    case user = "user"
    case project = "project"
    case local = "local"
}
