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

// MARK: - Catalog Models

struct MCPCatalogEntry: Identifiable {
    struct Param: Identifiable {
        let id = UUID().uuidString
        let key: String
        let displayName: String
        let description: String
        let placeholder: String
        let isRequired: Bool
        let isSecret: Bool
        let target: ParamTarget

        enum ParamTarget {
            case inCommand  // substitute {KEY} in commandTemplate
            case envVar     // pass as -e KEY=value
        }
    }

    enum Category: String, CaseIterable {
        case browser = "Browser"
        case database = "Database"
        case sourceControl = "Source Control"
        case filesystem = "Filesystem"
        case productivity = "Productivity"

        var icon: String {
            switch self {
            case .browser: return "safari"
            case .database: return "cylinder.split.1x2"
            case .sourceControl: return "arrow.triangle.branch"
            case .filesystem: return "folder"
            case .productivity: return "checkmark.circle"
            }
        }
    }

    let id: String
    let name: String
    let description: String
    let icon: String
    let commandTemplate: String
    let params: [Param]
    let category: Category

    func resolvedCommand(with values: [String: String]) -> String {
        var cmd = commandTemplate
        for param in params where param.target == .inCommand {
            let value = values[param.key] ?? ""
            cmd = cmd.replacingOccurrences(of: "{\(param.key)}", with: value)
        }
        return cmd
    }

    func resolvedEnvVars(with values: [String: String]) -> [(key: String, value: String)] {
        params.compactMap { param in
            guard param.target == .envVar,
                  let value = values[param.key],
                  !value.isEmpty else { return nil }
            return (key: param.key, value: value)
        }
    }

    var hasRequiredParams: Bool {
        params.contains { $0.isRequired }
    }
}

extension MCPServerManager {
    static let catalog: [MCPCatalogEntry] = [
        MCPCatalogEntry(
            id: "playwright",
            name: "Playwright",
            description: "Browser automation — Claude can control real browsers, fill forms, take screenshots, and run end-to-end tests.",
            icon: "safari",
            commandTemplate: "npx @playwright/mcp@latest",
            params: [],
            category: .browser
        ),
        MCPCatalogEntry(
            id: "supabase",
            name: "Supabase",
            description: "Direct database access — Claude can query your Supabase database, inspect schema, and run migrations.",
            icon: "cylinder.split.1x2",
            commandTemplate: "npx @supabase/mcp-server-supabase@latest --access-token {SUPABASE_ACCESS_TOKEN}",
            params: [
                MCPCatalogEntry.Param(
                    key: "SUPABASE_ACCESS_TOKEN",
                    displayName: "Access Token",
                    description: "supabase.com > Account > Access Tokens",
                    placeholder: "sbp_...",
                    isRequired: true,
                    isSecret: true,
                    target: .inCommand
                )
            ],
            category: .database
        ),
        MCPCatalogEntry(
            id: "github",
            name: "GitHub",
            description: "Repository management — Claude can read code, create PRs, manage issues, and search across your repos.",
            icon: "chevron.left.forwardslash.chevron.right",
            commandTemplate: "npx @modelcontextprotocol/server-github",
            params: [
                MCPCatalogEntry.Param(
                    key: "GITHUB_PERSONAL_ACCESS_TOKEN",
                    displayName: "Personal Access Token",
                    description: "github.com/settings/tokens — needs repo scope",
                    placeholder: "ghp_...",
                    isRequired: true,
                    isSecret: true,
                    target: .envVar
                )
            ],
            category: .sourceControl
        ),
        MCPCatalogEntry(
            id: "filesystem",
            name: "Filesystem",
            description: "Explicit file access — grant Claude read/write access to specific directories outside the current project.",
            icon: "folder",
            commandTemplate: "npx @modelcontextprotocol/server-filesystem {ALLOWED_PATH}",
            params: [
                MCPCatalogEntry.Param(
                    key: "ALLOWED_PATH",
                    displayName: "Allowed Path",
                    description: "Absolute path Claude can read and write",
                    placeholder: "/Users/you/Documents",
                    isRequired: true,
                    isSecret: false,
                    target: .inCommand
                )
            ],
            category: .filesystem
        ),
        MCPCatalogEntry(
            id: "postgres",
            name: "PostgreSQL",
            description: "Direct Postgres connection — Claude can query any Postgres database using a connection string.",
            icon: "cylinder.split.1x2.fill",
            commandTemplate: "npx @modelcontextprotocol/server-postgres {DATABASE_URL}",
            params: [
                MCPCatalogEntry.Param(
                    key: "DATABASE_URL",
                    displayName: "Connection String",
                    description: "Full PostgreSQL connection URL",
                    placeholder: "postgresql://user:pass@host/db",
                    isRequired: true,
                    isSecret: true,
                    target: .inCommand
                )
            ],
            category: .database
        ),
        MCPCatalogEntry(
            id: "memory",
            name: "Memory",
            description: "Persistent memory — Claude remembers facts and context across conversations using a local knowledge graph.",
            icon: "brain",
            commandTemplate: "npx @modelcontextprotocol/server-memory",
            params: [],
            category: .productivity
        ),
        MCPCatalogEntry(
            id: "linear",
            name: "Linear",
            description: "Issue tracking — Claude can read and create Linear issues, update project status, and manage workflows.",
            icon: "checkmark.circle.fill",
            commandTemplate: "npx @linear/mcp-server",
            params: [
                MCPCatalogEntry.Param(
                    key: "LINEAR_API_KEY",
                    displayName: "API Key",
                    description: "linear.app/settings/api",
                    placeholder: "lin_api_...",
                    isRequired: true,
                    isSecret: true,
                    target: .envVar
                )
            ],
            category: .productivity
        ),
        MCPCatalogEntry(
            id: "slack",
            name: "Slack",
            description: "Messaging — Claude can read channels, search messages, and post updates to your Slack workspace.",
            icon: "message.fill",
            commandTemplate: "npx @modelcontextprotocol/server-slack",
            params: [
                MCPCatalogEntry.Param(
                    key: "SLACK_BOT_TOKEN",
                    displayName: "Bot Token",
                    description: "api.slack.com/apps > Bot User OAuth Token",
                    placeholder: "xoxb-...",
                    isRequired: true,
                    isSecret: true,
                    target: .envVar
                ),
                MCPCatalogEntry.Param(
                    key: "SLACK_TEAM_ID",
                    displayName: "Team ID",
                    description: "Your Slack workspace ID (starts with T)",
                    placeholder: "T01234567",
                    isRequired: true,
                    isSecret: false,
                    target: .envVar
                )
            ],
            category: .productivity
        ),
    ]
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

    // MARK: - Catalog

    /// Whether a catalog entry is already installed (name matches an existing server)
    func isCatalogEntryInstalled(_ entry: MCPCatalogEntry) -> Bool {
        servers.contains { $0.name.lowercased() == entry.id.lowercased() }
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
