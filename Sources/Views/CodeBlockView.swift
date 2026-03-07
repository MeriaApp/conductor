import SwiftUI
import HighlightSwift

/// Renders a syntax-highlighted code block with language label and copy button
struct CodeBlockView: View {
    let block: CodeBlock
    @EnvironmentObject private var theme: ThemeEngine
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar with language + copy button
            HStack {
                if let lang = block.language {
                    Text(lang)
                        .font(Typography.codeMeta)
                        .foregroundColor(theme.muted)
                }

                if let filename = block.filename {
                    Text(filename)
                        .font(Typography.codeMeta)
                        .foregroundColor(theme.secondary)
                }

                Spacer()

                Button(action: copyCode) {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                        Text(copied ? "Copied" : "Copy")
                            .font(Typography.codeMeta)
                    }
                    .foregroundColor(copied ? theme.sage : theme.muted)
                }
                .buttonStyle(.plain)
                .opacity(copied ? 1 : 0.6)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(theme.codeBackground.opacity(0.5))

            // Code content with syntax highlighting
            CodeHighlightView(code: block.code, language: block.language)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .background(theme.codeBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.separator.opacity(0.3), lineWidth: 1)
        )
    }

    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(block.code, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run { copied = false }
        }
    }
}

/// Renders syntax-highlighted code using HighlightSwift
struct CodeHighlightView: View {
    let code: String
    let language: String?
    @EnvironmentObject private var theme: ThemeEngine

    var body: some View {
        if let hlLang = resolveLanguage(language) {
            CodeText(code)
                .highlightLanguage(hlLang)
                .codeTextColors(.theme(.atomOne))
                .codeTextStyle(.plain)
                .font(Typography.codeBlock)
        } else {
            CodeText(code)
                .codeTextColors(.theme(.atomOne))
                .codeTextStyle(.plain)
                .font(Typography.codeBlock)
        }
    }

    /// Map common language shorthand to HighlightLanguage
    private func resolveLanguage(_ lang: String?) -> HighlightLanguage? {
        guard let lang = lang?.lowercased() else { return nil }
        let map: [String: HighlightLanguage] = [
            "swift": .swift,
            "javascript": .javaScript, "js": .javaScript, "jsx": .javaScript,
            "typescript": .typeScript, "ts": .typeScript, "tsx": .typeScript,
            "python": .python, "py": .python,
            "ruby": .ruby, "rb": .ruby,
            "rust": .rust, "rs": .rust,
            "go": .go, "golang": .go,
            "java": .java,
            "kotlin": .kotlin, "kt": .kotlin,
            "c": .c, "cpp": .cPlusPlus, "c++": .cPlusPlus,
            "csharp": .cSharp, "cs": .cSharp, "c#": .cSharp,
            "html": .html, "css": .css,
            "json": .json, "yaml": .yaml, "yml": .yaml,
            "bash": .bash, "sh": .bash, "zsh": .bash, "shell": .bash,
            "sql": .sql,
            "markdown": .markdown, "md": .markdown,
            "php": .php,
            "dart": .dart,
            "dockerfile": .dockerfile,
            "graphql": .graphQL,
        ]
        return map[lang]
    }
}
