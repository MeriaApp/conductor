import Foundation

// MARK: - Claude CLI stream-json Event Types
// Reference: claude -p --output-format stream-json --include-partial-messages --verbose
// Events arrive as NDJSON (one JSON object per line)
// With --include-partial-messages, streaming deltas arrive inside stream_event wrappers

/// Top-level wrapper that routes to specific event types
enum StreamEvent: Identifiable {
    case system(SystemEvent)
    case assistant(AssistantEvent)
    case user(UserEvent)
    case contentBlockDelta(ContentBlockDelta)
    case result(ResultEvent)

    var id: String {
        switch self {
        case .system(let e): return e.id
        case .assistant(let e): return e.id
        case .user(let e): return e.id
        case .contentBlockDelta(let e): return e.id
        case .result(let e): return e.id
        }
    }
}

// MARK: - System Event (session init)

struct SystemEvent: Identifiable {
    let id: String
    let type: String
    let subtype: String?
    let sessionId: String?
    let model: String?
    let tools: [String]?
    let cliVersion: String?
    let cwd: String?
    let permissionMode: String?
    let agents: [String]?
    let skills: [String]?

    init(id: String = UUID().uuidString, type: String = "system",
         subtype: String? = nil, sessionId: String? = nil,
         model: String? = nil, tools: [String]? = nil,
         cliVersion: String? = nil, cwd: String? = nil,
         permissionMode: String? = nil, agents: [String]? = nil,
         skills: [String]? = nil) {
        self.id = id
        self.type = type
        self.subtype = subtype
        self.sessionId = sessionId
        self.model = model
        self.tools = tools
        self.cliVersion = cliVersion
        self.cwd = cwd
        self.permissionMode = permissionMode
        self.agents = agents
        self.skills = skills
    }
}

// MARK: - Assistant Event (Claude's messages)

struct AssistantEvent: Identifiable {
    let id: String
    let type: String
    let message: AssistantMessage
    let sessionId: String?

    init(id: String = UUID().uuidString, type: String = "assistant",
         message: AssistantMessage, sessionId: String? = nil) {
        self.id = id
        self.type = type
        self.message = message
        self.sessionId = sessionId
    }
}

struct AssistantMessage {
    let role: String
    let content: [RawContentBlock]
    let model: String?
    let stopReason: String?
}

// MARK: - Raw Content Blocks (from API)

struct RawContentBlock: Identifiable {
    let stableId: String
    var id: String { stableId }
    let type: String          // "text", "tool_use", "thinking"
    let text: String?
    let name: String?         // tool name for tool_use
    let toolUseId: String?    // tool_use block ID
    let input: AnyCodable?    // tool input JSON
    let thinking: String?     // for thinking blocks
    let index: Int?
}

// MARK: - User Event (tool results)

struct UserEvent: Identifiable {
    let id: String
    let type: String
    let message: UserMessage

    init(id: String = UUID().uuidString, type: String = "user",
         message: UserMessage) {
        self.id = id
        self.type = type
        self.message = message
    }
}

struct UserMessage {
    let role: String
    let content: [ToolResultBlock]
}

struct ToolResultBlock {
    let type: String
    let toolUseId: String
    let content: String?
    let isError: Bool?
}

// MARK: - Content Block Delta (streaming)

struct ContentBlockDelta: Identifiable {
    let id: String
    let type: String
    let index: Int
    let delta: DeltaContent

    init(id: String = UUID().uuidString, type: String = "content_block_delta",
         index: Int = 0, delta: DeltaContent) {
        self.id = id
        self.type = type
        self.index = index
        self.delta = delta
    }
}

struct DeltaContent {
    let type: String          // "text_delta", "thinking_delta", "input_json_delta"
    let text: String?
    let thinking: String?
    let partialJson: String?
}

// MARK: - Result Event (final)

struct ResultEvent: Identifiable {
    let id: String
    let type: String
    let subtype: String?
    let durationMs: Double?
    let isError: Bool?
    let numTurns: Int?
    let sessionId: String?
    let usage: UsageStats?
    let totalCostUSD: Double?
    let result: String?
    let stopReason: String?

    init(id: String = UUID().uuidString, type: String = "result",
         subtype: String? = nil, durationMs: Double? = nil,
         isError: Bool? = nil, numTurns: Int? = nil,
         sessionId: String? = nil, usage: UsageStats? = nil,
         totalCostUSD: Double? = nil, result: String? = nil,
         stopReason: String? = nil) {
        self.id = id
        self.type = type
        self.subtype = subtype
        self.durationMs = durationMs
        self.isError = isError
        self.numTurns = numTurns
        self.sessionId = sessionId
        self.usage = usage
        self.totalCostUSD = totalCostUSD
        self.result = result
        self.stopReason = stopReason
    }
}

struct UsageStats {
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheReadInputTokens: Int?
    let cacheCreationInputTokens: Int?
}

// MARK: - AnyCodable (for arbitrary JSON)

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }

    var dictionary: [String: Any]? { value as? [String: Any] }
    var string: String? { value as? String }

    var prettyJSON: String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: value, options: [.prettyPrinted, .sortedKeys]
        ), let str = String(data: data, encoding: .utf8) else {
            return String(describing: value)
        }
        return str
    }
}

// MARK: - NDJSON Parser (manual JSON → Swift structs)
// Uses JSONSerialization for flexibility with field names that don't match Swift conventions

enum StreamEventParser {

    /// Parse a single line of NDJSON into a StreamEvent
    static func parse(line: String) -> StreamEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = raw["type"] as? String else { return nil }

