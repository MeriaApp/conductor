import Foundation

/// Cross-project shared intelligence registry
/// When one project discovers a useful API/tool/automation, it writes an entry.
/// When any project needs to automate something, it checks the registry first.
/// Stored at ~/.claude/shared-intelligence/registry.json
@MainActor
final class SharedIntelligence: ObservableObject {
    static let shared = SharedIntelligence()

    @Published var entries: [IntelligenceEntry] = []
    @Published var lastScanDate: Date?

    private let registryDir: URL
    private let registryFile: URL

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        registryDir = home.appendingPathComponent(".claude/shared-intelligence", isDirectory: true)
        registryFile = registryDir.appendingPathComponent("registry.json")
        try? FileManager.default.createDirectory(at: registryDir, withIntermediateDirectories: true)
        loadRegistry()
    }

    // MARK: - Registry Access

    /// Look up entries matching a query (searches name, description, tags)
    func lookup(_ query: String) -> [IntelligenceEntry] {
        let q = query.lowercased()
        return entries.filter { entry in
            entry.name.lowercased().contains(q) ||
            entry.description.lowercased().contains(q) ||
            entry.tags.contains(where: { $0.lowercased().contains(q) }) ||
            entry.category.rawValue.lowercased().contains(q)
        }.sorted { $0.confidence > $1.confidence }
    }

    /// Find the best entry for a specific need
    func findBest(for need: String, category: IntelligenceCategory? = nil) -> IntelligenceEntry? {
        var results = lookup(need)
        if let cat = category {
            results = results.filter { $0.category == cat }
        }
        return results.first { $0.isValid }
    }

    // MARK: - Registry Write

    /// Add or update an entry in the registry
    func register(_ entry: IntelligenceEntry) {
        // Check for existing entry with same name
        if let idx = entries.firstIndex(where: { $0.name.lowercased() == entry.name.lowercased() }) {
            // Update if newer or higher confidence
            if entry.confidence >= entries[idx].confidence {
                entries[idx] = entry
            }
        } else {
            entries.append(entry)
        }
        saveRegistry()
    }

    /// Remove stale entries
    func prune() {
        entries.removeAll { !$0.isValid }
        saveRegistry()
    }

    /// Mark an entry as verified (bump confidence, update timestamp)
    func verify(id: String) {
        if let idx = entries.firstIndex(where: { $0.id == id }) {
            entries[idx].confidence = min(entries[idx].confidence + 0.1, 1.0)
            entries[idx].lastVerified = Date()
            saveRegistry()
        }
    }

    /// Mark an entry as stale or invalid
    func invalidate(id: String, reason: String) {
        if let idx = entries.firstIndex(where: { $0.id == id }) {
            entries[idx].confidence = 0
            entries[idx].notes = "INVALIDATED: \(reason)"
            saveRegistry()
        }
    }

    // MARK: - Bulk Operations

    /// Seed the registry with common useful entries
    func seedDefaults() {
        let defaults: [IntelligenceEntry] = [
            IntelligenceEntry(
                name: "IndexNow API",
                description: "Instantly notify Bing, Yandex, Seznam about new/updated URLs. Much faster than waiting for crawl.",
                category: .api,
                tags: ["seo", "indexing", "search-engine", "bing"],
                howToUse: "POST https://api.indexnow.org/indexnow with key + URL list. Free, no rate limit.",
                discoveredIn: "meriachai.com",
                confidence: 0.9,
                alternatives: ["Google Search Console manual submission"]
            ),
            IntelligenceEntry(
                name: "Pexels API",
                description: "Free stock photos API. No attribution required for most uses. Better quality than Unsplash for blog images.",
                category: .api,
                tags: ["images", "stock-photos", "blog", "content"],
                howToUse: "GET https://api.pexels.com/v1/search?query=X with Authorization header. Returns URLs.",
                discoveredIn: "staycomposed.app",
                confidence: 0.85
            ),
            IntelligenceEntry(
                name: "pg_cron",
                description: "PostgreSQL extension for scheduled jobs. Runs SQL on a schedule inside the database. No external cron needed.",
                category: .tool,
                tags: ["supabase", "postgres", "cron", "scheduling", "automation"],
                howToUse: "Enable in Supabase dashboard or migration. SELECT cron.schedule('name', '*/15 * * * *', 'SELECT fn()').",
                discoveredIn: "staycomposed.app",
                confidence: 0.95
            ),
            IntelligenceEntry(
                name: "Resend Email API",
                description: "Modern email sending API. Simple, reliable, good deliverability. Better DX than SendGrid/Mailgun.",
                category: .api,
                tags: ["email", "transactional", "marketing", "resend"],
                howToUse: "POST https://api.resend.com/emails with from/to/subject/html. API key in Authorization header.",
                discoveredIn: "staycomposed.app",
                confidence: 0.9
            ),
            IntelligenceEntry(
                name: "satori (OG Image Generation)",
                description: "Generate Open Graph images from JSX at build time. Used by Vercel. No browser/puppeteer needed.",
                category: .tool,
                tags: ["og-images", "seo", "social-media", "build-time"],
                howToUse: "npm install satori. Pass JSX + fonts → returns SVG. Convert to PNG with @resvg/resvg-js.",
                discoveredIn: "staycomposed.app",
                confidence: 0.85
            ),
            IntelligenceEntry(
                name: "Claude CLI stream-json mode",
                description: "Claude CLI outputs NDJSON events when run with --output-format stream-json. Events: system, assistant, user, result.",
                category: .tool,
                tags: ["claude", "cli", "streaming", "json", "subprocess"],
                howToUse: "claude -p 'prompt' --output-format stream-json --verbose --include-partial-messages",
                discoveredIn: "Conductor",
                confidence: 1.0
            ),
            IntelligenceEntry(
                name: "Claude CLI --resume flag",
                description: "Resume a previous Claude CLI session by ID. Maintains full conversation history.",
                category: .tool,
                tags: ["claude", "cli", "session", "continuity"],
                howToUse: "claude -p 'msg' --resume SESSION_ID. Session ID comes from system event's session_id field.",
                discoveredIn: "Conductor",
                confidence: 1.0
            ),
            IntelligenceEntry(
                name: "AppleScript inter-process communication",
                description: "Send messages between running macOS apps using osascript. Proven for Claude instance communication.",
                category: .automation,
                tags: ["macos", "ipc", "applescript", "inter-process"],
                howToUse: "osascript -e 'tell application \"AppName\" to do something'. Can target windows by name.",
                discoveredIn: "Conductor",
                confidence: 0.8
            ),
        ]

        for entry in defaults {
            if !entries.contains(where: { $0.name == entry.name }) {
                entries.append(entry)
            }
        }
        saveRegistry()
    }

    /// Export registry as markdown for injection into Claude context
    func exportAsMarkdown() -> String {
        var md = "# Shared Intelligence Registry\n\n"
        md += "*\(entries.count) entries, last updated \(ISO8601DateFormatter().string(from: Date()))*\n\n"

        let grouped = Dictionary(grouping: entries.filter { $0.isValid }, by: { $0.category })
        for category in IntelligenceCategory.allCases {
            guard let items = grouped[category], !items.isEmpty else { continue }
            md += "## \(category.displayName)\n\n"
            for item in items.sorted(by: { $0.confidence > $1.confidence }) {
                md += "### \(item.name)\n"
                md += "\(item.description)\n"
                md += "**How to use:** \(item.howToUse)\n"
                if !item.tags.isEmpty {
                    md += "**Tags:** \(item.tags.joined(separator: ", "))\n"
                }
                md += "**Confidence:** \(Int(item.confidence * 100))%"
                if let project = item.discoveredIn {
                    md += " | **Found in:** \(project)"
                }
                md += "\n\n"
            }
        }
        return md
    }

    // MARK: - Persistence

    private func loadRegistry() {
        guard FileManager.default.fileExists(atPath: registryFile.path),
              let data = try? Data(contentsOf: registryFile),
              let decoded = try? JSONDecoder().decode([IntelligenceEntry].self, from: data) else {
            // First launch — seed defaults
            seedDefaults()
            return
        }
        entries = decoded
    }

    private func saveRegistry() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: registryFile)
    }
}

