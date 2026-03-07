import Foundation

/// Session handoff data — everything needed to resume a session perfectly
struct SessionArtifact: Codable, Identifiable {
    let id: String
    let sessionId: String
    let projectPath: String?
    let timestamp: Date

    // What happened
    var accomplishments: [String]            // Completed tasks with file paths
    var inProgressWork: InProgressWork?      // Current task, blockers, next steps
    var decisions: [ContextDecision]         // Key decisions with reasoning
    var filesModified: [FileChange]          // Files changed with line ranges

    // State
    var buildDeployStatus: BuildStatus?      // Did it compile? Was it deployed?
    var activeBranch: String?                // Git branch
    var uncommittedChanges: Bool             // Any unstaged work?

    // Context for next session
    var contextForResume: String             // Structured "here's where we left off" text

    init(
        id: String = UUID().uuidString,
        sessionId: String,
        projectPath: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.sessionId = sessionId
        self.projectPath = projectPath
        self.timestamp = timestamp
        self.accomplishments = []
        self.inProgressWork = nil
        self.decisions = []
        self.filesModified = []
        self.buildDeployStatus = nil
        self.activeBranch = nil
        self.uncommittedChanges = false
        self.contextForResume = ""
    }

    /// Generate a structured resume prompt from this artifact
    func generateResumePrompt() -> String {
        var lines: [String] = []

        lines.append("## Session Resumption Context")
        lines.append("")

        if let project = projectPath {
            lines.append("**Project:** \(project)")
        }
        if let branch = activeBranch {
            lines.append("**Branch:** \(branch)")
        }
        lines.append("")

        if !accomplishments.isEmpty {
            lines.append("### Completed")
            for item in accomplishments {
                lines.append("- \(item)")
            }
            lines.append("")
        }

        if let work = inProgressWork {
            lines.append("### In Progress")
            lines.append("**Task:** \(work.task)")
            if !work.blockers.isEmpty {
                lines.append("**Blockers:** \(work.blockers.joined(separator: ", "))")
            }
            if !work.nextSteps.isEmpty {
                lines.append("**Next steps:**")
                for step in work.nextSteps {
                    lines.append("- \(step)")
                }
            }
            lines.append("")
        }

        if !decisions.isEmpty {
            lines.append("### Key Decisions")
            for decision in decisions {
                lines.append("- **\(decision.description)**: \(decision.reasoning)")
            }
            lines.append("")
        }

        if !filesModified.isEmpty {
            lines.append("### Files Modified")
            for file in filesModified {
                let range = file.lineRange.map { " (lines \($0))" } ?? ""
                lines.append("- \(file.filePath)\(range): \(file.summary)")
            }
            lines.append("")
        }

        if let build = buildDeployStatus {
            lines.append("### Build Status")
            lines.append("- Compiled: \(build.compiled ? "Yes" : "No")")
            lines.append("- Deployed: \(build.deployed ? "Yes to \(build.deployTarget ?? "unknown")" : "No")")
        }

        return lines.joined(separator: "\n")
    }
}

struct InProgressWork: Codable {
    var task: String
    var blockers: [String]
    var nextSteps: [String]
    var relevantFiles: [String]   // File paths the task is touching
}