        switch type {
        case "system":
            return parseSystem(raw)

        case "assistant":
            return parseAssistant(raw)

        case "user":
            return parseUser(raw)

        case "stream_event":
            // With --include-partial-messages, deltas arrive wrapped in stream_event
            return parseStreamEvent(raw)

        case "content_block_delta":
            // Bare delta (fallback — normally wrapped in stream_event)
            return parseDelta(raw)

        case "result":
            return parseResult(raw)

        case "rate_limit_event":
            // Informational — not critical for UI
            return nil

        default:
            print("[StreamEventParser] Unknown event type: \(type)")
            return nil
        }
    }

    /// Parse multiple NDJSON lines
    static func parseLines(_ text: String) -> [StreamEvent] {
        text.components(separatedBy: .newlines).compactMap { parse(line: $0) }
    }

    // MARK: - Individual Parsers

    private static func parseSystem(_ raw: [String: Any]) -> StreamEvent? {
        let event = SystemEvent(
            id: raw["uuid"] as? String ?? UUID().uuidString,
            subtype: raw["subtype"] as? String,
            sessionId: raw["session_id"] as? String,
            model: raw["model"] as? String,
            tools: raw["tools"] as? [String],
            cliVersion: raw["claude_code_version"] as? String,
            cwd: raw["cwd"] as? String,
            permissionMode: raw["permissionMode"] as? String,
            agents: raw["agents"] as? [String],
            skills: raw["skills"] as? [String]
        )
        return .system(event)
    }

    private static func parseAssistant(_ raw: [String: Any]) -> StreamEvent? {
        guard let messageDict = raw["message"] as? [String: Any],
              let contentArray = messageDict["content"] as? [[String: Any]] else { return nil }

        let blocks = contentArray.map { parseContentBlock($0) }

        let message = AssistantMessage(
            role: messageDict["role"] as? String ?? "assistant",
            content: blocks,
            model: messageDict["model"] as? String,
            stopReason: messageDict["stop_reason"] as? String
        )

        let event = AssistantEvent(
            id: raw["uuid"] as? String ?? UUID().uuidString,
            message: message,
            sessionId: raw["session_id"] as? String
        )
        return .assistant(event)
    }

    private static func parseContentBlock(_ raw: [String: Any]) -> RawContentBlock {
        let type = raw["type"] as? String ?? "text"
        var input: AnyCodable? = nil
        if let inputObj = raw["input"] {
            input = AnyCodable(inputObj)
        }
        let blockId = raw["id"] as? String
        return RawContentBlock(
            stableId: blockId ?? "\(type)_\(raw["index"] as? Int ?? 0)_\(UUID().uuidString.prefix(8))",
            type: type,
            text: raw["text"] as? String,
            name: raw["name"] as? String,
            toolUseId: blockId,
            input: input,
            thinking: raw["thinking"] as? String,
            index: raw["index"] as? Int
        )
    }

    private static func parseUser(_ raw: [String: Any]) -> StreamEvent? {
        guard let messageDict = raw["message"] as? [String: Any],
              let contentArray = messageDict["content"] as? [[String: Any]] else { return nil }

        let blocks = contentArray.compactMap { dict -> ToolResultBlock? in
            guard let type = dict["type"] as? String else { return nil }
            return ToolResultBlock(
                type: type,
                toolUseId: dict["tool_use_id"] as? String ?? "",
                content: dict["content"] as? String,
                isError: dict["is_error"] as? Bool
            )
        }

        let message = UserMessage(
            role: messageDict["role"] as? String ?? "user",
            content: blocks
        )

        return .user(UserEvent(
            id: raw["uuid"] as? String ?? UUID().uuidString,
            message: message
        ))
    }

    private static func parseStreamEvent(_ raw: [String: Any]) -> StreamEvent? {
        guard let innerEvent = raw["event"] as? [String: Any],
              let innerType = innerEvent["type"] as? String else { return nil }

        switch innerType {
        case "content_block_delta":
            return parseDelta(innerEvent)
        // message_start, content_block_start, content_block_stop, message_delta, message_stop
        // are informational — the full assistant event handles final message state
        default:
            return nil
        }
    }

    private static func parseDelta(_ raw: [String: Any]) -> StreamEvent? {
        guard let deltaDict = raw["delta"] as? [String: Any],
              let deltaType = deltaDict["type"] as? String else { return nil }

        let delta = DeltaContent(
            type: deltaType,
            text: deltaDict["text"] as? String,
            thinking: deltaDict["thinking"] as? String,
            partialJson: deltaDict["partial_json"] as? String
        )

        let event = ContentBlockDelta(
            id: UUID().uuidString,
            index: raw["index"] as? Int ?? 0,
            delta: delta
        )
        return .contentBlockDelta(event)
    }

    private static func parseResult(_ raw: [String: Any]) -> StreamEvent? {
        var usage: UsageStats? = nil
        if let usageDict = raw["usage"] as? [String: Any] {
            usage = UsageStats(
                inputTokens: usageDict["input_tokens"] as? Int,
                outputTokens: usageDict["output_tokens"] as? Int,
                cacheReadInputTokens: usageDict["cache_read_input_tokens"] as? Int,
                cacheCreationInputTokens: usageDict["cache_creation_input_tokens"] as? Int
            )
        }

        let event = ResultEvent(
            id: raw["uuid"] as? String ?? UUID().uuidString,
            subtype: raw["subtype"] as? String,
            durationMs: raw["duration_ms"] as? Double,
            isError: raw["is_error"] as? Bool,
            numTurns: raw["num_turns"] as? Int,
            sessionId: raw["session_id"] as? String,
            usage: usage,
            totalCostUSD: raw["total_cost_usd"] as? Double,
            result: raw["result"] as? String,
            stopReason: raw["stop_reason"] as? String
        )
        return .result(event)
    }
}
