import Foundation

/// Detects Claude CLI capabilities, installed MCP servers, hooks, skills, and project context
/// Runs on startup and generates feature suggestions
@MainActor
final class FeatureDetector: ObservableObject {
    static let shared = FeatureDetector()

    @Published var cliVersion: String?
    @Published var installedMCPServers: [String] = []
    @Published var installedHooks: [String] = []
    @Published var installedSkills: [String] = []
    @Published var installedAgents: [String] = []
    @Published var projectType: ProjectType?
    @Published var suggestions: [FeatureSuggestion] = []
    @Published var activeFeatures: [DetectedFeature] = []
    @Published var isScanning = false

    private let claudePath: String
    private let claudeConfigDir: String
    private var _workingDirectory: String?

    /// Set the working directory for project detection
    func setWorkingDirectory(_ dir: String) {
        _workingDirectory = dir
    }

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        claudeConfigDir = "\(home)/.claude"
        let candidates = [
            "\(home)/.local/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude"
        ]
        claudePath = candidates.first { FileManager.default.fileExists(atPath: $0) }
            ?? "\(home)/.local/bin/claude"
    }

    // MARK: - Full Scan

    func scan(directory: String? = nil) async {
        isScanning = true
        defer { isScanning = false }

        if let dir = directory {
            _workingDirectory = dir
        }

        activeFeatures.removeAll()
        await scanCLIVersion()
        await scanMCPServers()
        scanHooks()
        scanSkills()
        scanAgents()
        detectProjectType()
        generateSuggestions()
    }

    // MARK: - CLI Version

    private func scanCLIVersion() async {
        let result = await runCommand(claudePath, args: ["--version"])
        cliVersion = result?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - MCP Servers

    private func scanMCPServers() async {
        // Check .claude/settings.json for MCP server configs
        let settingsPath = "\(claudeConfigDir)/settings.json"
        guard let data = FileManager.default.contents(atPath: settingsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mcpServers = json["mcpServers"] as? [String: Any] else {
            return
        }
        installedMCPServers = Array(mcpServers.keys)

        activeFeatures.append(DetectedFeature(
            name: "MCP Servers",
            description: "\(installedMCPServers.count) servers configured",
            category: .integration
        ))
    }

    // MARK: - Hooks

    private func scanHooks() {
        let settingsPath = "\(claudeConfigDir)/settings.json"
        guard let data = FileManager.default.contents(atPath: settingsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return
        }
        installedHooks = Array(hooks.keys)

        if !installedHooks.isEmpty {
            activeFeatures.append(DetectedFeature(
                name: "Hooks",
                description: "\(installedHooks.count) hooks configured: \(installedHooks.joined(separator: ", "))",
                category: .automation
            ))
        }
    }

    // MARK: - Skills

    private func scanSkills() {
        let skillsDir = "\(claudeConfigDir)/skills"
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: skillsDir) else {
            return
        }
        installedSkills = entries.filter { $0.hasSuffix(".md") }

        if !installedSkills.isEmpty {
            activeFeatures.append(DetectedFeature(
                name: "Skills",
                description: "\(installedSkills.count) custom skills",
                category: .workflow
            ))
        }
    }

    // MARK: - Agents

    private func scanAgents() {
        let agentsDir = "\(claudeConfigDir)/agents"
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: agentsDir) else {
            return
        }
        installedAgents = entries.filter { $0.hasSuffix(".md") || $0.hasSuffix(".json") }

        if !installedAgents.isEmpty {
            activeFeatures.append(DetectedFeature(
                name: "Custom Agents",
                description: "\(installedAgents.count) agents defined",
                category: .workflow
            ))
        }
    }

    // MARK: - Project Type Detection

    /// Detect project type from the given directory (not cwd — GUI apps use "/" as cwd)
    func detectProjectType(in directory: String? = nil) {
        let fm = FileManager.default
        guard let dir = directory ?? _workingDirectory else { return }

        if fm.fileExists(atPath: "\(dir)/Package.swift") || fm.fileExists(atPath: "\(dir)/project.yml") {
            projectType = .swift
        } else if fm.fileExists(atPath: "\(dir)/package.json") {
            projectType = .node
        } else if fm.fileExists(atPath: "\(dir)/Cargo.toml") {
            projectType = .rust
        } else if fm.fileExists(atPath: "\(dir)/go.mod") {
            projectType = .go
        } else if fm.fileExists(atPath: "\(dir)/requirements.txt") || fm.fileExists(atPath: "\(dir)/pyproject.toml") {
            projectType = .python
        } else if fm.fileExists(atPath: "\(dir)/Gemfile") {
            projectType = .ruby
        } else {
            projectType = nil
        }

        if let pt = projectType {
            // Remove old project type feature if re-scanning
            activeFeatures.removeAll { $0.category == .context && $0.name == "Project Type" }
            activeFeatures.append(DetectedFeature(
                name: "Project Type",
                description: pt.displayName,
                category: .context
            ))
        }
    }

    // MARK: - Suggestions

    private func generateSuggestions() {
        suggestions.removeAll()

        // Suggest PreCompact hook if not installed
        if !installedHooks.contains("PreCompact") {
            suggestions.append(FeatureSuggestion(
                title: "Add PreCompact Hook",
                description: "Auto-save context before compaction to prevent information loss",
                impact: .high,
                category: .automation,
                autoApplyable: true
            ))
        }

        // Suggest experimental MCP CLI if not enabled
        suggestions.append(FeatureSuggestion(
            title: "Enable MCP Tool Search",
            description: "Load MCP tools on-demand, saving 80%+ tokens on MCP-heavy sessions",
            impact: .high,
            category: .performance,
            autoApplyable: true
        ))

        // Suggest output modes if not configured
        let outputModesDir = "\(claudeConfigDir)/output-modes"
        if !FileManager.default.fileExists(atPath: outputModesDir) {
            suggestions.append(FeatureSuggestion(
                title: "Set Up Output Modes",
                description: "Create Concise, Educational, Code Reviewer, and Rapid Prototyping presets",
                impact: .medium,
                category: .workflow,
                autoApplyable: true
            ))
        }

        // Suggest MCP servers based on project type
        if let pt = projectType {
            switch pt {
            case .node, .swift:
                if !installedMCPServers.contains("github") {
                    suggestions.append(FeatureSuggestion(
                        title: "Add GitHub MCP Server",
                        description: "Access PRs, issues, and repos directly from Claude",
                        impact: .medium,
                        category: .integration,
                        autoApplyable: false
                    ))
                }
            default:
                break
            }
        }
    }

    // MARK: - Helpers

    private func runCommand(_ path: String, args: [String]) async -> String? {
        // Run off main thread to avoid blocking UI
        await withCheckedContinuation { continuation in
            Task.detached {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: path)
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

// MARK: - Supporting Types

enum ProjectType: String {
    case swift, node, rust, go, python, ruby, java, other

    var displayName: String {
        switch self {
        case .swift: return "Swift / Xcode"
        case .node: return "Node.js / TypeScript"
        case .rust: return "Rust"
        case .go: return "Go"
        case .python: return "Python"
        case .ruby: return "Ruby"
        case .java: return "Java"
        case .other: return "Unknown"
        }
    }
}

struct DetectedFeature: Identifiable {
    let id = UUID().uuidString
    let name: String
    let description: String
    let category: FeatureCategory
}

struct FeatureSuggestion: Identifiable {
    let id = UUID().uuidString
    let title: String
    let description: String
    let impact: SuggestionImpact
    let category: FeatureCategory
    let autoApplyable: Bool
}

enum FeatureCategory: String {
    case integration
    case automation
    case workflow
    case performance
    case context
}

enum SuggestionImpact: String {
    case high
    case medium
    case low
}
