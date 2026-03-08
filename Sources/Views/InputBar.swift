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

    // Dynamic text height (starts compact, grows with content)
    @State private var textContentHeight: CGFloat = 22

    // Image/file attachments
    @State private var attachedImages: [URL] = []

    // Slash autocomplete state
    @State private var slashMatches: [SlashSuggestion] = []
    @State private var selectedSlashIndex = 0

    // File path autocomplete state
    @State private var filePathMatches: [String] = []
    @State private var selectedFilePathIndex = 0
    @State private var filePathPrefix = ""

    // Message history (up/down arrow recall)
    @State private var messageHistory: [String] = []
    @State private var historyIndex: Int = -1
    @State private var savedCurrentInput: String = ""

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

                // File path autocomplete popup
                if !filePathMatches.isEmpty {
                    FilePathAutocompletePopup(
                        matches: filePathMatches,
                        selectedIndex: selectedFilePathIndex,
                        theme: theme,
                        onSelect: { path in
                            insertFilePathSuggestion(path)
                        }
                    )
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .zIndex(10)
                }

                VStack(spacing: 0) {
                    // Attached images strip
                    if !attachedImages.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(attachedImages, id: \.absoluteString) { url in
                                    AttachmentThumbnail(url: url, theme: theme) {
                                        withAnimation(.easeOut(duration: 0.15)) {
                                            attachedImages.removeAll { $0 == url }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                        }
                        .background(theme.elevated.opacity(0.5))

                        Rectangle()
                            .fill(theme.separator.opacity(0.2))
                            .frame(height: 1)
                    }

                    HStack(alignment: .bottom, spacing: 12) {
                        // Prompt character (hidden in vibe mode — placeholder replaces it)
                        if !process.isVibeCoder {
                            Text("\u{25B8}")
                                .font(Typography.input)
                                .foregroundColor(theme.sky)
                                .padding(.bottom, 4)
                        }

                        // Input field with vibe mode placeholder
                        ZStack(alignment: .leading) {
                            if inputText.isEmpty {
                                Text(process.isVibeCoder ? "What do you want to build?" : "Message Claude...")
                                    .font(Typography.input)
                                    .foregroundColor(theme.muted.opacity(0.6))
                                    .padding(.leading, 2)
                                    .padding(.bottom, 4)
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
                                    updateFilePathSuggestions(for: newText)
                                },
                                onHeightChange: { height in
                                    textContentHeight = height
                                },
                                onImagePaste: { urls in
                                    withAnimation(.easeOut(duration: 0.15)) {
                                        for url in urls where !attachedImages.contains(url) {
                                            attachedImages.append(url)
                                        }
                                    }
                                },
                                onFileDrop: { urls in
                                    for url in urls {
                                        if !inputText.isEmpty && !inputText.hasSuffix("\n\n") {
                                            inputText += inputText.hasSuffix("\n") ? "\n" : "\n\n"
                                        }
                                        inputText += "@\(url.path)\n\n"
                                    }
                                },
                                onArrowUp: {
                                    // File path autocomplete
                                    if !filePathMatches.isEmpty {
                                        selectedFilePathIndex = max(0, selectedFilePathIndex - 1)
                                        return true
                                    }
                                    // Slash autocomplete takes priority
                                    if !slashMatches.isEmpty {
                                        selectedSlashIndex = max(0, selectedSlashIndex - 1)
                                        return true
                                    }
                                    // Message history recall
                                    guard !messageHistory.isEmpty else { return false }
                                    if historyIndex == -1 {
                                        savedCurrentInput = inputText
                                        historyIndex = messageHistory.count - 1
                                    } else if historyIndex > 0 {
                                        historyIndex -= 1
                                    } else {
                                        return true
                                    }
                                    inputText = messageHistory[historyIndex]
                                    return true
                                },
                                onArrowDown: {
                                    if !filePathMatches.isEmpty {
                                        selectedFilePathIndex = min(filePathMatches.count - 1, selectedFilePathIndex + 1)
                                        return true
                                    }
                                    if !slashMatches.isEmpty {
                                        selectedSlashIndex = min(slashMatches.count - 1, selectedSlashIndex + 1)
                                        return true
                                    }
                                    // Navigate forward through history
                                    guard historyIndex >= 0 else { return false }
                                    if historyIndex < messageHistory.count - 1 {
                                        historyIndex += 1
                                        inputText = messageHistory[historyIndex]
                                    } else {
                                        historyIndex = -1
                                        inputText = savedCurrentInput
                                    }
                                    return true
                                },
                                onTab: {
                                    if !filePathMatches.isEmpty, selectedFilePathIndex < filePathMatches.count {
                                        insertFilePathSuggestion(filePathMatches[selectedFilePathIndex])
                                        return true
                                    }
                                    guard !slashMatches.isEmpty,
                                          selectedSlashIndex < slashMatches.count else { return false }
                                    insertSlashSuggestion(slashMatches[selectedSlashIndex])
                                    return true
                                },
                                onEscape: {
                                    if !filePathMatches.isEmpty {
                                        filePathMatches = []
                                        return true
                                    }
                                    guard !slashMatches.isEmpty else { return false }
                                    slashMatches = []
                                    return true
                                }
                            )
                            .font(Typography.input)
                            .foregroundColor(theme.primary)
                            .focused($isFocused)
                            .frame(height: min(max(textContentHeight, 22), 200))
                        } // End ZStack

                        // Send button (visible when there's text or attachments)
                        if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachedImages.isEmpty {
                            Button(action: sendMessage) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(theme.sky)
                            }
                            .buttonStyle(.plain)
                            .padding(.bottom, 2)
                        }

                        // Interrupt button (visible when streaming)
                        if process.isStreaming {
                            Button(action: { process.interrupt() }) {
                                Image(systemName: "stop.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(theme.rose)
                            }
                            .buttonStyle(.plain)
                            .padding(.bottom, 2)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
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
        guard !text.isEmpty || !attachedImages.isEmpty else { return }
        slashMatches = []
        filePathMatches = []

        // Build message with image attachments
        var message = text
        if !attachedImages.isEmpty {
            let refs = attachedImages.map { "@\($0.path)" }.joined(separator: "\n")
            if message.isEmpty {
                message = refs
            } else {
                message = "\(refs)\n\n\(message)"
            }
            attachedImages.removeAll()
        }

        // Save to history for up-arrow recall
        if !text.isEmpty {
            messageHistory.append(text)
        }
        historyIndex = -1
        savedCurrentInput = ""

        process.send(message)
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

    // MARK: - File Path Autocomplete

    private func updateFilePathSuggestions(for text: String) {
        // Find the last @path token being typed
        guard let atRange = text.range(of: "@", options: .backwards) else {
            filePathMatches = []
            return
        }

        let afterAt = String(text[atRange.upperBound...])
        // Only activate if typing a path (no spaces after @, and it looks like a path)
        guard !afterAt.isEmpty,
              !afterAt.contains(" "),
              afterAt.count >= 2 else {
            filePathMatches = []
            return
        }

        filePathPrefix = "@" + afterAt
        let expandedPath = (afterAt as NSString).expandingTildeInPath

        let fm = FileManager.default
        let dir: String
        let partial: String

        if expandedPath.hasSuffix("/") {
            dir = expandedPath
            partial = ""
        } else {
            dir = (expandedPath as NSString).deletingLastPathComponent
            partial = (expandedPath as NSString).lastPathComponent.lowercased()
        }

        guard fm.fileExists(atPath: dir) else {
            filePathMatches = []
            return
        }

        do {
            let contents = try fm.contentsOfDirectory(atPath: dir)
            let matches = contents
                .filter { partial.isEmpty || $0.lowercased().hasPrefix(partial) }
                .sorted()
                .prefix(8)
                .map { item -> String in
                    let fullPath = (dir as NSString).appendingPathComponent(item)
                    var isDir: ObjCBool = false
                    fm.fileExists(atPath: fullPath, isDirectory: &isDir)
                    return isDir.boolValue ? fullPath + "/" : fullPath
                }
            filePathMatches = Array(matches)
            selectedFilePathIndex = 0
        } catch {
            filePathMatches = []
        }
    }

    private func insertFilePathSuggestion(_ path: String) {
        // Replace the @partial with @fullPath
        if let atRange = inputText.range(of: filePathPrefix, options: .backwards) {
            inputText.replaceSubrange(atRange, with: "@\(path)")
        }
        // If path is a directory, keep suggestions open; otherwise close
        if !path.hasSuffix("/") {
            filePathMatches = []
        } else {
            updateFilePathSuggestions(for: inputText)
        }
    }

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp", "svg"]

    /// Handle dropped file URLs — images go to attachment strip, other files inline as @/path
    private func handleFileDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    let ext = url.pathExtension.lowercased()
                    Task { @MainActor in
                        if Self.imageExtensions.contains(ext) {
                            withAnimation(.easeOut(duration: 0.15)) {
                                if !attachedImages.contains(url) {
                                    attachedImages.append(url)
                                }
                            }
                        } else {
                            if !inputText.isEmpty && !inputText.hasSuffix("\n\n") {
                                inputText += inputText.hasSuffix("\n") ? "\n" : "\n\n"
                            }
                            inputText += "@\(url.path)\n\n"
                        }
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
    var onHeightChange: ((CGFloat) -> Void)?
    var onImagePaste: (([URL]) -> Void)?
    var onFileDrop: (([URL]) -> Void)?
    var onArrowUp: (() -> Bool)?
    var onArrowDown: (() -> Bool)?
    var onTab: (() -> Bool)?
    var onEscape: (() -> Bool)?

    func makeNSView(context: Context) -> NSScrollView {
        // Build a fresh text stack so PasteAwareTextView owns its text container
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let pasteTV = PasteAwareTextView(frame: .zero, textContainer: textContainer)
        pasteTV.registerForDraggedTypes([.fileURL])
        pasteTV.onImagePaste = { urls in
            context.coordinator.onImagePaste?(urls)
        }
        pasteTV.onFileDrop = { urls in
            context.coordinator.onFileDrop?(urls)
        }

        pasteTV.delegate = context.coordinator
        pasteTV.isEditable = true
        pasteTV.isSelectable = true
        pasteTV.isRichText = false
        pasteTV.isAutomaticQuoteSubstitutionEnabled = false
        pasteTV.isAutomaticDashSubstitutionEnabled = false
        pasteTV.isAutomaticTextReplacementEnabled = false
        pasteTV.isAutomaticSpellingCorrectionEnabled = false
        pasteTV.allowsUndo = true
        pasteTV.drawsBackground = false
        pasteTV.textContainerInset = NSSize(width: 0, height: 2)
        pasteTV.font = Typography.inputNS
        pasteTV.textColor = textColor
        pasteTV.insertionPointColor = textColor
        pasteTV.isVerticallyResizable = true
        pasteTV.isHorizontallyResizable = false
        pasteTV.autoresizingMask = [.width]
        pasteTV.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        pasteTV.minSize = NSSize(width: 0, height: 0)

        let scrollView = NSScrollView()
        scrollView.documentView = pasteTV
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! NSTextView
        if textView.string != text {
            textView.string = text
            // Recalculate height when text is cleared
            context.coordinator.recalcHeight(textView: textView)
        }
        // Update text color and font when theme/scale changes
        textView.textColor = textColor
        textView.insertionPointColor = textColor
        textView.font = Typography.inputNS

        // Update coordinator callbacks
        context.coordinator.onTextChange = onTextChange
        context.coordinator.onHeightChange = onHeightChange
        context.coordinator.onImagePaste = onImagePaste
        context.coordinator.onFileDrop = onFileDrop
        context.coordinator.onArrowUp = onArrowUp
        context.coordinator.onArrowDown = onArrowDown
        context.coordinator.onTab = onTab
        context.coordinator.onEscape = onEscape

        // Keep paste-aware text view's callbacks in sync
        if let pasteTV = textView as? PasteAwareTextView {
            pasteTV.onImagePaste = { urls in
                context.coordinator.onImagePaste?(urls)
            }
            pasteTV.onFileDrop = { urls in
                context.coordinator.onFileDrop?(urls)
            }
        }

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
        var onHeightChange: ((CGFloat) -> Void)?
        var onImagePaste: (([URL]) -> Void)?
        var onFileDrop: (([URL]) -> Void)?
        var onArrowUp: (() -> Bool)?
        var onArrowDown: (() -> Bool)?
        var onTab: (() -> Bool)?
        var onEscape: (() -> Bool)?
        var hasFocused = false

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self._text = text
            self.onSubmit = onSubmit
        }

        func recalcHeight(textView: NSTextView) {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }
            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let height = usedRect.height + 4 // small padding
            onHeightChange?(height)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
            onTextChange?(textView.string)
            recalcHeight(textView: textView)
            // Keep cursor visible when typing into lower lines
            textView.scrollRangeToVisible(textView.selectedRange())
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

// MARK: - Paste-Aware Text View

/// NSTextView subclass that intercepts Cmd+V to detect pasted images
class PasteAwareTextView: NSTextView {
    var onImagePaste: (([URL]) -> Void)?
    var onFileDrop: (([URL]) -> Void)?

    private static let imageTypes: [NSPasteboard.PasteboardType] = [
        .tiff, .png,
        NSPasteboard.PasteboardType("public.jpeg"),
        NSPasteboard.PasteboardType("public.heic"),
    ]

    private static let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp", "svg"]

    override func awakeFromNib() {
        super.awakeFromNib()
        registerForDraggedTypes([.fileURL])
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
            return .copy
        }
        return super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL], !urls.isEmpty {
            let imageURLs = urls.filter { Self.imageExts.contains($0.pathExtension.lowercased()) }
            let otherURLs = urls.filter { !Self.imageExts.contains($0.pathExtension.lowercased()) }

            if !imageURLs.isEmpty {
                onImagePaste?(imageURLs)
            }
            if !otherURLs.isEmpty {
                onFileDrop?(otherURLs)
            }
            if !imageURLs.isEmpty || !otherURLs.isEmpty {
                return true
            }
        }
        return super.performDragOperation(sender)
    }

    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general

        // Check for image data on pasteboard (screenshots, copied images)
        let hasImage = Self.imageTypes.contains { pb.data(forType: $0) != nil }

        if hasImage {
            // Save image to temp file and pass URL to attachment strip
            if let saved = saveClipboardImage(from: pb) {
                onImagePaste?([saved])
                return
            }
        }

        // Check for file URLs that are images
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp", "svg"]
            let imageURLs = urls.filter { imageExts.contains($0.pathExtension.lowercased()) }
            if !imageURLs.isEmpty {
                onImagePaste?(imageURLs)
                // Also paste any non-image URLs as text
                let nonImages = urls.filter { !imageExts.contains($0.pathExtension.lowercased()) }
                if !nonImages.isEmpty {
                    let paths = nonImages.map { "@\($0.path)" }.joined(separator: "\n\n") + "\n\n"
                    insertText(paths, replacementRange: selectedRange())
                }
                return
            }
        }

        // Default paste behavior for text
        super.paste(sender)
    }

    private func saveClipboardImage(from pb: NSPasteboard) -> URL? {
        // Try to get image data in order of preference
        let typeOrder: [(NSPasteboard.PasteboardType, String)] = [
            (.png, "png"),
            (NSPasteboard.PasteboardType("public.jpeg"), "jpg"),
            (.tiff, "png"), // Convert TIFF to PNG (screenshots are TIFF)
            (NSPasteboard.PasteboardType("public.heic"), "heic"),
        ]

        for (type, ext) in typeOrder {
            if let data = pb.data(forType: type) {
                let fileName = "clipboard-\(Int(Date().timeIntervalSince1970))-\(Int.random(in: 1000...9999)).\(ext)"
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

                // For TIFF, convert to PNG
                if type == .tiff {
                    if let image = NSImage(data: data),
                       let tiffData = image.tiffRepresentation,
                       let bitmap = NSBitmapImageRep(data: tiffData),
                       let pngData = bitmap.representation(using: .png, properties: [:]) {
                        try? pngData.write(to: tempURL)
                        return tempURL
                    }
                } else {
                    try? data.write(to: tempURL)
                    return tempURL
                }
            }
        }
        return nil
    }
}

