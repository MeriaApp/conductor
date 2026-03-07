import SwiftUI

/// Feature discovery overlay — shows Active, Configure, and Suggestions
/// Adapted from UX_DESIGN.md feature map concept
struct FeatureMapOverlay: View {
    @EnvironmentObject private var featureDetector: FeatureDetector
    @EnvironmentObject private var evolutionAgent: EvolutionAgent
    @EnvironmentObject private var theme: ThemeEngine
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Feature Map")
                    .font(Typography.heading1)
                    .foregroundColor(theme.bright)

                Spacer()

                if featureDetector.isScanning || evolutionAgent.isChecking {
                    ProgressView()
                        .controlSize(.small)
                }

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(theme.muted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            // Tab bar
            HStack(spacing: 0) {
                TabButton(title: "Active", count: featureDetector.activeFeatures.count, isSelected: selectedTab == 0) {
                    selectedTab = 0
                }
                TabButton(title: "Suggestions", count: pendingSuggestions.count, isSelected: selectedTab == 1) {
                    selectedTab = 1
                }
                TabButton(title: "Configure", count: nil, isSelected: selectedTab == 2) {
                    selectedTab = 2
                }
            }
            .padding(.horizontal, 20)

            Divider().opacity(0.3)

            // Content
            ScrollView {
                switch selectedTab {
                case 0:
                    activeTab
                case 1:
                    suggestionsTab
                case 2:
                    configureTab
                default:
                    EmptyView()
                }
            }
        }
        .background(theme.surface)
        .frame(minWidth: 500, minHeight: 400)
        .onAppear {
            Task {
                await featureDetector.scan()
            }
        }
    }

    // MARK: - Active Features

    private var activeTab: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            if featureDetector.activeFeatures.isEmpty {
                Text("Scanning features...")
                    .font(Typography.body)
                    .foregroundColor(theme.muted)
                    .padding()
            } else {
                ForEach(featureDetector.activeFeatures) { feature in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(theme.sage)
                            .frame(width: 8, height: 8)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.name)
                                .font(Typography.bodyBold)
                                .foregroundColor(theme.bright)
                            Text(feature.description)
                                .font(Typography.caption)
                                .foregroundColor(theme.secondary)
                        }

                        Spacer()

                        Text(feature.category.rawValue)
                            .font(Typography.caption)
                            .foregroundColor(theme.muted)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(theme.elevated)
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
                }
            }

            // CLI info
            if let version = featureDetector.cliVersion {
                HStack {
                    Text("Claude CLI")
                        .font(Typography.caption)
                        .foregroundColor(theme.muted)
                    Spacer()
                    Text(version)
                        .font(Typography.caption)
                        .foregroundColor(theme.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
        }
        .padding(.vertical, 12)
    }

    // MARK: - Suggestions

    private var pendingSuggestions: [EvolutionProposal] {
        evolutionAgent.proposals.filter { $0.status == .pending }
    }

    private var suggestionsTab: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            if pendingSuggestions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 24))
                        .foregroundColor(theme.muted)
                    Text("No suggestions right now")
                        .font(Typography.body)
                        .foregroundColor(theme.muted)
                    Text("The evolution agent checks periodically for improvements")
                        .font(Typography.caption)
                        .foregroundColor(theme.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
            } else {
                ForEach(pendingSuggestions) { proposal in
                    SuggestionRow(proposal: proposal)
                }
            }

            // Manual scan button
            Button {
                Task { await evolutionAgent.performCheck() }
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Scan for improvements")
                }
                .font(Typography.caption)
                .foregroundColor(theme.sky)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        .padding(.vertical, 12)
    }

    // MARK: - Configure

    private var configureTab: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            ConfigSection(title: "MCP Servers", items: featureDetector.installedMCPServers)
            ConfigSection(title: "Hooks", items: featureDetector.installedHooks)
            ConfigSection(title: "Skills", items: featureDetector.installedSkills)
            ConfigSection(title: "Agents", items: featureDetector.installedAgents)
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Supporting Views

private struct TabButton: View {
    let title: String
    let count: Int?
    let isSelected: Bool
    let action: () -> Void
    @EnvironmentObject private var theme: ThemeEngine

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(Typography.statusBar)
                    .foregroundColor(isSelected ? theme.bright : theme.muted)

                if let count, count > 0 {
                    Text("\(count)")
                        .font(Typography.caption)
                        .foregroundColor(isSelected ? theme.sky : theme.muted)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? theme.elevated : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

private struct SuggestionRow: View {
    let proposal: EvolutionProposal
    @EnvironmentObject private var evolutionAgent: EvolutionAgent
    @EnvironmentObject private var theme: ThemeEngine

    var body: some View {
        HStack(spacing: 12) {
            // Priority indicator
            Circle()
                .fill(priorityColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(proposal.title)
                    .font(Typography.bodyBold)
                    .foregroundColor(theme.bright)
                Text(proposal.description)
                    .font(Typography.caption)
                    .foregroundColor(theme.secondary)
            }

            Spacer()

            if proposal.autoApplyable {
                Button {
                    Task { await evolutionAgent.apply(proposalId: proposal.id) }
                } label: {
                    Text("Apply")
                        .font(Typography.caption)
                        .foregroundColor(theme.sky)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(theme.sky.opacity(0.15))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            Button {
                evolutionAgent.dismiss(proposalId: proposal.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundColor(theme.muted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }

    private var priorityColor: Color {
        switch proposal.priority {
        case .high: return theme.amber
        case .medium: return theme.sky
        case .low: return theme.muted
        }
    }
}

private struct ConfigSection: View {
    let title: String
    let items: [String]
    @EnvironmentObject private var theme: ThemeEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Typography.bodyBold)
                .foregroundColor(theme.bright)
                .padding(.horizontal, 20)

            if items.isEmpty {
                Text("None configured")
                    .font(Typography.caption)
                    .foregroundColor(theme.muted)
                    .padding(.horizontal, 20)
            } else {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(Typography.caption)
                        .foregroundColor(theme.secondary)
                        .padding(.horizontal, 28)
                }
            }
        }
    }
}
