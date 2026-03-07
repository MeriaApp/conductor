import SwiftUI
import HighlightSwift

/// Inline file preview panel — shows syntax-highlighted file contents
struct FilePreviewPanel: View {
    let filePath: String
    @Binding var isPresented: Bool
    @EnvironmentObject private var theme: ThemeEngine
    @State private var fileContent: String?
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 12))
                    .foregroundColor(theme.sky)

                Text(shortenPath(filePath))
                    .font(Typography.bodyBold)
                    .foregroundColor(theme.bright)
                    .lineLimit(1)

                if let content = fileContent {
                    let lineCount = content.components(separatedBy: "\n").count
                    Text("\(lineCount) lines")
                        .font(Typography.caption)
                        .foregroundColor(theme.muted)
                }

                Spacer()

                // Copy path
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(filePath, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundColor(theme.muted)
                }
                .buttonStyle(.plain)

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(theme.muted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(theme.codeBackground.opacity(0.8))

            Divider().opacity(0.3)

            // Content
            if let error = loadError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 24))
                        .foregroundColor(theme.rose)
                    Text(error)
                        .font(Typography.body)
                        .foregroundColor(theme.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(20)
            } else if let content = fileContent {
                ScrollView([.horizontal, .vertical]) {
                    HStack(alignment: .top, spacing: 0) {
                        // Line numbers gutter
                        let lines = content.components(separatedBy: "\n")
                        VStack(alignment: .trailing, spacing: 0) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { idx, _ in
                                Text("\(idx + 1)")
                                    .font(Typography.codeBlock)
                                    .foregroundColor(theme.muted.opacity(0.5))
                                    .frame(minWidth: 30, alignment: .trailing)
                                    .padding(.trailing, 8)
                            }
                        }
                        .padding(.vertical, 8)

                        Divider().opacity(0.2)

                        // Syntax-highlighted code
                        CodeHighlightView(
                            code: content,
                            language: detectLanguage(from: filePath)
                        )
                        .padding(8)
                    }
                }
                .frame(maxHeight: NSScreen.main.map { $0.frame.height * 0.6 } ?? 500)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: 100)
            }
        }
        .background(theme.codeBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.sky.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 30, y: 10)
        .onAppear { loadFile() }
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
    }

    private func loadFile() {
        guard FileManager.default.fileExists(atPath: filePath) else {
            loadError = "File not found"
            return
        }

        guard let data = FileManager.default.contents(atPath: filePath),
              let content = String(data: data, encoding: .utf8) else {
            loadError = "Could not read file"
            return
        }

        // Limit to ~5000 lines for performance
        let lines = content.components(separatedBy: "\n")
        if lines.count > 5000 {
            fileContent = lines.prefix(5000).joined(separator: "\n") + "\n\n... (truncated at 5000 lines)"
        } else {
            fileContent = content
        }
    }

    private func shortenPath(_ path: String) -> String {
        let components = path.components(separatedBy: "/").filter { !$0.isEmpty }
        if components.count <= 3 { return path }
        return ".../" + components.suffix(3).joined(separator: "/")
    }

    /// Detect language from file extension (mirrors CodeBlockView's mapping)
    private func detectLanguage(from path: String) -> String? {
        let ext = (path as NSString).pathExtension.lowercased()
        let map: [String: String] = [
            "swift": "swift",
            "js": "javascript", "jsx": "javascript",
            "ts": "typescript", "tsx": "typescript",
            "py": "python",
            "rb": "ruby",
            "rs": "rust",
            "go": "go",
            "java": "java",
            "kt": "kotlin",
            "c": "c", "h": "c",
            "cpp": "cpp", "hpp": "cpp", "cc": "cpp",
            "cs": "csharp",
            "html": "html", "htm": "html",
            "css": "css",
            "json": "json",
            "yaml": "yaml", "yml": "yaml",
            "sh": "bash", "bash": "bash", "zsh": "bash",
            "sql": "sql",
            "md": "markdown",
            "php": "php",
            "dart": "dart",
            "dockerfile": "dockerfile",
            "graphql": "graphql", "gql": "graphql",
            "xml": "html",
            "toml": "yaml",
        ]
        return map[ext]
    }
}
