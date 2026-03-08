import SwiftUI

/// Renders an inline diff with added/removed line highlighting
/// Supports unified (default) and side-by-side view modes
struct DiffView: View {
    let block: DiffBlock
    var onExpand: ((DiffBlock) -> Void)?
    @EnvironmentObject private var theme: ThemeEngine
    @State private var sideBySide = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                if let filename = block.filename {
                    Image(systemName: "doc.text")
                        .font(.system(size: 10))
                        .foregroundColor(theme.muted)
                    Text(filename)
                        .font(Typography.codeMeta)
                        .foregroundColor(theme.secondary)
                }

                Spacer()

                // Expand to fullscreen
                if onExpand != nil {
                    Button {
                        onExpand?(block)
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10))
                            .foregroundColor(theme.muted)
                    }
                    .buttonStyle(.plain)
                }

                // View mode toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        sideBySide.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: sideBySide ? "text.alignleft" : "rectangle.split.2x1")
                            .font(.system(size: 10))
                        Text(sideBySide ? "Unified" : "Side by Side")
                            .font(Typography.codeMeta)
                    }
                    .foregroundColor(theme.muted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(theme.codeBackground.opacity(0.5))

            // Diff content — auto-fallback to unified on narrow windows
            DiffContentView(hunks: block.hunks, sideBySide: sideBySide)
        }
        .background(theme.codeBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.separator.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Diff Content (auto-fallback to unified on narrow windows)

struct DiffContentView: View {
    let hunks: [DiffHunk]
    let sideBySide: Bool
    @EnvironmentObject private var theme: ThemeEngine

    var body: some View {
        GeometryReader { geo in
            let forceUnified = geo.size.width < 600
            let useUnified = !sideBySide || forceUnified
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if !useUnified {
                        SideBySideDiffView(hunks: hunks)
                    } else {
                        ForEach(Array(hunks.enumerated()), id: \.offset) { _, hunk in
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
                                    DiffLineView(line: line)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Side-by-Side Diff View

struct SideBySideDiffView: View {
    let hunks: [DiffHunk]
    @EnvironmentObject private var theme: ThemeEngine

    var body: some View {
        ForEach(Array(hunks.enumerated()), id: \.offset) { _, hunk in
            let (leftLines, rightLines) = splitHunk(hunk)
            HStack(alignment: .top, spacing: 0) {
                // Left column (removed + context)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(leftLines.enumerated()), id: \.offset) { _, line in
                        SideBySideLineView(line: line)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Divider
                Rectangle()
                    .fill(theme.separator.opacity(0.3))
                    .frame(width: 1)

                // Right column (added + context)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rightLines.enumerated()), id: \.offset) { _, line in
                        SideBySideLineView(line: line)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Split a hunk into left (removed+context) and right (added+context) columns
    /// Pads the shorter column with empty lines to keep alignment
    private func splitHunk(_ hunk: DiffHunk) -> ([SideBySideLine], [SideBySideLine]) {
        var left: [SideBySideLine] = []
        var right: [SideBySideLine] = []

        for line in hunk.lines {
            switch line.type {
            case .context:
                // Balance columns before adding context
                while left.count < right.count {
                    left.append(SideBySideLine(text: "", type: .empty))
                }
                while right.count < left.count {
                    right.append(SideBySideLine(text: "", type: .empty))
                }
                left.append(SideBySideLine(text: line.text, type: .context))
                right.append(SideBySideLine(text: line.text, type: .context))
            case .removed:
                left.append(SideBySideLine(text: line.text, type: .removed))
            case .added:
                right.append(SideBySideLine(text: line.text, type: .added))
            }
        }

        // Final balance
        while left.count < right.count {
            left.append(SideBySideLine(text: "", type: .empty))
        }
        while right.count < left.count {
            right.append(SideBySideLine(text: "", type: .empty))
        }

        return (left, right)
    }
}

struct SideBySideLine {
    let text: String
    let type: SideBySideLineType
}

enum SideBySideLineType {
    case context, added, removed, empty
}

struct SideBySideLineView: View {
    let line: SideBySideLine
    @EnvironmentObject private var theme: ThemeEngine

    var body: some View {
        HStack(spacing: 0) {
            Text(line.text)
                .font(Typography.codeBlock)
                .foregroundColor(textColor)
                .textSelection(.enabled)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .background(backgroundColor)
        .frame(minHeight: 18)
    }

    private var textColor: Color {
        switch line.type {
        case .added: return theme.sage
        case .removed: return theme.rose
        case .context: return theme.primary
        case .empty: return .clear
        }
    }

    private var backgroundColor: Color {
        switch line.type {
        case .added: return theme.sage.opacity(0.08)
        case .removed: return theme.rose.opacity(0.08)
        case .context, .empty: return .clear
        }
    }
}

struct DiffLineView: View {
    let line: DiffLine
    @EnvironmentObject private var theme: ThemeEngine

    var body: some View {
        HStack(spacing: 0) {
            // Gutter indicator
            Text(gutterChar)
                .font(Typography.codeBlock)
                .foregroundColor(gutterColor)
                .frame(width: 20, alignment: .center)

            // Line content
            Text(line.text)
                .font(Typography.codeBlock)
                .foregroundColor(textColor)
                .textSelection(.enabled)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .background(backgroundColor)
    }

    private var gutterChar: String {
        switch line.type {
        case .added: return "+"
        case .removed: return "-"
        case .context: return " "
        }
    }

    private var gutterColor: Color {
        switch line.type {
        case .added: return theme.sage
        case .removed: return theme.rose
        case .context: return theme.muted
        }
    }

    private var textColor: Color {
        switch line.type {
        case .added: return theme.sage
        case .removed: return theme.rose
        case .context: return theme.primary
        }
    }

    private var backgroundColor: Color {
        switch line.type {
        case .added: return theme.sage.opacity(0.08)
        case .removed: return theme.rose.opacity(0.08)
        case .context: return .clear
        }
    }
}

// MARK: - Fullscreen Diff Overlay

struct FullscreenDiffOverlay: View {
    let block: DiffBlock
    @Binding var isPresented: Bool
    @EnvironmentObject private var theme: ThemeEngine
    @State private var sideBySide = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                if let filename = block.filename {
                    Image(systemName: "doc.text")
                        .font(.system(size: 12))
                        .foregroundColor(theme.muted)
                    Text(filename)
                        .font(Typography.bodyBold)
                        .foregroundColor(theme.bright)
                }

                Spacer()

                // View mode toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        sideBySide.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: sideBySide ? "text.alignleft" : "rectangle.split.2x1")
                            .font(.system(size: 11))
                        Text(sideBySide ? "Unified" : "Side by Side")
                            .font(Typography.caption)
                    }
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
            .padding(16)

            Divider().opacity(0.3)

            // Diff content (scrollable, full width)
            ScrollView {
                if sideBySide {
                    SideBySideDiffView(hunks: block.hunks)
                } else {
                    ForEach(Array(block.hunks.enumerated()), id: \.offset) { _, hunk in
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
                                DiffLineView(line: line)
                            }
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
        .padding(40)
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
    }
}
