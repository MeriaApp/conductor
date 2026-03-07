import SwiftUI

/// Visual CRUD overlay for Claude CLI hooks (PreToolUse, PostToolUse, etc.)
/// Reads/writes ~/.claude/settings.json hooks dict
struct HooksOverlay: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var theme: ThemeEngine
    @StateObject private var hooksManager = HooksManager.shared

    @State private var selectedEvent: String = "PreToolUse"
    @State private var newCommand = ""
    @State private var newTimeout = ""
    @State private var newMatcher = ""
    @State private var showAddForm = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "gearshape.2")
                    .font(.system(size: 14))
                    .foregroundColor(theme.sky)
                Text("CLI Hooks")
                    .font(Typography.heading2)
                    .foregroundColor(theme.bright)

                Text("\(hooksManager.totalCount) active")
                    .font(Typography.caption)
                    .foregroundColor(theme.muted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(theme.surface)
                    .clipShape(Capsule())

                Spacer()

                Button {
                    hooksManager.load()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                        .foregroundColor(theme.muted)
                }
                .buttonStyle(.plain)
                .help("Reload from settings.json")

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

            // Body: left event list + right hook list
            HStack(spacing: 0) {
                // Left column: event types
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(HooksManager.eventTypes, id: \.name) { event in
                            let count = hooksManager.hooksByEvent[event.name]?.count ?? 0
                            Button {
                                selectedEvent = event.name
                                showAddForm = false
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(event.name)
                                            .font(Typography.bodyBold)
                                            .foregroundColor(selectedEvent == event.name ? theme.sky : theme.primary)
                                        Text(event.description)
                                            .font(Typography.caption)
                                            .foregroundColor(theme.muted)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    if count > 0 {
                                        Text("\(count)")
                                            .font(Typography.caption)
                                            .foregroundColor(theme.sky)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(theme.sky.opacity(0.1))
                                            .clipShape(Capsule())
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(selectedEvent == event.name ? theme.sky.opacity(0.1) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                }
                .frame(width: 240)

                Divider().opacity(0.3)

                // Right column: hooks for selected event
                VStack(alignment: .leading, spacing: 0) {
                    // Event header + add button
                    HStack {
                        Text(selectedEvent)
                            .font(Typography.heading2)
                            .foregroundColor(theme.bright)

                        Spacer()

                        Button {
                            withAnimation(.easeOut(duration: 0.15)) {
                                showAddForm.toggle()
                                newCommand = ""
                                newTimeout = ""
                                newMatcher = ""
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 12))
                                Text("Add Hook")
                                    .font(Typography.caption)
                            }
                            .foregroundColor(theme.sky)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    // Add form
                    if showAddForm {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Command (e.g., /path/to/script.sh)", text: $newCommand)
                                .textFieldStyle(.plain)
                                .font(Typography.codeBlock)
                                .foregroundColor(theme.primary)
                                .padding(8)
                                .background(theme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                            HStack(spacing: 8) {
                                TextField("Timeout (ms)", text: $newTimeout)
                                    .textFieldStyle(.plain)
                                    .font(Typography.caption)
                                    .foregroundColor(theme.primary)
                                    .padding(6)
                                    .background(theme.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .frame(width: 100)

                                TextField("Matcher regex (optional)", text: $newMatcher)
                                    .textFieldStyle(.plain)
                                    .font(Typography.caption)
                                    .foregroundColor(theme.primary)
                                    .padding(6)
                                    .background(theme.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))

                                Button("Add") {
                                    let timeout = Int(newTimeout)
                                    let matcher = newMatcher.isEmpty ? nil : newMatcher
                                    hooksManager.addHook(
                                        event: selectedEvent,
                                        command: newCommand,
                                        timeout: timeout,
                                        matcher: matcher
                                    )
                                    showAddForm = false
                                    newCommand = ""
                                    newTimeout = ""
                                    newMatcher = ""
                                }
                                .disabled(newCommand.isEmpty)
                                .font(Typography.bodyBold)
                                .foregroundColor(newCommand.isEmpty ? theme.muted : theme.sky)
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                        .transition(.opacity)
                    }

                    Divider().opacity(0.3)

                    // Hook entries
                    let entries = hooksManager.hooksByEvent[selectedEvent] ?? []
                    if entries.isEmpty {
                        VStack(spacing: 8) {
                            Spacer()
                            Image(systemName: "gearshape")
                                .font(.system(size: 24))
                                .foregroundColor(theme.muted)
                            Text("No hooks for \(selectedEvent)")
                                .font(Typography.body)
                                .foregroundColor(theme.muted)
                            Text("Add a hook to run a command on this event")
                                .font(Typography.caption)
                                .foregroundColor(theme.muted)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 6) {
                                ForEach(entries) { entry in
                                    HookEntryRow(
                                        entry: entry,
                                        event: selectedEvent,
                                        hooksManager: hooksManager
                                    )
                                }
                            }
                            .padding(12)
                        }
                    }
                }
            }
            .frame(maxHeight: 400)
        }
        .background(theme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.sky.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 30, y: 10)
        .frame(width: 680)
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
    }
}

// MARK: - Hook Entry Row

struct HookEntryRow: View {
    let entry: HookEntry
    let event: String
    @ObservedObject var hooksManager: HooksManager
    @EnvironmentObject private var theme: ThemeEngine

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "terminal")
                .font(.system(size: 10))
                .foregroundColor(theme.sage)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.command)
                    .font(Typography.codeBlock)
                    .foregroundColor(theme.primary)
                    .textSelection(.enabled)

                HStack(spacing: 8) {
                    if let timeout = entry.timeout {
                        HStack(spacing: 3) {
                            Image(systemName: "clock")
                                .font(.system(size: 9))
                            Text("\(timeout)ms")
                                .font(Typography.caption)
                        }
                        .foregroundColor(theme.muted)
                    }
                    if let matcher = entry.matcher {
                        HStack(spacing: 3) {
                            Image(systemName: "textformat.abc")
                                .font(.system(size: 9))
                            Text(matcher)
                                .font(Typography.caption)
                        }
                        .foregroundColor(theme.lavender)
                    }
                }
            }

            Spacer()

            Button {
                hooksManager.removeHook(event: event, id: entry.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundColor(theme.rose)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
