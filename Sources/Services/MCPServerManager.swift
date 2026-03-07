import Foundation

/// Represents an MCP (Model Context Protocol) server
struct MCPServer: Identifiable {
    let id: String
    let name: String
    let transport: MCPTransport
    let endpoint: String
    let status: MCPServerStatus
}

enum MCPTransport: String {
    case stdio
    case http
}

enum MCPServerStatus {
    case healthy
    case needsAuth
    case error(String)

    var displayName: String {
        switch self {
        case .healthy: return "Healthy"
        case .needsAuth: return "Needs Auth"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    var color: String {
        switch self {
        case .healthy: return "sage"
        case .needsAuth: return "amber"
        case .error: return "rose"
        }
    }
}

/// Manages MCP servers using `claude mcp` CLI commands
@MainActor
final class MCPServerManager: ObservableObject {
    static let shared = MCPServerManager()

    @Published var servers: [MCPServer] = []
    @Published var isLoading = false

    private let claudePath: String

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude"
        ]
        claudePath = candidates.first { FileManager.default.fileExists(atPath: $0) }
            ?? "\(home)/.local/bin/claude"
        load()
    }

    // MARK: - Load

    func load() {
        isLoading = true
        Task {
            let result = await runCommand(args: ["mcp", "list"])
            await MainActor.run {
                parseServerList(result ?? "")
                isLoading = false
            }
        }
    }

    // MARK: - Add

    func add(
        name: String,
        transport: MCPTransport = .stdio,
        endpoint: String,
        envVars: [(key: String, value: String)] = [],
        headers: [(key: String, value: String)] = [],
        scope: String = "local"
    ) {
        isLoading = true
        Task {
            var args = ["mcp", "add", name, "--transport", transport.rawValue]

            if transport == .http {
                args += [endpoint]
            } else {
                // For stdio, endpoint is the command + args
                let parts = endpoint.components(separatedBy: " ")
                args += parts
            }

            for ev in envVars where !ev.key.isEmpty {
                args += ["-e", "\(ev.key)=\(ev.value)"]
            }

            for h in headers where !h.key.isEmpty {
                args += ["-H", "\(h.key): \(h.value)"]
            }

            args += ["-s", scope]

            _ = await runCommand(args: args)
            await MainActor.run {
                load()
            }
        }
    }

    // MARK: - Remove

    func remove(name: String) {
        isLoading = true
        Task {
            _ = await runCommand(args: ["mcp", "remove", name])
            await MainActor.run {
                load()
            }
        }
    }

    // MARK: - Parse

    private func parseServerList(_ output: String) {
        servers = []
        let lines = output.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Parse format: "name: endpoint - status" or variations
            // Also handle: "name (transport): endpoint"
            let parts = trimmed.components(separatedBy: ":")
            guard parts.count >= 2 else { continue }

            let namePart = parts[0].trimmingCharacters(in: .whitespaces)
            let rest = parts.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)

            // Determine status from the line
            let status: MCPServerStatus
            if trimmed.lowercased().contains("needs auth") || trimmed.lowercased().contains("authentication") {
                status = .needsAuth
            } else if trimmed.lowercased().contains("error") || trimmed.lowercased().contains("failed") {
                status = .error("Connection failed")
            } else {
                status = .healthy
            }

            // Determine transport
            let transport: MCPTransport = trimmed.lowercased().contains("http") ? .http : .stdio

            servers.append(MCPServer(
                id: namePart,
                name: namePart,
                transport: transport,
                endpoint: rest,
                status: status
            ))
        }
    }

    // MARK: - Subprocess

    private func runCommand(args: [String]) async -> String? {
        await withCheckedContinuation { continuation in
            Task.detached {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: self.claudePath)
                proc.arguments = args

                var env = ProcessInfo.processInfo.environment
                env.removeValue(forKey: "CLAUDECODE")
                proc.environment = env

                let pipe = Pipe()
                proc.standardOutput = pipe
                proc.standardError = Pipe()

                do {
                    try proc.run()
                    proc.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    continuation.resume(returning: String(data: data, encoding: .utf8))
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
