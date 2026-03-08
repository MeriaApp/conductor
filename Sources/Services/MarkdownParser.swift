import Foundation

/// Parses Claude's markdown output into typed ContentBlock arrays
/// Uses regex-based parsing for reliability (swift-markdown AST is used for inline rendering)
enum MarkdownParser {

    /// Parse a markdown string into an array of ContentBlocks
    static func parse(_ text: String) -> [any ContentBlockProtocol] {
        var blocks: [any ContentBlockProtocol] = []
        var currentText = ""
        var inCodeBlock = false
        var codeLanguage: String?
        var codeContent = ""

        let lines = text.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // Check for fenced code block start/end
            if line.hasPrefix("```") {
                if inCodeBlock {
                    // End of code block
                    inCodeBlock = false
                    let trimmedCode = codeContent.trimmingCharacters(in: .newlines)

                    if codeLanguage == "diff" || trimmedCode.hasPrefix("---") && trimmedCode.contains("+++") {
                        blocks.append(parseDiff(trimmedCode))
                    } else {
                        blocks.append(CodeBlock(code: trimmedCode, language: codeLanguage))
                    }
                    codeLanguage = nil
                    codeContent = ""
                } else {
                    // Start of code block — flush text first
                    flushText(&currentText, into: &blocks)
                    inCodeBlock = true
                    let langStr = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    codeLanguage = langStr.isEmpty ? nil : langStr
                }
                i += 1
                continue
            }

            if inCodeBlock {
                if !codeContent.isEmpty { codeContent += "\n" }
                codeContent += line
                i += 1
                continue
            }

            // Headings
            if line.hasPrefix("# ") || line.hasPrefix("## ") || line.hasPrefix("### ") {
                flushText(&currentText, into: &blocks)
                blocks.append(TextBlock(text: line))
                i += 1
                continue
            }

            // Blockquotes
            if line.hasPrefix("> ") || line == ">" {
                flushText(&currentText, into: &blocks)
                var quoteLines: [String] = []
                while i < lines.count {
                    let l = lines[i]
                    if l.hasPrefix("> ") {
                        quoteLines.append(String(l.dropFirst(2)))
                    } else if l == ">" {
                        quoteLines.append("")
                    } else {
                        break
                    }
                    i += 1
                }
                blocks.append(BlockquoteBlock(text: quoteLines.joined(separator: "\n")))
                continue
            }

            // Unordered lists
            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                flushText(&currentText, into: &blocks)
                var items: [String] = []
                while i < lines.count {
                    let l = lines[i]
                    if l.hasPrefix("- ") {
                        items.append(String(l.dropFirst(2)))
                    } else if l.hasPrefix("* ") {
                        items.append(String(l.dropFirst(2)))
                    } else if l.hasPrefix("+ ") {
                        items.append(String(l.dropFirst(2)))
                    } else {
                        break
                    }
                    i += 1
                }
                blocks.append(ListBlock(items: items, style: .bullet))
                continue
            }

            // Ordered lists
            if let _ = line.range(of: #"^\d+\. "#, options: .regularExpression) {
                flushText(&currentText, into: &blocks)
                var items: [String] = []
                while i < lines.count {
                    let l = lines[i]
                    if let range = l.range(of: #"^\d+\. "#, options: .regularExpression) {
                        items.append(String(l[range.upperBound...]))
                    } else {
                        break
                    }
                    i += 1
                }
                blocks.append(ListBlock(items: items, style: .numbered))
                continue
            }

            // Thematic breaks
            if line == "---" || line == "***" || line == "___" {
                flushText(&currentText, into: &blocks)
                i += 1
                continue
            }

            // Regular text
            if !line.isEmpty {
                if !currentText.isEmpty { currentText += "\n" }
                currentText += line
            } else {
                // Empty line separates paragraphs
                flushText(&currentText, into: &blocks)
            }
            i += 1
        }

        // Flush remaining
        if inCodeBlock && !codeContent.isEmpty {
            // Unterminated code block — treat as code anyway
            blocks.append(CodeBlock(code: codeContent, language: codeLanguage))
        }
        flushText(&currentText, into: &blocks)

        return blocks.isEmpty ? [TextBlock(text: text)] : blocks
    }

    // MARK: - Helpers

    private static func flushText(_ text: inout String, into blocks: inout [any ContentBlockProtocol]) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            blocks.append(TextBlock(text: trimmed))
        }
        text = ""
    }

    private static func parseDiff(_ text: String) -> DiffBlock {
        var hunks: [DiffHunk] = []
        var currentLines: [DiffLine] = []

        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("+") && !line.hasPrefix("+++") {
                currentLines.append(DiffLine(type: .added, text: line))
            } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                currentLines.append(DiffLine(type: .removed, text: line))
            } else if line.hasPrefix("@@") {
                if !currentLines.isEmpty {
                    hunks.append(DiffHunk(lines: currentLines))
                    currentLines = []
                }
            } else {
                currentLines.append(DiffLine(type: .context, text: line))
            }
        }

        if !currentLines.isEmpty {
            hunks.append(DiffHunk(lines: currentLines))
        }

        return DiffBlock(hunks: hunks)
    }
}