// MARK: - Data Models

struct IntelligenceEntry: Identifiable, Codable {
    let id: String
    var name: String
    var description: String
    var category: IntelligenceCategory
    var tags: [String]
    var howToUse: String
    var discoveredIn: String?       // Which project discovered this
    var discoveredAt: Date
    var lastVerified: Date?
    var confidence: Double          // 0.0–1.0
    var notes: String?
    var alternatives: [String]

    /// Entry is valid if confidence > 0 and discovered within the last year
    var isValid: Bool {
        confidence > 0
    }

    init(
        name: String,
        description: String,
        category: IntelligenceCategory,
        tags: [String] = [],
        howToUse: String,
        discoveredIn: String? = nil,
        confidence: Double = 0.5,
        notes: String? = nil,
        alternatives: [String] = []
    ) {
        self.id = UUID().uuidString
        self.name = name
        self.description = description
        self.category = category
        self.tags = tags
        self.howToUse = howToUse
        self.discoveredIn = discoveredIn
        self.discoveredAt = Date()
        self.lastVerified = nil
        self.confidence = confidence
        self.notes = notes
        self.alternatives = alternatives
    }
}

enum IntelligenceCategory: String, Codable, CaseIterable {
    case api            // External APIs
    case tool           // CLI tools, libraries, frameworks
    case automation     // Automation techniques, scripts
    case pattern        // Code patterns, architectural decisions
    case config         // Configuration tricks, settings
    case service        // Services, platforms, SaaS

    var displayName: String {
        switch self {
        case .api: return "APIs"
        case .tool: return "Tools & Libraries"
        case .automation: return "Automation"
        case .pattern: return "Patterns"
        case .config: return "Configuration"
        case .service: return "Services"
        }
    }

    var icon: String {
        switch self {
        case .api: return "network"
        case .tool: return "wrench.and.screwdriver"
        case .automation: return "gearshape.2"
        case .pattern: return "square.grid.3x3"
        case .config: return "slider.horizontal.3"
        case .service: return "cloud"
        }
    }
}
