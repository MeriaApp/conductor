import SwiftUI
import UniformTypeIdentifiers

/// User input area — expands for multiline, Enter to send, Shift+Enter for newline
/// Per UX_DESIGN.md: "Single line that expands to multiline on Shift+Enter"
struct InputBar: View {
    @EnvironmentObject private var process: ClaudeProcess
    @EnvironmentObject private var theme: ThemeEngine
    @State private var inputText = ""
    @State private var isDragOver = false
    @FocusState private var isFocused: Bool

    // Slash autocomplete state
    @State private var slashMatches: [SlashSuggestion] = []
    @State private var selectedSlashIndex = 0

    /// Callbacks for shortcuts strip actions
    var onCommandPalette: (() -> Void)?
    var onToggleVibe: (() -> Void)?
    var onShowHelp: (() -> Void)?
    var onSessionBrowser: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Top separator
            Rectangle()
                .fill(theme.separator.opacity(0.3))
                .frame(height: 1)

            // Persistent shortcuts strip
            ShortcutsStrip(
                onCommandPalette: onCommandPalette,
                onToggleVibe: onToggleVibe,
                onShowHelp: onShowHelp,
                onSessionBrowser: onSessionBrowser
            )

            ZStack(alignment: .bottom) {
                // Slash autocomplete popup (positioned above input)
                if !slashMatches.isEmpty {
                    SlashAutocompletePopup(
                        matches: slashMatches,
                        selectedIndex: selectedSlashIndex,
                        theme: theme,
                        onSelect: { suggestion in
                            insertSlashSuggestion(suggestion)
                        }
                    )
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .zIndex(10)
                }

                HStack(alignment: .bottom, spacing: 12) {
                    // Prompt character (hidden in vibe mode — placeholder replaces it)
                    if !process.isVibeCoder {
                        Text("\u{25B8}")
                            .font(Typography.input)
                            .foregroundColor(theme.sky)
                            .padding(.bottom, 6)
                    }

                    // Input field with vibe mode placeholder
                    ZStack(alignment: .leading) {
                        if process.isVibeCoder && inputText.isEmpty {
                            Text("What do you want to build?")
                                .font(Typography.input)
                                .foregroundColor(theme.muted.opacity(0.6))
                                .padding(.leading, 2)
                                .padding(.bottom, 6)
                                .allowsHitTesting(false)
                        }

                        InputTextEditor(
                            text: $inputText,
                            textColor: ColorPalette.primary.withLightness(
                                ColorPalette.primary.lightness + ((1.0 - 2 * ColorPalette.primary.lightness + 0.05) * theme.luminance)
                            ).nsColor,
                            onSubmit: sendMessage,
                            onTextChange: { newText in
                                updateSlashSuggestions(for: newText)
                            },
                            onArrowUp: {
                                guard !slashMatches.isEmpty else { return false }
                                selectedSlashIndex = max(0, selectedSlashIndex - 1)
                                return true
                            },
                            onArrowDown: {
                                guard !slashMatches.isEmpty else { return false }
                                selectedSlashIndex = min(slashMatches.count - 1, selectedSlashIndex + 1)
                                return true
                            },
                            onTab: {
                                guard !slashMatches.isEmpty,
                                      selectedSlashIndex < slashMatches.count else { return false }
                                insertSlashSuggestion(slashMatches[selectedSlashIndex])
                                return true
                            },
                            onEscape: {
                                guard !slashMatches.isEmpty else { return false }
                                slashMatches = []
                                return true
                            }
                        )
                        .font(Typography.input)
                        .foregroundColor(theme.primary)
                        .focused($isFocused)
                        .frame(minHeight: 20, maxHeight: 200)
                    } // End ZStack

                    // Send button (visible when there's text)
                    if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button(action: sendMessage) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(theme.sky)
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 4)
                    }

