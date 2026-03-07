import SwiftUI

/// Browse, view, create, and invoke Claude CLI skills
/// Skills are reusable prompt templates stored in ~/.claude/skills/<name>/SKILL.md
struct SkillsBrowser: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var process: ClaudeProcess
    @EnvironmentObject private var theme: ThemeEngine
    @StateObject private var skillsManager = SkillsManager.shared

    @State private var selectedSkill: SkillDefinition?
    @State private var showCreateForm = false
    @State private var newName = ""
    @State private var newDescription = ""
    @State private var newContent = ""
    @State private var newTools = ""
    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 14))
                    .foregroundColor(theme.sky)
                Text("Skills")
                    .font(Typography.heading2)
                    .foregroundColor(theme.bright)

                Text("\(skillsManager.skills.count)")
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
                        selectedSkill = nil
                        resetCreateForm()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 12))
                        Text("New Skill")
                            .font(Typography.caption)
                    }
                    .foregroundColor(theme.sky)
                }
                .buttonStyle(.plain)

                Button {
                    skillsManager.load()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                        .foregroundColor(theme.muted)
                }
                .buttonStyle(.plain)
                .help("Reload skills from disk")

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
                // Left: skill list
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(skillsManager.skills) { skill in
                            Button {
                                selectedSkill = skill
                                showCreateForm = false
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(skill.name)
                                            .font(Typography.bodyBold)
                                            .foregroundColor(selectedSkill?.id == skill.id ? theme.sky : theme.primary)
                                        if !skill.description.isEmpty {
                                            Text(skill.description)
                                                .font(Typography.caption)
                                                .foregroundColor(theme.muted)
                                                .lineLimit(2)
                                        }
                                    }
                                    Spacer()
                                    if skill.model != nil {
                                        Image(systemName: "cpu")
                                            .font(.system(size: 9))
                                            .foregroundColor(theme.muted)
                                    }
                                    if skill.allowedTools != nil {
                                        Image(systemName: "lock")
                                            .font(.system(size: 9))
                                            .foregroundColor(theme.muted)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(selectedSkill?.id == skill.id ? theme.sky.opacity(0.1) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }

                        if skillsManager.skills.isEmpty {
                            VStack(spacing: 8) {
                                Spacer()
                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 24))
                                    .foregroundColor(theme.muted)
                                Text("No skills found")
                                    .font(Typography.body)
                                    .foregroundColor(theme.muted)
                                Text("Create one or add to ~/.claude/skills/")
                                    .font(Typography.caption)
                                    .foregroundColor(theme.muted)
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

                // Right: skill detail or create form
                if showCreateForm {
                    createFormView
                } else if let skill = selectedSkill {
                    skillDetailView(skill)
                } else {
                    VStack {
                        Spacer()
                        Text("Select a skill or create a new one")
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

    // MARK: - Skill Detail View

    private func skillDetailView(_ skill: SkillDefinition) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Skill header
            HStack {
                Text(skill.name)
                    .font(Typography.heading2)
                    .foregroundColor(theme.bright)

                Spacer()

                Button {
                    skillsManager.invokeSkill(name: skill.name, process: process)
                    isPresented = false
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                        Text("Invoke")
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

            // Metadata
            if skill.model != nil || skill.allowedTools != nil {
                HStack(spacing: 12) {
                    if let model = skill.model {
                        HStack(spacing: 3) {
                            Image(systemName: "cpu")
                                .font(.system(size: 9))
                            Text(model)
                                .font(Typography.caption)
                        }
                        .foregroundColor(theme.lavender)
                    }
                    if let tools = skill.allowedTools {
                        HStack(spacing: 3) {
                            Image(systemName: "lock")
                                .font(.system(size: 9))
                            Text(tools.joined(separator: ", "))
                                .font(Typography.caption)
                        }
                        .foregroundColor(theme.amber)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            Divider().opacity(0.3)

            // Content
            ScrollView {
                Text(skill.content)
                    .font(Typography.codeBlock)
                    .foregroundColor(theme.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
        .alert("Delete Skill?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                skillsManager.deleteSkill(name: skill.name)
                selectedSkill = nil
            }
        } message: {
            Text("This will delete the skill directory ~/.claude/skills/\(skill.name)")
        }
    }

    // MARK: - Create Form

    private var createFormView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Skill")
                .font(Typography.heading2)
                .foregroundColor(theme.bright)
                .padding(.horizontal, 16)
                .padding(.top, 12)

            VStack(alignment: .leading, spacing: 8) {
                TextField("Skill name (becomes directory name)", text: $newName)
                    .textFieldStyle(.plain)
                    .font(Typography.body)
                    .foregroundColor(theme.primary)
                    .padding(8)
                    .background(theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                TextField("Description", text: $newDescription)
                    .textFieldStyle(.plain)
                    .font(Typography.body)
                    .foregroundColor(theme.primary)
                    .padding(8)
                    .background(theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                TextField("Allowed tools (comma-separated, optional)", text: $newTools)
                    .textFieldStyle(.plain)
                    .font(Typography.caption)
                    .foregroundColor(theme.primary)
                    .padding(6)
                    .background(theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Text("Skill prompt:")
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
                    let tools = newTools.isEmpty ? nil : newTools.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    skillsManager.createSkill(
                        name: newName,
                        description: newDescription,
                        content: newContent,
                        tools: tools
                    )
                    showCreateForm = false
                    resetCreateForm()
                    // Select the newly created skill
                    if let created = skillsManager.skills.last {
                        selectedSkill = created
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
        newTools = ""
    }
}
