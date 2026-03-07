import SwiftUI

/// Global font scale — persisted, adjustable with Cmd+/Cmd-
/// All dynamic fonts multiply their base size by this value
class FontScale: ObservableObject {
    static let shared = FontScale()

    @Published var scale: Double

    private init() {
        self.scale = UserDefaults.standard.double(forKey: "fontScale")
        if self.scale < 0.1 { self.scale = 1.0 } // First launch or invalid
    }

    private func persist() {
        UserDefaults.standard.set(scale, forKey: "fontScale")
    }

    /// Increase font size (Cmd+)
    func increase() {
        scale = min(scale + 0.1, 2.0)
        persist()
    }

    /// Decrease font size (Cmd-)
    func decrease() {
        scale = max(scale - 0.1, 0.6)
        persist()
    }

    /// Reset to default (Cmd+0)
    func reset() {
        scale = 1.0
        persist()
    }
}

/// Typography definitions — clean system font for conversation, monospace for code only
/// Use `scaled()` variants for content that should respect Cmd+/- font scaling
enum Typography {

    private static var s: Double { FontScale.shared.scale }

    // MARK: - Code Only (monospace) — scales

    /// Code block content
    static var codeBlock: Font { .system(size: 12.5 * s, design: .monospaced) }

    /// Small metadata in code blocks (language label, line numbers)
    static var codeMeta: Font { .system(size: 10.5 * s, design: .monospaced) }

    /// Primary code font (inline code, tool inputs)
    static var code: Font { .system(size: 13 * s, design: .monospaced) }

    // MARK: - UI Chrome (fixed size — doesn't scale)

    /// Status bar items
    static let statusBar = Font.system(size: 11.5, weight: .medium)

    /// Status bar secondary info
    static let statusBarSecondary = Font.system(size: 11, weight: .regular)

    // MARK: - Conversation (clean system font) — scales

    /// Section headings
    static var heading1: Font { .system(size: 17 * s, weight: .semibold) }
    static var heading2: Font { .system(size: 15 * s, weight: .semibold) }
    static var heading3: Font { .system(size: 14 * s, weight: .medium) }

    /// Body text in conversation
    static var body: Font { .system(size: 13.5 * s) }

    /// Bold body
    static var bodyBold: Font { .system(size: 13.5 * s, weight: .semibold) }

    /// Muted / metadata text
    static var caption: Font { .system(size: 11.5 * s) }

    /// Input bar
    static var input: Font { .system(size: 14 * s) }

    /// Input bar NSFont (for NSTextView)
    static var inputNS: NSFont { .systemFont(ofSize: 14 * s, weight: .regular) }

    /// Tool use labels
    static var toolLabel: Font { .system(size: 12 * s, weight: .medium) }

    /// Thinking block text
    static var thinking: Font { .system(size: 13 * s).italic() }
}
