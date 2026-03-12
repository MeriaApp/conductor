import SwiftUI

/// Dev Tools panel — run CodeRabbit, SwiftLint, Periphery, and Fastlane from within Conductor.
/// Triggered via Cmd+Shift+L or command palette.
struct DevToolPanel: View {
    @Binding var isPresented: Bool
    let projectDir: String?
    @EnvironmentObject private var theme: ThemeEngine
    @ObservedObject private var service = DevToolService.shared

    @State private var selectedTool: DevTool = .codeRabbit

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)
            HStack(spacing: 0) {
                toolList
                Divider().opacity(0.3)
                outputPanel
            }
            .frame(height: 380)
        }
        .background(theme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.sand.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 30, y: 10)
        .frame(width: 720)
        .onKeyPress(.escape) {
            if service.isRunning { service.cancel() } else { isPresented = false }
            return .handled
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "hammer.fill")
                .font(.system(size: 14))
                .foregroundColor(theme.sand)
            Text("Dev Tools")
                .font(Typography.heading2)
                .foregroundColor(theme.bright)

            Spacer()

            statusBadge

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

    @ViewBuilder
    private var statusBadge: some View {
        if service.isRunning {
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("Running \(service.activeTool?.displayName ?? "")...")
                    .font(Typography.caption)
                    .foregroundColor(theme.muted)
            }
        } else if let code = service.exitCode {
            HStack(spacing: 4) {
                Circle()
                    .fill(code == 0 ? theme.sage : theme.rose)
                    .frame(width: 7, height: 7)
                Text(code == 0 ? (service.activeTool?.successMessage ?? "Done") : "Exit \(code)")
                    .font(Typography.caption)
                    .foregroundColor(code == 0 ? theme.sage : theme.rose)
            }
        }
    }

    // MARK: - Tool List

    private var toolList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(DevTool.allCases) { tool in
                toolRow(tool)
            }
            Spacer()
        }
        .padding(8)
        .frame(width: 200)
    }

    private func toolRow(_ tool: DevTool) -> some View {
        Button {
            selectedTool = tool
        } label: {
            HStack(spacing: 8) {
                Image(systemName: tool.icon)
                    .font(.system(size: 12))
                    .foregroundColor(selectedTool == tool ? theme.sand : theme.muted)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tool.displayName)
                        .font(Typography.bodyBold)
                        .foregroundColor(selectedTool == tool ? theme.sand : theme.primary)
                    Text(tool.description)
                        .font(Typography.caption)
                        .foregroundColor(theme.muted)
                        .lineLimit(1)
                }
                Spacer()
                // Running indicator
                if service.isRunning && service.activeTool == tool {
                    ProgressView().controlSize(.mini)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(selectedTool == tool ? theme.sand.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Output Panel

    private var outputPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            actionBar
            Divider().opacity(0.2)
            outputView
        }
    }

    private var actionBar: some View {
        HStack {
            if let dir = projectDir {
                Text(URL(fileURLWithPath: dir).lastPathComponent)
                    .font(Typography.caption)
                    .foregroundColor(theme.muted)
            } else {
                Text("No project directory — set one first")
                    .font(Typography.caption)
                    .foregroundColor(theme.rose)
            }

            Spacer()

            if service.isRunning {
                Button("Cancel") { service.cancel() }
                    .buttonStyle(.plain)
                    .font(Typography.caption)
                    .foregroundColor(theme.rose)
            } else {
                if !service.output.isEmpty {
                    Button("Clear") { service.clearOutput() }
                        .buttonStyle(.plain)
                        .font(Typography.caption)
                        .foregroundColor(theme.muted)
                }

                Button {
                    guard let dir = projectDir else { return }
                    service.run(selectedTool, projectDir: dir)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill").font(.system(size: 9))
                        Text("Run \(selectedTool.displayName)")
                            .font(Typography.caption)
                    }
                    .foregroundColor(projectDir != nil ? theme.sand : theme.muted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(projectDir != nil ? theme.sand.opacity(0.15) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .disabled(projectDir == nil)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var outputView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(service.output.isEmpty ? "Output will appear here..." : service.output)
                    .font(Typography.codeBlock)
                    .foregroundColor(service.output.isEmpty ? theme.muted : theme.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .id("devtool-output-bottom")
            }
            .onChange(of: service.output) { _, _ in
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo("devtool-output-bottom", anchor: .bottom)
                }
            }
        }
    }
}
