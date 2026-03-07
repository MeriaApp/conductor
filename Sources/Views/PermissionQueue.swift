import SwiftUI

/// Non-blocking permission approval UI
/// Shows pending requests in a compact queue, supports batch approval
struct PermissionQueue: View {
    @EnvironmentObject private var permissionManager: PermissionManager
    @EnvironmentObject private var theme: ThemeEngine

    var body: some View {
        if !permissionManager.pendingRequests.isEmpty {
            VStack(spacing: 0) {
                // Header with count and batch actions
                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(theme.sand)
                            .frame(width: 8, height: 8)

                        Text("\(permissionManager.pendingRequests.count) pending")
                            .font(Typography.statusBar)
                            .foregroundColor(theme.sand)
                    }

                    Spacer()

                    // Approve all
                    Button {
                        permissionManager.approveAll()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11))
                            Text("Approve All")
                                .font(Typography.caption)
                        }
                        .foregroundColor(theme.sage)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("a", modifiers: .command)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                // Request list
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(permissionManager.pendingRequests.enumerated()), id: \.element.id) { idx, request in
                            PermissionRequestRow(request: request, index: idx + 1)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
                .frame(maxHeight: 200)
            }
            .background(theme.overlay)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(theme.sand.opacity(0.3), lineWidth: 1)
            )
            // Number key approval (1-9)
            .onKeyPress(characters: CharacterSet(charactersIn: "123456789"), phases: .down) { press in
                guard let digit = Int(String(press.characters)) else { return .ignored }
                let index = digit - 1
                if index < permissionManager.pendingRequests.count {
                    permissionManager.approve(requestId: permissionManager.pendingRequests[index].id)
                    return .handled
                }
                return .ignored
            }
        }
    }
}

// MARK: - Permission Request Row

struct PermissionRequestRow: View {
    let request: PermissionRequest
    var index: Int = 0
    @EnvironmentObject private var permissionManager: PermissionManager
    @EnvironmentObject private var theme: ThemeEngine

    var body: some View {
        HStack(spacing: 8) {
            // Number badge (for keyboard approval)
            if index > 0 && index <= 9 {
                Text("\(index)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(theme.sky)
                    .frame(width: 16)
            }

            // Risk indicator
            Circle()
                .fill(riskColor)
                .frame(width: 6, height: 6)

            // Agent name
            Text(request.agentName)
                .font(Typography.caption)
                .foregroundColor(theme.sky)

            // Tool + input
            Text(request.toolName)
                .font(Typography.toolLabel)
                .foregroundColor(theme.secondary)

            Text(request.input.prefix(40) + (request.input.count > 40 ? "..." : ""))
                .font(Typography.caption)
                .foregroundColor(theme.muted)
                .lineLimit(1)

            Spacer()

            // Actions
            Button {
                permissionManager.approve(requestId: request.id)
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(theme.sage)
            }
            .buttonStyle(.plain)

            Button {
                permissionManager.deny(requestId: request.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(theme.rose)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(theme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var riskColor: Color {
        switch request.riskLevel {
        case .low: return theme.sage
        case .medium: return theme.sky
        case .high: return theme.sand
        case .critical: return theme.rose
        }
    }
}
