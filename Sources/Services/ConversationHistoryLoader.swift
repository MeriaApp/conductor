import Foundation

/// Loads conversation history from Claude CLI's session JSONL files
/// Used when resuming a session to populate the conversation view with prior messages
enum ConversationHistoryLoader {

    /// Load messages from a CLI session file
    /// - Parameters:
    ///   - sessionId: The CLI session UUID
    ///   - projectDir: The project directory (used to compute the CLI project key)
    /// - Returns: Array of ConversationMessages, or nil if file not found
    static func load(sessionId: String, projectDir: String?) -> [ConversationMessage]? {
        guard let fileURL = resolveSessionFile(sessionId: sessionId, projectDir: projectDir) else {
            return nil
        }

        guard let data = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return nil
        }

        let lines = data.components(separatedBy: .newlines)
        var messages: [ConversationMessage] = []

        for line in lines {
            guard let event = StreamEventParser.parse(line: line) else { continue }

            switch event {
            case .user(let e):
                // Only include actual user text messages, not tool results
                let textContent = e.message.content.compactMap { block -> String? in
                    // Tool result blocks have type "tool_result" — skip those
                    if block.type == "tool_result" { return nil }
                    return block.content
                }
                // User events in the JSONL that contain tool results are intermediate — skip
                if textContent.isEmpty { continue }
                // Real user messages have role "user" and text content
                // But in CLI JSONL format, user messages with text come as a different shape
                // The user events in stream-json are tool results, not user prompts
                // User prompts are passed via -p flag and don't appear in the JSONL
                continue

            case .assistant(let e):
                var blocks: [any ContentBlockProtocol] = []

                for raw in e.message.content {
                    switch raw.type {
                    case "text":
                        if let text = raw.text {
                            blocks.append(contentsOf: MarkdownParser.parse(text))
                        }
                    case "tool_use":
                        let toolName = raw.name ?? "unknown"
                        let input = raw.input?.prettyJSON ?? ""
                        blocks.append(ToolUseBlock(
                            toolName: toolName,
                            input: input,
                            status: .completed
                        ))
                    case "thinking":
                        let text = raw.thinking ?? raw.text ?? ""
                        blocks.append(ThinkingBlock(text: text, isCollapsed: true))
                    default:
                        if let text = raw.text {
                            blocks.append(TextBlock(text: text))
                        }
                    }
                }

                if !blocks.isEmpty {
                    messages.append(ConversationMessage(
                        role: .assistant,
                        blocks: blocks
                    ))
                }

            case .system, .contentBlockDelta, .result:
                // System/delta/result events are metadata — skip for history display
                continue
            }
        }

        return messages.isEmpty ? nil : messages
    }

    // MARK: - File Resolution

    /// Resolve the path to the CLI session JSONL file
    private static func resolveSessionFile(sessionId: String, projectDir: String?) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let claudeDir = home.appendingPathComponent(".claude")

        // Try project-specific path first
        if let dir = projectDir {
            // CLI project key: replace / with -, strip leading -
            var projectKey = dir.replacingOccurrences(of: "/", with: "-")
            if projectKey.hasPrefix("-") {
                projectKey = String(projectKey.dropFirst())
            }
            let projectFile = claudeDir
                .appendingPathComponent("projects")
                .appendingPathComponent(projectKey)
                .appendingPathComponent("\(sessionId).jsonl")

            if FileManager.default.fileExists(atPath: projectFile.path) {
                return projectFile
            }
        }

        // Fallback: try all project directories
        let projectsDir = claudeDir.appendingPathComponent("projects")
        if let subdirs = try? FileManager.default.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: nil
        ) {
            for subdir in subdirs {
                let candidate = subdir.appendingPathComponent("\(sessionId).jsonl")
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
        }

        return nil
    }
}