// MARK: - Attachment Thumbnail

struct AttachmentThumbnail: View {
    let url: URL
    let theme: ThemeEngine
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(theme.separator.opacity(0.3), lineWidth: 1)
                    )
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(theme.elevated)
                    .frame(width: 56, height: 56)
                    .overlay(
                        VStack(spacing: 2) {
                            Image(systemName: "photo")
                                .font(.system(size: 16))
                                .foregroundColor(theme.muted)
                            Text(url.pathExtension.uppercased())
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(theme.muted)
                        }
                    )
            }

            // Remove button
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(theme.muted)
                    .background(Circle().fill(theme.base).padding(2))
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: -4)
        }
        .help(url.lastPathComponent)
    }
}

// MARK: - File Path Autocomplete Popup

struct FilePathAutocompletePopup: View {
    let matches: [String]
    let selectedIndex: Int
    let theme: ThemeEngine
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(matches.enumerated()), id: \.offset) { index, path in
                        Button {
                            onSelect(path)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: path.hasSuffix("/") ? "folder.fill" : "doc.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(path.hasSuffix("/") ? theme.sky : theme.muted)
                                    .frame(width: 14)

                                Text(shortenForDisplay(path))
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(theme.primary)
                                    .lineLimit(1)

                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(index == selectedIndex ? theme.sky.opacity(0.1) : Color.clear)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 200)
        }
        .background(theme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.sky.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 10, y: -4)
        .padding(.horizontal, 16)
        .padding(.bottom, 50)
    }

    private func shortenForDisplay(_ path: String) -> String {
        let components = path.components(separatedBy: "/").filter { !$0.isEmpty }
        if components.count <= 3 { return path }
        return ".../" + components.suffix(3).joined(separator: "/") + (path.hasSuffix("/") ? "" : "")
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
