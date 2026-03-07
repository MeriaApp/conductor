import Foundation
import AppKit
import Vision

/// Manages moodboards, analyzes dropped images, and provides design intelligence
/// Works with or without user input — smart enough to design autonomously
@MainActor
final class MoodBoardEngine: ObservableObject {
    @Published var activeBoard: MoodBoard?
    @Published var boards: [MoodBoard] = []
    @Published var isAnalyzing = false
    @Published var hasPromptedUser = false

    private let storageDir: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        storageDir = appSupport.appendingPathComponent("Conductor/moodboards", isDirectory: true)
        try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
        loadBoards()
    }

    // MARK: - Non-Blocking Prompt

    /// Called once at the start of a design task. Non-blocking — work continues regardless.
    /// Returns a gentle prompt string to show the user, but does NOT wait for a response.
    func promptForInspirationIfNeeded(taskDescription: String) -> String? {
        // Only prompt once per session, and only for design-related tasks
        guard !hasPromptedUser, isDesignTask(taskDescription) else { return nil }
        hasPromptedUser = true

        return """
        Drop any screenshots or images for design inspiration if you have them. \
        Drag files onto the app window or paste from clipboard. \
        This is optional — the design will be world-class either way.
        """
    }

    /// Check if a task description involves design work
    private func isDesignTask(_ description: String) -> Bool {
        let designKeywords = [
            "design", "ui", "ux", "layout", "style", "theme", "color",
            "visual", "interface", "component", "page", "screen", "view",
            "beautiful", "aesthetic", "brand", "logo", "icon", "typography",
            "responsive", "mobile", "desktop", "app", "website", "landing"
        ]
        let lowered = description.lowercased()
        return designKeywords.contains { lowered.contains($0) }
    }

    // MARK: - Image Drop / Paste

    /// Process dropped image files
    func addImages(urls: [URL]) {
        if activeBoard == nil {
            activeBoard = MoodBoard(name: "Current Project")
        }

        for url in urls {
            guard isImageFile(url) else { continue }

            // Copy to our storage
            let dest = storageDir.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.copyItem(at: url, to: dest)

            var item = MoodBoardItem(imagePath: dest.path)
            activeBoard?.items.append(item)

            // Analyze asynchronously
            Task {
                await analyzeImage(itemId: item.id, path: dest.path)
            }
        }

        saveBoards()
    }

    /// Process pasted image from clipboard
    func addFromClipboard() {
        let pasteboard = NSPasteboard.general

        // Check for image data
        if let image = NSImage(pasteboard: pasteboard),
           let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {

            let filename = "clipboard_\(UUID().uuidString.prefix(8)).png"
            let dest = storageDir.appendingPathComponent(filename)
            try? pngData.write(to: dest)

            if activeBoard == nil {
                activeBoard = MoodBoard(name: "Current Project")
            }

            let item = MoodBoardItem(imagePath: dest.path)
            activeBoard?.items.append(item)

            Task {
                await analyzeImage(itemId: item.id, path: dest.path)
            }

            saveBoards()
        }

        // Check for file URLs
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] {
            addImages(urls: urls.filter { isImageFile($0) })
        }
    }

    // MARK: - Image Analysis (Cosmos-Inspired Multi-Signal Pipeline)

    /// Extract colors, Vision tags, CIELAB fingerprint, and design signals from an image.
    /// Inspired by Cosmos.so's parallel analysis pipeline (CLIP + CNN + pHash + color vectors).
    /// We use Apple's on-device Vision framework instead of CLIP/CNN for privacy and speed.
    private func analyzeImage(itemId: String, path: String) async {
        isAnalyzing = true
        defer { isAnalyzing = false }

        guard let image = NSImage(contentsOfFile: path),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }

        // Run analysis in parallel (like Cosmos parallelizes CNN + CLIP + pHash)
        async let colors = extractDominantColors(from: cgImage)
        async let visionTags = classifyWithVision(cgImage: cgImage)
        async let fingerprint = extractCIELABFingerprint(from: cgImage)

        let extractedColors = await colors
        let tags = await visionTags
        let labFingerprint = await fingerprint

        // Update the item with all analysis results
        if let boardIdx = boards.firstIndex(where: { $0.id == activeBoard?.id }),
           let itemIdx = boards[boardIdx].items.firstIndex(where: { $0.id == itemId }) {
            boards[boardIdx].items[itemIdx].extractedColors = extractedColors
            boards[boardIdx].items[itemIdx].visionTags = tags
            boards[boardIdx].items[itemIdx].colorFingerprint = labFingerprint
        }
        if let itemIdx = activeBoard?.items.firstIndex(where: { $0.id == itemId }) {
            activeBoard?.items[itemIdx].extractedColors = extractedColors
            activeBoard?.items[itemIdx].visionTags = tags
            activeBoard?.items[itemIdx].colorFingerprint = labFingerprint
        }

        // Rebuild the board's palette from all items
        rebuildPalette()
        saveBoards()
    }

    // MARK: - Vision Framework (Auto-Tagging)

    /// Use Apple's Vision framework for scene classification — on-device, no network needed.
    /// This replaces what Cosmos does with CLIP embeddings for semantic understanding.
    private nonisolated func classifyWithVision(cgImage: CGImage) async -> [VisionTag] {
        await withCheckedContinuation { continuation in
            let request = VNClassifyImageRequest { request, error in
                guard error == nil,
                      let results = request.results as? [VNClassificationObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                // Take high-confidence classifications (>20%)
                let tags = results
                    .filter { $0.confidence > 0.2 }
                    .prefix(8)
                    .map { VisionTag(label: $0.identifier, confidence: Double($0.confidence)) }

                continuation.resume(returning: tags)
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }

    // MARK: - CIELAB Color Fingerprint (Cosmos-Inspired)

    /// Extract top 5 dominant colors as CIELAB vectors — perceptually uniform color space.
    /// Cosmos stores 5 CIELAB vectors per element (primary through quinary) for color search.
    /// We do the same for local similarity matching.
    private nonisolated func extractCIELABFingerprint(from cgImage: CGImage) async -> [CIELABColor] {
        let width = min(cgImage.width, 80)
        let height = min(cgImage.height, 80)

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [] }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else { return [] }
        let pointer = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let totalPixels = width * height

        // Collect CIELAB values with bucketing for deduplication
        var labBuckets: [String: (lab: CIELABColor, count: Int)] = [:]

        for i in 0..<totalPixels {
            let offset = i * 4
            let r = Int(pointer[offset])
            let g = Int(pointer[offset + 1])
            let b = Int(pointer[offset + 2])

            let lab = CIELABColor.fromRGB(r: r, g: g, b: b)

            // Bucket by rounding L/a/b to nearest 10
            let bucketKey = "\(Int(lab.l / 10) * 10)_\(Int(lab.a / 10) * 10)_\(Int(lab.b / 10) * 10)"
            if let existing = labBuckets[bucketKey] {
                labBuckets[bucketKey] = (existing.lab, existing.count + 1)
            } else {
                labBuckets[bucketKey] = (lab, 1)
            }
        }

        // Return top 5 by frequency (like Cosmos's primary through quinary)
        return labBuckets.values
            .sorted { $0.count > $1.count }
            .prefix(5)
            .map(\.lab)
    }

    // MARK: - Find Similar (Cosmos-Inspired Discovery)

    /// Find items visually similar to a given item using CIELAB color distance.
    /// Cosmos uses vector similarity across CLIP + CNN + color; we use color fingerprint + tag overlap.
    func findSimilar(to item: MoodBoardItem, limit: Int = 5) -> [MoodBoardItem] {
        guard let board = activeBoard else { return [] }

        return board.items
            .filter { $0.id != item.id }
            .map { other in
                let colorDist = item.colorDistance(to: other)
                let tagOverlap = Set(item.visionTags.map(\.label))
                    .intersection(Set(other.visionTags.map(\.label))).count
                // Lower score = more similar (color distance minus tag bonus)
                let score = colorDist - Double(tagOverlap) * 5.0
                return (item: other, score: score)
            }
            .sorted { $0.score < $1.score }
            .prefix(limit)
            .map(\.item)
    }

    /// Extract dominant colors from a CGImage using pixel sampling
    private func extractDominantColors(from cgImage: CGImage) -> [ExtractedColor] {
        let width = min(cgImage.width, 100)  // Downsample for speed
        let height = min(cgImage.height, 100)

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [] }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else { return [] }
        let pointer = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

        // Simple color bucketing
        var colorCounts: [String: Int] = [:]
        let totalPixels = width * height

        for i in 0..<totalPixels {
            let offset = i * 4
            let r = Int(pointer[offset])
            let g = Int(pointer[offset + 1])
            let b = Int(pointer[offset + 2])

            // Bucket to reduce noise (round to nearest 16)
            let br = (r / 16) * 16
            let bg = (g / 16) * 16
            let bb = (b / 16) * 16

            let hex = String(format: "#%02X%02X%02X", br, bg, bb)
            colorCounts[hex, default: 0] += 1
        }

        // Sort by frequency, take top 6
        return colorCounts
            .sorted { $0.value > $1.value }
            .prefix(6)
            .map { hex, count in
                // Parse hex back to RGB for CIELAB conversion
                let scanner = Scanner(string: hex.replacingOccurrences(of: "#", with: ""))
                var rgb: UInt64 = 0
                scanner.scanHexInt64(&rgb)
                let r = Int((rgb >> 16) & 0xFF)
                let g = Int((rgb >> 8) & 0xFF)
                let b = Int(rgb & 0xFF)

                return ExtractedColor(
                    hex: hex,
                    name: describeColor(hex: hex),
                    percentage: Double(count) / Double(totalPixels),
                    lab: CIELABColor.fromRGB(r: r, g: g, b: b)
                )
            }
    }

    /// Give a human-readable name to a hex color
    private func describeColor(hex: String) -> String? {
        // Parse hex
        let scanner = Scanner(string: hex.replacingOccurrences(of: "#", with: ""))
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        let r = Int((rgb >> 16) & 0xFF)
        let g = Int((rgb >> 8) & 0xFF)
        let b = Int(rgb & 0xFF)

        let brightness = (r + g + b) / 3

        if brightness < 30 { return "near black" }
        if brightness > 225 { return "near white" }

        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let saturation = maxC > 0 ? Double(maxC - minC) / Double(maxC) : 0

        if saturation < 0.15 {
            if brightness < 85 { return "dark gray" }
            if brightness < 170 { return "gray" }
            return "light gray"
        }

        // Determine hue family
        if r > g && r > b {
            return g > b ? "warm orange" : "red"
        } else if g > r && g > b {
            return r > b ? "yellow-green" : "green"
        } else {
            return r > g ? "purple" : "blue"
        }
    }

    /// Rebuild the board-level palette from all item colors
    private func rebuildPalette() {
        guard let board = activeBoard, !board.items.isEmpty else { return }

        var allColors: [ExtractedColor] = []
        for item in board.items {
            allColors.append(contentsOf: item.extractedColors)
        }

        // Merge and deduplicate by proximity
        let dominant = Array(allColors.sorted { $0.percentage > $1.percentage }.prefix(8))

        // Analyze warmth
        let warmColors = dominant.filter { isWarmColor($0.hex) }.count
        let warmth = warmColors > dominant.count / 2 ? "warm" : warmColors == 0 ? "cool" : "neutral"

        // Analyze contrast
        let brightest = dominant.map { brightness(of: $0.hex) }.max() ?? 0
        let darkest = dominant.map { brightness(of: $0.hex) }.min() ?? 0
        let contrastStr = (brightest - darkest) > 150 ? "high" : (brightest - darkest) > 80 ? "medium" : "low"

        activeBoard?.extractedPalette = ExtractedPalette(
            dominantColors: dominant,
            warmth: warmth,
            contrast: contrastStr,
            mood: inferMood(warmth: warmth, contrast: contrastStr, colorCount: dominant.count)
        )
    }

    private func isWarmColor(_ hex: String) -> Bool {
        let scanner = Scanner(string: hex.replacingOccurrences(of: "#", with: ""))
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        let r = Int((rgb >> 16) & 0xFF)
        let b = Int(rgb & 0xFF)
        return r > b
    }

    private func brightness(of hex: String) -> Int {
        let scanner = Scanner(string: hex.replacingOccurrences(of: "#", with: ""))
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        let r = Int((rgb >> 16) & 0xFF)
        let g = Int((rgb >> 8) & 0xFF)
        let b = Int(rgb & 0xFF)
        return (r + g + b) / 3
    }

    private func inferMood(warmth: String, contrast: String, colorCount: Int) -> String {
        if contrast == "high" && colorCount <= 3 { return "bold" }
        if warmth == "cool" && contrast == "low" { return "minimal" }
        if warmth == "warm" && contrast == "medium" { return "premium" }
        if colorCount > 5 { return "playful" }
        return "balanced"
    }

    // MARK: - Autonomous Design Intelligence

    /// When no moodboard exists, generate world-class design parameters from first principles.
    /// This is what makes the app smart enough to design without user input.
    func generateAutonomousDesignBrief(
        projectType: String,
        targetAudience: String? = nil,
        existingBrandColors: [String]? = nil
    ) -> String {
        // Start with best-in-class defaults
        var brief = """
        ## Autonomous Design Brief
        *Generated by Conductor's Design Intelligence — no moodboard provided*

        ### Design Philosophy
        Build at the level of the best in the world. Reference these standards:
        - **Apple HIG** — clarity, deference, depth
        - **Linear** — information density without clutter
        - **Stripe** — precision, polish, whitespace mastery
        - **Vercel** — developer-focused elegance
        - **Arc Browser** — bold innovation with calm execution

        ### Core Principles
        1. **Remove until it breaks.** Every element must earn its pixel.
        2. **Calm confidence.** The UI should feel like it knows what it's doing.
        3. **Information density without noise.** Show everything needed, nothing extra.
        4. **Motion with purpose.** Every animation communicates state, not decoration.
        5. **Typography as architecture.** Type scale creates hierarchy, not color.

        ### Technical Defaults
        - **Spacing:** 4px base grid, generous padding (16-24px)
        - **Border radius:** 8-12px (consistent, not mixed)
        - **Shadows:** Subtle, layered (0 1px 2px for lifts, 0 8px 24px for modals)
        - **Font:** System default or Inter/SF Pro — never decorative
        - **Colors:** Neutral base + one accent. Max 3 accent colors total.
        - **Contrast:** WCAG AA minimum. AAA for primary text.

        """

        // Adjust for project type
        switch projectType.lowercased() {
        case let t where t.contains("mobile") || t.contains("ios") || t.contains("app"):
            brief += """
            ### Platform-Specific: Mobile/iOS
            - Touch targets: minimum 44pt
            - Safe areas respected
            - Bottom navigation preferred over hamburger menus
            - Haptic feedback for confirmations
            - Swipe gestures for common actions
            """

        case let t where t.contains("web") || t.contains("site") || t.contains("landing"):
            brief += """
            ### Platform-Specific: Web
            - Mobile-first responsive design
            - Above-the-fold clarity (hero must communicate value in 3 seconds)
            - Performance: no layout shift, fast paint
            - Dark/light mode support
            - Keyboard navigable, screen-reader friendly
            """

        case let t where t.contains("dashboard") || t.contains("admin") || t.contains("saas"):
            brief += """
            ### Platform-Specific: Dashboard/SaaS
            - Sidebar navigation (collapsible)
            - Data density: tables, charts, metrics visible at a glance
            - Filters and search always accessible
            - Batch actions for power users
            - Empty states that guide, not just inform
            """

        default:
            brief += """
            ### General
            - Adapt to the platform and context
            - When in doubt, choose clarity over cleverness
            """
        }

        if let audience = targetAudience {
            brief += "\n\n### Target Audience\n\(audience)\n"
        }

        if let colors = existingBrandColors, !colors.isEmpty {
            brief += "\n\n### Existing Brand Colors\n"
            for color in colors {
                brief += "- \(color)\n"
            }
            brief += "\nIncorporate these. Don't fight the existing brand.\n"
        }

        return brief
    }

    /// Get the design context for agents — moodboard if available, autonomous brief if not
    func getDesignContext(
        projectType: String = "general",
        targetAudience: String? = nil,
        existingBrandColors: [String]? = nil
    ) -> String {
        if let board = activeBoard, board.hasSignal {
            return board.toDesignPrompt()
        }

        // No moodboard — generate world-class defaults autonomously
        return generateAutonomousDesignBrief(
            projectType: projectType,
            targetAudience: targetAudience,
            existingBrandColors: existingBrandColors
        )
    }

    // MARK: - Helpers

    private func isImageFile(_ url: URL) -> Bool {
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp", "svg"]
        return imageExtensions.contains(url.pathExtension.lowercased())
    }

    // MARK: - Persistence

    private func loadBoards() {
        let file = storageDir.appendingPathComponent("boards.json")
        guard let data = try? Data(contentsOf: file),
              let decoded = try? JSONDecoder().decode([MoodBoard].self, from: data) else {
            return
        }
        boards = decoded
        activeBoard = boards.first
    }

    private func saveBoards() {
        if let board = activeBoard {
            if let idx = boards.firstIndex(where: { $0.id == board.id }) {
                boards[idx] = board
            } else {
                boards.insert(board, at: 0)
            }
        }

        let file = storageDir.appendingPathComponent("boards.json")
        if let data = try? JSONEncoder().encode(boards) {
            try? data.write(to: file)
        }
    }
}
