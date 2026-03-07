import Foundation

/// Manages known project directories for quick switching
@MainActor
final class ProjectManager: ObservableObject {
    static let shared = ProjectManager()

    @Published var projects: [ProjectEntry] = []

    private let persistPath: String

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Conductor")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        persistPath = dir.appendingPathComponent("projects.json").path
        load()
    }

    // MARK: - Load & Refresh

    /// Rebuild project list from sessions + persisted pins + Claude CLI projects
    func load() {
        // 1. Load persisted data (pins, manual additions)
        let persisted = loadPersisted()

        // 2. Aggregate from sessions
        let sessions = SessionManager.shared.sessions
        var projectMap: [String: ProjectEntry] = [:]

        for session in sessions {
            guard let path = session.projectPath, !path.isEmpty else { continue }

            if var existing = projectMap[path] {
                existing.sessionCount += 1
                if session.lastActiveAt > existing.lastActiveAt {
                    existing.lastActiveAt = session.lastActiveAt
                    existing.lastGitBranch = session.gitBranch
                    existing.lastModel = session.model
                }
                projectMap[path] = existing
            } else {
                projectMap[path] = ProjectEntry(
                    path: path,
                    displayName: displayName(for: path),
                    lastActiveAt: session.lastActiveAt,
                    lastGitBranch: session.gitBranch,
                    lastModel: session.model,
                    sessionCount: 1,
                    projectType: detectType(in: path),
                    isPinned: persisted[path]?.isPinned ?? false
                )
            }
        }

        // 3. Scan ~/.claude/projects/ for known projects
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let claudeProjectsDir = "\(home)/.claude/projects"
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: claudeProjectsDir) {
            for entry in entries where !entry.hasPrefix(".") {
                // Directory names in .claude/projects are path-encoded (e.g. "-Users-jesse-project")
                let decoded = "/" + entry.replacingOccurrences(of: "-", with: "/")
                // Check if this looks like a real directory
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: decoded, isDirectory: &isDir), isDir.boolValue {
                    if projectMap[decoded] == nil {
                        projectMap[decoded] = ProjectEntry(
                            path: decoded,
                            displayName: displayName(for: decoded),
                            lastActiveAt: Date.distantPast,
                            lastGitBranch: nil,
                            lastModel: "claude-opus-4-6",
                            sessionCount: 0,
                            projectType: detectType(in: decoded),
                            isPinned: persisted[decoded]?.isPinned ?? false
                        )
                    }
                }
            }
        }

        // 4. Add manually-added projects from persisted data
        for (path, entry) in persisted where entry.isManuallyAdded {
            if projectMap[path] == nil {
                projectMap[path] = entry
            }
        }

        projects = Array(projectMap.values).sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            return a.lastActiveAt > b.lastActiveAt
        }
    }

    // MARK: - Actions

    func addProject(path: String) {
        guard !projects.contains(where: { $0.path == path }) else { return }
        let entry = ProjectEntry(
            path: path,
            displayName: displayName(for: path),
            lastActiveAt: Date(),
            lastGitBranch: nil,
            lastModel: "claude-opus-4-6",
            sessionCount: 0,
            projectType: detectType(in: path),
            isPinned: false,
            isManuallyAdded: true
        )
        projects.insert(entry, at: projects.firstIndex(where: { !$0.isPinned }) ?? projects.count)
        savePersisted()
    }

    func removeProject(path: String) {
        projects.removeAll { $0.path == path }
        savePersisted()
    }

    func pinProject(path: String) {
        guard let idx = projects.firstIndex(where: { $0.path == path }) else { return }
        projects[idx].isPinned.toggle()
        projects.sort { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            return a.lastActiveAt > b.lastActiveAt
        }
        savePersisted()
    }

    // MARK: - Helpers

    private func displayName(for path: String) -> String {
        path.components(separatedBy: "/").last ?? path
    }

    private func detectType(in path: String) -> String? {
        let fm = FileManager.default
        if fm.fileExists(atPath: "\(path)/Package.swift") || fm.fileExists(atPath: "\(path)/project.yml") {
            return "swift"
        } else if fm.fileExists(atPath: "\(path)/package.json") {
            return "node"
        } else if fm.fileExists(atPath: "\(path)/Cargo.toml") {
            return "rust"
        } else if fm.fileExists(atPath: "\(path)/go.mod") {
            return "go"
        } else if fm.fileExists(atPath: "\(path)/requirements.txt") || fm.fileExists(atPath: "\(path)/pyproject.toml") {
            return "python"
        } else if fm.fileExists(atPath: "\(path)/Gemfile") {
            return "ruby"
        }
        return nil
    }

    // MARK: - Persistence

    private func savePersisted() {
        let entries = projects.filter { $0.isPinned || $0.isManuallyAdded }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: URL(fileURLWithPath: persistPath))
    }

    private func loadPersisted() -> [String: ProjectEntry] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: persistPath)),
              let entries = try? JSONDecoder().decode([ProjectEntry].self, from: data) else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0) })
    }
}

// MARK: - Data Model

struct ProjectEntry: Identifiable, Codable {
    var id: String { path }
    let path: String
    var displayName: String
    var lastActiveAt: Date
    var lastGitBranch: String?
    var lastModel: String
    var sessionCount: Int
    var projectType: String?
    var isPinned: Bool
    var isManuallyAdded: Bool = false

    var typeIcon: String {
        switch projectType {
        case "swift": return "swift"
        case "node": return "n.square"
        case "rust": return "gearshape"
        case "go": return "g.square"
        case "python": return "p.square"
        case "ruby": return "r.square"
        default: return "folder"
        }
    }

    var shortPath: String {
        let components = path.components(separatedBy: "/").filter { !$0.isEmpty }
        if components.count <= 3 { return path }
        return ".../" + components.suffix(3).joined(separator: "/")
    }
}
