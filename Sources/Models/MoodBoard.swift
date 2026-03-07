import Foundation
import AppKit

/// A collection of design inspiration that informs autonomous design decisions
struct MoodBoard: Identifiable, Codable {
    let id: String
    var name: String
    var items: [MoodBoardItem]
    var extractedPalette: ExtractedPalette?
    var extractedPatterns: [DesignPattern]
    var designBrief: String?             // User's optional text description of the vibe
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        name: String = "Untitled Board",
        items: [MoodBoardItem] = [],
        designBrief: String? = nil
    ) {
        self.id = id
        self.name = name
        self.items = items
        self.extractedPalette = nil
        self.extractedPatterns = []
        self.designBrief = designBrief
        self.createdAt = Date()
    }

    /// Whether this board has enough signal to influence design
    var hasSignal: Bool {
        !items.isEmpty || designBrief != nil
    }

    /// Generate a design prompt from this moodboard for agents
    func toDesignPrompt() -> String {
        var lines: [String] = []
        lines.append("## Design Moodboard Context")
        lines.append("")

        if let brief = designBrief {
            lines.append("**Design brief:** \(brief)")
            lines.append("")
        }

        if let palette = extractedPalette {
            lines.append("**Extracted color palette:**")
            for color in palette.dominantColors {
                lines.append("- \(color.hex) (\(color.name ?? "unnamed"))")
            }
            lines.append("- Overall warmth: \(palette.warmth)")
            lines.append("- Overall contrast: \(palette.contrast)")
            lines.append("")
        }

        if !extractedPatterns.isEmpty {
            lines.append("**Design patterns observed:**")
            for pattern in extractedPatterns {
                lines.append("- \(pattern.category.rawValue): \(pattern.description)")
            }
            lines.append("")
        }

        // Vision-detected themes across all items
        let allVisionTags = items.flatMap(\.visionTags)
            .sorted { $0.confidence > $1.confidence }
        let uniqueTags = Array(Set(allVisionTags.map(\.label)).prefix(10))
        if !uniqueTags.isEmpty {
            lines.append("**Visual themes detected (AI Vision):** \(uniqueTags.joined(separator: ", "))")
            lines.append("")
        }

        if !items.isEmpty {
            lines.append("**\(items.count) reference images provided** — the user wants a design that captures the essence of these references while being original and world-class.")
        }

        return lines.joined(separator: "\n")
    }
}

struct MoodBoardItem: Identifiable, Codable {
    let id: String
    var imagePath: String              // Local file path to the screenshot/image
    var sourceURL: String?             // Optional URL where this came from
    var notes: String?                 // User's notes about what they like about this
    var extractedColors: [ExtractedColor]
    var tags: [String]                 // e.g., ["minimal", "dark", "glass", "bold typography"]
    var visionTags: [VisionTag]        // Auto-detected by Apple Vision framework
    var colorFingerprint: [CIELABColor]  // Top 5 CIELAB colors for similarity matching
    let addedAt: Date

    init(
        id: String = UUID().uuidString,
        imagePath: String,
        sourceURL: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.imagePath = imagePath
        self.sourceURL = sourceURL
        self.notes = notes
        self.extractedColors = []
        self.tags = []
        self.visionTags = []
        self.colorFingerprint = []
        self.addedAt = Date()
    }

    /// Color similarity to another item (0 = identical, higher = more different)
    func colorDistance(to other: MoodBoardItem) -> Double {
        guard !colorFingerprint.isEmpty, !other.colorFingerprint.isEmpty else { return .infinity }
        // Average distance across matched color vectors (like Cosmos's 5-vector approach)
        let count = min(colorFingerprint.count, other.colorFingerprint.count)
        var totalDist = 0.0
        for i in 0..<count {
            totalDist += colorFingerprint[i].distance(to: other.colorFingerprint[i])
        }
        return totalDist / Double(count)
    }
}

/// A tag auto-detected by Apple's Vision framework
struct VisionTag: Codable, Identifiable {
    var id: String { label }
    let label: String            // e.g., "architecture", "nature", "text", "dark mode"
    let confidence: Double       // 0-1
}

struct ExtractedColor: Codable, Identifiable {
    var id: String { hex }
    let hex: String
    let name: String?
    let percentage: Double             // How dominant this color is (0-1)
    var lab: CIELABColor?             // Perceptual color for similarity matching (Cosmos-inspired)
}

/// CIELAB color representation — perceptually uniform color space
/// Distances between CIELAB colors match human perception of color difference
/// Inspired by Cosmos.so's use of CIELAB for color search (via Qdrant case study)
struct CIELABColor: Codable, Equatable {
    let l: Double  // Lightness (0-100)
    let a: Double  // Green(-) to Red(+)
    let b: Double  // Blue(-) to Yellow(+)

    /// Euclidean distance — perceptual color difference
    func distance(to other: CIELABColor) -> Double {
        let dl = l - other.l
        let da = a - other.a
        let db = b - other.b
        return sqrt(dl * dl + da * da + db * db)
    }

    /// Convert from sRGB (0-255) to CIELAB via XYZ
    static func fromRGB(r: Int, g: Int, b: Int) -> CIELABColor {
        // sRGB → linear RGB
        func linearize(_ v: Double) -> Double {
            let s = v / 255.0
            return s > 0.04045 ? pow((s + 0.055) / 1.055, 2.4) : s / 12.92
        }
        let lr = linearize(Double(r))
        let lg = linearize(Double(g))
        let lb = linearize(Double(b))

        // Linear RGB → XYZ (D65 illuminant)
        let x = (lr * 0.4124564 + lg * 0.3575761 + lb * 0.1804375) / 0.95047
        let y = (lr * 0.2126729 + lg * 0.7151522 + lb * 0.0721750) / 1.00000
        let z = (lr * 0.0193339 + lg * 0.1191920 + lb * 0.9503041) / 1.08883

        // XYZ → CIELAB
        func f(_ t: Double) -> Double {
            t > 0.008856 ? pow(t, 1.0 / 3.0) : (7.787 * t) + (16.0 / 116.0)
        }
        let lStar = 116.0 * f(y) - 16.0
        let aStar = 500.0 * (f(x) - f(y))
        let bStar = 200.0 * (f(y) - f(z))

        return CIELABColor(l: lStar, a: aStar, b: bStar)
    }
}

struct ExtractedPalette: Codable {
    var dominantColors: [ExtractedColor]
    var warmth: String                 // "cool", "neutral", "warm"
    var contrast: String               // "low", "medium", "high"
    var mood: String                   // "minimal", "bold", "playful", "premium", "organic"
}

struct DesignPattern: Identifiable, Codable {
    let id: String
    let category: DesignPatternCategory
    let description: String
    let confidence: Double             // 0-1 how confident we are in this observation

    init(id: String = UUID().uuidString, category: DesignPatternCategory, description: String, confidence: Double = 0.8) {
        self.id = id
        self.category = category
        self.description = description
        self.confidence = confidence
    }
}

enum DesignPatternCategory: String, Codable, CaseIterable {
    case layout          // Grid, asymmetric, centered, full-bleed
    case typography      // Serif, sans-serif, mono, mixed, scale ratio
    case spacing         // Tight, generous, asymmetric padding
    case color           // Monochrome, complementary, analogous, gradient
    case motion          // Subtle, bold, parallax, none
    case surface         // Flat, glass, neomorphic, material
    case density         // Sparse, balanced, dense
    case hierarchy       // Clear, flat, nested
}
