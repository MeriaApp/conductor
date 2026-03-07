import Foundation

/// Perfect handoff between sessions — no "what were we doing?" ever again
/// Auto-saves on session end, auto-loads on session start
@MainActor
final class SessionContinuity: ObservableObject {
    @Published var artifacts: [SessionArtifact] = []
    @Published var lastArtifact: SessionArtifact?

    private let artifactsDir: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        artifactsDir = appSupport.appendingPathComponent("Conductor/artifacts", isDirectory: true)
        try? FileManager.default.createDirectory(at: artifactsDir, withIntermediateDirectories: true)
        loadArtifacts()
    }

    // MARK: - Auto-Save on Session End

    /// Save a session artifact when a session ends
    func saveSessionEnd(
        sessionId: String,
        projectPath: String?,
        process: ClaudeProcess,
        contextManager: ContextStateManager
    ) {
        var artifact = SessionArtifact(
            sessionId: sessionId,
            projectPath: projectPath
        )

        // Gather state from context manager
        if let snapshot = contextManager.currentSnapshot {
            artifact.decisions = snapshot.decisions
            artifact.filesModified = snapshot.fileChanges

            if let task = snapshot.currentTask {
                artifact.inProgressWork = InProgressWork(
                    task: task,
                    blockers: [],
                    nextSteps: snapshot.nextSteps,
                    relevantFiles: snapshot.fileChanges.map { $0.filePath }
                )
            }

            for item in snapshot.taskProgress where item.status == .completed {
                artifact.accomplishments.append(item.description)
            }

            artifact.buildDeployStatus = snapshot.buildStatus
        }

        // Generate resume prompt
        artifact.contextForResume = artifact.generateResumePrompt()

        // Save
        artifacts.insert(artifact, at: 0)
        lastArtifact = artifact
        persistArtifact(artifact)

        // Also write CONTEXT_STATE.md
        if let dir = projectPath {
            contextManager.writeContextState(to: dir)
        }
    }

    // MARK: - Auto-Load on Session Start

    /// Load context for a new session in the same project
    func loadSessionContext(projectPath: String?) -> String? {
        guard let path = projectPath else { return nil }

        // Find the most recent artifact for this project
        let matching = artifacts.filter { $0.projectPath == path }
        guard let latest = matching.first else { return nil }

        lastArtifact = latest
        return latest.contextForResume
    }

    /// Find the most recent artifact for a project
    func latestArtifact(for projectPath: String) -> SessionArtifact? {
        artifacts.first { $0.projectPath == projectPath }
    }

    // MARK: - Search

    /// Search across all session artifacts
    func search(query: String) -> [SessionArtifact] {
        let lowered = query.lowercased()
        return artifacts.filter { artifact in
            artifact.contextForResume.lowercased().contains(lowered) ||
            artifact.accomplishments.contains { $0.lowercased().contains(lowered) } ||
            artifact.decisions.contains { $0.description.lowercased().contains(lowered) } ||
            artifact.filesModified.contains { $0.filePath.lowercased().contains(lowered) }
        }
    }

    // MARK: - Persistence

    private func loadArtifacts() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: artifactsDir, includingPropertiesForKeys: [.creationDateKey]
        ) else { return }

        let decoder = JSONDecoder()
        artifacts = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> SessionArtifact? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(SessionArtifact.self, from: data)
            }
            .sorted { $0.timestamp > $1.timestamp }

        // Keep only last 100
        if artifacts.count > 100 {
            let toRemove = artifacts.suffix(from: 100)
            for artifact in toRemove {
                let file = artifactsDir.appendingPathComponent("\(artifact.id).json")
                try? FileManager.default.removeItem(at: file)
            }
            artifacts = Array(artifacts.prefix(100))
        }

        lastArtifact = artifacts.first
    }

    private func persistArtifact(_ artifact: SessionArtifact) {
        let file = artifactsDir.appendingPathComponent("\(artifact.id).json")
        if let data = try? JSONEncoder().encode(artifact) {
            try? data.write(to: file)
        }
    }
}
