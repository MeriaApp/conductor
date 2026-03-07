import SwiftUI

/// Full-screen overlay showing all files modified during the current session with unified diffs
/// "What did this session actually change?" — the bridge between trust and commit
struct SessionDiffOverlay: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var process: ClaudeProcess
    @EnvironmentObject private var theme: ThemeEngine

    @State private var changedFiles: [DiffFileEntry] = []
    @State private var selectedFile: DiffFileEntry?
    @State private var selectedDiff: String = ""
    @State private var summaryLine: String = ""
    @State private var isLoading = true
    @State private var commitMessage = ""
    @State private var showCommitField = false
    @State private var showRevertConfirm = false
    @State private var showRevertAllConfirm = false
    @State private var fileToRevert: DiffFileEntry?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            topBar

            Divider().opacity(0.3)

            if isLoading {
                loadingView
            } else if changedFiles.isEmpty {
                emptyView
            } else {
                // Main content: file list + diff viewer
                HSplitView {
                    fileList
                        .frame(minWidth: 200, maxWidth: 280)

                    diffViewer
                        .frame(maxWidth: .infinity)
                }
            }

            Divider().opacity(0.3)

            // Bottom bar
            bottomBar
        }
        .background(theme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.sky.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 30, y: 10)
        .padding(40)
        .onAppear {
            isFocused = true
            loadDiffs()
        }
        .onKeyPress(.escape) {
            if showCommitField {
                showCommitField = false
            } else {
                isPresented = false
            }
            return .handled
        }
        .alert("Revert File?", isPresented: $showRevertConfirm) {
            Button("Revert", role: .destructive) {
                if let file = fileToRevert {
                    revertFile(file)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            if let file = fileToRevert {
                Text("This will discard all changes to \(file.shortName). This cannot be undone.")
            }
        }
        .alert("Revert All Changes?", isPresented: $showRevertAllConfirm) {
            Button("Revert All", role: .destructive) {
                revertAll()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will discard ALL uncommitted changes in the working directory. This cannot be undone.")
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 14))
                .foregroundColor(theme.sky)

            Text("Session Diff Review")
                .font(Typography.heading2)
                .foregroundColor(theme.bright)

            if !summaryLine.isEmpty {
                Text(summaryLine)
                    .font(Typography.caption)
                    .foregroundColor(theme.muted)
            }

            Spacer()

            // Revert All
            if !changedFiles.isEmpty {
                Button {
                    showRevertAllConfirm = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 10))
                        Text("Revert All")
                            .font(Typography.caption)
                    }
                    .foregroundColor(theme.rose)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(theme.rose.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }

            // Close
            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(theme.muted)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
    }

    // MARK: - File List

    private var fileList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(changedFiles) { file in
                    fileRow(file)
                        .onTapGesture {
                            selectFile(file)
                        }
                }
            }
            .padding(8)
        }
        .background(theme.surface.opacity(0.5))
    }

    private func fileRow(_ file: DiffFileEntry) -> some View {
        let isSelected = selectedFile?.id == file.id

        return HStack(spacing: 6) {
            // Status indicator
            Text(file.statusIcon)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(file.statusColor(theme))
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(file.shortName)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(theme.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let dir = file.directory {
                    Text(dir)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(theme.muted)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }

            Spacer()

            if let stats = file.diffStats {
                Text(stats)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(theme.sage)
            }

            // Per-file revert
            Button {
                fileToRevert = file
                showRevertConfirm = true
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 9))
                    .foregroundColor(theme.muted)
            }
            .buttonStyle(.plain)
            .help("Revert this file")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isSelected ? theme.sky.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
    }

    // MARK: - Diff Viewer

    private var diffViewer: some View {
        Group {
            if selectedDiff.isEmpty && selectedFile != nil {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "doc.text")
                        .font(.system(size: 24))
                        .foregroundColor(theme.muted)
                    Text("No changes to display")
                        .font(Typography.body)
                        .foregroundColor(theme.muted)
                    Spacer()
                }
            } else if selectedFile == nil {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "arrow.left")
                        .font(.system(size: 24))
                        .foregroundColor(theme.muted)
                    Text("Select a file to view its diff")
                        .font(Typography.body)
                        .foregroundColor(theme.muted)
                    Spacer()
                }
            } else {
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(parseDiffLines(selectedDiff).enumerated()), id: \.offset) { _, line in
                            diffLine(line)
                        }
                    }
                    .padding(8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.codeBackground)
    }

    private func diffLine(_ line: DiffDisplayLine) -> some View {
        HStack(spacing: 0) {
            // Gutter
            Text(line.gutter)
                .font(Typography.codeBlock)
                .foregroundColor(line.gutterColor(theme))
                .frame(width: 20, alignment: .center)

            // Content
            Text(line.text)
                .font(Typography.codeBlock)
                .foregroundColor(line.textColor(theme))
                .textSelection(.enabled)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .background(line.backgroundColor(theme))
        .frame(minHeight: 18)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 10) {
            if showCommitField {
                HStack(spacing: 8) {
                    TextField("Commit message...", text: $commitMessage)
                        .textFieldStyle(.plain)
                        .font(Typography.body)
                        .foregroundColor(theme.primary)
                        .focused($isFocused)
                        .onSubmit {
                            commitChanges()
                        }

                    Button("Commit") {
                        commitChanges()
                    }
                    .buttonStyle(.plain)
                    .font(Typography.bodyBold)
                    .foregroundColor(theme.sky)
                    .disabled(commitMessage.isEmpty)

                    Button("Cancel") {
                        showCommitField = false
                        commitMessage = ""
                    }
                    .buttonStyle(.plain)
                    .font(Typography.caption)
                    .foregroundColor(theme.muted)
                }
            } else {
                // Copy diff
                Button {
                    copyFullDiff()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                        Text("Copy Diff")
                            .font(Typography.caption)
                    }
                    .foregroundColor(theme.muted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(theme.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)

                // Open in editor
                if let file = selectedFile {
                    Button {
                        openInEditor(file)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "pencil")
                                .font(.system(size: 10))
                            Text("Open in Editor")
                                .font(Typography.caption)
                        }
                        .foregroundColor(theme.muted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(theme.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                // Commit button
                if !changedFiles.isEmpty {
                    Button {
                        showCommitField = true
                        isFocused = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 10))
                            Text("Commit...")
                                .font(Typography.caption)
                        }
                        .foregroundColor(theme.sage)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(theme.sage.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Loading / Empty States

    private var loadingView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .scaleEffect(0.8)
            Text("Scanning for changes...")
                .font(Typography.body)
                .foregroundColor(theme.muted)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 32))
                .foregroundColor(theme.sage)
            Text("No uncommitted changes")
                .font(Typography.heading2)
                .foregroundColor(theme.bright)
            Text("Working directory is clean")
                .font(Typography.body)
                .foregroundColor(theme.muted)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func loadDiffs() {
        guard let dir = process.workingDirectory else {
            isLoading = false
            return
        }

        Task {
            let service = GitDiffService.shared
            let files = await service.changedFiles(in: dir)

            var entries: [DiffFileEntry] = []
            for file in files {
                let stats = await service.diffStat(for: file.path, in: dir)
                entries.append(DiffFileEntry(
                    path: file.path,
                    gitStatus: file.status,
                    diffStats: stats
                ))
            }

            changedFiles = entries
            summaryLine = "\(entries.count) file\(entries.count == 1 ? "" : "s") changed"

            // Auto-select first file
            if let first = entries.first {
                selectFile(first)
            }

            isLoading = false
        }
    }

    private func selectFile(_ file: DiffFileEntry) {
        selectedFile = file
        guard let dir = process.workingDirectory else { return }

        Task {
            let diffOutput = await GitDiffService.shared.diff(for: file.path, in: dir)
            selectedDiff = diffOutput ?? ""
        }
    }

    private func revertFile(_ file: DiffFileEntry) {
        guard let dir = process.workingDirectory else { return }

        Task {
            let success = await GitDiffService.shared.revert(path: file.path, in: dir)
            if success {
                changedFiles.removeAll { $0.id == file.id }
                if selectedFile?.id == file.id {
                    selectedFile = changedFiles.first
                    if let first = selectedFile {
                        selectFile(first)
                    } else {
                        selectedDiff = ""
                    }
                }
                summaryLine = "\(changedFiles.count) file\(changedFiles.count == 1 ? "" : "s") changed"
            }
        }
    }

    private func revertAll() {
        guard let dir = process.workingDirectory else { return }

        Task {
            for file in changedFiles {
                _ = await GitDiffService.shared.revert(path: file.path, in: dir)
            }
            changedFiles.removeAll()
            selectedFile = nil
            selectedDiff = ""
            summaryLine = "All changes reverted"
        }
    }

    private func commitChanges() {
        guard let dir = process.workingDirectory, !commitMessage.isEmpty else { return }

        Task {
            let success = await GitDiffService.shared.commit(message: commitMessage, in: dir)
            if success {
                changedFiles.removeAll()
                selectedFile = nil
                selectedDiff = ""
                summaryLine = "Committed successfully"
                commitMessage = ""
                showCommitField = false
            }
        }
    }

    private func copyFullDiff() {
        guard let dir = process.workingDirectory else { return }

        Task {
            if let diff = await GitDiffService.shared.diffAll(in: dir) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(diff, forType: .string)
            }
        }
    }

    private func openInEditor(_ file: DiffFileEntry) {
        guard let dir = process.workingDirectory else { return }
        let fullPath = dir.hasSuffix("/") ? "\(dir)\(file.path)" : "\(dir)/\(file.path)"
        NSWorkspace.shared.open(URL(fileURLWithPath: fullPath))
    }

    // MARK: - Diff Parsing

    private func parseDiffLines(_ diff: String) -> [DiffDisplayLine] {
        diff.components(separatedBy: "\n").map { line in
            if line.hasPrefix("+") && !line.hasPrefix("+++") {
                return DiffDisplayLine(text: String(line.dropFirst()), gutter: "+", type: .added)
            } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                return DiffDisplayLine(text: String(line.dropFirst()), gutter: "-", type: .removed)
            } else if line.hasPrefix("@@") {
                return DiffDisplayLine(text: line, gutter: " ", type: .header)
            } else {
                let text = line.hasPrefix(" ") ? String(line.dropFirst()) : line
                return DiffDisplayLine(text: text, gutter: " ", type: .context)
            }
        }
    }
}

// MARK: - Data Models

struct DiffFileEntry: Identifiable {
    let id = UUID().uuidString
    let path: String
    let gitStatus: String
    var diffStats: String?

    var shortName: String {
        path.components(separatedBy: "/").last ?? path
    }

    var directory: String? {
        let components = path.components(separatedBy: "/")
        guard components.count > 1 else { return nil }
        return components.dropLast().joined(separator: "/")
    }

    var statusIcon: String {
        switch gitStatus {
        case "M", "MM": return "✎"
        case "A", "??": return "+"
        case "D": return "−"
        case "R": return "→"
        default: return "●"
        }
    }

    @MainActor func statusColor(_ theme: ThemeEngine) -> Color {
        switch gitStatus {
        case "M", "MM": return theme.sky
        case "A", "??": return theme.sage
        case "D": return theme.rose
        default: return theme.muted
        }
    }
}

struct DiffDisplayLine {
    let text: String
    let gutter: String
    let type: DiffDisplayLineType

    @MainActor func gutterColor(_ theme: ThemeEngine) -> Color {
        switch type {
        case .added: return theme.sage
        case .removed: return theme.rose
        case .header: return theme.sky
        case .context: return theme.muted
        }
    }

    @MainActor func textColor(_ theme: ThemeEngine) -> Color {
        switch type {
        case .added: return theme.sage
        case .removed: return theme.rose
        case .header: return theme.sky
        case .context: return theme.primary
        }
    }

    @MainActor func backgroundColor(_ theme: ThemeEngine) -> Color {
        switch type {
        case .added: return theme.sage.opacity(0.08)
        case .removed: return theme.rose.opacity(0.08)
        case .header: return theme.sky.opacity(0.05)
        case .context: return .clear
        }
    }
}

enum DiffDisplayLineType {
    case added, removed, context, header
}