                    // Interrupt button (visible when streaming)
                    if process.isStreaming {
                        Button(action: { process.interrupt() }) {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(theme.rose)
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isDragOver ? theme.sky.opacity(0.08) : theme.inputBackground)
                .overlay(
                    isDragOver
                        ? RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(theme.sky.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6, 3]))
                        : nil
                )
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
            handleFileDrop(providers)
        }
        .onAppear { isFocused = true }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        slashMatches = []
        process.send(text)
        inputText = ""
    }

    // MARK: - Slash Autocomplete

    private static let builtinCommands: [(name: String, description: String)] = [
        ("compact", "Compact context"),
        ("help", "Show help"),
        ("clear", "Clear conversation"),
        ("cost", "Show session cost"),
        ("doctor", "Run diagnostics"),
        ("memory", "Manage persistent memory"),
        ("model", "Switch model"),
        ("permissions", "View permissions"),
        ("review", "Review recent changes"),
        ("status", "Show session status"),
        ("vim", "Toggle vim mode"),
        ("login", "Log in to Claude"),
        ("logout", "Log out of Claude"),
    ]

    private func updateSlashSuggestions(for text: String) {
        // Only activate for text starting with / and no spaces (typing a command name)
        guard text.hasPrefix("/"),
              !text.contains(" "),
              text.count > 0 else {
            slashMatches = []
            return
        }

        let query = String(text.dropFirst()).lowercased() // Remove leading /

        var suggestions: [SlashSuggestion] = []

        // Built-in commands
        for cmd in Self.builtinCommands {
            if query.isEmpty || cmd.name.lowercased().hasPrefix(query) {
                suggestions.append(SlashSuggestion(
                    name: cmd.name,
                    description: cmd.description,
                    category: "builtin"
                ))
            }
        }

        // Skills
        for skill in SkillsManager.shared.skills {
            let skillName = "skill:\(skill.name)"
            if query.isEmpty || skillName.lowercased().hasPrefix(query) || skill.name.lowercased().hasPrefix(query) {
                suggestions.append(SlashSuggestion(
                    name: skillName,
                    description: skill.description.isEmpty ? "Custom skill" : skill.description,
                    category: "skill"
                ))
            }
        }

        // Custom commands
        for command in CommandsManager.shared.commands {
            if query.isEmpty || command.name.lowercased().hasPrefix(query) {
                suggestions.append(SlashSuggestion(
                    name: command.name,
                    description: command.description.isEmpty ? "Custom command" : command.description,
                    category: "command"
                ))
            }
        }

        // Limit to 8 visible
        slashMatches = Array(suggestions.prefix(8))
        selectedSlashIndex = 0
    }

    private func insertSlashSuggestion(_ suggestion: SlashSuggestion) {
        inputText = "/\(suggestion.name) "
        slashMatches = []
    }

    /// Handle dropped file URLs — insert as @/path/to/file references
    private func handleFileDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    let path = url.path
                    Task { @MainActor in
                        if !inputText.isEmpty && !inputText.hasSuffix("\n") {
                            inputText += "\n"
                        }
                        inputText += "@\(path)"
                    }
                }
            }
        }
        return handled
    }
}

// MARK: - Slash Suggestion Model

struct SlashSuggestion: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let category: String  // "builtin", "skill", "command"
}

// MARK: - Slash Autocomplete Popup

struct SlashAutocompletePopup: View {
    let matches: [SlashSuggestion]
    let selectedIndex: Int
    let theme: ThemeEngine
    let onSelect: (SlashSuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(matches.enumerated()), id: \.element.id) { index, suggestion in
                        Button {
                            onSelect(suggestion)
                        } label: {
                            HStack(spacing: 8) {
                                Text("/\(suggestion.name)")
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundColor(theme.sky)

                                Text(suggestion.description)
                                    .font(.system(size: 11))
                                    .foregroundColor(theme.muted)
                                    .lineLimit(1)

                                Spacer()

                                Text(suggestion.category)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(categoryColor(suggestion.category))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(categoryColor(suggestion.category).opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(index == selectedIndex ? theme.sky.opacity(0.1) : Color.clear)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 250)
        }
        .background(theme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.sky.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 10, y: -4)
        .padding(.horizontal, 16)
        .padding(.bottom, 50) // Position above the input area
    }

    private func categoryColor(_ category: String) -> Color {
        switch category {
        case "builtin": return theme.sage
        case "skill": return theme.lavender
        case "command": return theme.sky
        default: return theme.muted
        }
    }
}

// MARK: - Custom TextEditor with Enter/Shift+Enter handling

struct InputTextEditor: NSViewRepresentable {
    @Binding var text: String
    var textColor: NSColor
    var onSubmit: () -> Void
    var onTextChange: ((String) -> Void)?
    var onArrowUp: (() -> Bool)?
    var onArrowDown: (() -> Bool)?
    var onTab: (() -> Bool)?
    var onEscape: (() -> Bool)?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.font = Typography.inputNS
        textView.textColor = textColor
        textView.insertionPointColor = textColor

