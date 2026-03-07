import Foundation

/// Represents a Claude CLI skill (SKILL.md file with optional YAML frontmatter)
struct SkillDefinition: Identifiable {
    var id: String { name }
    let name: String
    var description: String
    var content: String
    var allowedTools: [String]?
    var model: String?
    let directoryPath: String
}

/// Manages Claude CLI skills from ~/.claude/skills/
/// Skills are reusable prompt templates with optional YAML frontmatter
@MainActor
final class SkillsManager: ObservableObject {
    static let shared = SkillsManager()

    @Published var skills: [SkillDefinition] = []

    private let skillsBaseDir: String

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        skillsBaseDir = "\(home)/.claude/skills"
        load()
    }

    // MARK: - Load

    func load() {
        skills = []
        let fm = FileManager.default

        guard fm.fileExists(atPath: skillsBaseDir),
              let dirs = try? fm.contentsOfDirectory(atPath: skillsBaseDir) else {
            return
        }

        for dir in dirs.sorted() {
            let skillDir = "\(skillsBaseDir)/\(dir)"
            let skillFile = "\(skillDir)/SKILL.md"

            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: skillDir, isDirectory: &isDir), isDir.boolValue,
                  fm.fileExists(atPath: skillFile),
                  let raw = try? String(contentsOfFile: skillFile, encoding: .utf8) else {
                continue
            }

            let (frontmatter, body) = parseFrontmatter(raw)

            let description = frontmatter["description"] ?? ""
            let model = frontmatter["model"]

            var allowedTools: [String]?
            if let toolsStr = frontmatter["tools"] {
                allowedTools = toolsStr.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            }

            skills.append(SkillDefinition(
                name: dir,
                description: description,
                content: body,
                allowedTools: allowedTools,
                model: model,
                directoryPath: skillDir
            ))
        }
    }

    // MARK: - Create

    func createSkill(name: String, description: String, content: String, tools: [String]? = nil, model: String? = nil) {
        let safeName = name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        let skillDir = "\(skillsBaseDir)/\(safeName)"

        try? FileManager.default.createDirectory(atPath: skillDir, withIntermediateDirectories: true)

        var frontmatter = "---\n"
        if !description.isEmpty {
            frontmatter += "description: \(description)\n"
        }
        if let tools = tools, !tools.isEmpty {
            frontmatter += "tools: \(tools.joined(separator: ", "))\n"
        }
        if let model = model, !model.isEmpty {
            frontmatter += "model: \(model)\n"
        }
        frontmatter += "---\n\n"

        let fileContent = frontmatter + content
        let filePath = "\(skillDir)/SKILL.md"
        try? fileContent.write(toFile: filePath, atomically: true, encoding: .utf8)

        load()
    }

    // MARK: - Delete

    func deleteSkill(name: String) {
        let safeName = name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        let skillDir = "\(skillsBaseDir)/\(safeName)"

        // Also try the exact name (skill dirs might not be lowercased)
        if FileManager.default.fileExists(atPath: skillDir) {
            try? FileManager.default.removeItem(atPath: skillDir)
        }

        // Try original name as directory
        let originalDir = "\(skillsBaseDir)/\(name)"
        if FileManager.default.fileExists(atPath: originalDir) {
            try? FileManager.default.removeItem(atPath: originalDir)
        }

        load()
    }

    // MARK: - Invoke

    /// Send /skill:<name> command to a ClaudeProcess
    func invokeSkill(name: String, process: ClaudeProcess) {
        process.send("/skill:\(name)")
    }

    // MARK: - YAML Frontmatter Parsing

    /// Simple line-by-line YAML frontmatter parser (between --- markers)
    private func parseFrontmatter(_ raw: String) -> (frontmatter: [String: String], body: String) {
        let lines = raw.components(separatedBy: "\n")
        var frontmatter: [String: String] = [:]
        var body = raw
        var inFrontmatter = false
        var frontmatterEnd = 0

        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" {
                if !inFrontmatter && i == 0 {
                    inFrontmatter = true
                    continue
                } else if inFrontmatter {
                    frontmatterEnd = i + 1
                    break
                }
            }
            if inFrontmatter {
                if let colonIdx = trimmed.firstIndex(of: ":") {
                    let key = String(trimmed[trimmed.startIndex..<colonIdx]).trimmingCharacters(in: .whitespaces)
                    let value = String(trimmed[trimmed.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                    frontmatter[key] = value
                }
            }
        }

        if frontmatterEnd > 0 {
            body = lines[frontmatterEnd...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return (frontmatter, body)
    }
}
