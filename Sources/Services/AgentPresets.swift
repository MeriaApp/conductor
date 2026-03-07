import Foundation

/// Persistent agent presets — save custom agent configurations for quick spawning
@MainActor
final class AgentPresets: ObservableObject {
    static let shared = AgentPresets()

    @Published var presets: [AgentPreset] = []

    private let presetsURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("Conductor", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        presetsURL = appDir.appendingPathComponent("agent_presets.json")
        loadPresets()
        addDefaultPresets()
    }

    // MARK: - CRUD

    func add(_ preset: AgentPreset) {
        presets.append(preset)
        save()
        writeAgentFile(for: preset)
    }

    func remove(id: String) {
        if let preset = presets.first(where: { $0.id == id }) {
            removeAgentFile(for: preset)
        }
        presets.removeAll { $0.id == id }
        save()
    }

    func update(_ preset: AgentPreset) {
        if let idx = presets.firstIndex(where: { $0.id == preset.id }) {
            removeAgentFile(for: presets[idx])
            presets[idx] = preset
            save()
            writeAgentFile(for: preset)
        }
    }

    // MARK: - Persistent Agent Files

    /// Write a ~/.claude/agents/<name>.md file with memory: user frontmatter
    private func writeAgentFile(for preset: AgentPreset) {
        guard preset.memoryEnabled else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let agentsDir = "\(home)/.claude/agents"
        try? FileManager.default.createDirectory(
            atPath: agentsDir,
            withIntermediateDirectories: true
        )
        let filename = preset.name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        let content = """
        ---
        name: \(preset.name)
        memory: user
        model: claude-opus-4-6
        ---

        \(preset.customSystemPrompt ?? "You are \(preset.name).")
        """
        let filePath = "\(agentsDir)/\(filename).md"
        try? content.write(toFile: filePath, atomically: true, encoding: .utf8)
    }

    /// Remove the agent file when preset is deleted or memory is toggled off
    private func removeAgentFile(for preset: AgentPreset) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let filename = preset.name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        let filePath = "\(home)/.claude/agents/\(filename).md"
        try? FileManager.default.removeItem(atPath: filePath)
    }

    // MARK: - Spawn from Preset

    func spawn(presetId: String, orchestrator: AgentOrchestrator, directory: String?) -> Agent? {
        guard let preset = presets.first(where: { $0.id == presetId }) else { return nil }

        let agent = orchestrator.spawnAgent(
            name: preset.name,
            role: preset.role,
            directory: directory
        )

        // Apply custom system prompt if set
        if let customPrompt = preset.customSystemPrompt, !customPrompt.isEmpty {
            if let process = orchestrator.getProcess(for: agent.id) {
                process.systemPrompt = customPrompt
            }
        }

        // Apply custom effort level
        if let effort = preset.effortLevel {
            if let process = orchestrator.getProcess(for: agent.id) {
                process.effortLevel = effort
            }
        }

        // Send initial task if configured
        if let task = preset.initialTask, !task.isEmpty {
            orchestrator.assignTask(agentId: agent.id, task: task)
        }

        return agent
    }

    // MARK: - Defaults

    private func addDefaultPresets() {
        let defaults: [AgentPreset] = [
            AgentPreset(
                name: "Quick Builder",
                role: .builder,
                effortLevel: .high,
                customSystemPrompt: "You are a fast builder. Write clean code, fix any build errors immediately. No explanations needed — just ship working code.",
                icon: "hammer.fill"
            ),
            AgentPreset(
                name: "Security Auditor",
                role: .reviewer,
                effortLevel: .high,
                customSystemPrompt: "You are a security auditor. Focus exclusively on: injection attacks, XSS, CSRF, auth bypass, secrets exposure, insecure dependencies. Report severity levels.",
                icon: "shield.lefthalf.filled"
            ),
            AgentPreset(
                name: "Refactor Scout",
                role: .researcher,
                effortLevel: .medium,
                customSystemPrompt: "You are a refactoring scout. Find code duplication, dead code, overly complex functions, and inconsistent patterns. Suggest specific, safe refactors.",
                icon: "magnifyingglass.circle"
            ),
            AgentPreset(
                name: "Test Writer",
                role: .tester,
                effortLevel: .high,
                customSystemPrompt: "You are a test writer. Read the codebase, identify untested code paths, and write comprehensive unit tests. Focus on edge cases and error paths.",
                initialTask: "Scan the codebase for untested code and write tests for the most critical paths.",
                icon: "testtube.2"
            ),
        ]

        for preset in defaults {
            if !presets.contains(where: { $0.name == preset.name }) {
                presets.append(preset)
            }
        }
    }

    // MARK: - Persistence

    private func loadPresets() {
        guard FileManager.default.fileExists(atPath: presetsURL.path),
              let data = try? Data(contentsOf: presetsURL),
              let decoded = try? JSONDecoder().decode([AgentPreset].self, from: data) else {
            return
        }
        presets = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        try? data.write(to: presetsURL)
    }
}

// MARK: - Preset Model

struct AgentPreset: Identifiable, Codable {
    let id: String
    var name: String
    var role: AgentRole
    var effortLevel: EffortLevel?
    var customSystemPrompt: String?
    var initialTask: String?
    var icon: String
    var memoryEnabled: Bool

    init(
        id: String = UUID().uuidString,
        name: String,
        role: AgentRole,
        effortLevel: EffortLevel? = nil,
        customSystemPrompt: String? = nil,
        initialTask: String? = nil,
        icon: String = "star.fill",
        memoryEnabled: Bool = false
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.effortLevel = effortLevel
        self.customSystemPrompt = customSystemPrompt
        self.initialTask = initialTask
        self.icon = icon
        self.memoryEnabled = memoryEnabled
    }
}

// Custom Decodable to handle presets saved before memoryEnabled existed
extension AgentPreset {
    enum CodingKeys: String, CodingKey {
        case id, name, role, effortLevel, customSystemPrompt, initialTask, icon, memoryEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        role = try container.decode(AgentRole.self, forKey: .role)
        effortLevel = try container.decodeIfPresent(EffortLevel.self, forKey: .effortLevel)
        customSystemPrompt = try container.decodeIfPresent(String.self, forKey: .customSystemPrompt)
        initialTask = try container.decodeIfPresent(String.self, forKey: .initialTask)
        icon = try container.decode(String.self, forKey: .icon)
        memoryEnabled = try container.decodeIfPresent(Bool.self, forKey: .memoryEnabled) ?? false
    }
}

// Make AgentRole and EffortLevel codable for preset persistence
extension AgentRole: Codable {}
extension EffortLevel: Codable {}
