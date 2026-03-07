import SwiftUI

/// Browse, view, create, and invoke custom CLI commands
/// Commands are flat .md files stored in ~/.claude/commands/<name>.md
struct CommandsBrowser: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var process: ClaudeProcess
    @EnvironmentObject private var theme: ThemeEngine
    @StateObject private var commandsManager = CommandsManager.shared

    @State private var selectedCommand: CommandDefinition?
    @State private var showCreateForm = false
    @State private var newName = ""
    @State private var newDescription = ""
    @State private var newContent = ""
    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 14))
                    .foregroundColor(theme.sky)
                Text("Custom Commands")
                    .font(Typography.heading2)
                    .foregroundColor(theme.bright)

                Text("\(commandsManager.commands.count)")
                    .font(Typography.caption)
                    .foregroundColor(theme.muted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(theme.surface)
                    .clipShape(Capsule())

                Spacer()

                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        showCreateForm.toggle()
                        selectedCommand = nil
                        resetCreateForm()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 12))
                        Text("New Command")
                            .font(Typography.caption)
                    }
                    .foregroundColor(theme.sky)
                }
                .buttonStyle(.plain)

                Button {
                    commandsManager.load()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                        .foregroundColor(theme.muted)
                }
                .buttonStyle(.plain)
                .help("Reload commands from disk")

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

            // Body
            HStack(spacing: 0) {
                // Left: command list
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(commandsManager.commands) { command in
                            Button {
                                selectedCommand = command
                                showCreateForm = false
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("/\(command.name)")
                                            .font(Typography.bodyBold)
                                            .foregroundColor(selectedCommand?.id == command.id ? theme.sky : theme.primary)
                                        if !command.description.isEmpty {
                                            Text(command.description)
                                                .font(Typography.caption)
                                                .foregroundColor(theme.muted)
                                                .lineLimit(2)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(selectedCommand?.id == command.id ? theme.sky.opacity(0.1) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }

                        if commandsManager.commands.isEmpty {
                            VStack(spacing: 8) {
                                Spacer()
                                Image(systemName: "terminal")
                                    .font(.system(size: 24))
                                    .foregroundColor(theme.muted)
                                Text("No commands found")
                                    .font(Typography.body)
                                    .foregroundColor(theme.muted)
                                Text("Create one or add .md files to\n~/.claude/commands/")
                                    .font(Typography.caption)
                                    .foregroundColor(theme.muted)
                                    .multilineTextAlignment(.center)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        }
                    }
                    .padding(8)
                }
                .frame(width: 220)

                Divider().opacity(0.3)

                // Right: command detail or create form
                if showCreateForm {
                    createFormView
                } else if let command = selectedCommand {
                    commandDetailView(command)
                } else {
                    VStack {
                        Spacer()
                        Text("Select a command or create a new one")
                            .font(Typography.body)
                            .foregroundColor(theme.muted)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxHeight: 450)
        }
        .background(theme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.sky.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 30, y: 10)
        .frame(width: 700)
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
    }

    // MARK: - Command Detail View

    private func commandDetailView(_ command: CommandDefinition) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("/\(command.name)")
                    .font(Typography.heading2)
                    .foregroundColor(theme.bright)

                Spacer()

                Button {
                    commandsManager.invokeCommand(name: command.name, process: process)
                    isPresented = false
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                        Text("Run")
                            .font(Typography.bodyBold)
                    }
                    .foregroundColor(theme.base)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(theme.sky)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Button {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(theme.rose)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if !command.description.isEmpty {
                Text(command.description)
                    .font(Typography.caption)
                    .foregroundColor(theme.muted)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            Divider().opacity(0.3)

            // Content
            ScrollView {
                Text(command.content)
                    .font(Typography.codeBlock)
                    .foregroundColor(theme.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
        .alert("Delete Command?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                commandsManager.deleteCommand(name: command.name)
                selectedCommand = nil
            }
        } message: {
            Text("This will delete ~/.claude/commands/\(command.name).md")
        }
    }

    // MARK: - Create Form

    private var createFormView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Command")
                .font(Typography.heading2)
                .foregroundColor(theme.bright)
                .padding(.horizontal, 16)
                .padding(.top, 12)

            VStack(alignment: .leading, spacing: 8) {
                TextField("Command name (becomes /name)", text: $newName)
                    .textFieldStyle(.plain)
                    .font(Typography.body)
                    .foregroundColor(theme.primary)
                    .padding(8)
                    .background(theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                TextField("Description (optional)", text: $newDescription)
                    .textFieldStyle(.plain)
                    .font(Typography.body)
                    .foregroundColor(theme.primary)
                    .padding(8)
                    .background(theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Text("Command prompt:")
                    .font(Typography.caption)
                    .foregroundColor(theme.muted)

                TextEditor(text: $newContent)
                    .font(Typography.codeBlock)
                    .foregroundColor(theme.primary)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .frame(minHeight: 150)
            }
            .padding(.horizontal, 16)

            HStack {
                Spacer()
                Button("Cancel") {
                    showCreateForm = false
                    resetCreateForm()
                }
                .font(Typography.body)
                .foregroundColor(theme.muted)
                .buttonStyle(.plain)

                Button("Create") {
                    commandsManager.createCommand(
                        name: newName,
                        description: newDescription,
                        content: newContent
                    )
                    showCreateForm = false
                    resetCreateForm()
                    if let created = commandsManager.commands.last {
                        selectedCommand = created
                    }
                }
                .disabled(newName.isEmpty || newContent.isEmpty)
                .font(Typography.bodyBold)
                .foregroundColor(newName.isEmpty || newContent.isEmpty ? theme.muted : theme.sky)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Spacer()
        }
    }

    private func resetCreateForm() {
        newName = ""
        newDescription = ""
        newContent = ""
    }
}
