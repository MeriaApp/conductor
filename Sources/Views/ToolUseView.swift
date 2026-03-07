import SwiftUI

/// Compact inline display for tool usage (Read, Edit, Bash, etc.)
struct ToolUseView: View {
    let block: ToolUseBlock
    var onFilePathTap: ((String) -> Void)?
    @EnvironmentObject private var theme: ThemeEngine
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Compact header — always visible
            HStack(spacing: 8) {
                statusIcon
                    .font(.system(size: 11))

                Text(block.toolName)
                    .font(Typography.toolLabel)
                    .foregroundColor(theme.secondary)

                // Tool input summary (truncated) — clickable for file tools
                if let filePath = extractFullFilePath(), onFilePathTap != nil {
                    Button {
                        onFilePathTap?(filePath)
                    } label: {
                        Text(inputSummary)
                            .font(Typography.caption)
                            .foregroundColor(theme.sky)
                            .lineLimit(1)
                            .underline()
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(inputSummary)
                        .font(Typography.caption)
                        .foregroundColor(theme.muted)
                        .lineLimit(1)
                }

                Spacer()

                // Duration
                if let duration = block.duration {
                    Text(formatDuration(duration))
                        .font(Typography.caption)
                        .foregroundColor(theme.muted)
                }

                // Status text
                statusText

                // Expand toggle if there's output
                if block.output != nil {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                        .foregroundColor(theme.muted)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture {
                if block.output != nil {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                }
            }

            // Expanded output
            if isExpanded, let output = block.output {
                Text(output)
                    .font(Typography.codeBlock)
                    .foregroundColor(theme.secondary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .padding(.leading, 20) // Indent under status icon
            }
        }
        .background(theme.toolBackground.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch block.status {
        case .pending:
            Image(systemName: "clock")
                .foregroundColor(theme.sand)
        case .running:
            ProgressView()
                .controlSize(.mini)
                .scaleEffect(0.7)
        case .completed:
            Image(systemName: "checkmark")
                .foregroundColor(theme.sage)
        case .failed:
            Image(systemName: "xmark")
                .foregroundColor(theme.rose)
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch block.status {
        case .pending:
            Text("pending")
                .font(Typography.caption)
                .foregroundColor(theme.sand)
        case .running:
            Text("...")
                .font(Typography.caption)
                .foregroundColor(theme.sky)
        case .completed:
            EmptyView()
        case .failed:
            Text("failed")
                .font(Typography.caption)
                .foregroundColor(theme.rose)
        }
    }

    /// Extract the full file path from tool input (for Read/Edit/Write tools)
    private func extractFullFilePath() -> String? {
        let fileTools = ["Read", "Edit", "Write"]
        guard fileTools.contains(block.toolName) else { return nil }

        guard let data = block.input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let path = json["file_path"] as? String else { return nil }

        return path
    }

    private var inputSummary: String {
        let input = block.input
        if input.isEmpty { return "" }

        // Parse JSON to extract the most meaningful field per tool type
        if let data = input.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            switch block.toolName {
            case "Read":
                if let path = json["file_path"] as? String {
                    return shortenPath(path)
                }
            case "Edit":
                if let path = json["file_path"] as? String {
                    return shortenPath(path)
                }
            case "Write":
                if let path = json["file_path"] as? String {
                    return shortenPath(path)
                }
            case "Bash":
                if let cmd = json["command"] as? String {
                    let trimmed = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.count > 80 ? String(trimmed.prefix(77)) + "..." : trimmed
                }
            case "Grep":
                if let pattern = json["pattern"] as? String {
                    let path = json["path"] as? String
                    let summary = "\"\(pattern)\""
                    if let p = path { return "\(summary) in \(shortenPath(p))" }
                    return summary
                }
            case "Glob":
                if let pattern = json["pattern"] as? String {
                    return pattern
                }
            case "Task":
                if let prompt = json["prompt"] as? String {
                    return prompt.count > 60 ? String(prompt.prefix(57)) + "..." : prompt
                }
            case "WebSearch":
                if let query = json["query"] as? String {
                    return "\"\(query)\""
                }
            case "WebFetch":
                if let url = json["url"] as? String {
                    return url.count > 60 ? String(url.prefix(57)) + "..." : url
                }
            case "ToolSearch":
                if let query = json["query"] as? String {
                    return query
                }
            default:
                break
            }
        }

        // Fallback: first line truncated
        let lines = input.components(separatedBy: .newlines)
        let first = lines.first ?? input
        return first.count > 60 ? String(first.prefix(57)) + "..." : first
    }

    /// Shorten a file path to the last 3 components
    private func shortenPath(_ path: String) -> String {
        let components = path.components(separatedBy: "/").filter { !$0.isEmpty }
        if components.count <= 3 { return path }
        return ".../" + components.suffix(3).joined(separator: "/")
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 1 {
            return String(format: "%.0fms", seconds * 1000)
        }
        return String(format: "%.1fs", seconds)
    }
}
