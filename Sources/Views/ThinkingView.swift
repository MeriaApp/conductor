import SwiftUI

/// Collapsible thinking block with lavender accent and streaming animation
struct ThinkingView: View {
    let block: ThinkingBlock
    @EnvironmentObject private var theme: ThemeEngine
    @State private var isCollapsed: Bool

    init(block: ThinkingBlock) {
        self.block = block
        self._isCollapsed = State(initialValue: block.isCollapsed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — always visible
            HStack(spacing: 8) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(theme.lavender)

                if block.isStreaming {
                    ThinkingPulse()
                        .foregroundColor(theme.lavender)
                }

                Text("Thinking")
                    .font(Typography.toolLabel)
                    .foregroundColor(theme.lavender)

                if let duration = block.duration {
                    Text(String(format: "%.1fs", duration))
                        .font(Typography.caption)
                        .foregroundColor(theme.muted)
                }

                Spacer()

                if !isCollapsed {
                    Text("\(block.text.count) chars")
                        .font(Typography.caption)
                        .foregroundColor(theme.muted)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isCollapsed.toggle()
                }
            }

            // Content — shown when expanded
            if !isCollapsed {
                Text(block.text)
                    .font(Typography.thinking)
                    .foregroundColor(theme.lavender.opacity(0.8))
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                    .padding(.leading, 20) // Indent under chevron
            }
        }
        .background(theme.thinkingBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(theme.lavender.opacity(0.15), lineWidth: 1)
        )
    }
}

/// Subtle pulsing indicator while Claude is thinking
struct ThinkingPulse: View {
    @State private var opacity: Double = 0.4

    var body: some View {
        Circle()
            .frame(width: 6, height: 6)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    opacity = 1.0
                }
            }
    }
}
