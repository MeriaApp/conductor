import SwiftUI

/// Floating command palette (Cmd+K) — central hub for all actions
struct CommandPalette: View {
    let commands: [CommandItem]
    @Binding var isPresented: Bool
    @EnvironmentObject private var theme: ThemeEngine
    @State private var searchText = ""
    @State private var selectedIndex = 0
    @FocusState private var isFocused: Bool

    var filteredCommands: [CommandItem] {
        if searchText.isEmpty { return commands }
        return commands.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundColor(theme.muted)
                TextField("Type a command...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(Typography.body)
                    .foregroundColor(theme.primary)
                    .focused($isFocused)
                    .onSubmit {
                        executeSelected()
                    }
            }
            .padding(14)

            Divider().opacity(0.3)

            // Command list
            if filteredCommands.isEmpty {
                Text("No matching commands")
                    .font(Typography.caption)
                    .foregroundColor(theme.muted)
                    .padding(16)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filteredCommands.enumerated()), id: \.element.id) { idx, command in
                                CommandRow(command: command, isSelected: idx == selectedIndex)
                                    .id(command.id)
                                    .onTapGesture {
                                        command.action()
                                        isPresented = false
                                    }
                            }
                        }
                    }
                    .frame(maxHeight: 340)
                    .onChange(of: selectedIndex) { _, newIdx in
                        if newIdx < filteredCommands.count {
                            proxy.scrollTo(filteredCommands[newIdx].id, anchor: .center)
                        }
                    }
                }
            }
        }
        .background(theme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.sky.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 30, y: 10)
        .frame(width: 520)
        .onAppear {
            isFocused = true
            selectedIndex = 0
        }
        .onChange(of: searchText) { _, _ in
            selectedIndex = 0
        }
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 { selectedIndex -= 1 }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if selectedIndex < filteredCommands.count - 1 { selectedIndex += 1 }
            return .handled
        }
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
    }

    private func executeSelected() {
        guard selectedIndex < filteredCommands.count else { return }
        filteredCommands[selectedIndex].action()
        isPresented = false
    }
}

// MARK: - Command Row

struct CommandRow: View {
    let command: CommandItem
    let isSelected: Bool
    @EnvironmentObject private var theme: ThemeEngine

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: command.icon)
                .font(.system(size: 12))
                .foregroundColor(command.category.color(theme))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(command.name)
                    .font(Typography.body)
                    .foregroundColor(theme.primary)

                if let subtitle = command.subtitle {
                    Text(subtitle)
                        .font(Typography.caption)
                        .foregroundColor(theme.muted)
                }
            }

            Spacer()

            if let shortcut = command.shortcut {
                Text(shortcut)
                    .font(Typography.codeBlock)
                    .foregroundColor(theme.muted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(isSelected ? theme.sky.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
    }
}

// MARK: - Command Model

struct CommandItem: Identifiable {
    let id = UUID().uuidString
    let name: String
    let icon: String
    let shortcut: String?
    let subtitle: String?
    let category: CommandCategory
    let action: () -> Void

    init(
        name: String,
        icon: String,
        shortcut: String? = nil,
        subtitle: String? = nil,
        category: CommandCategory = .general,
        action: @escaping () -> Void
    ) {
        self.name = name
        self.icon = icon
        self.shortcut = shortcut
        self.subtitle = subtitle
        self.category = category
        self.action = action
    }
}

enum CommandCategory {
    case general
    case agent
    case view
    case session

    @MainActor
    func color(_ theme: ThemeEngine) -> Color {
        switch self {
        case .general: return theme.sky
        case .agent: return theme.lavender
        case .view: return theme.sage
        case .session: return theme.sand
        }
    }
}
