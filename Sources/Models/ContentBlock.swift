import Foundation

// MARK: - Content Block Protocol

/// A renderable piece of content in the conversation
protocol ContentBlockProtocol: Identifiable {
    var id: String { get }
    /// Plain text for clipboard
    func copyText() -> String
}

// MARK: - Conversation Message

struct ConversationMessage: Identifiable {
    let id: String
    let role: MessageRole
    var blocks: [any ContentBlockProtocol]
    let timestamp: Date
    var isStreaming: Bool
    var duration: TimeInterval?
    var isPinned: Bool

    init(
        id: String = UUID().uuidString,
        role: MessageRole,
        blocks: [any ContentBlockProtocol] = [],
        timestamp: Date = Date(),
        isStreaming: Bool = false,
        duration: TimeInterval? = nil,
        isPinned: Bool = false
    ) {
        self.id = id
        self.role = role
        self.blocks = blocks
        self.timestamp = timestamp
        self.isStreaming = isStreaming
        self.duration = duration
        self.isPinned = isPinned
    }

    /// Full copyable text of the message
    func copyText() -> String {
        blocks.map { $0.copyText() }.joined(separator: "\n\n")
    }
}

enum MessageRole: String {
    case user
    case assistant
    case system
}

// MARK: - Concrete Block Types

struct TextBlock: ContentBlockProtocol {
    let id: String
    var text: String

    init(id: String = UUID().uuidString, text: String) {
        self.id = id
        self.text = text
    }

    func copyText() -> String { text }
}

struct CodeBlock: ContentBlockProtocol {
    let id: String
    var code: String
    var language: String?
    var filename: String?

    init(id: String = UUID().uuidString, code: String, language: String? = nil, filename: String? = nil) {
        self.id = id
        self.code = code
        self.language = language
        self.filename = filename
    }

    func copyText() -> String { code }
}

struct DiffBlock: ContentBlockProtocol {
    let id: String
    var hunks: [DiffHunk]
    var filename: String?

    init(id: String = UUID().uuidString, hunks: [DiffHunk] = [], filename: String? = nil) {
        self.id = id
        self.hunks = hunks
        self.filename = filename
    }

    func copyText() -> String {
        hunks.map { $0.lines.map { $0.text }.joined(separator: "\n") }.joined(separator: "\n")
    }
}

struct DiffHunk {
    var lines: [DiffLine]
}

struct DiffLine {
    let type: DiffLineType
    let text: String
}

enum DiffLineType {
    case context
    case added
    case removed
}

struct ToolUseBlock: ContentBlockProtocol {
    let id: String
    var toolName: String
    var input: String          // Summary or pretty-printed input
    var status: ToolStatus
    var duration: TimeInterval?
    var output: String?
    var isError: Bool

    init(
        id: String = UUID().uuidString,
        toolName: String,
        input: String = "",
        status: ToolStatus = .running,
        duration: TimeInterval? = nil,
        output: String? = nil,
        isError: Bool = false
    ) {
        self.id = id
        self.toolName = toolName
        self.input = input
        self.status = status
        self.duration = duration
        self.output = output
        self.isError = isError
    }

    func copyText() -> String {
        var result = "\(toolName): \(input)"
        if let output { result += "\n\(output)" }
        return result
    }
}

enum ToolStatus: String {
    case pending    // Waiting for approval
    case running    // Currently executing
    case completed  // Finished successfully
    case failed     // Finished with error
}

struct ThinkingBlock: ContentBlockProtocol {
    let id: String
    var text: String
    var duration: TimeInterval?
    var isCollapsed: Bool
    var isStreaming: Bool

    init(
        id: String = UUID().uuidString,
        text: String = "",
        duration: TimeInterval? = nil,
        isCollapsed: Bool = true,
        isStreaming: Bool = false
    ) {
        self.id = id
        self.text = text
        self.duration = duration
        self.isCollapsed = isCollapsed
        self.isStreaming = isStreaming
    }

    func copyText() -> String { text }
}

struct ListBlock: ContentBlockProtocol {
    let id: String
    var items: [String]
    var style: ListStyle

    init(id: String = UUID().uuidString, items: [String], style: ListStyle = .bullet) {
        self.id = id
        self.items = items
        self.style = style
    }

    func copyText() -> String {
        items.enumerated().map { idx, item in
            switch style {
            case .bullet: return "- \(item)"
            case .numbered: return "\(idx + 1). \(item)"
            case .checkbox: return "- [ ] \(item)"
            }
        }.joined(separator: "\n")
    }
}

enum ListStyle {
    case bullet
    case numbered
    case checkbox
}

struct BlockquoteBlock: ContentBlockProtocol {
    let id: String
    var text: String

    init(id: String = UUID().uuidString, text: String) {
        self.id = id
        self.text = text
    }

    func copyText() -> String { "> " + text.replacingOccurrences(of: "\n", with: "\n> ") }
}
