import Foundation

/// Hook entry representing a single CLI hook command
struct HookEntry: Identifiable, Equatable {
    let id: String
    var command: String
    var timeout: Int?
    var matcher: String?

    init(id: String = UUID().uuidString, command: String, timeout: Int? = nil, matcher: String? = nil) {
        self.id = id
        self.command = command
        self.timeout = timeout
        self.matcher = matcher
    }
}

/// Manages Claude CLI hooks from ~/.claude/settings.json
/// Provides CRUD operations for hooks grouped by event type
@MainActor
final class HooksManager: ObservableObject {
    static let shared = HooksManager()

    @Published var hooksByEvent: [String: [HookEntry]] = [:]

    /// All supported hook event types with descriptions
    static let eventTypes: [(name: String, description: String)] = [
        ("PreToolUse", "Runs before any tool call. Exit 2 to block the tool."),
        ("PostToolUse", "Runs after a tool completes. Receives tool output."),
        ("Notification", "Runs when Claude sends a notification."),
        ("Stop", "Runs when Claude finishes responding."),
        ("SubagentStop", "Runs when a sub-agent finishes."),
        ("SessionStart", "Runs when a new session begins."),
        ("SessionEnd", "Runs when a session ends."),
    ]

    private let settingsPath: String

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        settingsPath = "\(home)/.claude/settings.json"
        load()
    }

    // MARK: - Load

    func load() {
        guard FileManager.default.fileExists(atPath: settingsPath),
              let data = FileManager.default.contents(atPath: settingsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            hooksByEvent = [:]
            return
        }

        var result: [String: [HookEntry]] = [:]
        for (eventType, value) in hooks {
            guard let hookArray = value as? [[String: Any]] else { continue }
            var entries: [HookEntry] = []
            for hookDict in hookArray {
                guard let command = hookDict["command"] as? String else { continue }
                let timeout = hookDict["timeout"] as? Int
                let matcher = hookDict["matcher"] as? String
                entries.append(HookEntry(command: command, timeout: timeout, matcher: matcher))
            }
            if !entries.isEmpty {
                result[eventType] = entries
            }
        }
        hooksByEvent = result
    }

    // MARK: - Save

    func save() {
        // Read existing settings to preserve other keys
        var settings: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: settingsPath),
           let data = FileManager.default.contents(atPath: settingsPath),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = existing
        }

        // Build hooks dict
        var hooksDict: [String: Any] = [:]
        for (eventType, entries) in hooksByEvent where !entries.isEmpty {
            var hookArray: [[String: Any]] = []
            for entry in entries {
                var dict: [String: Any] = ["command": entry.command]
                if let timeout = entry.timeout { dict["timeout"] = timeout }
                if let matcher = entry.matcher, !matcher.isEmpty { dict["matcher"] = matcher }
                hookArray.append(dict)
            }
            hooksDict[eventType] = hookArray
        }

        if hooksDict.isEmpty {
            settings.removeValue(forKey: "hooks")
        } else {
            settings["hooks"] = hooksDict
        }

        // Ensure ~/.claude/ directory exists
        let dir = (settingsPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        // Write with pretty printing
        if let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: settingsPath))
        }
    }

    // MARK: - CRUD

    func addHook(event: String, command: String, timeout: Int? = nil, matcher: String? = nil) {
        let entry = HookEntry(command: command, timeout: timeout, matcher: matcher)
        hooksByEvent[event, default: []].append(entry)
        save()
    }

    func removeHook(event: String, id: String) {
        hooksByEvent[event]?.removeAll { $0.id == id }
        if hooksByEvent[event]?.isEmpty == true {
            hooksByEvent.removeValue(forKey: event)
        }
        save()
    }

    func updateHook(event: String, id: String, command: String, timeout: Int?, matcher: String?) {
        guard let idx = hooksByEvent[event]?.firstIndex(where: { $0.id == id }) else { return }
        hooksByEvent[event]?[idx].command = command
        hooksByEvent[event]?[idx].timeout = timeout
        hooksByEvent[event]?[idx].matcher = matcher
        save()
    }

    /// Total hook count across all events
    var totalCount: Int {
        hooksByEvent.values.reduce(0) { $0 + $1.count }
    }
}
