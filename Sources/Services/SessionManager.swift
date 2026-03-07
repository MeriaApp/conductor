import Foundation

/// Manages session history, persistence, and active session state
@MainActor
final class SessionManager: ObservableObject {
    static let shared = SessionManager()

    @Published var sessions: [Session] = []
    @Published var activeSession: Session?

    private let sessionsURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("Conductor", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        sessionsURL = appDir.appendingPathComponent("sessions.json")

        loadSessions()
    }

    // MARK: - Session Management

    func createSession(directory: String? = nil) -> Session {
        let dirName = directory.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "~"
        let session = Session(
            title: dirName,
            projectPath: directory
        )
        sessions.insert(session, at: 0)
        activeSession = session
        saveSessions()
        return session
    }

    func updateActiveSession(from process: ClaudeProcess) {
        guard var session = activeSession else { return }
        session.sessionId = process.sessionId
        session.model = process.currentModel
        session.totalCostUSD = process.totalCostUSD
        session.totalInputTokens = process.totalInputTokens
        session.totalOutputTokens = process.totalOutputTokens
        session.messageCount = process.messages.count
        session.lastActiveAt = Date()

        activeSession = session

        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = session
        }
        saveSessions()
    }

    /// Update a specific session by ID (multi-window safe)
    func updateSession(id: String, from process: ClaudeProcess) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].sessionId = process.sessionId
        sessions[idx].model = process.currentModel
        sessions[idx].totalCostUSD = process.totalCostUSD
        sessions[idx].totalInputTokens = process.totalInputTokens
        sessions[idx].totalOutputTokens = process.totalOutputTokens
        sessions[idx].messageCount = process.messages.count
        sessions[idx].lastActiveAt = Date()
        saveSessions()
    }

    func endSession(messages: [ConversationMessage] = []) {
        if var session = activeSession {
            session.isActive = false
            if !messages.isEmpty {
                session.summary = generateSummary(from: messages)
            }
            if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
                sessions[idx] = session
            }
        }
        activeSession = nil
        saveSessions()
    }

    /// End a specific session by ID (multi-window safe)
    func endSession(id: String, messages: [ConversationMessage] = []) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].isActive = false
        if !messages.isEmpty {
            sessions[idx].summary = generateSummary(from: messages)
        }
        saveSessions()
    }

    /// Fork a session — creates a copy with the same settings
    func forkSession(_ session: Session) -> Session {
        var forked = Session(
            title: session.title + " (fork)",
            model: session.model,
            projectPath: session.projectPath
        )
        forked.forkedFrom = session.id
        forked.gitBranch = session.gitBranch
        sessions.insert(forked, at: 0)
        saveSessions()
        return forked
    }

    /// Delete a session
    func deleteSession(id: String) {
        sessions.removeAll { $0.id == id }
        if activeSession?.id == id {
            activeSession = nil
        }
        saveSessions()
    }

    // MARK: - Summary Generation

    private func generateSummary(from messages: [ConversationMessage]) -> String {
        let files = extractFileNames(from: messages)
        let turnCount = messages.filter { $0.role == .assistant }.count
        var summary = "\(turnCount) turns"
        if !files.isEmpty {
            summary += " · Files: \(files.prefix(5).joined(separator: ", "))"
        }
        return summary
    }

    private func extractFileNames(from messages: [ConversationMessage]) -> [String] {
        var fileNames: Set<String> = []
        for message in messages {
            for block in message.blocks {
                guard let tool = block as? ToolUseBlock else { continue }
                if ["Read", "Edit", "Write"].contains(tool.toolName) {
                    // Extract filename from path in input
                    if let range = tool.input.range(of: "\"([^\"]+)\"", options: .regularExpression) {
                        let path = String(tool.input[range]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                        let filename = URL(fileURLWithPath: path).lastPathComponent
                        fileNames.insert(filename)
                    }
                }
            }
        }
        return Array(fileNames).sorted()
    }

    // MARK: - Cost Aggregation

    /// Total cost across all sessions today
    var costToday: Double {
        let today = Calendar.current.startOfDay(for: Date())
        return sessions
            .filter { $0.lastActiveAt >= today }
            .reduce(0) { $0 + $1.totalCostUSD }
    }

    /// Total cost across all sessions this week
    var costThisWeek: Double {
        guard let startOfWeek = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start else {
            return costToday
        }
        return sessions
            .filter { $0.lastActiveAt >= startOfWeek }
            .reduce(0) { $0 + $1.totalCostUSD }
    }

    // MARK: - Persistence

    private func loadSessions() {
        guard FileManager.default.fileExists(atPath: sessionsURL.path),
              let data = try? Data(contentsOf: sessionsURL),
              let decoded = try? JSONDecoder().decode([Session].self, from: data) else {
            return
        }
        sessions = decoded
    }

    private func saveSessions() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        try? data.write(to: sessionsURL)
    }
}