        // Make the scroll view transparent
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! NSTextView
        if textView.string != text {
            textView.string = text
        }
        // Update text color and font when theme/scale changes
        textView.textColor = textColor
        textView.insertionPointColor = textColor
        textView.font = Typography.inputNS

        // Update coordinator callbacks
        context.coordinator.onTextChange = onTextChange
        context.coordinator.onArrowUp = onArrowUp
        context.coordinator.onArrowDown = onArrowDown
        context.coordinator.onTab = onTab
        context.coordinator.onEscape = onEscape

        // Make NSTextView first responder on first update (SwiftUI .focused() doesn't work with NSViewRepresentable)
        if !context.coordinator.hasFocused, let window = textView.window {
            window.makeFirstResponder(textView)
            context.coordinator.hasFocused = true
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var onSubmit: () -> Void
        var onTextChange: ((String) -> Void)?
        var onArrowUp: (() -> Bool)?
        var onArrowDown: (() -> Bool)?
        var onTab: (() -> Bool)?
        var onEscape: (() -> Bool)?
        var hasFocused = false

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self._text = text
            self.onSubmit = onSubmit
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
            onTextChange?(textView.string)
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // Enter = send (or accept suggestion if autocomplete showing), Shift+Enter = newline
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let flags = NSApp.currentEvent?.modifierFlags ?? []
                if flags.contains(.shift) {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                    return true
                } else {
                    onSubmit()
                    return true
                }
            }
            // Arrow up — intercept for autocomplete
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                if let handler = onArrowUp, handler() {
                    return true
                }
            }
            // Arrow down — intercept for autocomplete
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                if let handler = onArrowDown, handler() {
                    return true
                }
            }
            // Tab — insert selected suggestion
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                if let handler = onTab, handler() {
                    return true
                }
            }
            // Escape — dismiss autocomplete
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                if let handler = onEscape, handler() {
                    return true
                }
            }
            return false
        }
    }
}

// MARK: - Persistent Shortcuts Strip

/// Always-visible strip above the input bar showing key capabilities.
/// Ensures the user always knows what they can do without memorizing anything.
struct ShortcutsStrip: View {
    @EnvironmentObject private var theme: ThemeEngine
    @EnvironmentObject private var process: ClaudeProcess

    var onCommandPalette: (() -> Void)?
    var onToggleVibe: (() -> Void)?
    var onShowHelp: (() -> Void)?
    var onSessionBrowser: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            stripButton("command", "Palette", "Cmd+K") { onCommandPalette?() }

            stripDivider

            stripButton("sparkles", process.isVibeCoder ? "Exit Vibe" : "Vibe Mode", "Ctrl+V") { onToggleVibe?() }

            stripDivider

            stripButton("clock.arrow.circlepath", "Sessions", "Cmd+S") { onSessionBrowser?() }

            stripDivider

            stripButton("keyboard", "All Shortcuts", "?") { onShowHelp?() }

            Spacer()

            Text("Enter to send · Shift+Enter for new line · / for commands")
                .font(.system(size: 10))
                .foregroundColor(theme.muted.opacity(0.6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .background(theme.surface.opacity(0.5))
    }

    private func stripButton(_ icon: String, _ label: String, _ shortcut: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundColor(theme.sky)

                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(theme.secondary)

                Text(shortcut)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(theme.muted)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(theme.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            }
        }
        .buttonStyle(.plain)
    }

    private var stripDivider: some View {
        Rectangle()
            .fill(theme.separator.opacity(0.2))
            .frame(width: 1, height: 12)
    }
}
