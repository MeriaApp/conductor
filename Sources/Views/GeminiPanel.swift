import SwiftUI

/// Gemini panel — ask Gemini CLI from within Conductor for second opinions,
/// long-context scans, and parallel AI research.
/// Triggered via Cmd+Shift+G or command palette.
struct GeminiPanel: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var theme: ThemeEngine
    @EnvironmentObject private var process: ClaudeProcess
    @ObservedObject private var gemini = GeminiProcess.shared

    @State private var promptText = ""
    @State private var selectedModel: GeminiModel = .flash
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)
            if !gemini.history.isEmpty {
                historyView
                Divider().opacity(0.3)
            }
            if let error = gemini.lastError {
                errorBanner(error)
                Divider().opacity(0.3)
            }
            inputBar
        }
        .background(theme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.lavender.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 30, y: 10)
        .frame(width: 680)
        .onAppear { isInputFocused = true }
        .onKeyPress(.escape) {
            if gemini.isRunning { gemini.cancel() } else { isPresented = false }
            return .handled
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "sparkles")
                .font(.system(size: 14))
                .foregroundColor(theme.lavender)
            Text("Ask Gemini")
                .font(Typography.heading2)
                .foregroundColor(theme.bright)

            Spacer()

            Picker("", selection: $selectedModel) {
                ForEach(GeminiModel.allCases, id: \.self) { model in
                    Label(model.displayName, systemImage: model.icon).tag(model)
                }
            }
            .pickerStyle(.menu)
            .font(Typography.caption)
            .frame(width: 180)

            if !gemini.history.isEmpty {
                Button("Clear") { gemini.clearHistory() }
                    .buttonStyle(.plain)
                    .font(Typography.caption)
                    .foregroundColor(theme.muted)
            }

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
    }

    // MARK: - History

    private var historyView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(gemini.history) { turn in
                        GeminiTurnRow(turn: turn)
                            .id(turn.id)
                    }
                }
                .padding(16)
            }
            .frame(maxHeight: 320)
            .onChange(of: gemini.history.count) { _, _ in
                if let last = gemini.history.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    // MARK: - Error

    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11))
            Text(error)
                .font(Typography.caption)
                .textSelection(.enabled)
        }
        .foregroundColor(theme.rose)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(
                "Ask Gemini anything — long context, second opinion, bulk review...",
                text: $promptText,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(Typography.body)
            .foregroundColor(theme.primary)
            .lineLimit(1...4)
            .focused($isInputFocused)

            if gemini.isRunning {
                ProgressView()
                    .controlSize(.small)
                Button("Stop") { gemini.cancel() }
                    .buttonStyle(.plain)
                    .font(Typography.caption)
                    .foregroundColor(theme.rose)
            } else {
                Button { sendMessage() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(
                            promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? theme.muted
                                : theme.lavender
                        )
                }
                .buttonStyle(.plain)
                .disabled(promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(14)
    }

    // MARK: - Actions

    private func sendMessage() {
        let trimmed = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !gemini.isRunning else { return }
        promptText = ""
        Task {
            await gemini.ask(trimmed, projectDir: process.workingDirectory, model: selectedModel)
        }
    }
}

// MARK: - Turn Row

private struct GeminiTurnRow: View {
    let turn: GeminiTurn
    @EnvironmentObject private var theme: ThemeEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "person.fill")
                    .font(.system(size: 10))
                    .foregroundColor(theme.muted)
                    .padding(.top, 2)
                Text(turn.prompt)
                    .font(Typography.body)
                    .foregroundColor(theme.muted)
                    .textSelection(.enabled)
            }

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: turn.model.icon)
                    .font(.system(size: 10))
                    .foregroundColor(theme.lavender)
                    .padding(.top, 2)
                Text(turn.response)
                    .font(Typography.body)
                    .foregroundColor(theme.primary)
                    .textSelection(.enabled)
            }
            .padding(10)
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}
