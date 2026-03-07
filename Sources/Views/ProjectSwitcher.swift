import SwiftUI
import AppKit

/// Project switcher overlay (Cmd+P) — quick-switch between known project directories
struct ProjectSwitcher: View {
    @EnvironmentObject private var process: ClaudeProcess
    @EnvironmentObject private var theme: ThemeEngine
    @EnvironmentObject private var sessionManager: SessionManager
    @EnvironmentObject private var featureDetector: FeatureDetector
    @EnvironmentObject private var projectManager: ProjectManager
    @Binding var isPresented: Bool

    @State private var searchText = ""
    @State private var selectedIndex = 0
    @FocusState private var isFocused: Bool

    var filteredProjects: [ProjectEntry] {
        if searchText.isEmpty { return projectManager.projects }
        return projectManager.projects.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.path.localizedCaseInsensitiveContains(searchText) ||
            ($0.lastGitBranch ?? "").localizedCaseInsensitiveContains(searchText) ||
            ($0.projectType ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 14))
                    .foregroundColor(theme.sky)
                Text("Switch Project")
                    .font(Typography.heading2)
                    .foregroundColor(theme.bright)
                Spacer()
                Text("\(projectManager.projects.count) projects")
                    .font(Typography.caption)
                    .foregroundColor(theme.muted)
            }
            .padding(14)

            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(theme.muted)
                TextField("Search projects...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(Typography.body)
                    .foregroundColor(theme.primary)
                    .focused($isFocused)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            Divider().opacity(0.3)

            // Project list
            if filteredProjects.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "folder")
                        .font(.system(size: 24))
                        .foregroundColor(theme.muted)
                    Text(searchText.isEmpty ? "No projects found" : "No matching projects")
                        .font(Typography.body)
                        .foregroundColor(theme.muted)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(filteredProjects.enumerated()), id: \.element.id) { idx, project in
                                ProjectRow(
                                    project: project,
                                    isSelected: idx == selectedIndex,
                                    isActive: process.workingDirectory == project.path
                                )
                                .id(project.id)
                                .onTapGesture {
                                    switchProject(project)
                                }
                                .contextMenu {
                                    Button(project.isPinned ? "Unpin" : "Pin to Top") {
                                        projectManager.pinProject(path: project.path)
                                    }
                                    Button("Reveal in Finder") {
                                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.path)
                                    }
                                    Divider()
                                    Button("Remove from List", role: .destructive) {
                                        projectManager.removeProject(path: project.path)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                    }
                    .frame(maxHeight: 400)
                    .onChange(of: selectedIndex) { _, newIdx in
                        if newIdx < filteredProjects.count {
                            proxy.scrollTo(filteredProjects[newIdx].id, anchor: .center)
                        }
                    }
                }
            }

            Divider().opacity(0.3)

            // Bottom: Add project button
            HStack {
                Button {
                    addProject()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 11))
                        Text("Add Project...")
                            .font(Typography.caption)
                    }
                    .foregroundColor(theme.sky)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Cmd+P")
                    .font(Typography.caption)
                    .foregroundColor(theme.muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(theme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.sky.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 30, y: 10)
        .frame(width: 560)
        .onAppear {
            isFocused = true
            selectedIndex = 0
            projectManager.load()
        }
        .onChange(of: searchText) { _, _ in
            selectedIndex = 0
        }
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 { selectedIndex -= 1 }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if selectedIndex < filteredProjects.count - 1 { selectedIndex += 1 }
            return .handled
        }
        .onKeyPress(.return) {
            if selectedIndex < filteredProjects.count {
                switchProject(filteredProjects[selectedIndex])
            }
            return .handled
        }
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
    }

    // MARK: - Actions

    private func switchProject(_ project: ProjectEntry) {
        let path = project.path
        process.stop()

        // Create a new session in the target directory
        _ = sessionManager.createSession(directory: path)

        // Start process in new directory
        process.start(directory: path)

        // Detect git branch
        detectGitBranch(in: path)

        // Feature detection
        Task {
            await featureDetector.scan(directory: path)
        }

        isPresented = false
    }

    private func detectGitBranch(in directory: String) {
        Task.detached {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            proc.arguments = ["rev-parse", "--abbrev-ref", "HEAD"]
            proc.currentDirectoryURL = URL(fileURLWithPath: directory)
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = Pipe()
            try? proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let branch = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !branch.isEmpty {
                    await MainActor.run {
                        if var session = SessionManager.shared.activeSession {
                            session.gitBranch = branch
                            SessionManager.shared.activeSession = session
                        }
                    }
                }
            }
        }
    }

    private func addProject() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Add Project Directory"
        panel.prompt = "Add"

        if panel.runModal() == .OK, let url = panel.url {
            projectManager.addProject(path: url.path)
        }
    }
}

// MARK: - Project Row

struct ProjectRow: View {
    let project: ProjectEntry
    let isSelected: Bool
    let isActive: Bool
    @EnvironmentObject private var theme: ThemeEngine

    var body: some View {
        HStack(spacing: 10) {
            // Active / pinned indicator
            ZStack {
                if isActive {
                    Circle()
                        .fill(theme.sage)
                        .frame(width: 6, height: 6)
                } else if project.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8))
                        .foregroundColor(theme.sand)
                } else {
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 6, height: 6)
                }
            }
            .frame(width: 12)

            // Project type icon
            Image(systemName: project.typeIcon)
                .font(.system(size: 12))
                .foregroundColor(theme.muted)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 3) {
                // Name + git branch
                HStack(spacing: 6) {
                    Text(project.displayName)
                        .font(Typography.bodyBold)
                        .foregroundColor(theme.bright)

                    if let branch = project.lastGitBranch {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 8))
                            Text(branch)
                                .font(Typography.caption)
                        }
                        .foregroundColor(theme.muted)
                    }
                }

                // Metadata row
                HStack(spacing: 10) {
                    if project.sessionCount > 0 {
                        Text(timeAgo(project.lastActiveAt))
                            .font(Typography.caption)
                            .foregroundColor(theme.muted)

                        Label("\(project.sessionCount) sessions", systemImage: "bubble.left")
                            .font(Typography.caption)
                            .foregroundColor(theme.muted)
                    }

                    if let type = project.projectType {
                        Text(type.capitalized)
                            .font(Typography.caption)
                            .foregroundColor(theme.muted)
                    }
                }

                // Path
                Text(project.shortPath)
                    .font(Typography.caption)
                    .foregroundColor(theme.muted)
                    .lineLimit(1)
            }

            Spacer()

            // Switch indicator
            Image(systemName: isActive ? "checkmark.circle.fill" : "arrow.right.circle")
                .font(.system(size: 12))
                .foregroundColor(isActive ? theme.sage : theme.sky.opacity(isSelected ? 1 : 0.5))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isSelected ? theme.sky.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }

    private func timeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        if interval < 604800 { return "\(Int(interval / 86400))d ago" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
}
