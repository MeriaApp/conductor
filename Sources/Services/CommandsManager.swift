import Foundation

/// Represents a custom Claude CLI command (~/.claude/commands/<name>.md)
struct CommandDefinition: Identifiable {
    var id: String { name }
    let name: String
    var description: String
    var content: String
}

/// Manages custom slash commands from ~/.claude/commands/
/// Commands are flat .md files that become /<name> slash commands
@MainActor
final class CommandsManager: ObservableObject {
    static let shared = CommandsManager()

    @Published var commands: [CommandDefinition] = []

    private let commandsDir: String

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        commandsDir = "\(home)/.claude/commands"
        load()
    }

    // MARK: - Load

    func load() {
        commands = []
        let fm = FileManager.default

        // Ensure directory exists
        if !fm.fileExists(atPath: commandsDir) {
            try? fm.createDirectory(atPath: commandsDir, withIntermediateDirectories: true)
        }

        guard let files = try? fm.contentsOfDirectory(atPath: commandsDir) else { return }

        for file in files.sorted() where file.hasSuffix(".md") {
            let filePath = "\(commandsDir)/\(file)"
            guard let raw = try? String(contentsOfFile: filePath, encoding: .utf8) else { continue }

            let name = String(file.dropLast(3)) // Remove .md
            let (frontmatter, body) = parseFrontmatter(raw)
            let description = frontmatter["description"] ?? ""

            commands.append(CommandDefinition(
                name: name,
                description: description,
                content: body
            ))
        }
    }

    // MARK: - Create

    func createCommand(name: String, description: String, content: String) {
        let safeName = name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")

        var fileContent = ""
        if !description.isEmpty {
            fileContent = "---\ndescription: \(description)\n---\n\n"
        }
        fileContent += content

        let filePath = "\(commandsDir)/\(safeName).md"
        try? fileContent.write(toFile: filePath, atomically: true, encoding: .utf8)
        load()
    }

    // MARK: - Delete

    func deleteCommand(name: String) {
        let filePath = "\(commandsDir)/\(name).md"
        if FileManager.default.fileExists(atPath: filePath) {
            try? FileManager.default.removeItem(atPath: filePath)
        }
        // Try lowercased variant
        let lowerPath = "\(commandsDir)/\(name.lowercased()).md"
        if FileManager.default.fileExists(atPath: lowerPath) {
            try? FileManager.default.removeItem(atPath: lowerPath)
        }
        load()
    }

    // MARK: - Invoke

    /// Send /<name> command to a ClaudeProcess
    func invokeCommand(name: String, process: ClaudeProcess) {
        process.send("/\(name)")
    }

    // MARK: - YAML Frontmatter Parsing

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
