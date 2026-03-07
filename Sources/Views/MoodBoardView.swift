import SwiftUI

/// Drop zone + moodboard gallery — drag screenshots here for design inspiration
/// Shows extracted colors, patterns, and the autonomous design brief
struct MoodBoardView: View {
    @EnvironmentObject private var engine: MoodBoardEngine
    @EnvironmentObject private var theme: ThemeEngine
    @State private var isDragOver = false
    @State private var showDesignBrief = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Design Moodboard")
                    .font(Typography.heading2)
                    .foregroundColor(theme.bright)

                Spacer()

                if engine.isAnalyzing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Analyzing...")
                            .font(Typography.caption)
                            .foregroundColor(theme.lavender)
                    }
                }

                // Paste button
                Button {
                    engine.addFromClipboard()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 11))
                        Text("Paste")
                            .font(Typography.caption)
                    }
                    .foregroundColor(theme.secondary)
                }
                .buttonStyle(.plain)

                // Show design brief
                Button {
                    showDesignBrief.toggle()
                } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundColor(theme.sky)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().opacity(0.3)

            if let board = engine.activeBoard, !board.items.isEmpty {
                // Moodboard gallery
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // Extracted palette
                        if let palette = board.extractedPalette {
                            paletteView(palette)
                        }

                        // Vision-detected themes (Cosmos-inspired auto-tagging)
                        let allTags = board.items.flatMap(\.visionTags)
                            .sorted { $0.confidence > $1.confidence }
                        let uniqueTags = Array(Set(allTags.map(\.label)).prefix(8))
                        if !uniqueTags.isEmpty {
                            visionTagsView(uniqueTags)
                        }

                        // Image grid
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 120, maximum: 180))
                        ], spacing: 8) {
                            ForEach(board.items) { item in
                                MoodBoardItemView(item: item)
                            }

                            // Drop target for more
                            addMoreDropTarget
                        }
                    }
                    .padding(12)
                }
            } else {
                // Empty state / drop zone
                dropZone
            }

            // Design brief panel
            if showDesignBrief {
                Divider().opacity(0.3)
                designBriefPanel
            }
        }
        .background(theme.surface)
        .onDrop(of: [.fileURL, .image], isTargeted: $isDragOver) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    // MARK: - Drop Zone

    private var dropZone: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 40))
                .foregroundColor(isDragOver ? theme.sky : theme.muted)

            Text("Drop screenshots for design inspiration")
                .font(Typography.body)
                .foregroundColor(theme.secondary)

            Text("Optional — the design will be great either way")
                .font(Typography.caption)
                .foregroundColor(theme.muted)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isDragOver ? theme.sky.opacity(0.05) : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isDragOver ? theme.sky : theme.separator.opacity(0.3),
                    style: StrokeStyle(lineWidth: isDragOver ? 2 : 1, dash: [8])
                )
                .padding(8)
        )
    }

    private var addMoreDropTarget: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 20))
                .foregroundColor(theme.muted)
            Text("Drop more")
                .font(Typography.caption)
                .foregroundColor(theme.muted)
        }
        .frame(height: 100)
        .frame(maxWidth: .infinity)
        .background(theme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.separator.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [6]))
        )
    }

    // MARK: - Palette View

    private func paletteView(_ palette: ExtractedPalette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Extracted Palette")
                .font(Typography.toolLabel)
                .foregroundColor(theme.secondary)

            HStack(spacing: 4) {
                ForEach(palette.dominantColors) { color in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(hex: color.hex))
                        .frame(height: 32)
                        .overlay(
                            Text(color.hex)
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.white.opacity(0.7))
                                .shadow(radius: 1)
                        )
                }
            }

            HStack(spacing: 16) {
                Label(palette.warmth, systemImage: "thermometer.medium")
                Label(palette.contrast + " contrast", systemImage: "circle.lefthalf.filled")
                Label(palette.mood, systemImage: "sparkles")
            }
            .font(Typography.caption)
            .foregroundColor(theme.muted)
        }
    }

    // MARK: - Vision Tags (Cosmos-Inspired Auto-Tagging)

    private func visionTagsView(_ tags: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Detected Themes")
                .font(Typography.toolLabel)
                .foregroundColor(theme.secondary)

            FlowLayout(spacing: 4) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 10, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(theme.lavender.opacity(0.15))
                        .foregroundColor(theme.lavender)
                        .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - Design Brief Panel

    private var designBriefPanel: some View {
        ScrollView {
            Text(engine.getDesignContext())
                .font(Typography.codeBlock)
                .foregroundColor(theme.secondary)
                .textSelection(.enabled)
                .padding(16)
        }
        .frame(maxHeight: 200)
        .background(theme.codeBackground)
    }

    // MARK: - Drop Handling

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, _ in
                    guard let urlData = data as? Data,
                          let url = URL(dataRepresentation: urlData, relativeTo: nil) else { return }
                    Task { @MainActor in
                        engine.addImages(urls: [url])
                    }
                }
            }
        }
    }
}

// MARK: - Moodboard Item

struct MoodBoardItemView: View {
    let item: MoodBoardItem
    @EnvironmentObject private var theme: ThemeEngine
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 0) {
            // Thumbnail
            ZStack(alignment: .bottomLeading) {
                if let image = NSImage(contentsOfFile: item.imagePath) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 100)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(theme.elevated)
                        .frame(height: 100)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(theme.muted)
                        )
                }

                // Vision tags overlay on hover
                if isHovering, !item.visionTags.isEmpty {
                    HStack(spacing: 2) {
                        ForEach(item.visionTags.prefix(3)) { tag in
                            Text(tag.label)
                                .font(.system(size: 8, design: .rounded))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(4)
                    .transition(.opacity)
                }
            }

            // Extracted color strip
            if !item.extractedColors.isEmpty {
                HStack(spacing: 0) {
                    ForEach(item.extractedColors.prefix(5)) { color in
                        Color(hex: color.hex)
                            .frame(height: 4)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.separator.opacity(0.3), lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Flow Layout (for wrapping tags)

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        return CGSize(width: maxWidth, height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: .unspecified)
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex.replacingOccurrences(of: "#", with: ""))
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >> 8) & 0xFF) / 255.0,
            blue: Double(rgb & 0xFF) / 255.0
        )
    }
}
