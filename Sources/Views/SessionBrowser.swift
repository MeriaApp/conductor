import SwiftUI

/// Session browser overlay (Cmd+S) — browse and resume previous sessions
struct SessionBrowser: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @EnvironmentObject private var process: ClaudeProcess
    @EnvironmentObject private var theme: ThemeEngine
    @Binding var isPresented: Bool
    @State private var searchText = ""
    @State private var selectedIndex = 0
    @FocusState private var isFocused: Bool

    var filteredSessions: [Session] {
        let sorted = sessionManager.sessions.sorted { $0.lastActiveAt > $1.lastActiveAt }
        if searchText.isEmpty { return sorted }
        return sorted.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            ($0.projectPath ?? "").localizedCaseInsensitiveContains(searchText) ||
            ($0.gitBranch ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 14))
                    .foregroundColor(theme.sky)
                Text("Sessions")
                    .font(Typography.heading2)
                    .foregroundColor(theme.bright)
                Spacer()
                Text("\(sessionManager.sessions.count) total")
                    .font(Typography.caption)
                    .foregroundColor(theme.muted)
            }
            .padding(14)

            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(theme.muted)
                TextField("Search sessions...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(Typography.body)
                    .foregroundColor(theme.primary)
                    .focused($isFocused)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            Divider().opacity(0.3)

            // Session list
            if filteredSessions.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.system(size: 24))
                        .foregroundColor(theme.muted)
                    Text("No sessions found")
                        .font(Typography.body)
                        .foregroundColor(theme.muted)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(filteredSessions.enumerated()), id: \.element.id) { idx, session in
                                SessionRow(
                                    session: session,
                                    isSelected: idx == selectedIndex,
                                    isActive: session.id == sessionManager.activeSession?.id
                                )
                                .id(session.id)
                                .onTapGesture {
                                    resumeSession(session)
                                }
                                .contextMenu {
                                    Button("Fork Session") {
                                        let forked = sessionManager.forkSession(session)
                                        resumeSession(forked)
                                    }
                                    Divider()
                                    Button("Delete", role: .destructive) {
                                        sessionManager.deleteSession(id: session.id)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                    }
                    .frame(maxHeight: 400)
                    .onChange(of: selectedIndex) { _, newIdx in
                        if newIdx < filteredSessions.count {
                            proxy.scrollTo(filteredSessions[newIdx].id, anchor: .center)
                        }
                    }
                }
            }
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
        }
        .onChange(of: searchText) { _, _ in
            selectedIndex = 0
        }
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 { selectedIndex -= 1 }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if selectedIndex < filteredSessions.count - 1 { selectedIndex += 1 }
            return .handled
        }
        .onKeyPress(.return) {
            if selectedIndex < filteredSessions.count {
                resumeSession(filteredSessions[selectedIndex])
            }
            return .handled
        }
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
    }

    private func resumeSession(_ session: Session) {
        guard let cliSessionId = session.sessionId else { return }
        process.stop()

        // Load conversation history from CLI session file
        if let history = ConversationHistoryLoader.load(
            sessionId: cliSessionId,
            projectDir: session.projectPath
        ), !history.isEmpty {
            process.messages = history
        }

        process.start(directory: session.projectPath, resumeSession: cliSessionId)
        sessionManager.activeSession = session
        if var s = sessionManager.activeSession {
            s.isActive = true
            s.lastActiveAt = Date()
            sessionManager.activeSession = s
        }
        isPresented = false
    }
}

// MARK: - Session Row

struct SessionRow: View {
    let session: Session
    let isSelected: Bool
    let isActive: Bool
    @EnvironmentObject private var theme: ThemeEngine

    var body: some View {
        HStack(spacing: 10) {
            // Active indicator
            Circle()
                .fill(isActive ? theme.sage : Color.clear)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 3) {
                // Title + project path
                HStack(spacing: 6) {
                    Text(session.title)
                        .font(Typography.bodyBold)
                        .foregroundColor(theme.bright)

                    if let branch = session.gitBranch {
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
                    // Time ago
                    Text(timeAgo(session.lastActiveAt))
                        .font(Typography.caption)
                        .foregroundColor(theme.muted)

                    // Messages
                    if session.messageCount > 0 {
                        Label("\(session.messageCount) msgs", systemImage: "bubble.left")
                            .font(Typography.caption)
                            .foregroundColor(theme.muted)
                    }

                    // Cost
                    if session.totalCostUSD > 0.01 {
                        Text(session.formattedCost)
                            .font(Typography.caption)
                            .foregroundColor(theme.amber)
                    }

                    // Model
                    Text(formatModel(session.model))
                        .font(Typography.caption)
                        .foregroundColor(theme.muted)
                }

                // Summary (auto-generated on session end)
                if let summary = session.summary {
                    Text(summary)
                        .font(Typography.caption)
                        .foregroundColor(theme.muted)
                        .lineLimit(1)
                }

                // Project path
                if let path = session.projectPath {
                    Text(shortenPath(path))
                        .font(Typography.caption)
                        .foregroundColor(theme.muted)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Resume indicator
            if session.sessionId != nil {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 11))
                    .foregroundColor(theme.sky.opacity(isSelected ? 1 : 0.5))
            } else {
                Text("no session")
                    .font(Typography.caption)
                    .foregroundColor(theme.muted.opacity(0.5))
            }
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

    private func formatModel(_ model: String) -> String {
        if model.contains("opus") { return "Opus" }
        if model.contains("sonnet") { return "Sonnet" }
        if model.contains("haiku") { return "Haiku" }
        return model.components(separatedBy: "-").last ?? model
    }

    private func shortenPath(_ path: String) -> String {
        let components = path.components(separatedBy: "/").filter { !$0.isEmpty }
        if components.count <= 3 { return path }
        return ".../" + components.suffix(3).joined(separator: "/")
    }
}
